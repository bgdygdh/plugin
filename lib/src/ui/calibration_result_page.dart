import 'dart:io';

import 'package:flutter/material.dart';

import '../models/scale_calibration_exception.dart';
import '../models/scale_calibration_result.dart';
import '../services/scale_calculator.dart';
import '../services/scale_calibration_service.dart';
import '../utils/format.dart';
import 'plugin_colors.dart';

/// Runs the height -> scale calibration on the two captured photos and shows
/// the outcome, including the formula with the real numbers.
///
/// Pops with the [ScaleCalibrationResult] when the user accepts it, or with
/// `null` when the user wants to retake the photos.
class CalibrationResultPage extends StatefulWidget {
  final String frontImagePath;
  final String sideImagePath;
  final double userHeightCm;

  const CalibrationResultPage({
    super.key,
    required this.frontImagePath,
    required this.sideImagePath,
    required this.userHeightCm,
  });

  @override
  State<CalibrationResultPage> createState() => _CalibrationResultPageState();
}

class _CalibrationResultPageState extends State<CalibrationResultPage> {
  static const Color _accent = PluginColors.accent;
  static const Color _warn = Color(0xFFD97706);
  static const Color _danger = Color(0xFFFF6B6B);

  ScaleCalibrationResult? _result;
  String? _error;
  bool _loading = true;

  /// User-adjustable head and feet positions in photo pixels.
  double _headTopY = 0;
  double _feetBottomY = 0;
  bool _isManualAdjusted = false;

  /// Whether the segmented cutout (background removed) is displayed.
  bool _showCutout = false;

