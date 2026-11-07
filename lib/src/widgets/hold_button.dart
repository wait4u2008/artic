import 'package:flutter/material.dart';

/// A button that requires a 3-second long press before [onComplete] fires.
/// Shows a circular progress ring while held; releasing early resets it.
class HoldButton extends StatefulWidget {
  const HoldButton({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );
  bool _holding = false;

  void _start() {
    setState(() => _holding = true);
    _controller.forward(from: 0).whenComplete(() {
      if (mounted && _holding) widget.onComplete();
    });
  }

  void _end() {
    _controller.stop();
    _controller.value = 0;
    if (_holding) setState(() => _holding = false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPressStart: (_) => _start(),
      onLongPressEnd: (_) => _end(),
      onLongPressCancel: _end,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return SizedBox(
                width: 110,
                height: 110,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 110,
                      height: 110,
                      child: CircularProgressIndicator(
                        value: _controller.value,
                        strokeWidth: 4,
                        backgroundColor: scheme.surfaceContainerHighest,
                        color: scheme.primary,
                      ),
                    ),
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _holding ? Icons.lock_open : Icons.lock_outline,
                        size: 36,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          Text(
            _holding ? 'Keep holding…' : 'Hold for 3 seconds',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
