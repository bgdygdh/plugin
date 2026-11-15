import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/body_lines.dart';
import '../models/body_part_measurement.dart';
import '../models/scale_calibration_result.dart';
import '../models/size_recommendation.dart';
import '../models/virtual_try_on.dart';
import '../services/body_lines_service.dart';
import '../services/circumference_calculator.dart';
import '../utils/format.dart';
import 'plugin_colors.dart';
import 'size_recommendation_page.dart';

/// Shows the chest, waist and hip lines on the front photo (body widths) and
/// on the side photo (body depths) — visual review only, no measurements.
///
/// Every line can be dragged up/down (its ends re-snap to the body outline at
/// the new height) and its two ends can be nudged left/right.
///
/// Pops with `true` to continue, or `false` to retake the photos.
class BodyLinesPage extends StatefulWidget {
  final String frontImagePath;
  final String sideImagePath;
  final ScaleCalibrationResult calibration;
  final Gender userGender;
  final GarmentType? initialGarmentType;
  final TryOnCategory? tryOnCategory;
  final String? garmentImageUrl;
  final String? fashnApiKey;

  const BodyLinesPage({
    super.key,
    required this.frontImagePath,
    required this.sideImagePath,
    required this.calibration,
    this.userGender = Gender.male,
    this.initialGarmentType,
    this.tryOnCategory,
    this.garmentImageUrl,
    this.fashnApiKey,
  });

  @override
  State<BodyLinesPage> createState() => _BodyLinesPageState();
}

Color _kindColor(BodyLineKind kind) => switch (kind) {
      BodyLineKind.chest => const Color(0xFF00E5FF),
      BodyLineKind.waist => const Color(0xFFFFD600),
      BodyLineKind.hips => const Color(0xFFE040FB),
    };

/// Darker variant of [_kindColor] used for text/dots on the white page.
Color _kindInk(BodyLineKind kind) => switch (kind) {
      BodyLineKind.chest => const Color(0xFF0097A7),
      BodyLineKind.waist => const Color(0xFFB7791F),
      BodyLineKind.hips => const Color(0xFFAA00FF),
    };

/// Clamps [value] into [low]..[high] and always returns a `double`.
double _clampD(double value, double low, double high) =>
    math.min(math.max(value, low), high);

class _BodyLinesPageState extends State<BodyLinesPage> {
  static const Color _accent = PluginColors.accent;
  static const Color _warn = Color(0xFFD97706);
  static const Color _danger = Color(0xFFDC2626);

  BodyLinesResult? _result;
  String? _error;
  bool _loading = true;

  /// 0 = front (widths), 1 = side (depths).
  int _tab = 0;

