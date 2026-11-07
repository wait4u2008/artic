import 'package:flutter/material.dart';

import '../models/vault_models.dart';
import '../storage/vault_store.dart';
import '../utils/auto_lock.dart';
import '../utils/file_actions.dart';
import '../utils/import_helper.dart';
import '../widgets/entry_tiles.dart';
import '../widgets/selection_bar.dart';

/// A folder view: subfolders + files inside [folderId]. Import and new
/// subfolder are available right here (FAB + app bar), plus multi-select
/// mode for bulk move/delete.
class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key, required this.folderId});

  final String folderId;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen>
    with AutoLockMixin, SingleTickerProviderStateMixin {
  bool _selectMode = false;
  final Set<String> _selected = {};
  late final TabController _tab = TabController(length: 3, vsync: this);

  FolderEntry get _folder =>
      vault.manifest.folders.firstWhere((f) => f.id == widget.folderId);

  /// Files in the current tab: 0 = text, 1 = images, 2 = videos.
  List<FileEntry> _tabFiles() {
    final files = vault.manifest.filesIn(widget.folderId);
    return switch (_tab.index) {
      0 => files.where((f) => !f.isImage && !f.isVideo).toList(),
      1 => files.where((f) => f.isImage).toList(),
      _ => files.where((f) => f.isVideo).toList(),
    };
  }

  @override
  void initState() {
    super.initState();
    _tab.addListener(_onTabChanged);
    // Remember this folder for the 1-minute password-free restore.
    vault.lastFolderId = widget.folderId;
    vault.lastReaderEntry = null;
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Leaving the folder clears its record (unless the auto-lock teardown
    // is in progress — the restore path needs it).
    if (!vault.positionLocked && vault.lastFolderId == widget.folderId) {
      vault.lastFolderId = null;
    }
    _tab.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _toggleSelect(String key) {
    setState(() {
      if (!_selected.add(key)) _selected.remove(key);
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  void _exitSelect() {
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  void _selectAll() {
    final manifest = vault.manifest;
    setState(() {
      _selected
        ..clear()
        ..addAll(manifest.foldersIn(widget.folderId).map((f) => 'd:${f.id}'))
        ..addAll(_tabFiles().map((f) => 'f:${f.id}'));
    });
  }

  Future<void> _bulkMove() async {
    final moved = await moveSelection(context, _selected);
    if (moved < 0 || !mounted) return;
    _exitSelect();
    _refresh();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Moved $moved item${moved == 1 ? '' : 's'}')),
    );
  }

  Future<void> _bulkDelete() async {
    final deleted = await deleteSelection(context, _selected);
    if (!deleted || !mounted) return;
    _exitSelect();
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final folder = _folder;
    final subfolders = vault.manifest.foldersIn(folder.id)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final files = _tabFiles()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final empty = subfolders.isEmpty && files.isEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: _selectMode
            ? IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.close),
                onPressed: _exitSelect,
              )
            : null,
        title: Text(
          _selectMode ? '${_selected.length} selected' : folder.name,
          overflow: TextOverflow.ellipsis,
        ),
        bottom: _selectMode
            ? null
            : TabBar(
                controller: _tab,
                tabs: const [
                  Tab(text: 'Text', icon: Icon(Icons.article_outlined)),
                  Tab(text: 'Images', icon: Icon(Icons.image_outlined)),
                  Tab(text: 'Videos', icon: Icon(Icons.videocam_outlined)),
                ],
              ),
        actions: _selectMode
            ? []
            : [
                IconButton(
                  tooltip: 'Import files',
                  icon: const Icon(Icons.upload_file_outlined),
                  onPressed: () => pickAndImport(
                      context, folderId: folder.id, onDone: _refresh),
                ),
                if (!empty)
                  IconButton(
                    tooltip: 'Select',
                    icon: const Icon(Icons.checklist),
                    onPressed: () => setState(() => _selectMode = true),
                  ),
                PopupMenuButton<String>(
                  onSelected: _onMenu,
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'newfolder', child: Text('New subfolder')),
                    PopupMenuItem(value: 'rename', child: Text('Rename folder')),
                    PopupMenuItem(value: 'delete', child: Text('Delete folder')),
                  ],
                ),
              ],
      ),
      floatingActionButton: _selectMode
          ? null
          : FloatingActionButton(
              tooltip: 'Add',
              onPressed: _showAddSheet,
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: _selectMode
          ? SelectionBar(
              count: _selected.length,
              onSelectAll: _selectAll,
              onMove: _bulkMove,
              onDelete: _bulkDelete,
            )
          : null,
      body: empty
          ? EmptyState(
              message: switch (_tab.index) {
                0 => 'This folder has no text files.\nTap + to create a '
                    'subfolder or import txt/md files.',
                1 => 'This folder has no images.\nTap + to import image files.',
                _ => 'This folder has no videos.\nTap + to import video files.',
              },
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final f in subfolders)
                  FolderTile(
                    folder: f,
                    refresh: _refresh,
                    selected:
                        _selectMode ? _selected.contains('d:${f.id}') : null,
                    onToggleSelect: () => _toggleSelect('d:${f.id}'),
                  ),
                for (final f in files)
                  FileTile(
                    entry: f,
                    refresh: _refresh,
                    selected:
                        _selectMode ? _selected.contains('f:${f.id}') : null,
                    onToggleSelect: () => _toggleSelect('f:${f.id}'),
                  ),
              ],
            ),
    );
  }

  Future<void> _showAddSheet() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: const Text('New subfolder'),
              onTap: () => Navigator.pop(ctx, 'folder'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: const Text('Import files'),
              onTap: () => Navigator.pop(ctx, 'import'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'folder') {
      await _newSubfolderDialog();
      _refresh();
    } else if (action == 'import') {
      await pickAndImport(context, folderId: widget.folderId, onDone: _refresh);
    }
  }

  Future<void> _newSubfolderDialog() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New subfolder'),
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
            child: const Text('Create'),
          ),
        ],
      ),
    );
    final name = controller.text.trim();
    controller.dispose();
    if (ok == true && name.isNotEmpty) {
      await vault.createFolder(name, widget.folderId);
    }
  }

  Future<void> _onMenu(String value) async {
    if (value == 'newfolder') {
      await _newSubfolderDialog();
      _refresh();
    } else if (value == 'rename') {
      await _renameFolderDialog();
      _refresh();
    } else if (value == 'delete') {
      await _deleteCurrentFolder();
    }
  }

  Future<void> _renameFolderDialog() async {
    final controller = TextEditingController(text: _folder.name);
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
    if (ok == true && name.isNotEmpty && name != _folder.name) {
      await vault.renameFolder(widget.folderId, name);
    }
  }

  Future<void> _deleteCurrentFolder() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete folder?'),
        content: Text(
            '"${_folder.name}" and everything inside it will be permanently '
            'deleted.'),
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
      await vault.deleteFolder(widget.folderId);
      if (mounted) Navigator.of(context).pop();
    }
  }
}
