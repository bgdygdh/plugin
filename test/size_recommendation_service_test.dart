import 'package:body_measurement_plugin/src/models/body_lines.dart';
import 'package:body_measurement_plugin/src/models/size_recommendation.dart';
import 'package:body_measurement_plugin/src/services/size_recommendation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = SizeRecommendationService();

  group('SizeRecommendationService', () {
    test('returns valid garment categories based on gender', () {
      final femaleGarments = GarmentType.garmentsFor(Gender.female);
      expect(femaleGarments, contains(GarmentType.dress));
      expect(femaleGarments.length, 4);

      final maleGarments = GarmentType.garmentsFor(Gender.male);
      expect(maleGarments, isNot(contains(GarmentType.dress)));
      expect(maleGarments.length, 3);
    });

    test('recommends Medium for male T-shirt with 93.5cm chest (PH Asian fit: 90-97cm)', () {
      final result = service.recommend(
        gender: Gender.male,
        garment: GarmentType.tShirt,
        chestCm: 93.5,
        waistCm: 80.0,
        hipsCm: 96.0,
      );

      expect(result.recommendedSize, 'M');
      expect(result.partAssessments.first.fitType, SizeFitType.optimal);
      // T-shirt is 100% chest based, so only chest assessment is generated
      expect(result.partAssessments.length, 1);
      expect(result.partAssessments.first.kind, BodyLineKind.chest);
      expect(result.partAssessments.first.description, contains('Chest'));
    });

    test('T-shirt size is 100% driven by chest regardless of waist/hip variation', () {
      // Chest 93.5 cm (Size M: 90-97 cm)
      final withSmallWaist = service.recommend(
        gender: Gender.male,
        garment: GarmentType.tShirt,
        chestCm: 93.5,
        waistCm: 60.0, // extra small waist
        hipsCm: 80.0,
      );

      final withLargeWaist = service.recommend(
        gender: Gender.male,
        garment: GarmentType.tShirt,
        chestCm: 93.5,
        waistCm: 105.0, // large waist
        hipsCm: 115.0,
      );

      expect(withSmallWaist.recommendedSize, 'M');
      expect(withLargeWaist.recommendedSize, 'M');
    });

    test('recommends Large when chest is large even if waist is extra small', () {
      // Chest 100 cm is L (97-104 cm in PH sizing), Waist 68 cm is XS (66-71 cm)
      final result = service.recommend(
        gender: Gender.male,
        garment: GarmentType.tShirt,
        chestCm: 100.0,
        waistCm: 68.0,
        hipsCm: 85.0,
      );

      expect(result.recommendedSize, 'L');
    });

    test('recommends proper size for female dress considering all 3 dimensions', () {
      // Female PH sizing: Bust 91cm (M: 88-94), Waist 73cm (M: 70-76), Hips 97cm (M: 94-100)
      final result = service.recommend(
        gender: Gender.female,
        garment: GarmentType.dress,
        chestCm: 91.0,
        waistCm: 73.0,
        hipsCm: 97.0,
      );

      expect(result.recommendedSize, 'M');
      expect(result.partAssessments.length, 3);
      expect(result.partAssessments.first.description, contains('Bust'));
    });

    test('recommends sizing based on waist and hips for pants', () {
      // Male pants (PH sizing): Waist 87cm (L: 83-91), Hips 104cm (L: 101-108), Chest ignored
      final result = service.recommend(
        gender: Gender.male,
        garment: GarmentType.pants,
        chestCm: 80.0, // small chest
        waistCm: 87.0, // L waist
        hipsCm: 104.0, // L hips
      );

      expect(result.recommendedSize, 'L');
    });

    test('provides alternate size when near boundary', () {
      // Male chest 96.5 cm is near the upper bound of M (90-97 cm in PH sizing)
      final result = service.recommend(
        gender: Gender.male,
        garment: GarmentType.tShirt,
        chestCm: 96.5,
        waistCm: 80.0,
        hipsCm: 95.0,
      );

      expect(result.recommendedSize, 'M');
      expect(result.alternateSize, 'L');
      expect(result.alternateSizeReason, contains('looser'));
    });
  });
}
