import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../crypto/vault_crypto.dart';
import '../models/vault_models.dart';

/// The single app-wide vault store.
///
/// Nothing is stored in plain text on disk (all inside the app's private
/// sandbox directory, invisible to file managers and other apps):
///  - `vault.salt`          : random salt for key derivation
///  - `vault.key`           : the random 256-bit vault key, AES-GCM wrapped
///                            by the password-derived key
///  - `manifest.enc`        : folder/file structure, encrypted with the
///                            vault key
///  - `files/<random>.enc`  : file contents, encrypted with the vault key
///
/// The vault key and the decrypted manifest exist only in memory while
/// unlocked. Forgetting the password means the data is unrecoverable.
final VaultStore vault = VaultStore();

class VaultStore {
  /// Hard-coded unlock password ("art"), per user request.
  static const String kPassword = 'art';

  static const String _dirName = 'vault';
  static const String _saltName = 'vault.salt';
  static const String _keyName = 'vault.key';
  static const String _manifestName = 'manifest.enc';
  static const String _filesDirName = 'files';

  /// True while the system file picker is open, so backgrounding during
  /// picking does not trigger an auto-lock.
  bool pickerActive = false;

  /// When the vault was last locked (for the 1-minute grace period).
  DateTime? lockedAt;

  /// Last position before locking, used to restore the screen after the
  /// 1-minute password-free unlock.
  String? lastFolderId; // null = home
  FileEntry? lastReaderEntry;

  /// True while the lock-navigation is tearing down screens (so their
  /// dispose handlers don't clear the position records we need to restore).
  bool positionLocked = false;

  Directory? _root;
  Uint8List? _vaultKey;
  VaultManifest? _manifest;

  bool get unlocked => _vaultKey != null;

  VaultManifest get manifest {
    final m = _manifest;
    if (m == null) throw StateError('Vault is locked');
    return m;
  }

  Future<Directory> _dir() async {
    if (_root != null) return _root!;
    final support = await getApplicationSupportDirectory();
    _root = Directory('${support.path}/$_dirName');
    return _root!;
  }

  Future<bool> hasVault() async =>
      File('${(await _dir()).path}/$_keyName').existsSync();

  /// Creates a brand-new vault and unlocks it.
  Future<void> createVault(String password) async {
    final dir = await _dir();
    dir.createSync(recursive: true);
    Directory('${dir.path}/$_filesDirName').createSync(recursive: true);

    final salt = VaultCrypto.randomBytes(16);
    final masterKey = await VaultCrypto.deriveKey(password, salt);
    final vaultKey = VaultCrypto.randomBytes(32);

    File('${dir.path}/$_saltName').writeAsBytesSync(salt);
    File('${dir.path}/$_keyName')
        .writeAsBytesSync(await VaultCrypto.encryptBytes(masterKey, vaultKey));

    _vaultKey = vaultKey;
    _manifest = VaultManifest(folders: [], files: []);
    await _saveManifest();
  }

  /// Tries to unlock with [password]. Returns false on wrong password.
  Future<bool> unlock(String password) async {
    final dir = await _dir();
    try {
      final salt = File('${dir.path}/$_saltName').readAsBytesSync();
      final masterKey = await VaultCrypto.deriveKey(password, salt);
      final wrapped = File('${dir.path}/$_keyName').readAsBytesSync();
      _vaultKey = await VaultCrypto.decryptBytes(masterKey, wrapped);
      await _loadManifest();
      return true;
    } catch (_) {
      lock();
      return false;
    }
  }

  /// Drops the key and manifest from memory.
  void lock() {
    _vaultKey = null;
    _manifest = null;
    lockedAt = DateTime.now();
  }

  /// Persists the reading position of [id] (used to resume articles).
  Future<void> saveFileScroll(String id, int offset) async {
    FileEntry? entry;
    for (final f in _manifest?.files ?? const <FileEntry>[]) {
      if (f.id == id) {
        entry = f;
        break;
      }
    }
    if (entry == null || entry.scrollOffset == offset) return;
    entry.scrollOffset = offset;
    await _saveManifest();
  }

  /// Changes the password (re-wraps the vault key; file blobs are untouched).
  /// Throws [Exception] if [oldPassword] is wrong.
  Future<void> changePassword(String oldPassword, String newPassword) async {
    if (!await unlock(oldPassword)) {
      throw Exception('Wrong current password');
    }
    final dir = await _dir();
    final salt = VaultCrypto.randomBytes(16);
    final masterKey = await VaultCrypto.deriveKey(newPassword, salt);
    File('${dir.path}/$_saltName').writeAsBytesSync(salt);
    File('${dir.path}/$_keyName')
        .writeAsBytesSync(await VaultCrypto.encryptBytes(masterKey, _vaultKey!));
  }

