import 'package:body_measurement_plugin/src/models/body_lines.dart';
import 'package:body_measurement_plugin/src/models/body_part_measurement.dart';
import 'package:body_measurement_plugin/src/models/scale_calibration_result.dart';
import 'package:body_measurement_plugin/src/models/size_recommendation.dart';
import 'package:body_measurement_plugin/src/ui/size_recommendation_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const dummyCalibration = ScaleCalibrationResult(
    userHeightCm: 175.0,
    headTopY: 100.0,
    feetBottomY: 1100.0,
    imageWidth: 1080,
    imageHeight: 1920,
  );

  const measurements = <BodyLineKind, BodyPartMeasurement>{
    BodyLineKind.chest: BodyPartMeasurement(
      kind: BodyLineKind.chest,
      widthPx: 450,
      widthCm: 38,
      depthPx: 290,
      depthCm: 24,
      circumferenceCm: 100.5,
      circumferenceInches: 39.6,
      baseEllipseCm: 97.1,
      shapeFactor: 1.035,
    ),
    BodyLineKind.waist: BodyPartMeasurement(
      kind: BodyLineKind.waist,
      widthPx: 380,
      widthCm: 32,
      depthPx: 250,
      depthCm: 21,
      circumferenceCm: 84.0,
      circumferenceInches: 33.1,
      baseEllipseCm: 82.8,
      shapeFactor: 1.015,
    ),
    BodyLineKind.hips: BodyPartMeasurement(
      kind: BodyLineKind.hips,
      widthPx: 480,
      widthCm: 40,
      depthPx: 300,
      depthCm: 25,
      circumferenceCm: 104.0,
      circumferenceInches: 40.9,
      baseEllipseCm: 99.0,
      shapeFactor: 1.050,
    ),
  };

  testWidgets('SizeRecommendationPage locks to selected female profile with bust terminology',
      (tester) async {
    SizeRecommendationResult? accepted;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                accepted = await Navigator.of(context).push<SizeRecommendationResult>(
                  MaterialPageRoute(
                    builder: (_) => const SizeRecommendationPage(
                      measurements: measurements,
                      calibration: dummyCalibration,
                      initialGender: Gender.female,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    // Open page
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Verify page header and hero size badge
    expect(find.text('SIZE RECOMMENDATION'), findsOneWidget);
    expect(find.byKey(const Key('recommended_size_badge')), findsOneWidget);

    // Profile indicator shows female profile
    expect(find.byKey(const Key('gender_profile_indicator')), findsOneWidget);
    expect(find.text('FEMALE PROFILE'), findsOneWidget);
    expect(find.byKey(const Key('gender_tab_male')), findsNothing);

    // In female mode, dress tab exists and bust terminology is shown
    expect(find.byKey(const Key('garment_tab_dress')), findsOneWidget);
    expect(find.text('Bust'), findsWidgets);

    // Tap ACCEPT SIZE button
    await tester.tap(find.text('ACCEPT SIZE'));
    await tester.pumpAndSettle();

    // Check outcome
    expect(accepted, isNotNull);
    expect(accepted!.gender, Gender.female);
  });

  testWidgets('SizeRecommendationPage locks to selected male profile with chest terminology',
      (tester) async {
    SizeRecommendationResult? accepted;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                accepted = await Navigator.of(context).push<SizeRecommendationResult>(
                  MaterialPageRoute(
                    builder: (_) => const SizeRecommendationPage(
                      measurements: measurements,
                      calibration: dummyCalibration,
                      initialGender: Gender.male,
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Profile indicator shows male profile
    expect(find.byKey(const Key('gender_profile_indicator')), findsOneWidget);
    expect(find.text('MALE PROFILE'), findsOneWidget);
    expect(find.byKey(const Key('gender_tab_female')), findsNothing);

    // In male mode, dress tab does NOT exist and chest terminology is shown
    expect(find.byKey(const Key('garment_tab_dress')), findsNothing);
    expect(find.text('Chest'), findsWidgets);

    await tester.tap(find.text('ACCEPT SIZE'));
    await tester.pumpAndSettle();

    expect(accepted, isNotNull);
    expect(accepted!.gender, Gender.male);
  });
}
