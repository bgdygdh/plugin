import 'dart:math' as math;

import 'package:body_measurement_plugin/src/models/body_lines.dart';
import 'package:body_measurement_plugin/src/services/circumference_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CircumferenceCalculator', () {
    test('computes exact circle perimeter when width equals depth', () {
      const diameter = 20.0;
      final perimeter = CircumferenceCalculator.calculateBaseEllipse(diameter, diameter);
      expect(perimeter, closeTo(diameter * math.pi, 1e-9));
    });

    test('returns 0 for non-positive or invalid dimensions', () {
      expect(CircumferenceCalculator.calculateBaseEllipse(0, 20), 0.0);
      expect(CircumferenceCalculator.calculateBaseEllipse(20, -5), 0.0);
      expect(CircumferenceCalculator.calculateBaseEllipse(double.nan, 20), 0.0);
    });

    test('computes accurate Ramanujan 2nd perimeter for typical torso aspect ratio', () {
      const width = 38.0;
      const depth = 24.0;
      final base = CircumferenceCalculator.calculateBaseEllipse(width, depth);

      // Pre-calculated mathematical Ramanujan 2nd value: ~98.636 cm
      expect(base, closeTo(98.636, 0.01));
    });

    test('applies distinct anthropometric shape factors per body part', () {
      const width = 38.0;
      const depth = 24.0;
      final base = CircumferenceCalculator.calculateBaseEllipse(width, depth);

      final chest = CircumferenceCalculator.calculateCircumference(
        BodyLineKind.chest,
        width,
        depth,
      );
      final waist = CircumferenceCalculator.calculateCircumference(
        BodyLineKind.waist,
        width,
        depth,
      );
      final hips = CircumferenceCalculator.calculateCircumference(
        BodyLineKind.hips,
        width,
        depth,
      );

      expect(chest, closeTo(base * 1.035, 1e-5));
      expect(waist, closeTo(base * 1.015, 1e-5));
      expect(hips, closeTo(base * 1.050, 1e-5));

      // Chest and hips are larger than waist for the same cross-section
      expect(hips, greaterThan(chest));
      expect(chest, greaterThan(waist));
      expect(waist, greaterThan(base));
    });

    test('converts centimeters to inches accurately', () {
      expect(CircumferenceCalculator.cmToInches(25.4), closeTo(10.0, 1e-9));
      expect(CircumferenceCalculator.cmToInches(101.6), closeTo(40.0, 1e-9));
    });
  });
}
