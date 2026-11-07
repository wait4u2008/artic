// Data model for the vault: folders and files as stored in the (encrypted)
// manifest. Names are the only metadata kept; content lives in random-named
// encrypted blobs on disk.

class FolderEntry {
  String id;
  String name;
  String? parentId; // null = root level
  int createdAt;

  FolderEntry({
    required this.id,
    required this.name,
    this.parentId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'parentId': parentId, 'createdAt': createdAt};

  factory FolderEntry.fromJson(Map<String, dynamic> json) => FolderEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        parentId: json['parentId'] as String?,
        createdAt: json['createdAt'] as int,
      );
}

/// File extensions treated as image / video files. Text files are anything
/// else (.txt / .md); the reader decides how to display based on these.
const List<String> _imageExts = [
  '.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp',
];
const List<String> _videoExts = [
  '.mp4', '.mkv', '.avi', '.mov', '.webm', '.3gp',
];

class FileEntry {
  String id;
  String name;
  String? folderId; // null = root level
  String blob; // random file name of the encrypted blob on disk
  int size; // plaintext size in bytes
  int createdAt;
  int modifiedAt;
  int scrollOffset; // remembered reading position in the reader
  // Encryption scheme used for this file's blob:
  //  - 'gcm': one-shot AES-256-GCM (text files, original format)
  //  - 'ctr' : streaming AES-256-CTR + HMAC-SHA256 (large image/video
  //            files, imported without loading the whole file in memory)
  String cipher;

  FileEntry({
    required this.id,
    required this.name,
    this.folderId,
    required this.blob,
    required this.size,
    required this.createdAt,
    required this.modifiedAt,
    this.scrollOffset = 0,
    this.cipher = 'gcm',
  });

  bool get isMarkdown => name.toLowerCase().endsWith('.md');

  bool get isImage {
    final lower = name.toLowerCase();
    return _imageExts.any(lower.endsWith);
  }

  bool get isVideo {
    final lower = name.toLowerCase();
    return _videoExts.any(lower.endsWith);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'folderId': folderId,
        'blob': blob,
        'size': size,
        'createdAt': createdAt,
        'modifiedAt': modifiedAt,
        'scrollOffset': scrollOffset,
        'cipher': cipher,
      };

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        folderId: json['folderId'] as String?,
        blob: json['blob'] as String,
        size: json['size'] as int,
        createdAt: json['createdAt'] as int,
        modifiedAt: json['modifiedAt'] as int,
        scrollOffset: (json['scrollOffset'] as int?) ?? 0,
        // Vaults created before media support stored everything as GCM.
        cipher: (json['cipher'] as String?) ?? 'gcm',
      );
}

class VaultManifest {
  List<FolderEntry> folders;
  List<FileEntry> files;

  VaultManifest({required this.folders, required this.files});

  List<FolderEntry> foldersIn(String? parentId) =>
      folders.where((f) => f.parentId == parentId).toList();

  List<FileEntry> filesIn(String? folderId) =>
      files.where((f) => f.folderId == folderId).toList();

  int folderItemCount(String folderId) =>
      foldersIn(folderId).length + filesIn(folderId).length;

  Map<String, dynamic> toJson() => {
        'folders': folders.map((e) => e.toJson()).toList(),
        'files': files.map((e) => e.toJson()).toList(),
      };

  factory VaultManifest.fromJson(Map<String, dynamic> json) => VaultManifest(
        folders: (json['folders'] as List)
            .map((e) => FolderEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        files: (json['files'] as List)
            .map((e) => FileEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
