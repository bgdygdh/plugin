import 'package:flutter/material.dart';
import '../models/capture_step.dart';
import '../models/pose_status.dart';

/// Draws a sleek, semi-translucent wireframe body silhouette over the camera preview.
/// The overlay acts as an ergonomic positioning guide for head-to-toe alignment.
class SilhouetteOverlayPainter extends CustomPainter {
  final CaptureStep step;
  final PoseStatus poseStatus;

  SilhouetteOverlayPainter({
    required this.step,
    required this.poseStatus,
  });

  Color get _overlayColor {
    switch (poseStatus) {
      case PoseStatus.poor:
        return const Color(0xFFFF4D4D); // Crisp neon coral/red
      case PoseStatus.fair:
        return const Color(0xFFFFCC00); // Warm amber yellow
      case PoseStatus.ready:
        return const Color(0xFF44FF88); // Neon green
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final color = _overlayColor;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.90)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..style = PaintingStyle.fill;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // Safe bounds: below top prompt bar and above bottom controls
    final top = size.height * 0.145;
    final bottom = size.height * 0.805;
    final height = bottom - top;
    final cx = size.width * 0.5;

    if (step == CaptureStep.front) {
      _drawFrontSilhouette(canvas, cx, top, bottom, height, paint, fillPaint, glowPaint);
    } else {
      _drawSideSilhouette(canvas, cx, top, bottom, height, paint, fillPaint, glowPaint);
    }

    _drawGuideBrackets(canvas, cx, top, bottom, height, color);
  }

  void _drawFrontSilhouette(
    Canvas canvas,
    double cx,
    double top,
    double bottom,
    double h,
    Paint paint,
    Paint fillPaint,
    Paint glowPaint,
  ) {
    // ── 1. HEAD ─────────────────────────────────────────────────────────────
    final headCy = top + h * 0.065;
    final headRx = h * 0.042;
    final headRy = h * 0.054;
    final headRect = Rect.fromCenter(
      center: Offset(cx, headCy),
      width: headRx * 2,
      height: headRy * 2,
    );
    final headPath = Path()..addOval(headRect);
    canvas.drawPath(headPath, glowPaint);
    canvas.drawPath(headPath, fillPaint);
    canvas.drawPath(headPath, paint);

    // ── 2. TORSO & LEGS (Single clean continuous path) ──────────────────────
    final body = Path();

    // Neck left
    body.moveTo(cx - h * 0.022, top + h * 0.120);

    // Left shoulder slope
    body.quadraticBezierTo(
      cx - h * 0.060, top + h * 0.138,
      cx - h * 0.125, top + h * 0.158,
    );

    // Left armpit / upper chest
    body.quadraticBezierTo(
      cx - h * 0.105, top + h * 0.185,
      cx - h * 0.090, top + h * 0.225,
    );

    // Left waist inward curve
    body.quadraticBezierTo(
      cx - h * 0.082, top + h * 0.290,
      cx - h * 0.076, top + h * 0.355,
    );

    // Left hip flare
    body.quadraticBezierTo(
      cx - h * 0.076, top + h * 0.410,
      cx - h * 0.098, top + h * 0.465,
    );

    // Left outer thigh to knee
    body.quadraticBezierTo(
      cx - h * 0.096, top + h * 0.550,
      cx - h * 0.082, top + h * 0.650,
    );

    // Left outer calf to ankle
    body.quadraticBezierTo(
      cx - h * 0.078, top + h * 0.730,
      cx - h * 0.068, bottom,
    );

    // Left foot base
    body.lineTo(cx - h * 0.032, bottom);

    // Left inner ankle to inner knee
    body.quadraticBezierTo(
      cx - h * 0.034, top + h * 0.730,
      cx - h * 0.032, top + h * 0.650,
    );

    // Left inner thigh up to crotch / inseam
    body.quadraticBezierTo(
      cx - h * 0.028, top + h * 0.550,
      cx, top + h * 0.495,
    );

    // Right inner thigh down to inner knee
    body.quadraticBezierTo(
      cx + h * 0.028, top + h * 0.550,
      cx + h * 0.032, top + h * 0.650,
    );

    // Right inner calf to foot
    body.quadraticBezierTo(
      cx + h * 0.034, top + h * 0.730,
      cx + h * 0.032, bottom,
    );

    // Right foot base
    body.lineTo(cx + h * 0.068, bottom);

    // Right outer calf from ankle to knee
    body.quadraticBezierTo(
      cx + h * 0.078, top + h * 0.730,
      cx + h * 0.082, top + h * 0.650,
    );

    // Right outer thigh to hip
    body.quadraticBezierTo(
      cx + h * 0.096, top + h * 0.550,
      cx + h * 0.098, top + h * 0.465,
    );

    // Right waist inward curve
    body.quadraticBezierTo(
      cx + h * 0.076, top + h * 0.410,
      cx + h * 0.076, top + h * 0.355,
    );

    // Right upper chest / armpit
    body.quadraticBezierTo(
      cx + h * 0.082, top + h * 0.290,
      cx + h * 0.090, top + h * 0.225,
    );

    // Right shoulder slope
    body.quadraticBezierTo(
      cx + h * 0.105, top + h * 0.185,
      cx + h * 0.125, top + h * 0.158,
    );

    // Neck right
    body.quadraticBezierTo(
      cx + h * 0.060, top + h * 0.138,
      cx + h * 0.022, top + h * 0.120,
    );

    body.close();

    canvas.drawPath(body, glowPaint);
    canvas.drawPath(body, fillPaint);
    canvas.drawPath(body, paint);

    // ── 3. ARMS (Slightly away from torso — A-pose) ─────────────────────────
    _drawFrontArm(canvas, cx, top, h, isLeft: true, paint: paint, fillPaint: fillPaint, glowPaint: glowPaint);
    _drawFrontArm(canvas, cx, top, h, isLeft: false, paint: paint, fillPaint: fillPaint, glowPaint: glowPaint);
  }

