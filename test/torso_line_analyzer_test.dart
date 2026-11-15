import 'dart:math' as math;

import 'package:body_measurement_plugin/src/models/body_lines.dart';
import 'package:body_measurement_plugin/src/services/torso_line_analyzer.dart';
import 'package:flutter_test/flutter_test.dart';

const int _frontW = 400;
const int _frontH = 800;

/// Synthetic front-view person: head, neck, torso (narrowest at y=330),
/// optional arms glued to the torso down to y=380, and two legs.
List<double> _frontMask({bool arms = false}) {
  final m = List<double>.filled(_frontW * _frontH, 0.0);
  void fill(int y, int x0, int x1) {
    for (var x = x0; x < x1; x++) {
      m[y * _frontW + x] = 1.0;
    }
  }

  for (var y = 40; y < 140; y++) {
    fill(y, 170, 230);
  }
  for (var y = 140; y < 200; y++) {
    fill(y, 185, 215);
  }
  for (var y = 200; y <= 520; y++) {
    final hw = 38 + math.min((y - 330).abs() * 0.3, 17);
    fill(y, (200 - hw).round(), (200 + hw).round());
    if (arms && y <= 380) {
      fill(y, (200 - hw - 25).round(), (200 + hw + 25).round());
    }
  }
  for (var y = 521; y <= 760; y++) {
    fill(y, 160, 195);
    fill(y, 205, 240);
  }
  return m;
}

const TorsoLandmarks _frontLandmarks = TorsoLandmarks(
  shoulderCenterX: 200,
  shoulderY: 200,
  shoulderWidth: 120,
  hipCenterX: 200,
  hipY: 400,
  hipSpan: 60,
);

