import 'package:flutter/material.dart';

import '../models/vault_models.dart';
import '../screens/folder_screen.dart';
import '../screens/reader_screen.dart';
import '../storage/vault_store.dart';
import '../utils/file_actions.dart';
import '../utils/helpers.dart';

/// List tile for a folder (used on the home and folder screens).
///
/// When [selected] is non-null the tile is in selection mode: tapping
/// toggles [onToggleSelect] instead of navigating, and the leading icon
/// becomes a check indicator.
class FolderTile extends StatelessWidget {
  const FolderTile({
    super.key,
    required this.folder,
    required this.refresh,
    this.selected,
    this.onToggleSelect,
  });

  final FolderEntry folder;
  final VoidCallback refresh;
  final bool? selected;
  final VoidCallback? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final selectMode = selected != null;
    final scheme = Theme.of(context).colorScheme;
    final count = vault.manifest.folderItemCount(folder.id);
    return ListTile(
      leading: selectMode
          ? Icon(
              selected! ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected!
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            )
          : const Icon(Icons.folder, color: Color(0xFFE8B44A)),
      title: Text(folder.name),
      subtitle: Text(count == 1 ? '1 item' : '$count items'),
      trailing: selectMode ? null : const Icon(Icons.chevron_right),
      onTap: selectMode
          ? onToggleSelect
          : () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => FolderScreen(folderId: folder.id),
              ));
              refresh();
            },
      onLongPress: selectMode
          ? onToggleSelect
          : () => showFolderActions(context, folder, refresh: refresh),
    );
  }
}

/// List tile for a file (used on the home and folder screens).
///
/// When [selected] is non-null the tile is in selection mode: tapping
/// toggles [onToggleSelect] instead of opening the reader.
class FileTile extends StatelessWidget {
  const FileTile({
    super.key,
    required this.entry,
    required this.refresh,
    this.selected,
    this.onToggleSelect,
  });

  final FileEntry entry;
  final VoidCallback refresh;
  final bool? selected;
  final VoidCallback? onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final selectMode = selected != null;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: selectMode
          ? Icon(
              selected! ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected!
                  ? scheme.primary
                  : scheme.onSurfaceVariant,
            )
          : Icon(
              entry.isVideo
                  ? Icons.videocam_outlined
                  : entry.isImage
                      ? Icons.image_outlined
                      : entry.isMarkdown
                          ? Icons.description_outlined
                          : Icons.article_outlined,
              color: scheme.primary,
            ),
      title: Text(entry.name),
      subtitle: Text('${formatSize(entry.size)} · ${formatDate(entry.modifiedAt)}'),
      onTap: selectMode
          ? onToggleSelect
          : () async {
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ReaderScreen(entry: entry),
              ));
              refresh();
            },
      onLongPress: selectMode
          ? onToggleSelect
          : () => showFileActions(context, entry, refresh: refresh),
    );
  }
}

/// Empty-state placeholder.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_outlined,
              size: 64,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
