import 'package:flutter/material.dart';

import '../models/vault_models.dart';
import '../screens/image_viewer_screen.dart';
import '../screens/reader_screen.dart';
import '../screens/video_player_screen.dart';
import '../storage/vault_store.dart';

/// Long-press actions for a file: Read / Rename / Move to… / Delete.
Future<void> showFileActions(
  BuildContext context,
  FileEntry entry, {
  required VoidCallback refresh,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: const Text('Read'),
            onTap: () => Navigator.pop(ctx, 'read'),
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(ctx, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outlined),
            title: const Text('Move to…'),
            onTap: () => Navigator.pop(ctx, 'move'),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(ctx).colorScheme.error,
            ),
            title: Text(
              'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  if (action == 'read') {
    if (entry.isVideo) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(entry: entry),
      ));
    } else if (entry.isImage) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ImageViewerScreen(entry: entry),
      ));
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReaderScreen(entry: entry)),
      );
    }
    refresh();
  } else if (action == 'rename') {
    await _renameFile(context, entry);
    refresh();
  } else if (action == 'move') {
    final targetId = await pickFolderSheet(context,
        excludeFolderIds: {if (entry.folderId != null) entry.folderId!});
    if (targetId != null) {
      await vault.moveFile(entry.id, targetId);
      refresh();
    }
  } else if (action == 'delete') {
    await _confirmDeleteFile(context, entry);
    refresh();
  }
}

/// Long-press actions for a folder: Rename / Delete.
Future<void> showFolderActions(
  BuildContext context,
  FolderEntry folder, {
  required VoidCallback refresh,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.drive_file_rename_outline),
            title: const Text('Rename'),
            onTap: () => Navigator.pop(ctx, 'rename'),
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(ctx).colorScheme.error,
            ),
            title: Text(
              'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  if (action == 'rename') {
    await _renameFolder(context, folder);
    refresh();
  } else if (action == 'delete') {
    await _confirmDeleteFolder(context, folder);
    refresh();
  }
}

/// Bulk move for selection-mode keys (`f:<fileId>` / `d:<folderId>`).
/// Returns the number of items moved, or -1 if cancelled.
Future<int> moveSelection(
  BuildContext context,
  Set<String> keys,
) async {
  final folderKeys = keys.where((k) => k.startsWith('d:')).toList();
  final movedFolderIds = folderKeys.map((k) => k.substring(2)).toSet();

  // Exclude the folders being moved plus all of their descendants.
  final excluded = <String>{};
  for (final id in movedFolderIds) {
    excluded.addAll(_descendantFolderIds(id));
  }

  final targetId = await pickFolderSheet(context, excludeFolderIds: excluded);
  if (targetId == null) return -1;
  var moved = 0;
  for (final k in keys) {
    if (k.startsWith('f:')) {
      await vault.moveFile(k.substring(2), targetId);
      moved++;
    } else {
      await vault.moveFolder(k.substring(2), targetId);
      moved++;
    }
  }
  return moved;
}

/// Bulk delete for selection-mode keys. Returns true if deleted.
Future<bool> deleteSelection(BuildContext context, Set<String> keys) async {
  final nFiles = keys.where((k) => k.startsWith('f:')).length;
  final nFolders = keys.length - nFiles;
  final parts = <String>[
    if (nFiles > 0) '$nFiles file${nFiles == 1 ? '' : 's'}',
    if (nFolders > 0) '$nFolders folder${nFolders == 1 ? '' : 's'}',
  ];
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete selected?'),
      content: Text('${parts.join(' and ')} will be permanently deleted.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  for (final k in keys) {
    if (k.startsWith('f:')) {
      await vault.deleteFile(k.substring(2));
    } else {
      await vault.deleteFolder(k.substring(2));
    }
  }
  return true;
}

/// Folder picker bottom sheet for moving items. Returns the chosen folder id
/// (null = move to root) or null if cancelled. [excludeFolderIds] (plus their
/// descendants) are hidden from the list.
Future<String?> pickFolderSheet(
  BuildContext context, {
  Set<String> excludeFolderIds = const {},
}) async {
  // Compute indentation depth for each folder.
  final depths = <String, int>{};
  void walk(String? parentId, int depth) {
    for (final f in vault.manifest.folders) {
      if (f.parentId == parentId && !depths.containsKey(f.id)) {
        depths[f.id] = depth;
        walk(f.id, depth + 1);
      }
    }
  }

  walk(null, 0);

  // Hide excluded folders and everything under them.
  final hidden = <String>{};
  for (final id in excludeFolderIds) {
    hidden.addAll(_descendantFolderIds(id));
  }
  final shown = vault.manifest.folders
      .where((f) => !hidden.contains(f.id))
      .toList();

  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Move to folder',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Root (top level)'),
            onTap: () => Navigator.pop(ctx, ''),
          ),
          for (final f in shown)
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text('${'    ' * (depths[f.id] ?? 0)}${f.name}'),
              onTap: () => Navigator.pop(ctx, f.id),
            ),
        ],
      ),
    ),
  ).then((v) => v == '' ? null : v);
}

/// All folder ids of [id] and its nested descendants.
Set<String> _descendantFolderIds(String id) {
  final result = <String>{id};
  var changed = true;
  while (changed) {
    changed = false;
    for (final f in vault.manifest.folders) {
      if (f.parentId != null &&
          result.contains(f.parentId) &&
          !result.contains(f.id)) {
        result.add(f.id);
        changed = true;
      }
    }
  }
  return result;
}

Future<void> _renameFile(BuildContext context, FileEntry entry) async {
  final controller = TextEditingController(text: entry.name);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rename file'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
  final name = controller.text.trim();
  controller.dispose();
  if (ok == true && name.isNotEmpty && name != entry.name) {
    await vault.renameFile(entry.id, name);
  }
}

Future<void> _renameFolder(BuildContext context, FolderEntry folder) async {
  final controller = TextEditingController(text: folder.name);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rename folder'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Folder name'),
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Rename'),
        ),
      ],
    ),
  );
  final name = controller.text.trim();
  controller.dispose();
  if (ok == true && name.isNotEmpty && name != folder.name) {
    await vault.renameFolder(folder.id, name);
  }
}

Future<void> _confirmDeleteFile(BuildContext context, FileEntry entry) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete file?'),
      content: Text('"${entry.name}" will be permanently deleted.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await vault.deleteFile(entry.id);
  }
}

Future<void> _confirmDeleteFolder(
    BuildContext context, FolderEntry folder) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete folder?'),
      content: Text(
          '"${folder.name}" and everything inside it will be permanently deleted.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(ctx).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await vault.deleteFolder(folder.id);
  }
}