  /// Deletes everything. Used by "Erase all data".
  Future<void> eraseAll() async {
    final dir = await _dir();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    _root = null;
    lock();
  }

  Future<void> _loadManifest() async {
    final dir = await _dir();
    final enc = File('${dir.path}/$_manifestName').readAsBytesSync();
    final plain = await VaultCrypto.decryptBytes(_vaultKey!, enc);
    _manifest = VaultManifest.fromJson(
        jsonDecode(utf8.decode(plain)) as Map<String, dynamic>);
  }

  Future<void> _saveManifest() async {
    final dir = await _dir();
    final plain = utf8.encode(jsonEncode(_manifest!.toJson()));
    final enc = await VaultCrypto.encryptBytes(_vaultKey!, plain);
    File('${dir.path}/$_manifestName').writeAsBytesSync(enc);
  }

  // ---------------------------------------------------------------- folders

  Future<FolderEntry> createFolder(String name, String? parentId) async {
    final folder = FolderEntry(
      id: VaultCrypto.randomHex(8),
      name: name,
      parentId: parentId,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _manifest!.folders.add(folder);
    await _saveManifest();
    return folder;
  }

  Future<void> renameFolder(String id, String newName) async {
    _manifest!.folders.firstWhere((f) => f.id == id).name = newName;
    await _saveManifest();
  }

  /// Moves a folder to [newParentId] (null = root). Refuses to move a folder
  /// into itself or one of its own descendants.
  Future<void> moveFolder(String id, String? newParentId) async {
    if (id == newParentId) return;
    var cur = newParentId;
    while (cur != null) {
      if (cur == id) {
        throw Exception('Cannot move a folder into itself');
      }
      cur = _manifest!.folders.firstWhere((f) => f.id == cur).parentId;
    }
    _manifest!.folders.firstWhere((f) => f.id == id).parentId = newParentId;
    await _saveManifest();
  }

  /// Deletes a folder, all of its subfolders and every file inside them.
  Future<void> deleteFolder(String id) async {
    final folderIds = <String>{id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final f in _manifest!.folders) {
        if (f.parentId != null &&
            folderIds.contains(f.parentId) &&
            !folderIds.contains(f.id)) {
          folderIds.add(f.id);
          changed = true;
        }
      }
    }
    final doomedFiles =
        _manifest!.files.where((f) => folderIds.contains(f.folderId)).toList();
    final dir = await _dir();
    for (final f in doomedFiles) {
      final p = '${dir.path}/$_filesDirName/${f.blob}';
      if (File(p).existsSync()) File(p).deleteSync();
    }
    _manifest!.files.removeWhere((f) => folderIds.contains(f.folderId));
    _manifest!.folders.removeWhere((f) => folderIds.contains(f.id));
    await _saveManifest();
  }

  // ------------------------------------------------------------------ files

  Future<FileEntry> importFile(
      String name, Uint8List content, String? folderId) async {
    final dir = await _dir();
    final blob = '${VaultCrypto.randomHex(16)}.enc';
    File('${dir.path}/$_filesDirName/$blob').writeAsBytesSync(
        await VaultCrypto.encryptBytes(_vaultKey!, content));
    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = FileEntry(
      id: VaultCrypto.randomHex(8),
      name: name,
      folderId: folderId,
      blob: blob,
      size: content.length,
      createdAt: now,
      modifiedAt: now,
    );
    _manifest!.files.add(entry);
    await _saveManifest();
    return entry;
  }

