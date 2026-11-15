import 'package:flutter/material.dart';

import '../models/body_lines.dart';
import '../models/body_part_measurement.dart';
import '../models/scale_calibration_result.dart';
import '../models/size_recommendation.dart';
import '../models/virtual_try_on.dart';
import '../services/size_recommendation_service.dart';
import '../utils/format.dart';
import 'plugin_colors.dart';
import 'virtual_try_on_page.dart';

/// Dedicated UI page that recommends the best clothing size for a user based on
/// their measured circumferences and selected garment category.
class SizeRecommendationPage extends StatefulWidget {
  final Map<BodyLineKind, BodyPartMeasurement> measurements;
  final ScaleCalibrationResult calibration;
  final String? frontImagePath;
  final Gender initialGender;
  final GarmentType? initialGarment;
  final TryOnCategory? tryOnCategory;
  final String? garmentImageUrl;
  final String? fashnApiKey;

  const SizeRecommendationPage({
    super.key,
    required this.measurements,
    required this.calibration,
    this.frontImagePath,
    this.initialGender = Gender.male,
    this.initialGarment,
    this.tryOnCategory,
    this.garmentImageUrl,
    this.fashnApiKey,
  });

  @override
  State<SizeRecommendationPage> createState() => _SizeRecommendationPageState();
}

class _SizeRecommendationPageState extends State<SizeRecommendationPage> {
  static const Color _accent = PluginColors.accent;
  static const Color _warn = Color(0xFFD97706);
  static const Color _cyan = Color(0xFF0097A7);

  late final Gender _gender;
  late GarmentType _garment;
  static const SizeRecommendationService _service = SizeRecommendationService();

  @override
  void initState() {
    super.initState();
    _gender = widget.initialGender;
    final valid = GarmentType.garmentsFor(_gender);
    if (widget.initialGarment != null && valid.contains(widget.initialGarment)) {
      _garment = widget.initialGarment!;
    } else {
      _garment = valid.first;
    }
  }

  Color _fitColor(SizeFitType fit) => switch (fit) {
        SizeFitType.optimal => _accent,
        SizeFitType.relaxed => _cyan,
        SizeFitType.snug => _warn,
        SizeFitType.tooSmall => const Color(0xFFFF9100),
        SizeFitType.tooLarge => const Color(0xFFFF5252),
      };

