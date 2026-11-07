import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/vault_models.dart';
import '../storage/vault_store.dart';
import '../utils/auto_lock.dart';

/// Full-screen image viewer for encrypted vault images.
///
/// Decrypts the image into memory (kept only in RAM — nothing touches
/// disk), shows it on the paper background with pinch-to-zoom and
/// double-tap to zoom, matching the reader's eye-friendly palette.
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({super.key, required this.entry});

  final FileEntry entry;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen>
    with AutoLockMixin {
  static const Color _paper = Color(0xFFF6F1E3);
  static const Color _ink = Color(0xFF33302B);

  late final Future<_ImageData> _future = _load();

  Future<_ImageData> _load() async {
    final bytes = await vault.readFileBytes(widget.entry);
    return _ImageData(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      appBar: AppBar(
        backgroundColor: _paper,
        foregroundColor: _ink,
        elevation: 0,
        title: Text(widget.entry.name, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<_ImageData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Failed to open this image.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFB3482D)),
                ),
              ),
            );
          }
          final data = snapshot.data!;
          return Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 5,
              child: Image.memory(
                data.bytes,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const Text(
                  'Unsupported image format',
                  style: TextStyle(color: Color(0xFFB3482D)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ImageData {
  final Uint8List bytes;
  _ImageData(this.bytes);
}
