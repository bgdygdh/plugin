import 'package:flutter/material.dart';

/// A vertical bubble-level indicator displayed on the right edge of the screen.
/// The bubble moves up/down based on [tiltRatio] and turns green when level.
class TiltIndicatorWidget extends StatelessWidget {
  /// Normalised tilt value: -1.0 (tilted back) to +1.0 (tilted toward user).
  /// 0.0 = perfectly level (phone upright, perpendicular to ground).
  final double tiltRatio;

  /// Whether the tilt is within the accepted threshold.
  final bool isLevel;

  const TiltIndicatorWidget({
    super.key,
    required this.tiltRatio,
    required this.isLevel,
  });

  @override
  Widget build(BuildContext context) {
    final trackH = 140.0;
    final bubbleR = 14.0;
    final usableH = trackH - bubbleR * 2;

    // Map tiltRatio [-1, 1] → bubble Y within track [0, usableH]
    // 0 tilt → centre of track
    final bubbleOffset = (tiltRatio * 0.5 + 0.5) * usableH;

    final bubbleColor = isLevel ? const Color(0xFF44FF88) : const Color(0xFFFFCC00);
    final trackColor = Colors.white.withValues(alpha: 0.15);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "90°" label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '90°',
            style: TextStyle(
              color: bubbleColor,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 6),
        // Track + bubble
        Container(
          width: 28,
          height: trackH,
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: Stack(
            children: [
              // Centre target line
              Positioned(
                left: 6,
                right: 6,
                top: trackH / 2 - 1,
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
              // Bubble
              AnimatedPositioned(
                duration: const Duration(milliseconds: 80),
                curve: Curves.easeOut,
                left: (28 - bubbleR * 2) / 2,
                top: bubbleOffset.clamp(0, usableH),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: bubbleR * 2,
                  height: bubbleR * 2,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: bubbleColor,
                    boxShadow: [
                      BoxShadow(
                        color: bubbleColor.withValues(alpha: 0.7),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
