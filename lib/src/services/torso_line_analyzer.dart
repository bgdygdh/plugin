import 'dart:math' as math;

import '../models/body_lines.dart';

/// Torso landmarks of the FRONT photo, in MASK pixel coordinates.
class TorsoLandmarks {
  final double shoulderCenterX;
  final double shoulderY;

  /// Distance between the two shoulder landmarks.
  final double shoulderWidth;

  final double hipCenterX;
  final double hipY;

  /// Distance between the two hip landmarks.
  final double hipSpan;

  /// Innermost hand / wrist landmark X on the left side of the torso (if visible).
  final double? leftArmInnerX;

  /// Innermost hand / wrist landmark X on the right side of the torso (if visible).
  final double? rightArmInnerX;

  const TorsoLandmarks({
    required this.shoulderCenterX,
    required this.shoulderY,
    required this.shoulderWidth,
    required this.hipCenterX,
    required this.hipY,
    required this.hipSpan,
    this.leftArmInnerX,
    this.rightArmInnerX,
  });
}

/// Front lines plus where each one sits on the torso, so the SIDE photo can
/// reuse the same anatomical heights.
class FrontLinesAnalysis {
  final BodyLinesView view;

  /// Position of each line as a fraction of the shoulder-to-hip distance
  /// (0 = shoulder level, 1 = hip landmark level).
  final Map<BodyLineKind, double> fractions;

  const FrontLinesAnalysis({required this.view, required this.fractions});
}

/// Places the chest, waist and hip lines on a person segmentation mask.
///
/// The key idea to keep the shoulders and arms OUT of the chest line:
///
///  * Heights come from pose landmarks (shoulder-to-hip distance), not from
///    the mask: the armpit level is ~22% of the way from the shoulders to the
///    hips, the waist is the narrowest torso row, the hips are the widest row.
///  * Widths are scanned OUTWARD from the body's centre line and are capped to
///    a "torso corridor" derived from the shoulder / hip landmarks, so arms
///    hanging against the body can never stretch a line past the torso.
class TorsoLineAnalyzer {
  /// Mask confidence needed to count a pixel as "person".
  final double threshold;

  /// Empty pixels tolerated while scanning outward before the edge is declared.
  final int gapTolerance;

  const TorsoLineAnalyzer({this.threshold = 0.5, this.gapTolerance = 3});

  /// Armpit (axilla) level as a fraction of shoulder-to-hip distance.
  static const double chestFraction = 0.22;

  static const double _waistMin = 0.48;
  static const double _waistMax = 0.78;
  static const double _waistPreferred = 0.62;

  static const double _hipsMin = 0.98;
  static const double _hipsMax = 1.15;
  static const double _hipsPreferred = 1.06;

  /// Band of rows (as torso fractions) covered by the drag profiles.
  static const double _bandTop = 0.05;
  static const double _bandBottom = 1.30;

