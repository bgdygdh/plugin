import '../models/body_lines.dart';
import '../models/size_recommendation.dart';

/// Rule-based engine that compares body circumferences to standardized size charts
/// and selects the optimal garment size.
class SizeRecommendationService {
  const SizeRecommendationService();

  /// Recommends the best size for a garment based on gender and circumferences.
  SizeRecommendationResult recommend({
    required Gender gender,
    required GarmentType garment,
    required double chestCm,
    required double waistCm,
    required double hipsCm,
  }) {
    final chart = sizeChartFor(gender, garment);
    final weights = _weightsFor(garment);

    SizeRange? bestSize;
    var lowestPenalty = double.infinity;
    final scores = <SizeRange, double>{};

    for (final size in chart) {
      var penalty = 0.0;

      // Evaluate each body part against size bounds
      if (weights[BodyLineKind.chest]! > 0) {
        penalty += _dimensionPenalty(
              chestCm,
              size.minChestCm,
              size.maxChestCm,
              isPrimary: garment == GarmentType.tShirt || garment == GarmentType.dress,
            ) *
            weights[BodyLineKind.chest]!;
      }

      if (weights[BodyLineKind.waist]! > 0) {
        penalty += _dimensionPenalty(
              waistCm,
              size.minWaistCm,
              size.maxWaistCm,
              isPrimary: garment != GarmentType.tShirt,
            ) *
            weights[BodyLineKind.waist]!;
      }

      if (weights[BodyLineKind.hips]! > 0) {
        penalty += _dimensionPenalty(
              hipsCm,
              size.minHipsCm,
              size.maxHipsCm,
              isPrimary: garment == GarmentType.pants || garment == GarmentType.shorts,
            ) *
            weights[BodyLineKind.hips]!;
      }

      scores[size] = penalty;
      if (penalty < lowestPenalty) {
        lowestPenalty = penalty;
        bestSize = size;
      }
    }

    final chosen = bestSize ?? chart[(chart.length / 2).floor()];

    // Generate assessments per part for the chosen size
    final assessments = <PartFitAssessment>[];

    if (weights[BodyLineKind.chest]! > 0) {
      assessments.add(_assessPart(
        kind: BodyLineKind.chest,
        measuredCm: chestCm,
        minCm: chosen.minChestCm,
        maxCm: chosen.maxChestCm,
        gender: gender,
      ));
    }

    if (weights[BodyLineKind.waist]! > 0) {
      assessments.add(_assessPart(
        kind: BodyLineKind.waist,
        measuredCm: waistCm,
        minCm: chosen.minWaistCm,
        maxCm: chosen.maxWaistCm,
        gender: gender,
      ));
    }

    if (weights[BodyLineKind.hips]! > 0) {
      assessments.add(_assessPart(
        kind: BodyLineKind.hips,
        measuredCm: hipsCm,
        minCm: chosen.minHipsCm,
        maxCm: chosen.maxHipsCm,
        gender: gender,
      ));
    }

    // Determine alternate size (e.g., if between sizes)
    String? alternate;
    String? alternateReason;
    final chosenIndex = chart.indexOf(chosen);

    // Check if user is near the upper border (could size up for relaxed fit)
    final isSnug = assessments.any((a) => a.fitType == SizeFitType.snug);
    final isRelaxed = assessments.any((a) => a.fitType == SizeFitType.relaxed);

    if (isSnug && chosenIndex < chart.length - 1) {
      alternate = chart[chosenIndex + 1].label;
      alternateReason = 'Choose $alternate if you prefer a looser, more relaxed drape.';
    } else if (isRelaxed && chosenIndex > 0) {
      alternate = chart[chosenIndex - 1].label;
      alternateReason = 'Choose $alternate if you prefer a snug, fitted silhouette.';
    }

    // Build human-friendly summary
    final summary = _buildSummary(garment, chosen.label, assessments, gender);

    return SizeRecommendationResult(
      gender: gender,
      garment: garment,
      recommendedSize: chosen.label,
      partAssessments: assessments,
      fitSummary: summary,
      alternateSize: alternate,
      alternateSizeReason: alternateReason,
      fullChart: chart,
    );
  }

  // ── Penalty Calculation ───────────────────────────────────────────────────

  /// Computes fit penalty. Measurements exceeding the maximum range receive a
  /// steep penalty to enforce the "wearability-first" rule (too tight is unwearable).
  double _dimensionPenalty(
    double measured,
    double minRange,
    double maxRange, {
    required bool isPrimary,
  }) {
    if (measured >= minRange && measured <= maxRange) {
      final span = maxRange - minRange;
      final center = minRange + span / 2.0;
      final distFromCenter = (measured - center).abs();
      return (distFromCenter / (span / 2.0)) * 5.0; // 0 to 5 penalty inside range
    }

    if (measured > maxRange) {
      // Too tight penalty (very high if primary driver to force sizing up)
      final excess = measured - maxRange;
      final multiplier = isPrimary ? 25.0 : 15.0;
      return 30.0 + excess * multiplier;
    }

    // Too loose penalty (user can still wear it, but looser)
    final deficit = minRange - measured;
    return 15.0 + deficit * 6.0;
  }

