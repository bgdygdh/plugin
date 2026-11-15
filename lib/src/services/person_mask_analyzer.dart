import 'dart:math' as math;

import '../models/scale_calibration_exception.dart';

/// Pose-derived reference points, expressed in MASK pixel coordinates
/// (x grows to the right, y grows downward).
///
/// They are only used to tell the analyzer WHERE to look (the head region and
/// the feet region). The actual edges always come from the segmentation mask.
class BodyAnchors {
  /// Nose (or eye-level fallback) position.
  final double noseX;
  final double noseY;

  /// Distance between the two shoulders, if both were detected.
  final double? shoulderWidth;

  /// X positions of the visible ankles / heels / toes.
  final List<double> footXs;

  /// Lowest (largest Y) of the visible ankle / heel / toe landmarks.
  final double lowestFootY;

  /// Lowest (largest Y) of the visible ankle landmarks.
  final double lowestAnkleY;

  const BodyAnchors({
    required this.noseX,
    required this.noseY,
    required this.shoulderWidth,
    required this.footXs,
    required this.lowestFootY,
    required this.lowestAnkleY,
  });

  /// Nose-to-ankle distance in pixels — a rough "body size" ruler used to
  /// scale all search distances. (Nose-to-ankle is about 88% of full height.)
  double get bodyScale => lowestAnkleY - noseY;
}

/// Where the person starts and ends vertically in the mask.
class HeightExtent {
  /// First row (inclusive) that contains the person — the top edge of the head.
  final int topRow;

  /// One past the last row that contains the person — the bottom edge of the feet.
  final int bottomRowExclusive;

  /// The person touches the top edge of the image (head probably cut off).
  final bool topTouchesImageEdge;

  /// The person touches the bottom edge of the image (feet probably cut off).
  final bool bottomTouchesImageEdge;

  /// The upward search hit its limit while still inside the mask
  /// (hair / hat / background may be merging with the head).
  final bool headSearchLimited;

  /// The downward search hit its limit while still inside the mask
  /// (floor shadow / reflection may be merging with the feet).
  final bool feetSearchLimited;

  const HeightExtent({
    required this.topRow,
    required this.bottomRowExclusive,
    required this.topTouchesImageEdge,
    required this.bottomTouchesImageEdge,
    required this.headSearchLimited,
    required this.feetSearchLimited,
  });

  /// Head-to-toe height in mask pixels.
  int get heightPx => bottomRowExclusive - topRow;
}

/// Finds the top of the head and the bottom of the feet inside a person
/// segmentation mask.
///
/// Instead of trusting "the first/last non-empty row of the whole mask"
/// (which breaks as soon as a ceiling light, a plant or a floor shadow is
/// wrongly included), it WALKS outward from pose landmarks:
///
///  * Head: start at the nose, walk UP while the narrow column band around
///    the head still contains person pixels.
///  * Feet: start at the lowest ankle/heel/toe landmark, walk DOWN while the
///    band around the feet still contains person pixels.
///
/// The walk stops at the first gap of more than [gapTolerance] empty rows, or
/// at a landmark-relative distance limit, so unrelated blobs are ignored.
class PersonMaskAnalyzer {
  /// Base mask pixel confidence threshold (0.0 to 1.0) for identifying body interior.
  final double threshold;

  /// Stricter threshold applied at the head and feet boundaries to filter
  /// out faint shadows on the floor and fuzzy wall background.
  final double boundaryThreshold;

  /// How many consecutive empty rows are tolerated before the walk stops.
  final int gapTolerance;

  const PersonMaskAnalyzer({
    this.threshold = 0.5,
    this.boundaryThreshold = 0.68,
    this.gapTolerance = 2,
  });