  /// Front view: body WIDTH at chest, waist and hips.
  FrontLinesAnalysis analyzeFront({
    required List<double> confidences,
    required int width,
    required int height,
    required TorsoLandmarks landmarks,
  }) {
    _validateMask(confidences, width, height);
    final lm = landmarks;
    final torso = lm.hipY - lm.shoulderY;
    if (!torso.isFinite || torso < height * 0.08) {
      throw const BodyLinesException(
        'We could not tell where your shoulders and hips are in the front '
        'photo. Stand straight, facing the camera, and retake it.',
      );
    }
    if (!lm.shoulderWidth.isFinite || lm.shoulderWidth <= 0) {
      throw const BodyLinesException(
        'We could not measure your shoulders in the front photo. '
        'Please retake it.',
      );
    }

    // Half-width of the "torso corridor" per level. Anything further from the
    // centre line than this is treated as arm / background.
    final s = lm.shoulderWidth;
    final halves = <BodyLineKind, double>{
      BodyLineKind.chest: 0.46 * s,
      BodyLineKind.waist: math.max(0.42 * s, 0.95 * lm.hipSpan),
      BodyLineKind.hips: math.min(0.48 * s, math.max(0.42 * s, 0.96 * lm.hipSpan)),
    };

    double centerAt(double y) {
      final t = ((y - lm.shoulderY) / torso).clamp(0.0, 1.0);
      return lm.shoulderCenterX + (lm.hipCenterX - lm.shoulderCenterX) * t;
    }

    final firstRow = _clampInt(
      (lm.shoulderY + _bandTop * torso).round(),
      0,
      height - 1,
    );
    final lastRow = _clampInt(
      (lm.shoulderY + _bandBottom * torso).round(),
      firstRow,
      height - 1,
    );

    final profiles = <BodyLineKind, EdgeProfile>{
      for (final kind in BodyLineKind.values)
        kind: _buildProfile(
          confidences: confidences,
          width: width,
          firstRow: firstRow,
          lastRow: lastRow,
          centerAt: centerAt,
          halfWidth: halves[kind]!,
          leftBound: kind == BodyLineKind.hips ? lm.leftArmInnerX : null,
          rightBound: kind == BodyLineKind.hips ? lm.rightArmInnerX : null,
          customGapTolerance: kind == BodyLineKind.hips ? 1 : null,
        ),
    };

    final chestY = lm.shoulderY + chestFraction * torso;
    final waistY = _findWaistY(profiles[BodyLineKind.waist]!, lm.shoulderY, torso);
    final hipsY = _findHipsY(profiles[BodyLineKind.hips]!, lm.shoulderY, torso);

    BodyLine lineFor(BodyLineKind kind, double y) {
      final snapped = profiles[kind]!.edgesAt(y);
      if (snapped != null) {
        return BodyLine(
          kind: kind,
          y: y,
          xStart: snapped.start,
          xEnd: snapped.end,
        );
      }
      // No body found on that row: still show a sensible line.
      final c = centerAt(y);
      final h = halves[kind]! * 0.8;
      var start = c - h;
      var end = c + h;
      if (kind == BodyLineKind.hips) {
        if (lm.leftArmInnerX != null && lm.leftArmInnerX! < c) {
          start = math.max(start, lm.leftArmInnerX!);
        }
        if (lm.rightArmInnerX != null && lm.rightArmInnerX! > c) {
          end = math.min(end, lm.rightArmInnerX!);
        }
      }
      return BodyLine(kind: kind, y: y, xStart: start, xEnd: end);
    }

    return FrontLinesAnalysis(
      view: BodyLinesView(
        width: width,
        height: height,
        lines: [
          lineFor(BodyLineKind.chest, chestY),
          lineFor(BodyLineKind.waist, waistY),
          lineFor(BodyLineKind.hips, hipsY),
        ],
        profiles: profiles,
      ),
      fractions: {
        BodyLineKind.chest: chestFraction,
        BodyLineKind.waist: (waistY - lm.shoulderY) / torso,
        BodyLineKind.hips: (hipsY - lm.shoulderY) / torso,
      },
    );
  }

  /// Side view: body DEPTH (front to back) at the same anatomical heights as
  /// the front view ([fractions]).
  BodyLinesView analyzeSide({
    required List<double> confidences,
    required int width,
    required int height,
    required double shoulderY,
    required double hipY,
    required Map<BodyLineKind, double> fractions,
  }) {
    _validateMask(confidences, width, height);
    final torso = hipY - shoulderY;
    if (!torso.isFinite || torso < height * 0.08) {
      throw const BodyLinesException(
        'We could not tell where your shoulders and hips are in the side '
        'photo. Stand straight, side-on to the camera, and retake it.',
      );
    }

    final firstRow = _clampInt(
      (shoulderY + _bandTop * torso).round(),
      0,
      height - 1,
    );
    final lastRow = _clampInt(
      (shoulderY + _bandBottom * torso).round(),
      firstRow,
      height - 1,
    );

    // Centre of the body = average X of all person pixels between the
    // shoulders and the hips.
    final bodyTop = _clampInt(shoulderY.round(), 0, height - 1);
    final bodyBottom = _clampInt(hipY.round(), bodyTop, height - 1);
    var sumX = 0.0;
    var count = 0;
    for (var y = bodyTop; y <= bodyBottom; y++) {
      final base = y * width;
      for (var x = 0; x < width; x++) {
        if (confidences[base + x] >= threshold) {
          sumX += x;
          count++;
        }
      }
    }
    if (count < 50) {
      throw const BodyLinesException(
        'We could not find your torso in the side photo. Make sure you are '
        'well lit and fully in the frame, then retake it.',
      );
    }
    final centerX = sumX / count;

    final profile = _buildProfile(
      confidences: confidences,
      width: width,
      firstRow: firstRow,
      lastRow: lastRow,
      centerAt: (_) => centerX,
      halfWidth: 0.6 * torso,
    );

    BodyLine lineFor(BodyLineKind kind) {
      final fraction = fractions[kind] ?? chestFraction;
      final y = (shoulderY + fraction * torso)
          .clamp(firstRow.toDouble(), lastRow.toDouble());
      final snapped = profile.edgesAt(y);
      if (snapped != null) {
        return BodyLine(
          kind: kind,
          y: y,
          xStart: snapped.start,
          xEnd: snapped.end,
        );
      }
      final h = 0.2 * torso;
      return BodyLine(kind: kind, y: y, xStart: centerX - h, xEnd: centerX + h);
    }

    return BodyLinesView(
      width: width,
      height: height,
      lines: [for (final kind in BodyLineKind.values) lineFor(kind)],
      profiles: {for (final kind in BodyLineKind.values) kind: profile},
    );
  }

