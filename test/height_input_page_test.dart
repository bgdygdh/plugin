import 'package:body_measurement_plugin/src/models/size_recommendation.dart';
import 'package:body_measurement_plugin/src/ui/height_input_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HeightInputPage', () {
    testWidgets('renders initial height in cm and submits valid value with gender',
        (WidgetTester tester) async {
      UserBioProfile? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<UserBioProfile>(
                    MaterialPageRoute(
                      builder: (_) => const HeightInputPage(
                        initialHeightCm: 175,
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

      // Open page
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Check pre-filled value
      expect(find.text('175'), findsOneWidget);

      // Tap Continue
      await tester.tap(find.byKey(const Key('height_continue_button')));
      await tester.pumpAndSettle();

      expect(result, const UserBioProfile(heightCm: 175.0, gender: Gender.male));
    });

    testWidgets('allows selecting female gender',
        (WidgetTester tester) async {
      UserBioProfile? result;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<UserBioProfile>(
                    MaterialPageRoute(
                      builder: (_) => const HeightInputPage(
                        initialHeightCm: 165,
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

      // Open page
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Tap Female
      await tester.tap(find.byKey(const Key('gender_select_female')));
      await tester.pumpAndSettle();

      // Tap Continue
      await tester.tap(find.byKey(const Key('height_continue_button')));
      await tester.pumpAndSettle();

      expect(result, const UserBioProfile(heightCm: 165.0, gender: Gender.female));
    });

    testWidgets('validates height range and shows error message',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const HeightInputPage(initialHeightCm: 170),
        ),
      );

      // Enter an invalid height (e.g. 50 cm)
      final textField = find.byType(TextField);
      await tester.enterText(textField, '50');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('height_continue_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Height must be between 100 cm and 250 cm'),
          findsOneWidget);
    });

    testWidgets('unit toggle converts value to feet/inches',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const HeightInputPage(initialHeightCm: 180),
        ),
      );

      // Switch to FT · IN
      await tester.tap(find.byKey(const Key('unit_ftin')));
      await tester.pumpAndSettle();

      // 180 cm ≈ 5 ft 11 in (71 inches)
      expect(find.text('5'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
    });
  });
}