void main() {
  const analyzer = TorsoLineAnalyzer();

  group('analyzeFront', () {
    test('places chest, waist and hips at the expected heights', () {
      final result = analyzer.analyzeFront(
        confidences: _frontMask(),
        width: _frontW,
        height: _frontH,
        landmarks: _frontLandmarks,
      );
      final lines = result.view.lines;
      expect(lines.map((l) => l.kind), BodyLineKind.values);

      final chest = lines[0];
      final waist = lines[1];
      final hips = lines[2];

      // Armpit level: 22% down from the shoulders.
      expect(chest.y, closeTo(244, 1));
      // Narrowest torso row.
      expect(waist.y, closeTo(330, 6));
      // Widest row, closest to the typical hip height.
      expect(hips.y, closeTo(416, 6));

      expect(chest.xEnd - chest.xStart, closeTo(110, 3));
      expect(waist.xEnd - waist.xStart, closeTo(76, 4));
      expect(hips.xEnd - hips.xStart, closeTo(110, 3));

      // Lines are ordered top to bottom.
      expect(chest.y, lessThan(waist.y));
      expect(waist.y, lessThan(hips.y));
    });

    test('keeps arms glued to the torso out of the chest line', () {
      final result = analyzer.analyzeFront(
        confidences: _frontMask(arms: true),
        width: _frontW,
        height: _frontH,
        landmarks: _frontLandmarks,
      );
      final chest = result.view.lines.first;
      final width = chest.xEnd - chest.xStart;

      // The torso is 110 px wide; with arms the silhouette is 160 px wide.
      expect(width, greaterThanOrEqualTo(100));
      expect(width, lessThanOrEqualTo(116));
      // Centred on the body.
      expect((chest.xStart + chest.xEnd) / 2, closeTo(200, 3));
    });

    test('keeps hands/arms near hips out of the hip line', () {
      final maskWithArmAtHip = _frontMask();
      // Add a hand artifact / bridge at hip level y=410..430 at x=120..145 and x=255..280
      for (var y = 410; y <= 430; y++) {
        for (var x = 120; x <= 145; x++) {
          maskWithArmAtHip[y * _frontW + x] = 1.0;
        }
        for (var x = 255; x <= 280; x++) {
          maskWithArmAtHip[y * _frontW + x] = 1.0;
        }
      }

      final result = analyzer.analyzeFront(
        confidences: maskWithArmAtHip,
        width: _frontW,
        height: _frontH,
        landmarks: const TorsoLandmarks(
          shoulderCenterX: 200,
          shoulderY: 200,
          shoulderWidth: 120,
          hipCenterX: 200,
          hipY: 400,
          hipSpan: 60,
          leftArmInnerX: 145,
          rightArmInnerX: 255,
        ),
      );
      final hips = result.view.lines[2];
      expect(hips.xStart, greaterThanOrEqualTo(145));
      expect(hips.xEnd, lessThanOrEqualTo(256));
    });

    test('exposes fractions for reuse on the side photo', () {
      final result = analyzer.analyzeFront(
        confidences: _frontMask(),
        width: _frontW,
        height: _frontH,
        landmarks: _frontLandmarks,
      );
      expect(result.fractions[BodyLineKind.chest],
          TorsoLineAnalyzer.chestFraction);
      expect(result.fractions[BodyLineKind.waist]!, closeTo(0.65, 0.04));
      expect(result.fractions[BodyLineKind.hips]!, closeTo(1.08, 0.04));
    });

    test('profiles let a dragged line re-snap to the body outline', () {
      final result = analyzer.analyzeFront(
        confidences: _frontMask(),
        width: _frontW,
        height: _frontH,
        landmarks: _frontLandmarks,
      );
      final profile = result.view.profiles[BodyLineKind.waist]!;

      final atWaist = profile.edgesAt(330)!;
      final atHips = profile.edgesAt(420)!;
      expect(atWaist.end - atWaist.start, lessThan(atHips.end - atHips.start));

      // Outside the covered band there is nothing to snap to.
      expect(profile.edgesAt(50), isNull);
      expect(profile.edgesAt(profile.lastRow + 50.0), isNull);
    });

    test('throws when the mask size does not match', () {
      expect(
        () => analyzer.analyzeFront(
          confidences: List<double>.filled(10, 1.0),
          width: _frontW,
          height: _frontH,
          landmarks: _frontLandmarks,
        ),
        throwsA(isA<BodyLinesException>()),
      );
    });

    test('throws when shoulders and hips are implausibly close', () {
      expect(
        () => analyzer.analyzeFront(
          confidences: _frontMask(),
          width: _frontW,
          height: _frontH,
          landmarks: const TorsoLandmarks(
            shoulderCenterX: 200,
            shoulderY: 200,
            shoulderWidth: 120,
            hipCenterX: 200,
            hipY: 210,
            hipSpan: 60,
          ),
        ),
        throwsA(isA<BodyLinesException>()),
      );
    });
  });

  group('analyzeSide', () {
    const sideW = 300;
    const sideH = 800;

    List<double> sideMask() {
      final m = List<double>.filled(sideW * sideH, 0.0);
      for (var y = 200; y <= 520; y++) {
        for (var x = 100; x < 170; x++) {
          m[y * sideW + x] = 1.0;
        }
      }
      return m;
    }

    test('measures the depth at the same anatomical heights', () {
      final view = analyzer.analyzeSide(
        confidences: sideMask(),
        width: sideW,
        height: sideH,
        shoulderY: 200,
        hipY: 400,
        fractions: const {
          BodyLineKind.chest: 0.22,
          BodyLineKind.waist: 0.62,
          BodyLineKind.hips: 1.08,
        },
      );
      expect(view.lines.map((l) => l.kind), BodyLineKind.values);
      expect(view.lines[0].y, closeTo(244, 1));
      expect(view.lines[1].y, closeTo(324, 1));
      expect(view.lines[2].y, closeTo(416, 1));
      for (final line in view.lines) {
        expect(line.xStart, closeTo(100, 1));
        expect(line.xEnd, closeTo(170, 1));
      }
    });

    test('throws when no torso is found', () {
      expect(
        () => analyzer.analyzeSide(
          confidences: List<double>.filled(sideW * sideH, 0.0),
          width: sideW,
          height: sideH,
          shoulderY: 200,
          hipY: 400,
          fractions: const {},
        ),
        throwsA(isA<BodyLinesException>()),
      );
    });
  });

  group('personRowExtent', () {
    test('finds the first and last rows with a person', () {
      final extent = analyzer.personRowExtent(
        confidences: _frontMask(),
        width: _frontW,
        height: _frontH,
      );
      expect(extent, isNotNull);
      expect(extent!.top, 40);
      expect(extent.bottom, 760);
    });

    test('returns null for an empty mask', () {
      expect(
        analyzer.personRowExtent(
          confidences: List<double>.filled(_frontW * _frontH, 0.0),
          width: _frontW,
          height: _frontH,
        ),
        isNull,
      );
    });
  });
}