  IconData _garmentIcon(GarmentType type) => switch (type) {
        GarmentType.tShirt => Icons.checkroom_rounded,
        GarmentType.dress => Icons.woman_rounded,
        GarmentType.shorts => Icons.straighten_rounded,
        GarmentType.pants => Icons.airline_seat_legroom_extra_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final chest = widget.measurements[BodyLineKind.chest]?.circumferenceCm ?? 0.0;
    final waist = widget.measurements[BodyLineKind.waist]?.circumferenceCm ?? 0.0;
    final hips = widget.measurements[BodyLineKind.hips]?.circumferenceCm ?? 0.0;

    final result = _service.recommend(
      gender: _gender,
      garment: _garment,
      chestCm: chest,
      waistCm: waist,
      hipsCm: hips,
    );

    return Scaffold(
      backgroundColor: PluginColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'SIZE RECOMMENDATION',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: PluginColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Rule-based sizing calibrated to international garment standards.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: PluginColors.textSecondary,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Gender Profile Indicator
                    _buildGenderProfileCard(),
                    const SizedBox(height: 16),

                    // Garment Selector
                    _buildGarmentSelector(),
                    const SizedBox(height: 20),

                    // Hero Recommended Size Card
                    _buildHeroSizeCard(result),
                    const SizedBox(height: 16),

                    // Fit Breakdown per Body Part
                    _buildFitBreakdownCard(result),
                    const SizedBox(height: 16),

                    // Size Chart Table
                    _buildSizeChartCard(result),
                  ],
                ),
              ),
            ),

            // Bottom Buttons
            _buildBottomBar(result),
          ],
        ),
      ),
    );
  }

  Widget _buildGenderProfileCard() {
    final isFemale = _gender == Gender.female;
    return Container(
      key: const Key('gender_profile_indicator'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: PluginColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PluginColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _accent.withValues(alpha: 0.15),
            ),
            child: Icon(
              isFemale ? Icons.female_rounded : Icons.male_rounded,
              size: 18,
              color: _accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_gender.label.toUpperCase()} PROFILE',
                  style: const TextStyle(
                    color: PluginColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sizing tailored for ${_gender.label.toLowerCase()} body proportions',
                  style: TextStyle(
                    color: PluginColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _accent.withValues(alpha: 0.4)),
            ),
            child: Text(
              _gender.label.toUpperCase(),
              style: const TextStyle(
                color: _accent,
                fontWeight: FontWeight.bold,
                fontSize: 10.5,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGarmentSelector() {
    final validGarments = GarmentType.garmentsFor(_gender);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final g in validGarments)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                key: Key('garment_tab_${g.name}'),
                onTap: () => setState(() => _garment = g),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _garment == g
                        ? _accent.withValues(alpha: 0.10)
                        : PluginColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _garment == g
                          ? _accent.withValues(alpha: 0.8)
                          : PluginColors.border,
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _garmentIcon(g),
                        size: 16,
                        color: _garment == g
                            ? _accent
                            : PluginColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        g.label,
                        style: TextStyle(
                          color: _garment == g
                              ? PluginColors.textPrimary
                              : PluginColors.textSecondary,
                          fontWeight: _garment == g
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeroSizeCard(SizeRecommendationResult result) {
    return Container(
      key: const Key('hero_size_recommendation_card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _accent.withValues(alpha: 0.10),
            PluginColors.background,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accent.withValues(alpha: 0.4), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'BEST FIT FOR ${_garment.label.toUpperCase()}',
            style: const TextStyle(
              color: _accent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _accent.withValues(alpha: 0.6)),
            ),
            child: Text(
              result.recommendedSize,
              key: const Key('recommended_size_badge'),
              style: const TextStyle(
                color: PluginColors.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 34,
                letterSpacing: 2.0,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            result.fitSummary,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: PluginColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.45,
            ),
          ),
          if (result.alternateSize != null &&
              result.alternateSizeReason != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: PluginColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline_rounded,
                      size: 15, color: _warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.alternateSizeReason!,
                      style: TextStyle(
                        color: PluginColors.textSecondary,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFitBreakdownCard(SizeRecommendationResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PluginColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PluginColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: _accent),
              SizedBox(width: 8),
              Text(
                'FIT BREAKDOWN BY BODY PART',
                style: TextStyle(
                  color: PluginColors.textPrimary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final a in result.partAssessments) ...[
            Padding(
              padding: EdgeInsets.only(
                  bottom: a == result.partAssessments.last ? 0 : 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: PluginColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          a.kind == BodyLineKind.chest
                              ? (_gender == Gender.female ? 'Bust' : 'Chest')
                              : a.kind.label,
                          style: const TextStyle(
                            color: PluginColors.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _fitColor(a.fitType).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: _fitColor(a.fitType).withValues(alpha: 0.6)),
                          ),
                          child: Text(
                            a.fitType.label,
                            style: TextStyle(
                              color: _fitColor(a.fitType),
                              fontWeight: FontWeight.bold,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your circumference: ${formatCm(a.measuredCm)} cm',
                      style: const TextStyle(
                        color: PluginColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Size ${result.recommendedSize} window: ${formatCm(a.minRangeCm)} – ${formatCm(a.maxRangeCm)} cm',
                      style: TextStyle(
                        color: PluginColors.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSizeChartCard(SizeRecommendationResult result) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PluginColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PluginColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.table_chart_outlined, size: 16, color: _accent),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_garment.label.toUpperCase()} SIZE CHART (${_gender.label.toUpperCase()})',
                      style: const TextStyle(
                        color: PluginColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Philippine / Asian Standard (cm) · Bench, Penshoppe & Uniqlo PH',
                      style: TextStyle(
                        color: PluginColors.textSecondary,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: PluginColors.border.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text('Size',
                      style: TextStyle(
                          color: PluginColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(
                    _gender == Gender.female ? 'Bust' : 'Chest',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: PluginColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Text('Waist',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: PluginColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('Hips',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: PluginColors.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Chart rows
          for (final row in result.fullChart) ...[
            Builder(
              builder: (context) {
                final isSelected = row.label == result.recommendedSize;
                return Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? _accent.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isSelected
                        ? Border.all(
                            color: _accent.withValues(alpha: 0.6), width: 1)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Text(
                              row.label,
                              style: TextStyle(
                                color: isSelected
                                    ? _accent
                                    : PluginColors.textPrimary,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 12,
                              ),
                            ),
                            if (isSelected) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.check_circle_rounded,
                                  size: 13, color: _accent),
                            ],
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${formatCm(row.minChestCm)}–${formatCm(row.maxChestCm)}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isSelected
                                ? PluginColors.textPrimary
                                : PluginColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${formatCm(row.minWaistCm)}–${formatCm(row.maxWaistCm)}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isSelected
                                ? PluginColors.textPrimary
                                : PluginColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${formatCm(row.minHipsCm)}–${formatCm(row.maxHipsCm)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: isSelected
                                ? PluginColors.textPrimary
                                : PluginColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomBar(SizeRecommendationResult result) {
    final hasFrontPhoto = widget.frontImagePath != null && widget.frontImagePath!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      decoration: BoxDecoration(
        color: PluginColors.background,
        border: Border(
          top: BorderSide(color: PluginColors.border),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('size_accept_only_button'),
              onPressed: () => Navigator.of(context).pop(result),
              style: OutlinedButton.styleFrom(
                foregroundColor: PluginColors.textSecondary,
                side: const BorderSide(color: PluginColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(hasFrontPhoto ? 'ACCEPT SIZE' : 'BACK'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              key: const Key('size_proceed_tryon_button'),
              onPressed: () async {
                if (hasFrontPhoto) {
                  final tryOn = await Navigator.of(context).push<VirtualTryOnResult>(
                    MaterialPageRoute(
                      builder: (_) => VirtualTryOnPage(
                        frontImagePath: widget.frontImagePath!,
                        recommendation: result,
                        apiKey: widget.fashnApiKey,
                        initialGarmentPath: widget.garmentImageUrl,
                        initialCategory: widget.tryOnCategory,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  Navigator.of(context).pop(
                    SizeRecommendationOutcome(
                      recommendation: result,
                      tryOnResult: tryOn,
                    ),
                  );
                } else {
                  Navigator.of(context).pop(result);
                }
              },
              icon: Icon(
                hasFrontPhoto
                    ? Icons.auto_awesome_rounded
                    : Icons.check_circle_rounded,
                size: 18,
              ),
              label: Text(
                hasFrontPhoto ? 'VIRTUAL TRY-ON' : 'ACCEPT SIZE',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, letterSpacing: 0.8),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
