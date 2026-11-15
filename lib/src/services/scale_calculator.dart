import '../models/scale_calibration_exception.dart';
import '../models/scale_calibration_result.dart';

/// Pure math for the height -> scale conversion (no ML Kit, no Flutter).
///
/// ```
/// pixelHeight = feetBottomY - headTopY
/// cmPerPixel  = userHeightCm / pixelHeight
/// ```
class ScaleCalculator {
  const ScaleCalculator._();

  /// Smallest height (cm) we accept from the user.
  static const double minUserHeightCm = 100;

  /// Largest height (cm) we accept from the user.
  static const double maxUserHeightCm = 250;

  /// The person must fill at least this fraction of the photo height,
  /// otherwise one pixel is too coarse to reach the accuracy target.
  static const double minPersonHeightFraction = 0.35;

  /// Throws a [ScaleCalibrationException] if [heightCm] is not a usable height.
  static void validateUserHeight(double heightCm) {
    if (!heightCm.isFinite ||
        heightCm < minUserHeightCm ||
        heightCm > maxUserHeightCm) {
      throw const ScaleCalibrationException(
        'Height must be between 100 cm and 250 cm.',
      );
    }
  }

  /// Builds a [ScaleCalibrationResult] from the measured head/feet positions.
  ///
  /// [headTopY] is the top edge of the highest head pixel and [feetBottomY]
  /// is the bottom edge of the lowest foot pixel, both in photo pixels.
  static ScaleCalibrationResult calculate({
    required double userHeightCm,
    required double headTopY,
    required double feetBottomY,
    required int imageWidth,
    required int imageHeight,
    double? sidePixelHeight,
    String? cutoutImagePath,
    List<String> warnings = const [],
  }) {
    validateUserHeight(userHeightCm);

    if (imageWidth <= 0 || imageHeight <= 0) {
      throw const ScaleCalibrationException(
        'The photo could not be read. Please retake it.',
      );
    }
    if (!headTopY.isFinite || !feetBottomY.isFinite) {
      throw const ScaleCalibrationException(
        'Could not locate your head and feet. Please retake the photo.',
      );
    }
    if (feetBottomY <= headTopY) {
      throw const ScaleCalibrationException(
        'Your feet were detected above your head. Please retake the photo.',
      );
    }
    if (headTopY < 0 || feetBottomY > imageHeight + 0.5) {
      throw const ScaleCalibrationException(
        'Your body extends outside the photo. Step back and retake it.',
      );
    }

    final pixelHeight = feetBottomY - headTopY;
    if (pixelHeight < imageHeight * minPersonHeightFraction) {
      throw const ScaleCalibrationException(
        'You look too small in the photo. Move closer so your head-to-toe '
        'fills most of the screen, then retake it.',
      );
    }

    return ScaleCalibrationResult(
      userHeightCm: userHeightCm,
      headTopY: headTopY,
      feetBottomY: feetBottomY,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      sidePixelHeight: sidePixelHeight,
      cutoutImagePath: cutoutImagePath,
      warnings: List.unmodifiable(warnings),
    );
  }
}
