import 'body_lines.dart';
import 'virtual_try_on.dart';

/// Gender for size chart selection.
enum Gender {
  male,
  female;

  String get label => switch (this) {
        Gender.male => 'Male',
        Gender.female => 'Female',
      };
}

/// The garment category to recommend sizing for.
enum GarmentType {
  tShirt,
  dress,
  shorts,
  pants;

  String get label => switch (this) {
        GarmentType.tShirt => 'T-Shirt / Top',
        GarmentType.dress => 'Dress',
        GarmentType.shorts => 'Shorts',
        GarmentType.pants => 'Pants / Trousers',
      };

  /// Returns valid garments for a given gender.
  /// Female: T-Shirt, Dress, Shorts, Pants.
  /// Male: T-Shirt, Shorts, Pants.
  static List<GarmentType> garmentsFor(Gender gender) => switch (gender) {
        Gender.female => const [
            GarmentType.tShirt,
            GarmentType.dress,
            GarmentType.shorts,
            GarmentType.pants,
          ],
        Gender.male => const [
            GarmentType.tShirt,
            GarmentType.shorts,
            GarmentType.pants,
          ],
      };
}

/// How a user's measurement compares to a specific size window.
enum SizeFitType {
  tooSmall, // User is smaller than this size window
  relaxed, // Bottom third of the size window (comfortable / roomy)
  optimal, // Middle of the size window (true to size / perfect fit)
  snug, // Upper third of the size window (fitted / tight)
  tooLarge; // User exceeds this size window (will be too tight)

  String get label => switch (this) {
        SizeFitType.tooSmall => 'Too Loose',
        SizeFitType.relaxed => 'Relaxed Fit',
        SizeFitType.optimal => 'Optimal Fit',
        SizeFitType.snug => 'Snug / Fitted',
        SizeFitType.tooLarge => 'Too Tight',
      };
}

/// A size entry in a chart (e.g., "M" with min/max ranges for chest, waist, hips).
class SizeRange {
  final String label;

  /// Min and max recommended body circumferences in cm.
  final double minChestCm;
  final double maxChestCm;

  final double minWaistCm;
  final double maxWaistCm;

  final double minHipsCm;
  final double maxHipsCm;

  const SizeRange({
    required this.label,
    required this.minChestCm,
    required this.maxChestCm,
    required this.minWaistCm,
    required this.maxWaistCm,
    required this.minHipsCm,
    required this.maxHipsCm,
  });

  /// Evaluates how [measuredCm] fits within the [minCm]..[maxCm] range.
  static SizeFitType evaluateFit(double measuredCm, double minCm, double maxCm) {
    if (measuredCm < minCm - 3.0) return SizeFitType.tooSmall;
    if (measuredCm > maxCm + 1.5) return SizeFitType.tooLarge;

    final span = maxCm - minCm;
    if (span <= 0) return SizeFitType.optimal;

    final ratio = (measuredCm - minCm) / span;
    if (ratio < 0.25) return SizeFitType.relaxed;
    if (ratio > 0.75) return SizeFitType.snug;
    return SizeFitType.optimal;
  }
}

/// Assessment of how one specific body part fits a candidate size.
class PartFitAssessment {
  final BodyLineKind kind;
  final double measuredCm;
  final double minRangeCm;
  final double maxRangeCm;
  final SizeFitType fitType;
  final String description;

  const PartFitAssessment({
    required this.kind,
    required this.measuredCm,
    required this.minRangeCm,
    required this.maxRangeCm,
    required this.fitType,
    required this.description,
  });
}

/// Complete recommendation result for a specific garment and gender.
class SizeRecommendationResult {
  final Gender gender;
  final GarmentType garment;
  final String recommendedSize;
  final List<PartFitAssessment> partAssessments;
  final String fitSummary;
  final String? alternateSize;
  final String? alternateSizeReason;
  final List<SizeRange> fullChart;

  const SizeRecommendationResult({
    required this.gender,
    required this.garment,
    required this.recommendedSize,
    required this.partAssessments,
    required this.fitSummary,
    this.alternateSize,
    this.alternateSizeReason,
    required this.fullChart,
  });
}

/// User physical profile (height and gender) collected during initial setup.
class UserBioProfile {
  final double heightCm;
  final Gender gender;

  const UserBioProfile({
    required this.heightCm,
    required this.gender,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserBioProfile &&
          runtimeType == other.runtimeType &&
          heightCm == other.heightCm &&
          gender == other.gender;

  @override
  int get hashCode => heightCm.hashCode ^ gender.hashCode;

  @override
  String toString() => 'UserBioProfile(heightCm: $heightCm, gender: $gender)';
}

/// Outcome of the size recommendation step, optionally bundled with a virtual try-on result.
class SizeRecommendationOutcome {
  final SizeRecommendationResult recommendation;
  final VirtualTryOnResult? tryOnResult;

  const SizeRecommendationOutcome({
    required this.recommendation,
    this.tryOnResult,
  });
}
