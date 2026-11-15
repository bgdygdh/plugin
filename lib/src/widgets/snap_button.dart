import 'package:flutter/material.dart';

/// Animated bottom-anchored snap / shutter button.
/// Disabled (greyed) when [enabled] is false.
/// Pulses with a glow when ready.
class SnapButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback onSnap;

  const SnapButton({
    super.key,
    required this.enabled,
    required this.onSnap,
  });

  @override
  State<SnapButton> createState() => _SnapButtonState();
}

class _SnapButtonState extends State<SnapButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulse;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.enabled
        ? const Color(0xFFFF3B3B)
        : Colors.white24;
    final glowColor = widget.enabled
        ? const Color(0xFFFF3B3B).withValues(alpha: 0.45)
        : Colors.transparent;

    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) {
        final scaleVal = widget.enabled ? _scale.value : 1.0;
        return Transform.scale(
          scale: scaleVal,
          child: GestureDetector(
            onTap: widget.enabled ? widget.onSnap : null,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: glowColor,
                    blurRadius: 20,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Container(
                margin: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