  PartFitAssessment _assessPart({
    required BodyLineKind kind,
    required double measuredCm,
    required double minCm,
    required double maxCm,
    required Gender gender,
  }) {
    final fitType = SizeRange.evaluateFit(measuredCm, minCm, maxCm);
    final label = switch (kind) {
      BodyLineKind.chest => gender == Gender.female ? 'Bust' : 'Chest',
      BodyLineKind.waist => 'Waist',
      BodyLineKind.hips => 'Hips',
    };

    final desc = switch (fitType) {
      SizeFitType.optimal =>
        '$label fits true to size (${measuredCm.toStringAsFixed(1)} cm fits within $minCm–$maxCm cm)',
      SizeFitType.relaxed =>
        '$label has comfortable room (${measuredCm.toStringAsFixed(1)} cm near lower bound of $minCm–$maxCm cm)',
      SizeFitType.snug =>
        '$label fits tailored / close to body (${measuredCm.toStringAsFixed(1)} cm near upper bound of $minCm–$maxCm cm)',
      SizeFitType.tooSmall =>
        '$label is slightly loose for this size range ($minCm–$maxCm cm)',
      SizeFitType.tooLarge =>
        '$label is snug on this size range ($minCm–$maxCm cm)',
    };

    return PartFitAssessment(
      kind: kind,
      measuredCm: measuredCm,
      minRangeCm: minCm,
      maxRangeCm: maxCm,
      fitType: fitType,
      description: desc,
    );
  }

  String _buildSummary(
    GarmentType garment,
    String sizeLabel,
    List<PartFitAssessment> assessments,
    Gender gender,
  ) {
    final primary = assessments.first;
    if (assessments.every((a) => a.fitType == SizeFitType.optimal)) {
      return 'Size $sizeLabel is a true-to-size match across all your body proportions.';
    }

    if (primary.fitType == SizeFitType.optimal) {
      return 'Size $sizeLabel fits your primary measurement perfectly with comfortable drape.';
    }

    if (primary.fitType == SizeFitType.snug) {
      final partName = primary.kind == BodyLineKind.chest
          ? (gender == Gender.female ? 'bust' : 'chest')
          : primary.kind.name;
      return 'Size $sizeLabel will give you a sleek, tailored fit across the $partName.';
    }

    return 'Size $sizeLabel provides the most balanced and comfortable fit for this ${garment.label}.';
  }

  Map<BodyLineKind, double> _weightsFor(GarmentType garment) => switch (garment) {
        GarmentType.tShirt => const {
            BodyLineKind.chest: 1.00,
            BodyLineKind.waist: 0.00,
            BodyLineKind.hips: 0.00,
          },
        GarmentType.dress => const {
            BodyLineKind.chest: 0.45,
            BodyLineKind.waist: 0.35,
            BodyLineKind.hips: 0.20,
          },
        GarmentType.shorts => const {
            BodyLineKind.chest: 0.00,
            BodyLineKind.waist: 0.60,
            BodyLineKind.hips: 0.40,
          },
        GarmentType.pants => const {
            BodyLineKind.chest: 0.00,
            BodyLineKind.waist: 0.55,
            BodyLineKind.hips: 0.45,
          },
      };

  // ── Size Charts (Philippine / Asian Standard: Bench, Penshoppe, Uniqlo PH) ──

  List<SizeRange> sizeChartFor(Gender gender, GarmentType garment) {
    if (gender == Gender.female) {
      switch (garment) {
        case GarmentType.tShirt:
        case GarmentType.dress:
          return _femaleTopsChart;
        case GarmentType.shorts:
        case GarmentType.pants:
          return _femaleBottomsChart;
      }
    } else {
      switch (garment) {
        case GarmentType.tShirt:
          return _maleTopsChart;
        case GarmentType.shorts:
        case GarmentType.pants:
        case GarmentType.dress:
          return _maleBottomsChart;
      }
    }
  }

