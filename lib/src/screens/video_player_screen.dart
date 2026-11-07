import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/vault_models.dart';
import '../storage/vault_store.dart';
import '../utils/auto_lock.dart';

/// Full-screen video player for encrypted vault videos.
///
/// Uses media_kit (libmpv + FFmpeg), which bundles its own decoders and
/// falls back to software decoding — videos that fail on the device's
/// hardware decoder (ExoPlayer/MediaCodec) play fine here, and far more
/// formats are supported (HEVC/AV1/mkv/avi/…).
///
/// The video is decrypted to a temp file in the app's private cache
/// directory (the player cannot read from memory), played, then **deleted
/// as soon as the screen is disposed** — playback is the only moment a
/// plaintext copy exists, and it lives in the app sandbox where file
/// managers and USB can't reach it.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({super.key, required this.entry});

  final FileEntry entry;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen>
    with AutoLockMixin {
  Player? _player;
  VideoController? _videoController;
  String? _tempPath;
  String? _pendingTemp; // temp path while still initializing
  bool _initializing = true;
  String? _error;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final tempPath = await vault.decryptToTempFile(widget.entry);
      _pendingTemp = tempPath;
      if (!mounted) {
        _deleteTemp(tempPath);
        return;
      }
      final player = Player();
      final videoController = VideoController(player);
      final media = Media('file://${tempPath.replaceAll(r'\', '/')}');
      await player.open(media, play: false);

      // Surface player errors (decode failures, missing codecs, …).
      _subs.add(player.stream.error.listen((err) {
        if (!mounted) return;
        setState(() {
          _error = err;
          _initializing = false;
        });
      }));

      if (!mounted) {
        player.dispose();
        _deleteTemp(tempPath);
        return;
      }
      setState(() {
        _player = player;
        _videoController = videoController;
        _tempPath = tempPath;
        _pendingTemp = null;
        _initializing = false;
      });
      player.play();
    } catch (e) {
      // Decrypt or init failed — remove any partial plaintext temp file.
      _deleteTemp(_pendingTemp);
      if (mounted) {
        setState(() {
          _initializing = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  void onBeforeLock() {
    // Stop playback before the vault key is dropped; the temp file is
    // deleted in dispose() which runs during the lock teardown.
    _player?.pause();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    // Playback over — remove the plaintext temp copy immediately.
    _deleteTemp(_tempPath);
    _deleteTemp(_pendingTemp);
    super.dispose();
  }

  void _deleteTemp(String? path) {
    if (path == null) return;
    try {
      File(path).deleteSync();
    } catch (_) {}
  }

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.entry.name, overflow: TextOverflow.ellipsis),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initializing) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    final controller = _videoController;
    final player = _player;
    if (_error != null || controller == null || player == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Unable to play this video.\n'
            'The video may be in an unsupported format or corrupted.\n'
            '$_error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Video(controller: controller),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (player.state.playing) {
                      player.pause();
                    } else {
                      player.play();
                    }
                    setState(() {});
                  },
                ),
                if (!player.state.playing)
                  const Icon(Icons.play_circle_outline,
                      size: 72, color: Colors.white70),
              ],
            ),
          ),
          // Controls live below the video, never overlapping the picture.
          _controls(player),
        ],
      ),
    );
  }

  Widget _controls(Player p) {
    return StreamBuilder<Duration>(
      stream: p.stream.position,
      initialData: p.state.position,
      builder: (context, snapPos) {
        final pos = snapPos.data ?? Duration.zero;
        final dur = p.state.duration;
        final frac = dur.inMilliseconds > 0
            ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;
        return Container(
          color: Colors.black.withValues(alpha: 0.55),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(
                  p.state.playing ? Icons.pause : Icons.play_arrow,
                  color: Colors.white,
                ),
                onPressed: () {
                  if (p.state.playing) {
                    p.pause();
                  } else {
                    p.play();
                  }
                  setState(() {});
                },
              ),
              Text('${_fmt(pos)} / ${_fmt(dur)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
              Expanded(
                child: Slider(
                  value: frac,
                  onChanged: (v) => p.seek(
                    Duration(milliseconds: (v * dur.inMilliseconds).round()),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
