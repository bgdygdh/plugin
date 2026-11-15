import '../utils/format.dart';

/// The outcome of the height -> scale calibration.
///
/// The ONE final scale is derived from the FRONT photo:
///
/// ```
/// frontPixelHeight = feetBottomY - headTopY
/// cmPerPixel       = userHeightCm / frontPixelHeight
/// pixelsPerCm      = frontPixelHeight / userHeightCm
/// ```
///
/// Every derived value is a getter computed from the three stored inputs, so
/// the numbers can never disagree with each other.
class ScaleCalibrationResult {
  /// The real height the user entered, in centimetres.
  final double userHeightCm;

  /// Y coordinate (pixels, top edge) of the highest point of the head
  /// in the front photo.
  final double headTopY;

  /// Y coordinate (pixels, bottom edge) of the lowest point of the feet
  /// in the front photo.
  final double feetBottomY;

  /// Width of the (upright) front photo in pixels.
  final int imageWidth;

  /// Height of the (upright) front photo in pixels.
  final int imageHeight;

  /// Head-to-toe height measured in the SIDE photo, in pixels.
  /// Diagnostic only — it is NOT used for [cmPerPixel]. `null` if the side
  /// photo could not be measured.
  final double? sidePixelHeight;

  /// Path to a cutout PNG of the person with the background removed,
  /// if available.
  final String? cutoutImagePath;

  /// Human-readable notes about anything that may reduce accuracy.
  final List<String> warnings;

  const ScaleCalibrationResult({
    required this.userHeightCm,
    required this.headTopY,
    required this.feetBottomY,
    required this.imageWidth,
    required this.imageHeight,
    this.sidePixelHeight,
    this.cutoutImagePath,
    this.warnings = const [],
  });

  /// Head-to-toe height of the person in the front photo, in pixels.
  double get frontPixelHeight => feetBottomY - headTopY;

  /// THE final scale: how many centimetres one pixel represents.
  double get cmPerPixel => userHeightCm / frontPixelHeight;

  /// The same scale expressed the other way round.
  double get pixelsPerCm => frontPixelHeight / userHeightCm;

  /// Side-photo height divided by front-photo height (1.0 = identical).
  double? get sideToFrontHeightRatio {
    final side = sidePixelHeight;
    return side == null ? null : side / frontPixelHeight;
  }

  /// The formula with the real numbers filled in, e.g.
  /// `175 cm ÷ 1,400 px = 0.1250 cm/px`.
  String get formula =>
      '${formatCm(userHeightCm)} cm ÷ ${formatPixels(frontPixelHeight)} px'
      ' = ${cmPerPixel.toStringAsFixed(4)} cm/px';

  @override
  String toString() => 'ScaleCalibrationResult($formula, '
      '${pixelsPerCm.toStringAsFixed(2)} px/cm, warnings: ${warnings.length})';
}
