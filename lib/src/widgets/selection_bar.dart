import 'package:flutter/material.dart';

/// Bottom action bar shown in selection mode: Select all / Move / Delete.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.onSelectAll,
    required this.onMove,
    required this.onDelete,
  });

  final int count;
  final VoidCallback onSelectAll;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              TextButton.icon(
                onPressed: onSelectAll,
                icon: const Icon(Icons.done_all, size: 20),
                label: const Text('All'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: count == 0 ? null : onMove,
                icon: const Icon(Icons.drive_file_move_outlined, size: 20),
                label: const Text('Move'),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: count == 0 ? null : onDelete,
                icon: Icon(Icons.delete_outline, size: 20, color: scheme.error),
                label: Text('Delete', style: TextStyle(color: scheme.error)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