  /// Guards against a stale run finishing after a newer one started.
  int _runId = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final runId = ++_runId;
    try {
      final result = await const ScaleCalibrationService().calibrate(
        frontImagePath: widget.frontImagePath,
        sideImagePath: widget.sideImagePath,
        userHeightCm: widget.userHeightCm,
      );
      if (!mounted || runId != _runId) return;
      setState(() {
        _result = result;
        _headTopY = result.headTopY;
        _feetBottomY = result.feetBottomY;
        _isManualAdjusted = false;
        _showCutout = false;
        _loading = false;
      });
    } on ScaleCalibrationException catch (e) {
      if (!mounted || runId != _runId) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || runId != _runId) return;
      setState(() {
        _error = 'Something went wrong while analysing your photos. '
            'Please retake them. ($e)';
        _loading = false;
      });
    }
  }

  void _retryAnalysis() {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    _run();
  }

  /// The active result reflecting any manual adjustments made by dragging.
  ScaleCalibrationResult get _activeResult {
    final base = _result!;
    if (!_isManualAdjusted) return base;
    return ScaleCalculator.calculate(
      userHeightCm: widget.userHeightCm,
      headTopY: _headTopY,
      feetBottomY: _feetBottomY,
      imageWidth: base.imageWidth,
      imageHeight: base.imageHeight,
      sidePixelHeight: base.sidePixelHeight,
      cutoutImagePath: base.cutoutImagePath,
      warnings: [
        ...base.warnings.where((w) => !w.contains('proportions')),
        'Head/feet lines adjusted manually by user.',
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PluginColors.background,
      body: SafeArea(
        child: _loading
            ? _buildLoading()
            : (_result != null ? _buildResult(_result!) : _buildError()),
      ),
    );
  }

  // ── Loading ────────────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      key: const Key('calibration_loading'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(strokeWidth: 3, color: _accent),
          ),
          const SizedBox(height: 22),
          const Text(
            'CALIBRATING SCALE',
            style: TextStyle(
              color: PluginColors.textPrimary,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Finding the top of your head and\nthe bottom of your feet…',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: PluginColors.textSecondary,
              fontSize: 12.5,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Error ──────────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Padding(
      key: const Key('calibration_error'),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _danger.withValues(alpha: 0.12),
              border: Border.all(color: _danger.withValues(alpha: 0.5)),
            ),
            child: const Icon(Icons.error_outline_rounded,
                color: _danger, size: 42),
          ),
          const SizedBox(height: 22),
          const Text(
            'COULD NOT MEASURE',
            style: TextStyle(
              color: PluginColors.textPrimary,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? 'Unknown error.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: PluginColors.textSecondary,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('calibration_retry_button'),
                  onPressed: _retryAnalysis,
                  style: _outlinedStyle,
                  child: const Text('TRY AGAIN'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  key: const Key('calibration_retake_button'),
                  onPressed: () => Navigator.of(context).pop(null),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'RETAKE PHOTOS',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1.0),
                  ),
                  style: _filledStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Success ────────────────────────────────────────────────────────────────

  Widget _buildResult(ScaleCalibrationResult r) {
    final active = _activeResult;
    final maxPhotoHeight = MediaQuery.of(context).size.height * 0.44;

    return Column(
      key: const Key('calibration_result'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'SCALE CALIBRATED',
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
                  _isManualAdjusted
                      ? 'Adjusted manually. You can drag the badges to fine-tune.'
                      : 'Drag the green HEAD and FEET badges if you need to fine-tune.\n'
                          'Toggle below to see the AI background removal.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PluginColors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                if (r.cutoutImagePath != null) _buildViewModeToggle(r),
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxPhotoHeight),
                    child: AspectRatio(
                      aspectRatio: r.imageWidth / r.imageHeight,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final boxH = constraints.maxHeight;

                            final screenHeadY =
                                (_headTopY / r.imageHeight) * boxH;
                            final screenFeetY =
                                (_feetBottomY / r.imageHeight) * boxH;

                            return Stack(
                              fit: StackFit.expand,
                              clipBehavior: Clip.none,
                              children: [
                                // Studio background behind transparent cutout
                                if (_showCutout)
                                  Container(
                                    decoration: const BoxDecoration(
                                      gradient: RadialGradient(
                                        colors: [
                                          Color(0xFFF1F5F9),
                                          Color(0xFFCBD5E1),
                                        ],
                                        radius: 0.85,
                                      ),
                                    ),
                                  ),

                                // Main photo or cutout
                                Image.file(
                                  File(_showCutout && r.cutoutImagePath != null
                                      ? r.cutoutImagePath!
                                      : widget.frontImagePath),
                                  fit: BoxFit.fill,
                                  errorBuilder: (_, _, _) => const ColoredBox(
                                    color: PluginColors.surface,
                                    child: Icon(Icons.broken_image_outlined,
                                        color: PluginColors.textSecondary),
                                  ),
                                ),

                                // Height Markers Overlay (Lines and px distance)
                                IgnorePointer(
                                  child: CustomPaint(
                                    painter: _HeightMarkersPainter(
                                      headFraction: _headTopY / r.imageHeight,
                                      feetFraction: _feetBottomY / r.imageHeight,
                                      label:
                                          '${formatPixels(active.frontPixelHeight)} px',
                                    ),
                                  ),
                                ),

                                // Draggable HEAD Handle (Top)
                                Positioned(
                                  top: (screenHeadY - 20)
                                      .clamp(-5.0, boxH - 30.0),
                                  left: 0,
                                  right: 0,
                                  height: 40,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onVerticalDragUpdate: (details) {
                                      final deltaPx =
                                          (details.primaryDelta! / boxH) *
                                              r.imageHeight;
                                      setState(() {
                                        _headTopY = (_headTopY + deltaPx)
                                            .clamp(0.0, _feetBottomY - 40.0);
                                        _isManualAdjusted = true;
                                      });
                                    },
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(right: 10),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF44FF88),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF44FF88)
                                                  .withValues(alpha: 0.45),
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.unfold_more_rounded,
                                                size: 13, color: Colors.black),
                                            SizedBox(width: 2),
                                            Text(
                                              'HEAD ↕',
                                              style: TextStyle(
                                                color: Colors.black,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 9.5,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                // Draggable FEET Handle (Bottom)
                                Positioned(
                                  top: (screenFeetY - 20)
                                      .clamp(10.0, boxH - 10.0),
                                  left: 0,
                                  right: 0,
                                  height: 40,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.translucent,
                                    onVerticalDragUpdate: (details) {
                                      final deltaPx =
                                          (details.primaryDelta! / boxH) *
                                              r.imageHeight;
                                      setState(() {
                                        _feetBottomY = (_feetBottomY + deltaPx)
                                            .clamp(_headTopY + 40.0,
                                                r.imageHeight.toDouble());
                                        _isManualAdjusted = true;
                                      });
                                    },
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Container(
                                        margin:
                                            const EdgeInsets.only(right: 10),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF44FF88),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF44FF88)
                                                  .withValues(alpha: 0.45),
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.unfold_more_rounded,
                                                size: 13, color: Colors.black),
                                            SizedBox(width: 2),
                                            Text(
                                              'FEET ↕',
                                              style: TextStyle(
                                                color: Colors.black,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 9.5,
                                                letterSpacing: 0.6,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                if (_isManualAdjusted) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFFD97706).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color:
                                const Color(0xFFD97706).withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Text(
                          'MANUAL ADJUSTMENT',
                          style: TextStyle(
                            color: Color(0xFFD97706),
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _headTopY = r.headTopY;
                            _feetBottomY = r.feetBottomY;
                            _isManualAdjusted = false;
                          });
                        },
                        icon: const Icon(Icons.undo_rounded,
                            size: 14, color: PluginColors.textSecondary),
                        label: const Text(
                          'Reset to AI',
                          style: TextStyle(
                              color: PluginColors.textSecondary, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  const Text(
                    '💡 Drag the green HEAD ↕ or FEET ↕ badges to fine-tune the lines.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: PluginColors.textSecondary, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                ],
                _buildFormulaCard(active),
                const SizedBox(height: 12),
                _buildDetailsCard(active),
                if (active.warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildWarnings(active.warnings),
                ],
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('calibration_result_retake_button'),
                  onPressed: () => Navigator.of(context).pop(null),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('RETAKE'),
                  style: _outlinedStyle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  key: const Key('calibration_accept_button'),
                  onPressed: () => Navigator.of(context).pop(active),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text(
                    'USE THIS SCALE',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1.0),
                  ),
                  style: _filledStyle,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildViewModeToggle(ScaleCalibrationResult r) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: PluginColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: PluginColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTogglePill(
              label: 'Original Photo',
              icon: Icons.image_outlined,
              isSelected: !_showCutout,
              onTap: () => setState(() => _showCutout = false),
            ),
            const SizedBox(width: 4),
            _buildTogglePill(
              label: 'Background Removed',
              icon: Icons.auto_fix_high_rounded,
              isSelected: _showCutout,
              onTap: () => setState(() => _showCutout = true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTogglePill({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? PluginColors.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: isSelected
              ? Border.all(
                  color: PluginColors.accent.withValues(alpha: 0.6))
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected
                  ? PluginColors.accent
                  : PluginColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? PluginColors.accent
                    : PluginColors.textSecondary,
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormulaCard(ScaleCalibrationResult r) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SCALE CALIBRATION FORMULA',
            style: TextStyle(
              color: _accent,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Scale = User Height (cm) ÷ Height (pixels)',
            style: TextStyle(color: PluginColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            'Scale = ${formatCm(r.userHeightCm)} cm ÷ '
            '${formatPixels(r.frontPixelHeight)} px',
            key: const Key('calibration_formula_text'),
            style: const TextStyle(
              color: PluginColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  label: '1 PIXEL =',
                  value: '${r.cmPerPixel.toStringAsFixed(4)} cm',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricTile(
                  label: '1 CM =',
                  value: '${r.pixelsPerCm.toStringAsFixed(2)} px',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsCard(ScaleCalibrationResult r) {
    final sideRatio = r.sideToFrontHeightRatio;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PluginColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PluginColors.border),
      ),
      child: Column(
        children: [
          _DetailRow(
              label: 'Head top (Y)', value: '${formatPixels(r.headTopY)} px'),
          _DetailRow(
              label: 'Feet bottom (Y)',
              value: '${formatPixels(r.feetBottomY)} px'),
          _DetailRow(
              label: 'Height in photo',
              value: '${formatPixels(r.frontPixelHeight)} px'),
          _DetailRow(
              label: 'Photo size', value: '${r.imageWidth} × ${r.imageHeight}'),
          _DetailRow(
            label: 'Side photo height',
            value: r.sidePixelHeight == null
                ? 'not measured'
                : '${formatPixels(r.sidePixelHeight!)} px '
                    '(${((sideRatio! - 1) * 100).toStringAsFixed(1)}% vs front)',
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _buildWarnings(List<String> warnings) {
    return Container(
      key: const Key('calibration_warnings'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _warn.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _warn.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: _warn, size: 18),
              SizedBox(width: 8),
              Text(
                'ACCURACY NOTES',
                style: TextStyle(
                  color: _warn,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '• $warning',
                style: TextStyle(
                  color: PluginColors.textSecondary,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }

  ButtonStyle get _outlinedStyle => OutlinedButton.styleFrom(
        foregroundColor: PluginColors.textSecondary,
        side: const BorderSide(color: PluginColors.border),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );

  ButtonStyle get _filledStyle => ElevatedButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
}

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;

  const _MetricTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PluginColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: PluginColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: PluginColors.accent,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
                color: PluginColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: PluginColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the detected head-top and feet-bottom lines plus the measured pixel
/// height on top of the front photo. Positions are fractions (0..1) of the
/// photo height, so they stay correct at any display size.
class _HeightMarkersPainter extends CustomPainter {
  final double headFraction;
  final double feetFraction;
  final String label;

  const _HeightMarkersPainter({
    required this.headFraction,
    required this.feetFraction,
    required this.label,
  });

  static const Color _lineColor = Color(0xFF44FF88);

  @override
  void paint(Canvas canvas, Size size) {
    final headY = (headFraction * size.height).clamp(0.0, size.height);
    final feetY = (feetFraction * size.height).clamp(0.0, size.height);

    final linePaint = Paint()
      ..color = _lineColor
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    _dashedHorizontalLine(canvas, size.width, headY, linePaint);
    _dashedHorizontalLine(canvas, size.width, feetY, linePaint);

    // Vertical measuring arrow on the right-hand side.
    final arrowX = size.width * 0.9;
    canvas.drawLine(Offset(arrowX, headY), Offset(arrowX, feetY), linePaint);
    const head = 6.0;
    canvas.drawLine(
        Offset(arrowX, headY), Offset(arrowX - head, headY + head), linePaint);
    canvas.drawLine(
        Offset(arrowX, headY), Offset(arrowX + head, headY + head), linePaint);
    canvas.drawLine(
        Offset(arrowX, feetY), Offset(arrowX - head, feetY - head), linePaint);
    canvas.drawLine(
        Offset(arrowX, feetY), Offset(arrowX + head, feetY - head), linePaint);

    _drawTag(canvas, 'HEAD TOP', Offset(8, headY), above: false);
    _drawTag(canvas, 'FEET BOTTOM', Offset(8, feetY), above: true);

    // Pixel-height label, centred next to the arrow.
    final midY = (headY + feetY) / 2;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final pill = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(arrowX - painter.width / 2 - 14, midY),
        width: painter.width + 12,
        height: painter.height + 8,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(pill, Paint()..color = _lineColor);
    painter.paint(
      canvas,
      Offset(pill.left + 6, pill.top + 4),
    );
  }

  void _dashedHorizontalLine(Canvas canvas, double width, double y, Paint p) {
    const dash = 9.0;
    const gap = 5.0;
    var x = 0.0;
    while (x < width) {
      canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0.0, width), y), p);
      x += dash + gap;
    }
  }

  void _drawTag(Canvas canvas, String text, Offset anchor,
      {required bool above}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final top = above ? anchor.dy - painter.height - 8 : anchor.dy + 3;
    final rect = Rect.fromLTWH(
        anchor.dx, top, painter.width + 10, painter.height + 5);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()..color = Colors.black.withValues(alpha: 0.7),
    );
    painter.paint(canvas, Offset(rect.left + 5, rect.top + 2.5));
  }

  @override
  bool shouldRepaint(_HeightMarkersPainter old) =>
      old.headFraction != headFraction ||
      old.feetFraction != feetFraction ||
      old.label != label;
}
