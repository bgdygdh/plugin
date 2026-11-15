import 'package:body_measurement_plugin/src/models/scale_calibration_exception.dart';
import 'package:body_measurement_plugin/src/services/person_mask_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PersonMaskAnalyzer', () {
    const analyzer = PersonMaskAnalyzer(threshold: 0.5, gapTolerance: 2);

    test('measures head top and feet bottom on synthetic person mask', () {
      const width = 100;
      const height = 200;
      final mask = List<double>.filled(width * height, 0.0);

      // Person from y=30 to y=180, centered around x=50, width ~20
      for (var y = 30; y <= 180; y++) {
        for (var x = 40; x <= 60; x++) {
          mask[y * width + x] = 1.0;
        }
      }

      const anchors = BodyAnchors(
        noseX: 50,
        noseY: 42,
        shoulderWidth: 30,
        footXs: [45, 55],
        lowestFootY: 175,
        lowestAnkleY: 170,
      );

      final extent = analyzer.measure(
        confidences: mask,
        width: width,
        height: height,
        anchors: anchors,
      );

      expect(extent.topRow, 30);
      expect(extent.bottomRowExclusive, 181);
      expect(extent.heightPx, 151);
      expect(extent.topTouchesImageEdge, isFalse);
      expect(extent.bottomTouchesImageEdge, isFalse);
    });

    test('bridges small gaps within gapTolerance', () {
      const width = 100;
      const height = 200;
      final mask = List<double>.filled(width * height, 0.0);

      // Person from y=30 to y=180, with a 1-row gap at y=40
      for (var y = 30; y <= 180; y++) {
        if (y == 40) continue; // 1-row gap
        for (var x = 40; x <= 60; x++) {
          mask[y * width + x] = 1.0;
        }
      }

      const anchors = BodyAnchors(
        noseX: 50,
        noseY: 42,
        shoulderWidth: 30,
        footXs: [45, 55],
        lowestFootY: 175,
        lowestAnkleY: 170,
      );

      final extent = analyzer.measure(
        confidences: mask,
        width: width,
        height: height,
        anchors: anchors,
      );

      expect(extent.topRow, 30);
      expect(extent.bottomRowExclusive, 181);
    });

    test('stops before disconnected blob when gap exceeds tolerance', () {
      const width = 100;
      const height = 200;
      final mask = List<double>.filled(width * height, 0.0);

      // Noise blob at y=10..15
      for (var y = 10; y <= 15; y++) {
        for (var x = 45; x <= 55; x++) {
          mask[y * width + x] = 1.0;
        }
      }

      // Real person from y=35 to y=170 (gap from 15 to 35 is 19 rows > gapTolerance)
      for (var y = 35; y <= 170; y++) {
        for (var x = 40; x <= 60; x++) {
          mask[y * width + x] = 1.0;
        }
      }

      const anchors = BodyAnchors(
        noseX: 50,
        noseY: 45,
        shoulderWidth: 30,
        footXs: [45, 55],
        lowestFootY: 165,
        lowestAnkleY: 160,
      );

      final extent = analyzer.measure(
        confidences: mask,
        width: width,
        height: height,
        anchors: anchors,
      );

      expect(extent.topRow, 35);
    });

    test('detects top and bottom touching image edges', () {
      const width = 100;
      const height = 200;
      final mask = List<double>.filled(width * height, 0.0);

      // Person touches both y=0 and y=199
      for (var y = 0; y < height; y++) {
        for (var x = 40; x <= 60; x++) {
          mask[y * width + x] = 1.0;
        }
      }

      const anchors = BodyAnchors(
        noseX: 50,
        noseY: 15,
        shoulderWidth: 30,
        footXs: [50],
        lowestFootY: 195,
        lowestAnkleY: 185,
      );

      final extent = analyzer.measure(
        confidences: mask,
        width: width,
        height: height,
        anchors: anchors,
      );

      expect(extent.topRow, 0);
      expect(extent.bottomRowExclusive, 200);
      expect(extent.topTouchesImageEdge, isTrue);
      expect(extent.bottomTouchesImageEdge, isTrue);
    });

    test('throws ScaleCalibrationException when mask dimensions mismatch', () {
      expect(
        () => analyzer.measure(
          confidences: [0.1, 0.2],
          width: 10,
          height: 10,
          anchors: const BodyAnchors(
            noseX: 5,
            noseY: 2,
            shoulderWidth: 4,
            footXs: [5],
            lowestFootY: 9,
            lowestAnkleY: 8,
          ),
        ),
        throwsA(isA<ScaleCalibrationException>()),
      );
    });

    test('throws ScaleCalibrationException when body scale is too small', () {
      const width = 100;
      const height = 200;
      final mask = List<double>.filled(width * height, 0.0);

      // nose at 50, ankle at 60 -> bodyScale = 10 < height * 0.2 (40)
      const anchors = BodyAnchors(
        noseX: 50,
        noseY: 50,
        shoulderWidth: 10,
        footXs: [50],
        lowestFootY: 65,
        lowestAnkleY: 60,
      );

      expect(
        () => analyzer.measure(
          confidences: mask,
          width: width,
          height: height,
          anchors: anchors,
        ),
        throwsA(isA<ScaleCalibrationException>()),
      );
    });

    test('throws ScaleCalibrationException when footXs is empty', () {
      const width = 100;
      const height = 200;
      final mask = List<double>.filled(width * height, 0.0);

      const anchors = BodyAnchors(
        noseX: 50,
        noseY: 30,
        shoulderWidth: 20,
        footXs: [],
        lowestFootY: 180,
        lowestAnkleY: 170,
      );

      expect(
        () => analyzer.measure(
          confidences: mask,
          width: width,
          height: height,
          anchors: anchors,
        ),
        throwsA(isA<ScaleCalibrationException>()),
      );
    });

    test('throws ScaleCalibrationException when head cannot be found', () {
      const width = 100;
      const height = 200;
      // All 0 mask - no person pixels
      final mask = List<double>.filled(width * height, 0.0);

      const anchors = BodyAnchors(
        noseX: 50,
        noseY: 30,
        shoulderWidth: 20,
        footXs: [50],
        lowestFootY: 180,
        lowestAnkleY: 170,
      );

      expect(
        () => analyzer.measure(
          confidences: mask,
          width: width,
          height: height,
          anchors: anchors,
        ),
        throwsA(isA<ScaleCalibrationException>()),
      );
    });
  });
}
