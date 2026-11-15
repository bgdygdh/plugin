import 'package:flutter/material.dart';
import '../models/pose_status.dart';

/// Bottom status bar showing alignment state and hint text.
class PoseFeedbackBar extends StatelessWidget {
  final PoseStatus poseStatus;
  final bool tiltOk;
  final bool canSnap;
  final int countdownSeconds;

  const PoseFeedbackBar({
    super.key,
    required this.poseStatus,
    required this.tiltOk,
    required this.canSnap,
    this.countdownSeconds = 0,
  });

  Color get _color {
    if (canSnap) return const Color(0xFF44FF88);
    if (poseStatus == PoseStatus.fair) return const Color(0xFFFFCC00);
    return const Color(0xFFFF4444);
  }

  String get _label {
    if (countdownSeconds > 0) return 'HOLD STILL — SNAPPING IN $countdownSeconds...';
    if (canSnap) return 'ALIGNMENT: READY | TAP TO SNAP';
    if (!tiltOk) return 'HOLD PHONE UPRIGHT AT 90°';
    if (poseStatus == PoseStatus.poor) return 'STEP BACK — FIT HEAD & FEET IN FRAME';
    return 'ALMOST THERE — ADJUST POSITION';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withValues(alpha: 0.5), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _color,
              boxShadow: [
                BoxShadow(
                  color: _color.withValues(alpha: 0.7),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 300),
            style: TextStyle(
              color: _color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
            child: Text(_label),
          ),
        ],
      ),
    );
  }
}