  /// First and last mask row that clearly contains a person, or `null`.
  /// Used only as a rough fallback when the side pose is not detected.
  ({int top, int bottom})? personRowExtent({
    required List<double> confidences,
    required int width,
    required int height,
    double minConfidence = 0.68,
  }) {
    if (width <= 0 || height <= 0 || confidences.length != width * height) {
      return null;
    }
    final minCount = math.max(2, (width * 0.01).round());
    int? top;
    int? bottom;
    for (var y = 0; y < height; y++) {
      final base = y * width;
      var count = 0;
      for (var x = 0; x < width; x++) {
        if (confidences[base + x] >= minConfidence) {
          count++;
          if (count >= minCount) break;
        }
      }
      if (count >= minCount) {
        top ??= y;
        bottom = y;
      }
    }
    if (top == null || bottom == null) return null;
    return (top: top, bottom: bottom);
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  /// Narrowest torso row in the waist band, gently biased toward the typical
  /// natural-waist height so noise cannot pull the line far away.
  double _findWaistY(EdgeProfile profile, double shoulderY, double torso) {
    final from = (shoulderY + _waistMin * torso).ceil();
    final to = (shoulderY + _waistMax * torso).floor();
    double? bestY;
    var bestScore = double.infinity;
    for (var row = from; row <= to; row++) {
      final w = _smoothedWidth(profile, row, 3);
      if (w == null) continue;
      final t = (row - shoulderY) / torso;
      final score = w * (1 + 2 * (t - _waistPreferred) * (t - _waistPreferred));
      if (score < bestScore) {
        bestScore = score;
        bestY = row.toDouble();
      }
    }
    return bestY ?? (shoulderY + _waistPreferred * torso);
  }

  /// Widest row in the hip band; among near-equally wide rows the one closest
  /// to the typical hip height wins.
  double _findHipsY(EdgeProfile profile, double shoulderY, double torso) {
    final from = (shoulderY + _hipsMin * torso).ceil();
    final to = (shoulderY + _hipsMax * torso).floor();
    final widths = <int, double>{};
    var maxWidth = 0.0;
    for (var row = from; row <= to; row++) {
      final w = _smoothedWidth(profile, row, 3);
      if (w == null) continue;
      widths[row] = w;
      if (w > maxWidth) maxWidth = w;
    }
    if (widths.isEmpty) return shoulderY + _hipsPreferred * torso;

    final preferredRow = shoulderY + _hipsPreferred * torso;
    int? bestRow;
    var bestDistance = double.infinity;
    widths.forEach((row, w) {
      if (w >= maxWidth * 0.98) {
        final d = (row - preferredRow).abs();
        if (d < bestDistance) {
          bestDistance = d;
          bestRow = row;
        }
      }
    });
    return (bestRow ?? preferredRow.round()).toDouble();
  }

  /// Width at [row] averaged with its neighbours (±[radius] rows) to ignore
  /// single noisy rows. `null` if [row] itself has no body.
  double? _smoothedWidth(EdgeProfile profile, int row, int radius) {
    if (profile.edgesAt(row.toDouble()) == null) return null;
    var sum = 0.0;
    var n = 0;
    for (var r = row - radius; r <= row + radius; r++) {
      final e = profile.edgesAt(r.toDouble());
      if (e == null) continue;
      sum += e.end - e.start;
      n++;
    }
    return n == 0 ? null : sum / n;
  }

  EdgeProfile _buildProfile({
    required List<double> confidences,
    required int width,
    required int firstRow,
    required int lastRow,
    required double Function(double y) centerAt,
    required double halfWidth,
    double? leftBound,
    double? rightBound,
    int? customGapTolerance,
  }) {
    final rows = lastRow - firstRow + 1;
    final left = List<double>.filled(rows, double.nan);
    final right = List<double>.filled(rows, double.nan);
    for (var i = 0; i < rows; i++) {
      final y = firstRow + i;
      final edges = _scanRow(
        confidences: confidences,
        width: width,
        y: y,
        center: centerAt(y.toDouble()),
        halfWidth: halfWidth,
        leftBound: leftBound,
        rightBound: rightBound,
        customGapTolerance: customGapTolerance,
      );
      if (edges != null) {
        left[i] = edges.start;
        right[i] = edges.end;
      }
    }
    return EdgeProfile(firstRow: firstRow, left: left, right: right);
  }

  /// Walks outward from [center] on row [y], never further than [halfWidth],
  /// and returns the left/right edge of the person run found there.
  ({double start, double end})? _scanRow({
    required List<double> confidences,
    required int width,
    required int y,
    required double center,
    required double halfWidth,
    double? leftBound,
    double? rightBound,
    int? customGapTolerance,
  }) {
    var limitLeft = _clampInt((center - halfWidth).floor(), 0, width - 1);
    var limitRight = _clampInt((center + halfWidth).ceil(), limitLeft, width - 1);

    if (leftBound != null && leftBound < center) {
      final minTorsoHalf = 0.35 * halfWidth;
      final effectiveBound = math.min(leftBound, center - minTorsoHalf);
      limitLeft = math.max(limitLeft, effectiveBound.round());
    }
    if (rightBound != null && rightBound > center) {
      final minTorsoHalf = 0.35 * halfWidth;
      final effectiveBound = math.max(rightBound, center + minTorsoHalf);
      limitRight = math.min(limitRight, effectiveBound.round());
    }
    if (limitLeft > limitRight) return null;

    final c = _clampInt(center.round(), limitLeft, limitRight);
    final base = y * width;
    final tol = customGapTolerance ?? gapTolerance;

    // Seed: the person pixel closest to the centre line.
    int? seed;
    final maxOffset = math.max(c - limitLeft, limitRight - c);
    for (var d = 0; d <= maxOffset; d++) {
      if (c - d >= limitLeft && confidences[base + c - d] >= threshold) {
        seed = c - d;
        break;
      }
      if (c + d <= limitRight && confidences[base + c + d] >= threshold) {
        seed = c + d;
        break;
      }
    }
    if (seed == null) return null;

    var left = seed;
    var misses = 0;
    for (var x = seed - 1; x >= limitLeft; x--) {
      if (confidences[base + x] >= threshold) {
        left = x;
        misses = 0;
      } else if (++misses > tol) {
        break;
      }
    }

    var right = seed;
    misses = 0;
    for (var x = seed + 1; x <= limitRight; x++) {
      if (confidences[base + x] >= threshold) {
        right = x;
        misses = 0;
      } else if (++misses > tol) {
        break;
      }
    }

    return (start: left.toDouble(), end: (right + 1).toDouble());
  }

  static void _validateMask(List<double> confidences, int width, int height) {
    if (width <= 0 || height <= 0 || confidences.length != width * height) {
      throw const BodyLinesException(
        'The person mask could not be read. Please retake the photos.',
      );
    }
  }

  static int _clampInt(int value, int low, int high) =>
      math.min(math.max(value, low), high);
}
