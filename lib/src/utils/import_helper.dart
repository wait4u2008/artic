import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../storage/vault_store.dart';

/// Extensions the import picker accepts, grouped by type.
const _textExts = ['txt', 'md'];
const _imageExts = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
const _videoExts = ['mp4', 'mkv', 'avi', 'mov', 'webm', '3gp'];

const _accepted = <String>[..._textExts, ..._imageExts, ..._videoExts];

/// True when the file is big enough that importing it in one memory chunk
/// would be wasteful (videos almost always are, images can be).
bool _shouldStream(String name) {
  final lower = name.toLowerCase();
  return _videoExts.any(lower.endsWith) || _imageExts.any(lower.endsWith);
}

bool _isAccepted(String name) {
  final lower = name.toLowerCase();
  return _accepted.any(lower.endsWith);
}

/// Opens the system file picker for txt/md/images/videos (multi-select) and
/// imports the picked files encrypted into [folderId].
///
/// Uses file_picker (not file_selector): on Android, file_selector copies the
/// picked file to cache **synchronously on the main thread** — a large video
/// makes the app ANR and crash. file_picker does the copy on a background
/// IO coroutine, so the UI stays alive. The stream encryption then runs on a
/// background isolate so it never blocks the UI either.
Future<void> pickAndImport(
  BuildContext context, {
  required String? folderId,
  required VoidCallback onDone,
}) async {
  vault.pickerActive = true;
  try {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: _accepted,
    );
    final files = picked;
    if (files.isEmpty) return;

    var count = 0;
    for (final f in files) {
      final base = f.name.split(RegExp(r'[/\\]')).last.trim();
      if (base.isEmpty || !_isAccepted(base)) continue;
      final unique = vault.uniqueName(base, folderId);
      final path = f.path;
      if (_shouldStream(base) && path != null && path.isNotEmpty) {
        // file_picker returns a real cached path (copied on a background
        // thread) — encrypt it on a background isolate.
        final size = await f.length();
        await vault.importFileStream(
          unique,
          path,
          folderId,
          size ?? 0,
        );
      } else {
        final bytes = await f.readAsBytes();
        await vault.importFile(unique, bytes, folderId);
      }
      count++;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count == 0
              ? 'No supported files selected.'
              : 'Imported $count file${count == 1 ? '' : 's'}'),
        ),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  } finally {
    vault.pickerActive = false;
    onDone();
  }
}