  void _drawFrontArm(
    Canvas canvas,
    double cx,
    double top,
    double h, {
    required bool isLeft,
    required Paint paint,
    required Paint fillPaint,
    required Paint glowPaint,
  }) {
    final sign = isLeft ? -1.0 : 1.0;
    final arm = Path();

    // Shoulder joint start
    arm.moveTo(cx + sign * h * 0.125, top + h * 0.158);

    // Outer arm down to elbow
    arm.quadraticBezierTo(
      cx + sign * h * 0.142, top + h * 0.240,
      cx + sign * h * 0.146, top + h * 0.335,
    );

    // Outer forearm to hand
    arm.quadraticBezierTo(
      cx + sign * h * 0.148, top + h * 0.420,
      cx + sign * h * 0.142, top + h * 0.525,
    );

    // Rounded hand tip
    arm.quadraticBezierTo(
      cx + sign * h * 0.132, top + h * 0.540,
      cx + sign * h * 0.122, top + h * 0.525,
    );

    // Inner forearm up to elbow
    arm.quadraticBezierTo(
      cx + sign * h * 0.125, top + h * 0.420,
      cx + sign * h * 0.122, top + h * 0.335,
    );

    // Inner arm up to armpit
    arm.quadraticBezierTo(
      cx + sign * h * 0.116, top + h * 0.240,
      cx + sign * h * 0.096, top + h * 0.210,
    );

    arm.close();

    canvas.drawPath(arm, glowPaint);
    canvas.drawPath(arm, fillPaint);
    canvas.drawPath(arm, paint);
  }

