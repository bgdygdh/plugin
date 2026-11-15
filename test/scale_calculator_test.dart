import 'package:body_measurement_plugin/body_measurement_plugin.dart';
import 'package:body_measurement_plugin/src/services/scale_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScaleCalculator.calculate', () {
    test('175 cm over 1400 px gives 0.125 cm/px and 8 px/cm', () {
      final result = ScaleCalculator.calculate(
        userHeightCm: 175,
        headTopY: 240,
        feetBottomY: 1640,
        imageWidth: 1080,
        imageHeight: 1920,
      );

      expect(result.frontPixelHeight, 1400);
      expect(result.cmPerPixel, closeTo(0.125, 1e-12));
      expect(result.pixelsPerCm, closeTo(8.0, 1e-12));
      // The two forms of the scale are exact inverses of each other.
      expect(result.cmPerPixel * result.pixelsPerCm, closeTo(1.0, 1e-12));
    });

    test('formula text contains the real numbers', () {
      final result = ScaleCalculator.calculate(
        userHeightCm: 175,
        headTopY: 240,
        feetBottomY: 1640,
        imageWidth: 1080,
        imageHeight: 1920,
      );

      expect(result.formula, '175 cm ÷ 1,400 px = 0.1250 cm/px');
    });

    test('decimal heights are shown with one decimal', () {
      final result = ScaleCalculator.calculate(
        userHeightCm: 162.5,
        headTopY: 100,
        feetBottomY: 1300,
        imageWidth: 720,
        imageHeight: 1400,
      );

      expect(result.formula, startsWith('162.5 cm ÷ 1,200 px'));
    });

    test('a waist measured in pixels converts to the right centimetres', () {
      final result = ScaleCalculator.calculate(
        userHeightCm: 175,
        headTopY: 240,
        feetBottomY: 1640,
        imageWidth: 1080,
        imageHeight: 1920,
      );

      // 256 px wide waist * 0.125 cm/px = 32 cm
      expect(256 * result.cmPerPixel, closeTo(32.0, 1e-9));
    });

    test('side height is reported as a ratio of the front height', () {
      final result = ScaleCalculator.calculate(
        userHeightCm: 175,
        headTopY: 240,
        feetBottomY: 1640,
        imageWidth: 1080,
        imageHeight: 1920,
        sidePixelHeight: 1330,
      );

      expect(result.sidePixelHeight, 1330);
      expect(result.sideToFrontHeightRatio, closeTo(0.95, 1e-12));
    });

    test('side ratio is null when the side photo was not measured', () {
      final result = ScaleCalculator.calculate(
        userHeightCm: 175,
        headTopY: 240,
        feetBottomY: 1640,
        imageWidth: 1080,
        imageHeight: 1920,
      );

      expect(result.sidePixelHeight, isNull);
      expect(result.sideToFrontHeightRatio, isNull);
    });

    test('rejects heights outside 100-250 cm', () {
      for (final bad in [0.0, 99.9, 250.1, -170.0, double.nan, double.infinity]) {
        expect(
          () => ScaleCalculator.calculate(
            userHeightCm: bad,
            headTopY: 240,
            feetBottomY: 1640,
            imageWidth: 1080,
            imageHeight: 1920,
          ),
          throwsA(isA<ScaleCalibrationException>()),
          reason: 'height $bad should be rejected',
        );
      }
    });

    test('accepts the boundary heights 100 and 250 cm', () {
      for (final ok in [100.0, 250.0]) {
        expect(
          () => ScaleCalculator.calculate(
            userHeightCm: ok,
            headTopY: 240,
            feetBottomY: 1640,
            imageWidth: 1080,
            imageHeight: 1920,
          ),
          returnsNormally,
        );
      }
    });

    test('rejects feet above the head', () {
      expect(
        () => ScaleCalculator.calculate(
          userHeightCm: 175,
          headTopY: 1640,
          feetBottomY: 240,
          imageWidth: 1080,
          imageHeight: 1920,
        ),
        throwsA(isA<ScaleCalibrationException>()),
      );
    });

    test('rejects equal head and feet positions', () {
      expect(
        () => ScaleCalculator.calculate(
          userHeightCm: 175,
          headTopY: 500,
          feetBottomY: 500,
          imageWidth: 1080,
          imageHeight: 1920,
        ),
        throwsA(isA<ScaleCalibrationException>()),
      );
    });

    test('rejects a body that extends outside the photo', () {
      expect(
        () => ScaleCalculator.calculate(
          userHeightCm: 175,
          headTopY: -10,
          feetBottomY: 1640,
          imageWidth: 1080,
          imageHeight: 1920,
        ),
        throwsA(isA<ScaleCalibrationException>()),
      );
      expect(
        () => ScaleCalculator.calculate(
          userHeightCm: 175,
          headTopY: 240,
          feetBottomY: 1930,
          imageWidth: 1080,
          imageHeight: 1920,
        ),
        throwsA(isA<ScaleCalibrationException>()),
      );
    });

    test('rejects a person who is too small in the photo', () {
      // 300 px of a 1920 px photo = 15.6% < 35% minimum.
      expect(
        () => ScaleCalculator.calculate(
          userHeightCm: 175,
          headTopY: 800,
          feetBottomY: 1100,
          imageWidth: 1080,
          imageHeight: 1920,
        ),
        throwsA(isA<ScaleCalibrationException>()),
      );
    });

    test('rejects non-finite positions and empty images', () {
      expect(
        () => ScaleCalculator.calculate(
          userHeightCm: 175,
          headTopY: double.nan,
          feetBottomY: 1640,
          imageWidth: 1080,
          imageHeight: 1920,
        ),
        throwsA(isA<ScaleCalibrationException>()),
      );
      expect(
        () => ScaleCalculator.calculate(
          userHeightCm: 175,
          headTopY: 240,
          feetBottomY: 1640,
          imageWidth: 0,
          imageHeight: 1920,
        ),
        throwsA(isA<ScaleCalibrationException>()),
      );
    });

    test('warnings list is unmodifiable', () {
      final result = ScaleCalculator.calculate(
        userHeightCm: 175,
        headTopY: 240,
        feetBottomY: 1640,
        imageWidth: 1080,
        imageHeight: 1920,
        warnings: ['a note'],
      );

      expect(result.warnings, ['a note']);
      expect(() => result.warnings.add('x'), throwsUnsupportedError);
    });
    test('preserves cutoutImagePath when provided', () {
      final result = ScaleCalculator.calculate(
        userHeightCm: 175,
        headTopY: 240,
        feetBottomY: 1640,
        imageWidth: 1080,
        imageHeight: 1920,
        cutoutImagePath: '/tmp/cutout.png',
      );

      expect(result.cutoutImagePath, '/tmp/cutout.png');
    });

    test('manual adjustment updates pixel height and scale correctly', () {
      final initial = ScaleCalculator.calculate(
        userHeightCm: 175,
        headTopY: 240,
        feetBottomY: 1640,
        imageWidth: 1080,
        imageHeight: 1920,
      );
      expect(initial.frontPixelHeight, 1400);

      // User drags head up by 50 px and feet down by 50 px -> +100 px total
      final adjusted = ScaleCalculator.calculate(
        userHeightCm: 175,
        headTopY: 190,
        feetBottomY: 1690,
        imageWidth: 1080,
        imageHeight: 1920,
      );
      expect(adjusted.frontPixelHeight, 1500);
      expect(adjusted.cmPerPixel, closeTo(175 / 1500, 1e-12));
      expect(adjusted.pixelsPerCm, closeTo(1500 / 175, 1e-12));
    });
  });

  group('BodyCaptureResult', () {
    test('exposes the calibration values and cutout image path', () {
      final calibration = ScaleCalculator.calculate(
        userHeightCm: 175,
        headTopY: 240,
        feetBottomY: 1640,
        imageWidth: 1080,
        imageHeight: 1920,
        cutoutImagePath: '/tmp/cutout.png',
      );
      final result = BodyCaptureResult(
        frontImagePath: '/tmp/front.jpg',
        sideImagePath: '/tmp/side.jpg',
        calibration: calibration,
      );

      expect(result.userHeightCm, 175);
      expect(result.frontPixelHeight, 1400);
      expect(result.cmPerPixel, closeTo(0.125, 1e-12));
      expect(result.pixelsPerCm, closeTo(8.0, 1e-12));
      expect(result.formula, '175 cm ÷ 1,400 px = 0.1250 cm/px');
      expect(result.cutoutImagePath, '/tmp/cutout.png');
    });
  });
}