  /// Current (possibly user-adjusted) lines. Replaced, never mutated in place.
  List<BodyLine> _frontLines = const [];
  List<BodyLine> _sideLines = const [];

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
      final result = await const BodyLinesService().analyze(
        frontImagePath: widget.frontImagePath,
        sideImagePath: widget.sideImagePath,
        frontHeadTopY: widget.calibration.headTopY,
        frontFeetBottomY: widget.calibration.feetBottomY,
      );
      if (!mounted || runId != _runId) return;
      setState(() {
        _result = result;
        _frontLines = List.of(result.front.lines);
        _sideLines = List.of(result.side.lines);
        _tab = 0;
        _loading = false;
      });
    } on BodyLinesException catch (e) {
      if (!mounted || runId != _runId) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || runId != _runId) return;
      setState(() {
        _error = 'Something went wrong while finding your body lines. '
            'Please try again or retake the photos. ($e)';
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

  List<BodyLine> get _currentLines => _tab == 0 ? _frontLines : _sideLines;

  void _replaceLine(int index, BodyLine line) {
    final updated = List<BodyLine>.of(_currentLines);
    updated[index] = line;
    setState(() {
      if (_tab == 0) {
        _frontLines = updated;
      } else {
        _sideLines = updated;
      }
    });
  }

  bool _isAdjusted(BodyLinesResult r) {
    bool differs(List<BodyLine> now, List<BodyLine> original) {
      if (now.length != original.length) return true;
      for (var i = 0; i < now.length; i++) {
        if (now[i].y != original[i].y ||
            now[i].xStart != original[i].xStart ||
            now[i].xEnd != original[i].xEnd) {
          return true;
        }
      }
      return false;
    }

    return differs(_frontLines, r.front.lines) ||
        differs(_sideLines, r.side.lines);
  }

  void _resetToAuto(BodyLinesResult r) {
    setState(() {
      _frontLines = List.of(r.front.lines);
      _sideLines = List.of(r.side.lines);
    });
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
      key: const Key('body_lines_loading'),
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
            'FINDING BODY LINES',
            style: TextStyle(
              color: PluginColors.textPrimary,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Locating your chest, waist and hips…',
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
      key: const Key('body_lines_error'),
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
            'COULD NOT FIND BODY LINES',
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
                  key: const Key('body_lines_retry_button'),
                  onPressed: _retryAnalysis,
                  style: _outlinedStyle,
                  child: const Text('TRY AGAIN'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  key: const Key('body_lines_error_retake_button'),
                  onPressed: () => Navigator.of(context).pop(false),
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
          const SizedBox(height: 10),
          TextButton(
            key: const Key('body_lines_skip_button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Continue without body lines',
              style: TextStyle(
                  color: PluginColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // ── Result ─────────────────────────────────────────────────────────────────

  Widget _buildResult(BodyLinesResult r) {
    final isFront = _tab == 0;
    final view = isFront ? r.front : r.side;
    final lines = _currentLines;
    final path = isFront ? widget.frontImagePath : widget.sideImagePath;
    final maxPhotoHeight = MediaQuery.of(context).size.height * 0.52;

    return Column(
      key: const Key('body_lines_result'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'BODY LINES',
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
                  'Check that each caliper line sits in the right place.\n'
                  'Drag a line or side tab up/down, or drag the ends to trim.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PluginColors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 14),
                _buildTabs(),
                const SizedBox(height: 12),
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: maxPhotoHeight),
                    child: AspectRatio(
                      aspectRatio: view.width / view.height,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final boxW = constraints.maxWidth;
                            final boxH = constraints.maxHeight;
                            final sx = boxW / view.width;
                            final sy = boxH / view.height;
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  File(path),
                                  key: ValueKey(path),
                                  fit: BoxFit.fill,
                                  errorBuilder: (_, _, _) => const ColoredBox(
                                    color: PluginColors.surface,
                                    child: Icon(Icons.broken_image_outlined,
                                        color: PluginColors.textSecondary),
                                  ),
                                ),
                                IgnorePointer(
                                  child: CustomPaint(
                                    painter: _BodyLinesPainter(
                                      lines: lines,
                                      imageWidth: view.width,
                                      imageHeight: view.height,
                                    ),
                                  ),
                                ),
                                for (var i = 0; i < lines.length; i++)
                                  ..._buildHandles(
                                    view: view,
                                    index: i,
                                    line: lines[i],
                                    sx: sx,
                                    sy: sy,
                                    boxW: boxW,
                                    boxH: boxH,
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (!isFront && r.sideEstimated) ...[
                  _buildNote(
                    'Your pose could not be read in the side photo, so the line '
                    'heights are estimated. Please check them and drag if needed.',
                  ),
                  const SizedBox(height: 12),
                ],
                if (_isAdjusted(r))
                  Center(
                    child: TextButton.icon(
                      key: const Key('body_lines_reset_button'),
                      onPressed: () => _resetToAuto(r),
                      icon: const Icon(Icons.undo_rounded,
                          size: 14, color: PluginColors.textSecondary),
                      label: const Text(
                        'Reset to AI',
                        style: TextStyle(
                            color: PluginColors.textSecondary, fontSize: 11),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                _buildMeasurementsTable(r),
                const SizedBox(height: 14),
                _buildLegend(isFront),
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
                  key: const Key('body_lines_retake_button'),
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('RETAKE'),
                  style: _outlinedStyle,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  key: const Key('body_lines_continue_button'),
                  onPressed: () async {
                    final measurements = {
                      for (final kind in BodyLineKind.values)
                        kind: _measurementFor(r, kind),
                    };
                    final outcome =
                        await Navigator.of(context).push<dynamic>(
                      MaterialPageRoute(
                        builder: (_) => SizeRecommendationPage(
                          measurements: measurements,
                          calibration: widget.calibration,
                          initialGender: widget.userGender,
                          frontImagePath: widget.frontImagePath,
                          initialGarment: widget.initialGarmentType,
                          tryOnCategory: widget.tryOnCategory,
                          garmentImageUrl: widget.garmentImageUrl,
                          fashnApiKey: widget.fashnApiKey,
                        ),
                      ),
                    );
                    if (!mounted || outcome == null) return;
                    Navigator.of(context).pop(outcome);
                  },
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text(
                    'CONTINUE',
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

  Widget _buildTabs() {
    Widget tab(int index, IconData icon, String title, String subtitle) {
      final selected = _tab == index;
      return Expanded(
        child: GestureDetector(
          key: Key('body_lines_tab_$index'),
          onTap: () => setState(() => _tab = index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected
                  ? _accent.withValues(alpha: 0.10)
                  : PluginColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? _accent.withValues(alpha: 0.7)
                    : PluginColors.border,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon,
                        size: 15,
                        color: selected ? _accent : PluginColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(
                      title,
                      style: TextStyle(
                        color: selected ? _accent : PluginColors.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: PluginColors.textSecondary,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(0, Icons.person_rounded, 'FRONT', 'widths'),
        const SizedBox(width: 10),
        tab(1, Icons.accessibility_new_rounded, 'SIDE', 'depths'),
      ],
    );
  }

  /// Drag handles for one line:
  /// - A minimal ruler tag pinned to the right margin (off the torso)
  /// - A direct-touch drag band along the line itself
  /// - Two end handles to trim the width left/right
  List<Widget> _buildHandles({
    required BodyLinesView view,
    required int index,
    required BodyLine line,
    required double sx,
    required double sy,
    required double boxW,
    required double boxH,
  }) {
    final color = _kindColor(line.kind);
    final y = line.y * sy;
    final xl = line.xStart * sx;
    final xr = line.xEnd * sx;
    const dot = 32.0;

    void updateVertical(double deltaDy) {
      final current = _currentLines[index];
      final profile = view.profiles[line.kind]!;
      final newY = _clampD(current.y + deltaDy / sy,
          profile.firstRow.toDouble(), profile.lastRow.toDouble());
      final edges = profile.edgesAt(newY);
      _replaceLine(
        index,
        current.copyWith(
          y: newY,
          xStart: edges?.start ?? current.xStart,
          xEnd: edges?.end ?? current.xEnd,
        ),
      );
    }

    return [
      // 1. Direct-touch vertical drag band along the measurement line itself
      Positioned(
        left: _clampD(xl + 12, 0.0, boxW),
        top: _clampD(y - 14, 0.0, boxH - 28),
        width: math.max(0.0, xr - xl - 24),
        height: 28,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: (d) => updateVertical(d.delta.dy),
        ),
      ),

      // 2. Minimal ruler tag pinned to the RIGHT margin (completely off the body)
      Positioned(
        top: _clampD(y - 11, 0.0, boxH - 22),
        right: 6,
        child: GestureDetector(
          key: Key('body_line_badge_${line.kind.name}'),
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) => updateVertical(d.delta.dy),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xCC0E0E14),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: color.withValues(alpha: 0.8),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  line.kind == BodyLineKind.chest
                      ? (widget.userGender == Gender.female ? 'BUST' : 'CHEST')
                      : line.kind.label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.bold,
                    fontSize: 8.5,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.unfold_more_rounded,
                  size: 11,
                  color: color,
                ),
              ],
            ),
          ),
        ),
      ),

      // 3. Left end: horizontal trim drag
      Positioned(
        left: _clampD(xl - dot / 2, 0.0, boxW - dot),
        top: _clampD(y - dot / 2, 0.0, boxH - dot),
        width: dot,
        height: dot,
        child: GestureDetector(
          key: Key('body_line_start_${line.kind.name}'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) {
            final current = _currentLines[index];
            final newX = _clampD(
                current.xStart + d.delta.dx / sx, 0.0, current.xEnd - 10.0);
            _replaceLine(index, current.copyWith(xStart: newX));
          },
          child: _endDot(color),
        ),
      ),

      // 4. Right end: horizontal trim drag
      Positioned(
        left: _clampD(xr - dot / 2, 0.0, boxW - dot),
        top: _clampD(y - dot / 2, 0.0, boxH - dot),
        width: dot,
        height: dot,
        child: GestureDetector(
          key: Key('body_line_end_${line.kind.name}'),
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (d) {
            final current = _currentLines[index];
            final newX = _clampD(current.xEnd + d.delta.dx / sx,
                current.xStart + 10.0, view.width.toDouble());
            _replaceLine(index, current.copyWith(xEnd: newX));
          },
          child: _endDot(color),
        ),
      ),
    ];
  }

  Widget _endDot(Color color) {
    return Center(
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.transparent,
          border: Border.all(color: color, width: 1.3),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(bool isFront) {
    final isFemale = widget.userGender == Gender.female;
    String describe(BodyLineKind kind) => switch (kind) {
          BodyLineKind.chest => isFront
              ? (isFemale
                  ? 'Across the fullest part of the bust — torso only'
                  : 'Across the fullest part of the chest — torso only')
              : (isFemale
                  ? 'Front of bust to back'
                  : 'Front of chest to back'),
          BodyLineKind.waist => isFront
              ? 'Narrowest part of the torso'
              : 'Same height as the waist in the front view',
          BodyLineKind.hips => isFront
              ? 'Widest part of the hips'
              : 'Same height as the hips in the front view',
        };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: PluginColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PluginColors.border),
      ),
      child: Column(
        children: [
          for (final kind in BodyLineKind.values)
            Padding(
              padding: EdgeInsets.only(
                  bottom: kind == BodyLineKind.values.last ? 0 : 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: _kindInk(kind),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 52,
                    child: Text(
                      kind == BodyLineKind.chest
                          ? (isFemale ? 'BUST' : 'CHEST')
                          : kind.label,
                      style: TextStyle(
                        color: _kindInk(kind),
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      describe(kind),
                      style: const TextStyle(
                        color: PluginColors.textSecondary,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  BodyPartMeasurement _measurementFor(BodyLinesResult r, BodyLineKind kind) {
    final frontScale = widget.calibration.imageWidth / r.front.width;
    final sideScale = widget.calibration.imageWidth / r.side.width;
    final frontCmPerPx = widget.calibration.cmPerPixel;
    final sideCmPerPx = (widget.calibration.sidePixelHeight != null &&
            widget.calibration.sidePixelHeight! > 0)
        ? (widget.calibration.userHeightCm / widget.calibration.sidePixelHeight!)
        : frontCmPerPx;

    final fLine = _frontLines.firstWhere((l) => l.kind == kind,
        orElse: () => r.front.lines.firstWhere((l) => l.kind == kind));
    final sLine = _sideLines.firstWhere((l) => l.kind == kind,
        orElse: () => r.side.lines.firstWhere((l) => l.kind == kind));

    final widthPx = (fLine.xEnd - fLine.xStart).abs() * frontScale;
    final widthCm = widthPx * frontCmPerPx;
    final depthPx = (sLine.xEnd - sLine.xStart).abs() * sideScale;
    final depthCm = depthPx * sideCmPerPx;

    final baseEllipseCm =
        CircumferenceCalculator.calculateBaseEllipse(widthCm, depthCm);
    final k = CircumferenceCalculator.shapeFactorFor(kind);
    final circumferenceCm = baseEllipseCm * k;
    final circumferenceInches =
        CircumferenceCalculator.cmToInches(circumferenceCm);

    return BodyPartMeasurement(
      kind: kind,
      widthPx: widthPx,
      widthCm: widthCm,
      depthPx: depthPx,
      depthCm: depthCm,
      circumferenceCm: circumferenceCm,
      circumferenceInches: circumferenceInches,
      baseEllipseCm: baseEllipseCm,
      shapeFactor: k,
    );
  }

  Widget _buildMeasurementsTable(BodyLinesResult r) {
    String partLabel(BodyLineKind kind) => switch (kind) {
          BodyLineKind.chest =>
            widget.userGender == Gender.female ? 'Bust' : 'Chest',
          BodyLineKind.waist => 'Waist',
          BodyLineKind.hips => 'Hips',
        };

    return Container(
      key: const Key('body_lines_measurements_table'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PluginColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PluginColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.straighten_rounded,
                    size: 16, color: _accent),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BODY MEASUREMENTS & CIRCUMFERENCES',
                      style: TextStyle(
                        color: PluginColors.textPrimary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Front width, side depth, and 3D circumference',
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
          const SizedBox(height: 14),
          for (final kind in BodyLineKind.values) ...[
            Builder(
              builder: (context) {
                final m = _measurementFor(r, kind);
                final color = _kindInk(kind);

                return Container(
                  key: Key('measurement_row_${kind.name}'),
                  margin: EdgeInsets.only(
                      bottom: kind == BodyLineKind.values.last ? 0 : 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: color.withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Top row: part name & circumference pill
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                partLabel(kind),
                                style: const TextStyle(
                                  color: PluginColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: color.withValues(alpha: 0.6),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${m.circumferenceCm.toStringAsFixed(1)} cm',
                                  key: Key('measurement_${kind.name}_circumference_cm'),
                                  style: TextStyle(
                                    color: color,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12.5,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  '  •  ${m.circumferenceInches.toStringAsFixed(1)} in',
                                  key: Key('measurement_${kind.name}_circumference_in'),
                                  style: TextStyle(
                                    color: color.withValues(alpha: 0.85),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      // Sub row: Front width and side depth
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: PluginColors.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'FRONT WIDTH',
                                    style: TextStyle(
                                      color: PluginColors.textSecondary,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${formatPixels(m.widthPx)} px ',
                                          style: const TextStyle(
                                            color: PluginColors.textPrimary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                        TextSpan(
                                          text: '(${formatCm(m.widthCm)} cm)',
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    key: Key('measurement_${kind.name}_width_px'),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              height: 26,
                              width: 1,
                              color: PluginColors.border,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'SIDE DEPTH',
                                    style: TextStyle(
                                      color: PluginColors.textSecondary,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  RichText(
                                    text: TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${formatPixels(m.depthPx)} px ',
                                          style: const TextStyle(
                                            color: PluginColors.textPrimary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                        TextSpan(
                                          text: '(${formatCm(m.depthCm)} cm)',
                                          style: TextStyle(
                                            color: color,
                                            fontSize: 10.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                    key: Key('measurement_${kind.name}_depth_px'),
                                  ),
                                ],
                              ),
                            ),
                          ],
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


  Widget _buildNote(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _warn.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _warn.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: _warn, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: PluginColors.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle get _filledStyle => ElevatedButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );

  ButtonStyle get _outlinedStyle => OutlinedButton.styleFrom(
        foregroundColor: PluginColors.textSecondary,
        side: const BorderSide(color: PluginColors.border),
        padding: const EdgeInsets.symmetric(vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      );
}

/// Draws the three lines (subtle guide + thin measuring bar with caliper
/// brackets) on top of the photo.
class _BodyLinesPainter extends CustomPainter {
  final List<BodyLine> lines;
  final int imageWidth;
  final int imageHeight;

  const _BodyLinesPainter({
    required this.lines,
    required this.imageWidth,
    required this.imageHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / imageWidth;
    final sy = size.height / imageHeight;

    for (final line in lines) {
      final color = _kindColor(line.kind);
      final y = line.y * sy;
      final xl = line.xStart * sx;
      final xr = line.xEnd * sx;

      // 1. Subtle horizontal guide across the whole photo width.
      final guide = Paint()
        ..color = color.withValues(alpha: 0.20)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;
      _dashedHorizontalLine(canvas, size.width, y, guide);

      // 2. High-contrast dark backing outline (crisp 1px border) so the thin colored
      //    line stands out sharply against any skin tone or clothing color.
      final darkBack = Paint()
        ..color = Colors.black.withValues(alpha: 0.75)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;

      const tickH = 7.0; // from y - 7 to y + 7 (14px total caliper height)
      const capW = 3.5; // inward bracket return cap

      // Dark backing: main line
      canvas.drawLine(Offset(xl, y), Offset(xr, y), darkBack);
      // Dark backing: vertical ticks
      canvas.drawLine(Offset(xl, y - tickH), Offset(xl, y + tickH), darkBack);
      canvas.drawLine(Offset(xr, y - tickH), Offset(xr, y + tickH), darkBack);
      // Dark backing: inward bracket caps [ and ]
      canvas.drawLine(Offset(xl, y - tickH), Offset(xl + capW, y - tickH), darkBack);
      canvas.drawLine(Offset(xl, y + tickH), Offset(xl + capW, y + tickH), darkBack);
      canvas.drawLine(Offset(xr, y - tickH), Offset(xr - capW, y - tickH), darkBack);
      canvas.drawLine(Offset(xr, y + tickH), Offset(xr - capW, y + tickH), darkBack);

      // 3. Crisp thin foreground colored line (1.2px) with caliper brackets
      final bar = Paint()
        ..color = color
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.butt
        ..style = PaintingStyle.stroke;

      // Main measuring line
      canvas.drawLine(Offset(xl, y), Offset(xr, y), bar);
      // Vertical caliper ticks
      canvas.drawLine(Offset(xl, y - tickH), Offset(xl, y + tickH), bar);
      canvas.drawLine(Offset(xr, y - tickH), Offset(xr, y + tickH), bar);
      // Inward bracket caps [ and ]
      canvas.drawLine(Offset(xl, y - tickH), Offset(xl + capW, y - tickH), bar);
      canvas.drawLine(Offset(xl, y + tickH), Offset(xl + capW, y + tickH), bar);
      canvas.drawLine(Offset(xr, y - tickH), Offset(xr - capW, y - tickH), bar);
      canvas.drawLine(Offset(xr, y + tickH), Offset(xr - capW, y + tickH), bar);
    }
  }

  void _dashedHorizontalLine(Canvas canvas, double width, double y, Paint p) {
    const dash = 4.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < width) {
      canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0.0, width), y), p);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_BodyLinesPainter old) =>
      old.lines != lines ||
      old.imageWidth != imageWidth ||
      old.imageHeight != imageHeight;
}
