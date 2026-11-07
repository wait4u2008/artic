import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../models/vault_models.dart';
import '../storage/vault_store.dart';
import '../utils/auto_lock.dart';
import '../utils/markdown_preprocess.dart';
import 'image_viewer_screen.dart';
import 'video_player_screen.dart';

/// Reads and displays a decrypted file. Uses a soft paper-like light palette
/// (warm background, dark ink) instead of the app's dark theme to be easy on
/// the eyes while reading. .md files render as Markdown (with a source view
/// toggle for documents whose tables/HTML don't render well), .txt as plain
/// text, images open in the zoomable viewer, videos in the temp-file player
/// (plaintext deleted when playback ends).
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.entry});

  final FileEntry entry;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with AutoLockMixin {
  static const Color _paper = Color(0xFFF6F1E3);
  static const Color _ink = Color(0xFF33302B);
  static const Color _mutedInk = Color(0xFF8A8378);
  static const Color _paperDark = Color(0xFFECE5D2);
  static const Color _border = Color(0xFFC9BFA6);

  late final Future<String> _future = vault.readFile(widget.entry);
  late final ScrollController _scroll =
      ScrollController(initialScrollOffset: widget.entry.scrollOffset.toDouble());
  bool _sourceMode = false;

  @override
  void initState() {
    super.initState();
    // Remember this screen for the 1-minute password-free restore.
    vault.lastReaderEntry = widget.entry;
    vault.lastFolderId = widget.entry.folderId;
  }

  @override
  void dispose() {
    _saveScroll();
    _scroll.dispose();
    if (!vault.positionLocked &&
        identical(vault.lastReaderEntry, widget.entry)) {
      vault.lastReaderEntry = null;
    }
    super.dispose();
  }

  /// Persists the scroll position (called on exit and before auto-lock).
  void _saveScroll() {
    if (_scroll.hasClients) {
      vault.saveFileScroll(widget.entry.id, _scroll.offset.round());
    }
  }

  @override
  void onBeforeLock() {
    _saveScroll();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    // Media files use their own screens; the text path below would try to
    // utf8-decode binary data and fail.
    if (entry.isImage) {
      return ImageViewerScreen(entry: entry);
    }
    if (entry.isVideo) {
      return VideoPlayerScreen(entry: entry);
    }
    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        backgroundColor: _paper,
        foregroundColor: _ink,
        elevation: 0,
        title: Text(entry.name, overflow: TextOverflow.ellipsis),
        actions: [
          if (entry.isMarkdown)
            IconButton(
              tooltip: _sourceMode ? 'Rendered view' : 'Source view',
              icon: Icon(_sourceMode ? Icons.article_outlined : Icons.code),
              onPressed: () => setState(() => _sourceMode = !_sourceMode),
            ),
        ],
      ),
      body: FutureBuilder<String>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: _mutedInk),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Failed to read this file.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFB3482D)),
                ),
              ),
            );
          }
          final data = snapshot.data ?? '';
          if (_sourceMode) return _buildSourceView(data);
          return _buildPreview(entry, data, _scroll);
        },
      ),
    );
  }

  Widget _buildSourceView(String data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      child: SelectableText(
        data,
        style: const TextStyle(
          color: _ink,
          fontFamily: 'monospace',
          fontSize: 13.5,
          height: 1.5,
        ),
      ),
    );
  }

  Widget _buildPreview(FileEntry entry, String data, ScrollController scroll) {
    final textStyle = TextStyle(
      color: _ink,
      fontSize: 16.5,
      height: 1.65,
    );
    return SingleChildScrollView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: entry.isMarkdown
          ? MarkdownBody(
              data: preprocessMarkdown(data),
              styleSheet: _markdownStyle(textStyle),
            )
          : SelectableText(data, style: textStyle),
    );
  }

  MarkdownStyleSheet _markdownStyle(TextStyle p) {
    // Do NOT use MarkdownStyleSheet.fromTheme(): it asserts
    // theme.textTheme.bodyMedium.fontSize != null, which current Flutter
    // themes (dynamic font scaling) don't satisfy — that assertion was the
    // white-screen-on-md bug. Construct only the styles we override;
    // everything else falls back to MarkdownBody's built-in sheet.
    return MarkdownStyleSheet(
      h1: const TextStyle(color: _ink, fontSize: 24, fontWeight: FontWeight.w700),
      h2: const TextStyle(color: _ink, fontSize: 21, fontWeight: FontWeight.w700),
      h3: const TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w700),
      code: const TextStyle(
        backgroundColor: _paperDark,
        color: _ink,
        fontFamily: 'monospace',
        fontSize: 13,
      ),
      codeblockDecoration: const BoxDecoration(color: _paperDark),
      codeblockPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      blockquoteDecoration: const BoxDecoration(
        color: _paperDark,
        border: Border(
          left: BorderSide(color: _border, width: 3),
        ),
      ),
      a: const TextStyle(color: Color(0xFF4A5FA8)),
      // Compact table styling so wide tables stay readable on phones.
      tableHead: const TextStyle(
        color: _ink,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      tableBody: const TextStyle(color: _ink, fontSize: 13),
      tableBorder: TableBorder.all(color: _border, width: 0.6),
      tableCellsPadding:
          const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      tablePadding: const EdgeInsets.all(2),
    ).copyWith(p: p);
  }
}