  /// Men's tops (t-shirts, polos, shirts) — Philippine / Asian Fit.
  /// Chest is the 100% primary driver for tops.
  static const List<SizeRange> _maleTopsChart = [
    SizeRange(label: 'XS', minChestCm: 78, maxChestCm: 84, minWaistCm: 66, maxWaistCm: 72, minHipsCm: 82, maxHipsCm: 88),
    SizeRange(label: 'S', minChestCm: 84, maxChestCm: 90, minWaistCm: 72, maxWaistCm: 78, minHipsCm: 88, maxHipsCm: 94),
    SizeRange(label: 'M', minChestCm: 90, maxChestCm: 97, minWaistCm: 78, maxWaistCm: 85, minHipsCm: 94, maxHipsCm: 101),
    SizeRange(label: 'L', minChestCm: 97, maxChestCm: 104, minWaistCm: 85, maxWaistCm: 92, minHipsCm: 101, maxHipsCm: 108),
    SizeRange(label: 'XL', minChestCm: 104, maxChestCm: 111, minWaistCm: 92, maxWaistCm: 100, minHipsCm: 108, maxHipsCm: 115),
    SizeRange(label: '2XL', minChestCm: 111, maxChestCm: 120, minWaistCm: 100, maxWaistCm: 110, minHipsCm: 115, maxHipsCm: 124),
  ];

  /// Men's bottoms (shorts, trousers) — based on Philippine waist sizes (inches: 26 to 42.5).
  static const List<SizeRange> _maleBottomsChart = [
    SizeRange(label: 'XS', minChestCm: 78, maxChestCm: 84, minWaistCm: 66, maxWaistCm: 71, minHipsCm: 82, maxHipsCm: 88),
    SizeRange(label: 'S', minChestCm: 84, maxChestCm: 90, minWaistCm: 71, maxWaistCm: 76, minHipsCm: 88, maxHipsCm: 94),
    SizeRange(label: 'M', minChestCm: 90, maxChestCm: 97, minWaistCm: 76, maxWaistCm: 83, minHipsCm: 94, maxHipsCm: 101),
    SizeRange(label: 'L', minChestCm: 97, maxChestCm: 104, minWaistCm: 83, maxWaistCm: 91, minHipsCm: 101, maxHipsCm: 108),
    SizeRange(label: 'XL', minChestCm: 104, maxChestCm: 111, minWaistCm: 91, maxWaistCm: 99, minHipsCm: 108, maxHipsCm: 116),
    SizeRange(label: '2XL', minChestCm: 111, maxChestCm: 120, minWaistCm: 99, maxWaistCm: 108, minHipsCm: 116, maxHipsCm: 125),
  ];

  /// Women's tops & dresses — Philippine / Asian Fit (Bench, Penshoppe, Bayo).
  static const List<SizeRange> _femaleTopsChart = [
    SizeRange(label: 'XS', minChestCm: 76, maxChestCm: 82, minWaistCm: 58, maxWaistCm: 64, minHipsCm: 82, maxHipsCm: 88),
    SizeRange(label: 'S', minChestCm: 82, maxChestCm: 88, minWaistCm: 64, maxWaistCm: 70, minHipsCm: 88, maxHipsCm: 94),
    SizeRange(label: 'M', minChestCm: 88, maxChestCm: 94, minWaistCm: 70, maxWaistCm: 76, minHipsCm: 94, maxHipsCm: 100),
    SizeRange(label: 'L', minChestCm: 94, maxChestCm: 101, minWaistCm: 76, maxWaistCm: 83, minHipsCm: 100, maxHipsCm: 107),
    SizeRange(label: 'XL', minChestCm: 101, maxChestCm: 108, minWaistCm: 83, maxWaistCm: 91, minHipsCm: 107, maxHipsCm: 114),
    SizeRange(label: '2XL', minChestCm: 108, maxChestCm: 116, minWaistCm: 91, maxWaistCm: 99, minHipsCm: 114, maxHipsCm: 122),
  ];

  /// Women's bottoms (shorts, trousers) — Philippine waist sizing (inches: 23 to 39).
  static const List<SizeRange> _femaleBottomsChart = [
    SizeRange(label: 'XS', minChestCm: 76, maxChestCm: 82, minWaistCm: 58, maxWaistCm: 64, minHipsCm: 82, maxHipsCm: 88),
    SizeRange(label: 'S', minChestCm: 82, maxChestCm: 88, minWaistCm: 64, maxWaistCm: 70, minHipsCm: 88, maxHipsCm: 94),
    SizeRange(label: 'M', minChestCm: 88, maxChestCm: 94, minWaistCm: 70, maxWaistCm: 76, minHipsCm: 94, maxHipsCm: 100),
    SizeRange(label: 'L', minChestCm: 94, maxChestCm: 101, minWaistCm: 76, maxWaistCm: 83, minHipsCm: 100, maxHipsCm: 107),
    SizeRange(label: 'XL', minChestCm: 101, maxChestCm: 108, minWaistCm: 83, maxWaistCm: 91, minHipsCm: 107, maxHipsCm: 114),
    SizeRange(label: '2XL', minChestCm: 108, maxChestCm: 116, minWaistCm: 91, maxWaistCm: 99, minHipsCm: 114, maxHipsCm: 122),
  ];
}