  /// Measures the vertical extent of the person.
  ///
  /// [confidences] is a row-major `width * height` mask. Throws a
  /// [ScaleCalibrationException] (with a user-facing message) if the person
  /// cannot be located reliably.
  HeightExtent measure({
    required List<double> confidences,
    required int width,
    required int height,
    required BodyAnchors anchors,
  }) {
    if (width <= 0 || height <= 0 || confidences.length != width * height) {
      throw const ScaleCalibrationException(
        'The person mask could not be read. Please retake the photo.',
      );
    }

    final bodyScale = anchors.bodyScale;
    if (!bodyScale.isFinite || bodyScale < height * 0.2) {
      throw const ScaleCalibrationException(
        'We could not see your whole body (head to ankles). '
        'Step back so your full body fits in the frame, then retake the photo.',
      );
    }
    if (anchors.footXs.isEmpty) {
      throw const ScaleCalibrationException(
        'We could not find your feet. Please retake the photo.',
      );
    }

    // ── HEAD ──────────────────────────────────────────────────────────────
    final headHalfWidth = math.max(
      (anchors.shoulderWidth ?? 0) * 0.35,
      bodyScale * 0.10,
    );
    final headX0 =
        _clampInt((anchors.noseX - headHalfWidth).floor(), 0, width - 1);
    final headX1 =
        _clampInt((anchors.noseX + headHalfWidth).ceil(), headX0 + 1, width);
    final headMinCount = _minCount(headX1 - headX0);

    final noseRow = _clampInt(anchors.noseY.round(), 0, height - 1);
    final headSearchDown = math.max(1, (bodyScale * 0.06).round());
    var headAnchorRow = -1;
    final headSearchEnd = math.min(height - 1, noseRow + headSearchDown);
    for (var y = noseRow; y <= headSearchEnd; y++) {
      if (_rowHas(confidences, width, y, headX0, headX1, headMinCount, threshold)) {
        headAnchorRow = y;
        break;
      }
    }
    if (headAnchorRow < 0) {
      throw const ScaleCalibrationException(
        'We could not find you clearly in the photo. Make sure you are well '
        'lit, in front of a plain background, then retake it.',
      );
    }

    // Anatomical skull crown ceiling: top of head is at most ~12.5% of bodyScale above nose.
    // Prevents wandering into lamps, wall fixtures, or ceiling.
    final headLimitRow =
        math.max(0, headAnchorRow - (bodyScale * 0.125).round());
    var top = headAnchorRow;
    var headMisses = 0;
    var headLimited = false;
    for (var y = headAnchorRow - 1; y >= 0; y--) {
      // Near the crown (further above the nose), narrow horizontal window and require boundaryThreshold
      // so wall objects to the left/right and faint ceiling bleed are excluded.
      final isNearCrown = y < headAnchorRow - (bodyScale * 0.05).round();
      final effectiveX0 = isNearCrown
          ? _clampInt((anchors.noseX - headHalfWidth * 0.75).floor(), 0, width - 1)
          : headX0;
      final effectiveX1 = isNearCrown
          ? _clampInt((anchors.noseX + headHalfWidth * 0.75).ceil(), effectiveX0 + 1, width)
          : headX1;
      final effectiveMinCount = _minCount(effectiveX1 - effectiveX0);
      final effectiveThreshold = isNearCrown ? boundaryThreshold : threshold;

      if (_rowHas(confidences, width, y, effectiveX0, effectiveX1, effectiveMinCount, effectiveThreshold)) {
        top = y;
        headMisses = 0;
        if (y <= headLimitRow) {
          headLimited = true;
          break;
        }
      } else if (++headMisses > gapTolerance) {
        break;
      }
    }

    // ── FEET ──────────────────────────────────────────────────────────────
    // Tighter horizontal margin to prevent floor shadows spreading sideways from being counted
    final footMargin = math.max(bodyScale * 0.045, width * 0.025);
    final minFootX = anchors.footXs.reduce(math.min);
    final maxFootX = anchors.footXs.reduce(math.max);
    final feetX0 = _clampInt((minFootX - footMargin).floor(), 0, width - 1);
    final feetX1 =
        _clampInt((maxFootX + footMargin).ceil(), feetX0 + 1, width);
    final feetMinCount = _minCount(feetX1 - feetX0);

    final footStartRow = _clampInt(anchors.lowestFootY.round(), 0, height - 1);
    final feetSearchUp = math.max(1, (bodyScale * 0.10).round());
    var feetAnchorRow = -1;
    final feetSearchEnd = math.max(0, footStartRow - feetSearchUp);
    for (var y = footStartRow; y >= feetSearchEnd; y--) {
      if (_rowHas(confidences, width, y, feetX0, feetX1, feetMinCount, threshold)) {
        feetAnchorRow = y;
        break;
      }
    }
    if (feetAnchorRow < 0) {
      throw const ScaleCalibrationException(
        'We could not find your feet in the photo. Make sure your feet are '
        'visible and the floor is clear, then retake it.',
      );
    }

    // Anatomical sole floor: shoe soles are at most ~3.8% of bodyScale below lowest foot landmark.
    // Anything below this is floor shadow or floor reflection.
    final feetLimitRow =
        math.min(height - 1, footStartRow + math.max(3, (bodyScale * 0.038).round()));
    var bottom = feetAnchorRow;
    var feetMisses = 0;
    var feetLimited = false;
    for (var y = feetAnchorRow + 1; y < height; y++) {
      // Below the heel landmark, enforce strict boundaryThreshold so faint floor shadows
      // (confidence 0.40 - 0.65) are cut off immediately.
      final isPastHeel = y > footStartRow;
      final effectiveThreshold = isPastHeel ? boundaryThreshold : threshold;

      if (_rowHas(confidences, width, y, feetX0, feetX1, feetMinCount, effectiveThreshold)) {
        bottom = y;
        feetMisses = 0;
        if (y >= feetLimitRow) {
          feetLimited = true;
          break;
        }
      } else if (++feetMisses > gapTolerance) {
        break;
      }
    }

    final bottomExclusive = bottom + 1;
    if (bottomExclusive <= top) {
      throw const ScaleCalibrationException(
        'Your head and feet could not be separated. Please retake the photo.',
      );
    }

    return HeightExtent(
      topRow: top,
      bottomRowExclusive: bottomExclusive,
      topTouchesImageEdge: top <= 0,
      bottomTouchesImageEdge: bottom >= height - 1,
      headSearchLimited: headLimited,
      feetSearchLimited: feetLimited,
    );
  }

  /// Minimum number of person pixels a row segment needs to count as
  /// "occupied" — ignores single stray noise pixels.
  static int _minCount(int bandWidth) =>
      math.max(2, (bandWidth * 0.01).round());

  static int _clampInt(int value, int low, int high) =>
      math.min(math.max(value, low), high);

  bool _rowHas(
    List<double> confidences,
    int width,
    int y,
    int x0,
    int x1,
    int minCount,
    double minConfidence,
  ) {
    final base = y * width;
    var count = 0;
    var peak = 0.0;
    for (var x = x0; x < x1; x++) {
      final c = confidences[base + x];
      if (c >= minConfidence) {
        count++;
        if (c > peak) peak = c;
        if (count >= minCount && peak >= minConfidence) return true;
      }
    }
    return false;
  }
}
