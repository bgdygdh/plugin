import 'dart:math' as math;

import '../models/body_lines.dart';

/// Calculates body circumferences from 2D flat widths and depths.
///
/// Uses Ramanujan's 2nd Formula (1914) for the baseline ellipse perimeter,
/// combined with standard ISO anthropometric shape factors to account for
/// the non-elliptical curvature of the human body (flatter back, pectorals,
/// and gluteal projection).
class CircumferenceCalculator {
  const CircumferenceCalculator._();

  /// Anthropometric shape factors (K) calibrated to standard 3D anthropometric
  /// datasets and physical measuring tapes:
  /// - Waist: almost purely elliptical (~1.5% adjustment).
  /// - Chest: ribcage, pectorals, lats, and flat back (~3.5% adjustment).
  /// - Hips: gluteal projection (~5.0% adjustment).
  static const double waistShapeFactor = 1.015;
  static const double chestShapeFactor = 1.035;
  static const double hipsShapeFactor = 1.050;

  /// Returns the shape factor $K$ for a given body line kind.
  static double shapeFactorFor(BodyLineKind kind) => switch (kind) {
        BodyLineKind.chest => chestShapeFactor,
        BodyLineKind.waist => waistShapeFactor,
        BodyLineKind.hips => hipsShapeFactor,
      };

  /// Calculates the Ramanujan (2nd formula) perimeter of an ellipse with
  /// total width [widthCm] and total depth [depthCm].
  ///
  /// Semi-major axis $a = \text{width} / 2$, semi-minor axis $b = \text{depth} / 2$.
  /// $$h = ((a - b) / (a + b))^2$$
  /// $$P = \pi (a + b) (1 + 3h / (10 + \sqrt{4 - 3h}))$$
  static double calculateBaseEllipse(double widthCm, double depthCm) {
    if (widthCm <= 0 || depthCm <= 0 || !widthCm.isFinite || !depthCm.isFinite) {
      return 0.0;
    }
    final a = widthCm / 2.0;
    final b = depthCm / 2.0;
    final sum = a + b;
    final diff = a - b;
    final h = (diff * diff) / (sum * sum);
    final denom = 10.0 + math.sqrt(4.0 - 3.0 * h);
    return math.pi * sum * (1.0 + (3.0 * h) / denom);
  }

  /// Calculates the final anthropometrically-adjusted circumference (in cm).
  static double calculateCircumference(
    BodyLineKind kind,
    double widthCm,
    double depthCm,
  ) {
    final base = calculateBaseEllipse(widthCm, depthCm);
    final k = shapeFactorFor(kind);
    return base * k;
  }

  /// Converts centimeters to inches (1 in = 2.54 cm).
  static double cmToInches(double cm) => cm / 2.54;
}
