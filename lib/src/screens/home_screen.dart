import 'package:flutter/material.dart';

import '../models/vault_models.dart';
import '../storage/vault_store.dart';
import '../utils/auto_lock.dart';
import '../utils/file_actions.dart';
import '../utils/import_helper.dart';
import '../widgets/entry_tiles.dart';
import '../widgets/selection_bar.dart';
import 'login_screen.dart';

/// Main screen: root-level folders and files. Supports multi-select mode
/// (AppBar checklist icon) for bulk move/delete.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutoLockMixin, SingleTickerProviderStateMixin {
  bool _selectMode = false;
  final Set<String> _selected = {};
  late final TabController _tab = TabController(length: 3, vsync: this);

  /// Files shown in the current tab: 0 = text, 1 = images, 2 = videos.
  List<FileEntry> _tabFiles() {
    final files = vault.manifest.filesIn(null);
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
    // Home is the fallback position for the 1-minute password-free restore.
    vault.lastFolderId = null;
    vault.lastReaderEntry = null;
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
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
        ..addAll(manifest.foldersIn(null).map((f) => 'd:${f.id}'))
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
    final manifest = vault.manifest;
    final folders = manifest.foldersIn(null)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final files = _tabFiles()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final empty = folders.isEmpty && files.isEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: _selectMode
            ? IconButton(
                tooltip: 'Cancel',
                icon: const Icon(Icons.close),
                onPressed: _exitSelect,
              )
            : null,
        title: Text(_selectMode ? '${_selected.length} selected' : 'Artic'),
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
                  onPressed: () =>
                      pickAndImport(context, folderId: null, onDone: _refresh),
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
                    PopupMenuItem(value: 'newfolder', child: Text('New folder')),
                    PopupMenuItem(value: 'erase', child: Text('Erase all data')),
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
                0 => 'No text files yet.\nTap + to create a folder or import '
                    'txt/md files.',
                1 => 'No images yet.\nTap + to import image files.',
                _ => 'No videos yet.\nTap + to import video files.',
              },
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                for (final f in folders)
                  FolderTile(
                    folder: f,
                    refresh: _refresh,
                    selected: _selectMode ? _selected.contains('d:${f.id}') : null,
                    onToggleSelect: () => _toggleSelect('d:${f.id}'),
                  ),
                for (final f in files)
                  FileTile(
                    entry: f,
                    refresh: _refresh,
                    selected: _selectMode ? _selected.contains('f:${f.id}') : null,
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
              title: const Text('New folder'),
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
      await _newFolderDialog();
      _refresh();
    } else if (action == 'import') {
      await pickAndImport(context, folderId: null, onDone: _refresh);
    }
  }

  Future<void> _newFolderDialog() async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
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
      await vault.createFolder(name, null);
    }
  }

  Future<void> _onMenu(String value) async {
    if (value == 'newfolder') {
      await _newFolderDialog();
      _refresh();
    } else if (value == 'erase') {
      await _eraseAllDialog();
    }
  }

  Future<void> _eraseAllDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Erase all data?'),
        content: const Text(
            'All folders and files will be permanently deleted and cannot be '
            'recovered.'),
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
            child: const Text('Erase'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await vault.eraseAll();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }
}
