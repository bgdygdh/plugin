import 'body_lines.dart';
import 'body_part_measurement.dart';
import 'scale_calibration_result.dart';
import 'size_recommendation.dart';
import 'virtual_try_on.dart';

/// The result returned to the host app after both photos are captured,
/// confirmed, and the height -> scale calibration has been computed.
class BodyCaptureResult {
  /// Absolute file path to the captured front-view image.
  final String frontImagePath;

  /// Absolute file path to the captured side-view image.
  final String sideImagePath;

  /// The calibration (height -> cm per pixel) computed from the front photo.
  final ScaleCalibrationResult calibration;

  /// The confirmed measurements for chest, waist, and hips (if reviewed).
  final Map<BodyLineKind, BodyPartMeasurement>? measurements;

  /// The rule-based size recommendation result (if accepted).
  final SizeRecommendationResult? recommendation;

  /// The user's selected gender (male or female).
  final Gender? gender;

  /// The virtual try-on result generated via Fashn AI (if run).
  final VirtualTryOnResult? tryOnResult;

  const BodyCaptureResult({
    required this.frontImagePath,
    required this.sideImagePath,
    required this.calibration,
    this.measurements,
    this.recommendation,
    this.gender,
    this.tryOnResult,
  });

  /// The real height the user entered, in centimetres.
  double get userHeightCm => calibration.userHeightCm;

  /// Head-to-toe height in the front photo, in pixels.
  double get frontPixelHeight => calibration.frontPixelHeight;

  /// THE final scale: centimetres per pixel (front photo).
  double get cmPerPixel => calibration.cmPerPixel;

  /// The same scale expressed as pixels per centimetre.
  double get pixelsPerCm => calibration.pixelsPerCm;

  /// The formula with real numbers, e.g. `175 cm ÷ 1,400 px = 0.1250 cm/px`.
  String get formula => calibration.formula;

  /// Absolute file path to the cutout PNG of the person with background removed, if available.
  String? get cutoutImagePath => calibration.cutoutImagePath;

  @override
  String toString() => 'BodyCaptureResult(front: $frontImagePath, '
      'side: $sideImagePath, $calibration)';
}
