import 'body_lines.dart';

/// Complete 2D flat and 3D circumference measurements for one anatomical level.
class BodyPartMeasurement {
  final BodyLineKind kind;

  /// Front width in full photo pixels.
  final double widthPx;

  /// Front width in real-world centimetres.
  final double widthCm;

  /// Side depth in full photo pixels.
  final double depthPx;

  /// Side depth in real-world centimetres.
  final double depthCm;

  /// Final anthropometrically-adjusted 3D circumference in centimetres.
  final double circumferenceCm;

  /// Final 3D circumference in inches.
  final double circumferenceInches;

  /// Baseline pure Ramanujan ellipse circumference before shape factor.
  final double baseEllipseCm;

  /// The shape factor ($K$) applied for this anatomical level.
  final double shapeFactor;

  const BodyPartMeasurement({
    required this.kind,
    required this.widthPx,
    required this.widthCm,
    required this.depthPx,
    required this.depthCm,
    required this.circumferenceCm,
    required this.circumferenceInches,
    required this.baseEllipseCm,
    required this.shapeFactor,
  });

  @override
  String toString() =>
      'BodyPartMeasurement(${kind.name}: ${circumferenceCm.toStringAsFixed(1)} cm / '
      '${circumferenceInches.toStringAsFixed(1)} in)';
}