  void _drawSideSilhouette(
    Canvas canvas,
    double cx,
    double top,
    double bottom,
    double h,
    Paint paint,
    Paint fillPaint,
    Paint glowPaint,
  ) {
    // ── 1. HEAD (Profile with subtle face direction to the right) ───────────
    final headCy = top + h * 0.065;
    final headRx = h * 0.046;
    final headRy = h * 0.054;
    final headRect = Rect.fromCenter(
      center: Offset(cx + h * 0.005, headCy),
      width: headRx * 2,
      height: headRy * 2,
    );
    final headPath = Path()..addOval(headRect);
    canvas.drawPath(headPath, glowPaint);
    canvas.drawPath(headPath, fillPaint);
    canvas.drawPath(headPath, paint);

    // ── 2. SIDE BODY (Profile torso and legs) ───────────────────────────────
    final body = Path();

    // Start back of neck
    body.moveTo(cx - h * 0.022, top + h * 0.122);

    // Upper back / shoulder blade curve
    body.quadraticBezierTo(
      cx - h * 0.048, top + h * 0.180,
      cx - h * 0.045, top + h * 0.260,
    );

    // Lower back inward curve (lordosis)
    body.quadraticBezierTo(
      cx - h * 0.040, top + h * 0.340,
      cx - h * 0.034, top + h * 0.400,
    );

    // Gluteus outward curve
    body.quadraticBezierTo(
      cx - h * 0.060, top + h * 0.460,
      cx - h * 0.045, top + h * 0.520,
    );

    // Hamstring down to back of knee
    body.quadraticBezierTo(
      cx - h * 0.035, top + h * 0.590,
      cx - h * 0.028, top + h * 0.660,
    );

    // Calf curve down to heel
    body.quadraticBezierTo(
      cx - h * 0.036, top + h * 0.730,
      cx - h * 0.026, bottom,
    );

    // Foot sole pointing right
    body.lineTo(cx + h * 0.052, bottom);

    // Toe tip curve to top of shoe
    body.quadraticBezierTo(
      cx + h * 0.058, bottom - h * 0.015,
      cx + h * 0.038, bottom - h * 0.028,
    );

    // Shin up to knee
    body.quadraticBezierTo(
      cx + h * 0.030, top + h * 0.740,
      cx + h * 0.036, top + h * 0.650,
    );

    // Front thigh up to hip
    body.quadraticBezierTo(
      cx + h * 0.042, top + h * 0.570,
      cx + h * 0.040, top + h * 0.480,
    );

    // Lower abdomen / waist front
    body.quadraticBezierTo(
      cx + h * 0.035, top + h * 0.400,
      cx + h * 0.042, top + h * 0.320,
    );

    // Chest outward curve
    body.quadraticBezierTo(
      cx + h * 0.058, top + h * 0.240,
      cx + h * 0.046, top + h * 0.180,
    );

    // Front of neck
    body.quadraticBezierTo(
      cx + h * 0.025, top + h * 0.145,
      cx + h * 0.018, top + h * 0.122,
    );

    body.close();

    canvas.drawPath(body, glowPaint);
    canvas.drawPath(body, fillPaint);
    canvas.drawPath(body, paint);

    // ── 3. ARM IN SIDE PROFILE (Resting naturally at side) ───────────────────
    final arm = Path();
    arm.moveTo(cx, top + h * 0.175);
    arm.quadraticBezierTo(
      cx + h * 0.008, top + h * 0.300,
      cx + h * 0.004, top + h * 0.480,
    );
    arm.quadraticBezierTo(
      cx - h * 0.012, top + h * 0.485,
      cx - h * 0.014, top + h * 0.460,
    );
    arm.quadraticBezierTo(
      cx - h * 0.012, top + h * 0.300,
      cx - h * 0.016, top + h * 0.185,
    );
    arm.close();

    canvas.drawPath(arm, glowPaint);
    canvas.drawPath(arm, fillPaint);
    canvas.drawPath(arm, paint);
  }

  /// Draws sleek, minimalist target bracket guides for head and feet.
  void _drawGuideBrackets(
    Canvas canvas,
    double cx,
    double top,
    double bottom,
    double h,
    Color color,
  ) {
    final bracketPaint = Paint()
      ..color = color.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final bracketW = h * 0.18;
    final bracketH = 14.0;

    // Top Head bracket (corner brackets: ┌    ┐)
    final topY = top - 4.0;
    // Top-left corner
    final topLeft = Path()
      ..moveTo(cx - bracketW, topY + bracketH)
      ..lineTo(cx - bracketW, topY)
      ..lineTo(cx - bracketW + 24, topY);
    canvas.drawPath(topLeft, bracketPaint);

    // Top-right corner
    final topRight = Path()
      ..moveTo(cx + bracketW, topY + bracketH)
      ..lineTo(cx + bracketW, topY)
      ..lineTo(cx + bracketW - 24, topY);
    canvas.drawPath(topRight, bracketPaint);

    // Bottom Feet bracket (corner brackets: └    ┘)
    final botY = bottom + 6.0;
    // Bottom-left corner
    final botLeft = Path()
      ..moveTo(cx - bracketW, botY - bracketH)
      ..lineTo(cx - bracketW, botY)
      ..lineTo(cx - bracketW + 24, botY);
    canvas.drawPath(botLeft, bracketPaint);

    // Bottom-right corner
    final botRight = Path()
      ..moveTo(cx + bracketW, botY - bracketH)
      ..lineTo(cx + bracketW, botY)
      ..lineTo(cx + bracketW - 24, botY);
    canvas.drawPath(botRight, bracketPaint);
  }

  @override
  bool shouldRepaint(SilhouetteOverlayPainter oldDelegate) =>
      oldDelegate.step != step || oldDelegate.poseStatus != poseStatus;
}