  /// Imports a file by streaming it (used for large images/videos that must
  /// not be loaded into memory all at once). The encryption runs on a
  /// background isolate so the UI thread never blocks (a large video would
  /// otherwise ANR the app). [sourcePath] is the absolute path of the
  /// picked file; returns the new entry.
  Future<FileEntry> importFileStream(
    String name,
    String sourcePath,
    String? folderId,
    int plaintextLength,
  ) async {
    final dir = await _dir();
    final blob = '${VaultCrypto.randomHex(16)}.enc';
    final blobPath = '${dir.path}/$_filesDirName/$blob';
    final key = _vaultKey!;

    // Encrypt on a background isolate: read the source in chunks, encrypt
    // with AES-CTR+HMAC, write the blob. dart:io works fine in isolates.
    await Isolate.run(() async {
      final out = File(blobPath).openWrite();
      try {
        await VaultCrypto.encryptStream(
          File(sourcePath).openRead(),
          out,
          key,
        );
      } catch (_) {
        // Clean up the partial blob on failure.
        try {
          out.close();
        } catch (_) {}
        if (File(blobPath).existsSync()) File(blobPath).deleteSync();
        rethrow;
      }
    });

    final now = DateTime.now().millisecondsSinceEpoch;
    final entry = FileEntry(
      id: VaultCrypto.randomHex(8),
      name: name,
      folderId: folderId,
      blob: blob,
      size: plaintextLength,
      createdAt: now,
      modifiedAt: now,
      cipher: 'ctr',
    );
    _manifest!.files.add(entry);
    await _saveManifest();
    return entry;
  }

  Future<String> readFile(FileEntry entry) async {
    final dir = await _dir();
    final enc =
        File('${dir.path}/$_filesDirName/${entry.blob}').readAsBytesSync();
    final plain = await VaultCrypto.decryptBytes(_vaultKey!, enc);
    return utf8.decode(plain, allowMalformed: true);
  }

  /// Decrypts a file into memory as raw bytes (for images).
  Future<Uint8List> readFileBytes(FileEntry entry) async {
    final dir = await _dir();
    if (entry.cipher == 'ctr') {
      final temp = File('${dir.path}/tmp_${entry.blob}');
      await VaultCrypto.decryptStream(
        File('${dir.path}/$_filesDirName/${entry.blob}'),
        temp.openWrite(),
        _vaultKey!,
      );
      final bytes = temp.readAsBytesSync();
      if (temp.existsSync()) temp.deleteSync();
      return bytes;
    }
    final enc =
        File('${dir.path}/$_filesDirName/${entry.blob}').readAsBytesSync();
    return VaultCrypto.decryptBytes(_vaultKey!, enc);
  }

  /// Decrypts a video (or any file) to a temp file in the app's private
  /// cache directory so the system video player can open it. Returns the
  /// temp file path; the caller MUST delete it after playback.
  Future<String> decryptToTempFile(FileEntry entry) async {
    final dir = await _dir();
    final cache = await getTemporaryDirectory();
    final tempPath = '${cache.path}/vault_${entry.id}_${entry.blob}';
    final out = File(tempPath).openWrite();
    if (entry.cipher == 'ctr') {
      await VaultCrypto.decryptStream(
        File('${dir.path}/$_filesDirName/${entry.blob}'),
        out,
        _vaultKey!,
      );
    } else {
      final enc =
          File('${dir.path}/$_filesDirName/${entry.blob}').readAsBytesSync();
      final plain = await VaultCrypto.decryptBytes(_vaultKey!, enc);
      out.add(plain);
      await out.close();
    }
    return tempPath;
  }

  Future<void> renameFile(String id, String newName) async {
    final entry = _manifest!.files.firstWhere((f) => f.id == id);
    entry.name = newName;
    entry.modifiedAt = DateTime.now().millisecondsSinceEpoch;
    await _saveManifest();
  }

  Future<void> moveFile(String id, String? newFolderId) async {
    final entry = _manifest!.files.firstWhere((f) => f.id == id);
    entry.folderId = newFolderId;
    entry.modifiedAt = DateTime.now().millisecondsSinceEpoch;
    await _saveManifest();
  }

  Future<void> deleteFile(String id) async {
    final entry = _manifest!.files.firstWhere((f) => f.id == id);
    final dir = await _dir();
    final p = '${dir.path}/$_filesDirName/${entry.blob}';
    if (File(p).existsSync()) File(p).deleteSync();
    _manifest!.files.removeWhere((f) => f.id == id);
    await _saveManifest();
  }

  /// Returns [baseName], or "base (2).ext" / "base (3).ext" … if that name
  /// is already taken in the destination folder.
  String uniqueName(String baseName, String? folderId) {
    final existing =
        _manifest!.filesIn(folderId).map((f) => f.name.toLowerCase()).toSet();
    if (!existing.contains(baseName.toLowerCase())) return baseName;
    final dot = baseName.lastIndexOf('.');
    final stem = dot > 0 ? baseName.substring(0, dot) : baseName;
    final ext = dot > 0 ? baseName.substring(dot) : '';
    var i = 2;
    while (existing.contains('$stem ($i)$ext'.toLowerCase())) {
      i++;
    }
    return '$stem ($i)$ext';
  }
}
