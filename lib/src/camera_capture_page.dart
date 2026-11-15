import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/capture_step.dart';
import 'models/pose_status.dart';
import 'models/body_capture_result.dart';
import 'models/scale_calibration_result.dart';
import 'models/size_recommendation.dart';
import 'models/virtual_try_on.dart';
import 'services/pose_validator.dart';
import 'services/tilt_validator.dart';
import 'widgets/silhouette_overlay.dart';
import 'widgets/tilt_indicator.dart';
import 'widgets/pose_feedback_bar.dart';
import 'widgets/snap_button.dart';
import 'review/capture_review_page.dart';
import 'ui/body_lines_page.dart';
import 'ui/calibration_result_page.dart';

/// Full-screen camera page that guides the user through capturing
/// a front-view and a side-view photo for body measurement.
class CameraCapturePage extends StatefulWidget {
  final CameraLensDirection initialLensDirection;

  /// The user's real height in centimetres — used to compute the scale
  /// (cm per pixel) once both photos are confirmed.
  final double userHeightCm;

  /// The user's selected gender (for tailored clothing sizing).
  final Gender userGender;

  final GarmentType? initialGarmentType;
  final TryOnCategory? tryOnCategory;
  final String? garmentImageUrl;
  final String? fashnApiKey;

  const CameraCapturePage({
    super.key,
    required this.userHeightCm,
    this.userGender = Gender.male,
    this.initialLensDirection = CameraLensDirection.back,
    this.initialGarmentType,
    this.tryOnCategory,
    this.garmentImageUrl,
    this.fashnApiKey,
  });

  @override
  State<CameraCapturePage> createState() => _CameraCapturePageState();
}

class _CameraCapturePageState extends State<CameraCapturePage>
    with WidgetsBindingObserver {
  // ── Camera ──────────────────────────────────────────────────────────────
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;
  CameraLensDirection _currentLensDirection = CameraLensDirection.back;

  // ── Hands-Free Auto-Snap (For Solo Users) ────────────────────────────────
  bool _autoSnapEnabled = false;
  int _countdownSeconds = 0;
  Timer? _countdownTimer;

  // ── State ────────────────────────────────────────────────────────────────
  CaptureStep _step = CaptureStep.front;
  PoseStatus _poseStatus = PoseStatus.poor;
  bool _tiltOk = false;
  double _tiltRatio = 0.0;

  String? _frontImagePath;

  // ── Services ─────────────────────────────────────────────────────────────
  late final PoseValidator _poseValidator;
  late final TiltValidator _tiltValidator;

  DateTime? _lastAlignedTime;

  /// While set to a future time, the hands-free countdown will not start.
  /// Gives a solo user time to turn sideways (or back to the front) before
  /// the timer begins.
  DateTime? _autoSnapHoldOffUntil;

  bool get _isInAutoSnapHoldOff {
    final until = _autoSnapHoldOffUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  bool get _isAligned =>
      (_poseStatus == PoseStatus.ready || _poseStatus == PoseStatus.fair) &&
      _tiltOk;

  bool get _canSnap {
    if (!_cameraReady) return false;
    if (_isAligned) return true;
    if (_lastAlignedTime != null) {
      final elapsed =
          DateTime.now().difference(_lastAlignedTime!).inMilliseconds;
      return elapsed < 1200; // 1.2 second grace period
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _currentLensDirection = widget.initialLensDirection;
    // Auto-enable hands-free timer for solo users when starting with front camera
    if (_currentLensDirection == CameraLensDirection.front) {
      _autoSnapEnabled = true;
    }

    _poseValidator = PoseValidator();
    _tiltValidator = TiltValidator();

    _initCamera();
    _tiltValidator.start((isLevel, ratio) {
      if (mounted) {
        setState(() {
          _tiltOk = isLevel;
          _tiltRatio = ratio;
          _checkAlignment();
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _countdownTimer?.cancel();
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _tiltValidator.stop();
    _poseValidator.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return;

    final description = _cameras.firstWhere(
      (c) => c.lensDirection == _currentLensDirection,
      orElse: () => _cameras.first,
    );
    _currentLensDirection = description.lensDirection;

    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await controller.initialize();
    if (!mounted) return;

    await controller.startImageStream(_onCameraFrame);

    setState(() {
      _cameraController = controller;
      _cameraReady = true;
    });
  }

  Future<void> _toggleCamera() async {
    if (_cameras.length <= 1 || !_cameraReady) return;

    _cancelCountdown();

    final targetDirection =
        _currentLensDirection == CameraLensDirection.back
            ? CameraLensDirection.front
            : CameraLensDirection.back;

    final targetDesc = _cameras.firstWhere(
      (c) => c.lensDirection == targetDirection,
      orElse: () => _cameras.first,
    );

    if (targetDesc.lensDirection == _currentLensDirection) return;

    setState(() {
      _cameraReady = false;
      _poseStatus = PoseStatus.poor;
      _lastAlignedTime = null;
      _currentLensDirection = targetDesc.lensDirection;
      // Auto-enable hands-free timer when switching to front camera for solo scanning
      if (targetDesc.lensDirection == CameraLensDirection.front) {
        _autoSnapEnabled = true;
      }
    });

    await _cameraController?.stopImageStream();
    await _cameraController?.dispose();

    final controller = CameraController(
      targetDesc,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    await controller.initialize();
    if (!mounted) return;

    await controller.startImageStream(_onCameraFrame);

    setState(() {
      _cameraController = controller;
      _cameraReady = true;
    });
  }

  void _onCameraFrame(CameraImage image) {
    final controller = _cameraController;
    if (controller == null) return;

    final screenSize = WidgetsBinding
            .instance.platformDispatcher.views.first.physicalSize /
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

    final imageSize = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );

    _poseValidator
        .processFrame(
      image: image,
      imageSize: imageSize,
      rotationDegrees: controller.description.sensorOrientation,
      screenSize: screenSize,
      step: _step,
    )
        .then((status) {
      if (mounted) {
        setState(() {
          _poseStatus = status;
          _checkAlignment();
        });
      }
    });
  }

  /// Updates the alignment latch and (in hands-free mode) starts the countdown.
  ///
  /// Always called from inside a `setState` callback, so it must NOT call
  /// `setState` itself.
  void _checkAlignment() {
    if (_isAligned) {
      _lastAlignedTime = DateTime.now();
      // Start the auto-capture countdown if hands-free mode is enabled — but
      // never while a photo is being taken, and not during the hold-off that
      // gives a solo user time to turn sideways after the front photo.
      if (_autoSnapEnabled &&
          _cameraReady &&
          _countdownTimer == null &&
          _countdownSeconds == 0 &&
          !_isInAutoSnapHoldOff) {
        _startCountdown();
      }
    } else {
      // User moved or tilted away — cancel active countdown
      if (_countdownTimer != null) {
        _cancelCountdown(notify: false);
      }
    }
  }

  /// Must be called from inside a `setState` callback (see [_checkAlignment]).
  void _startCountdown() {
    _countdownSeconds = 3;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (!_canSnap) {
        _cancelCountdown();
        return;
      }
      setState(() {
        _countdownSeconds--;
      });
      if (_countdownSeconds <= 0) {
        _cancelCountdown();
        _onSnap();
      }
    });
  }

  /// Stops the countdown. Pass `notify: false` when already inside `setState`.
  void _cancelCountdown({bool notify = true}) {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdownSeconds == 0) return;
    if (notify && mounted) {
      setState(() => _countdownSeconds = 0);
    } else {
      _countdownSeconds = 0;
    }
  }

  /// Puts the flow back to the front photo and restarts the live analysis.
  Future<void> _restartFlow() async {
    if (!mounted) return;
    setState(() {
      _step = CaptureStep.front;
      _frontImagePath = null;
      _poseStatus = PoseStatus.poor;
      _lastAlignedTime = null;
      // Time for a solo user to turn back to face the camera.
      _autoSnapHoldOffUntil = DateTime.now().add(const Duration(seconds: 3));
      _countdownSeconds = 0;
      _cameraReady = true;
    });
    await _cameraController?.startImageStream(_onCameraFrame);
  }

  Future<void> _onSnap() async {
    if (!_canSnap) return;
    _cancelCountdown();
    _lastAlignedTime = null;
    setState(() => _cameraReady = false);

    try {
      await _cameraController?.stopImageStream();
      final file = await _cameraController?.takePicture();
      if (file == null) {
        throw StateError('The camera returned no picture.');
      }

      if (_step == CaptureStep.front) {
        setState(() {
          _frontImagePath = file.path;
          _step = CaptureStep.side;
          _poseStatus = PoseStatus.poor;
          _lastAlignedTime = null;
          // Time for a solo user to turn 90° before the timer can start.
          _autoSnapHoldOffUntil =
              DateTime.now().add(const Duration(seconds: 4));
          _countdownSeconds = 0;
          _cameraReady = true;
        });
        await _cameraController?.startImageStream(_onCameraFrame);
      } else {
        // Both captured → review → scale calibration
        final frontPath = _frontImagePath!;
        final sidePath = file.path;

        if (!mounted) return;
        final confirmed = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => CaptureReviewPage(
              frontImagePath: frontPath,
              sideImagePath: sidePath,
            ),
          ),
        );

        if (!mounted) return;
        if (confirmed != true) {
          await _restartFlow();
          return;
        }

        final calibration =
            await Navigator.of(context).push<ScaleCalibrationResult>(
          MaterialPageRoute(
            builder: (_) => CalibrationResultPage(
              frontImagePath: frontPath,
              sideImagePath: sidePath,
              userHeightCm: widget.userHeightCm,
            ),
          ),
        );

        if (!mounted) return;
        if (calibration == null) {
          // User chose to retake (or the measurement failed) — start over.
          await _restartFlow();
          return;
        }

        // Visual review of the chest / waist / hip lines (front + side),
        // followed by the size recommendation page.
        final outcome = await Navigator.of(context).push<dynamic>(
          MaterialPageRoute(
            builder: (_) => BodyLinesPage(
              frontImagePath: frontPath,
              sideImagePath: sidePath,
              calibration: calibration,
              userGender: widget.userGender,
              initialGarmentType: widget.initialGarmentType,
              tryOnCategory: widget.tryOnCategory,
              garmentImageUrl: widget.garmentImageUrl,
              fashnApiKey: widget.fashnApiKey,
            ),
          ),
        );

        if (!mounted) return;
        if (outcome == false || outcome == null) {
          // User chose to retake the photos — start over.
          await _restartFlow();
          return;
        }

        final SizeRecommendationResult? recommendation;
        final VirtualTryOnResult? tryOnResult;
        if (outcome is SizeRecommendationOutcome) {
          recommendation = outcome.recommendation;
          tryOnResult = outcome.tryOnResult;
        } else if (outcome is SizeRecommendationResult) {
          recommendation = outcome;
          tryOnResult = null;
        } else {
          recommendation = null;
          tryOnResult = null;
        }

        Navigator.of(context).pop(
          BodyCaptureResult(
            frontImagePath: frontPath,
            sideImagePath: sidePath,
            calibration: calibration,
            recommendation: recommendation,
            gender: recommendation?.gender ?? widget.userGender,
            tryOnResult: tryOnResult,
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _cameraReady = true);
      try {
        await _cameraController?.startImageStream(_onCameraFrame);
      } catch (_) {
        // The stream may already be running — nothing more to do.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Camera preview ──────────────────────────────────────────────
          if (_cameraReady && _cameraController != null)
            _buildCameraPreview(size)
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // ── Silhouette overlay ──────────────────────────────────────────
          if (_cameraReady)
            CustomPaint(
              painter: SilhouetteOverlayPainter(
                step: _step,
                poseStatus: _poseStatus,
              ),
            ),

          // ── Top prompt bar ──────────────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 0,
            right: 0,
            child: _buildPromptBar(),
          ),

          // ── Close button (top-left) ──────────────────────────────────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: _buildCloseButton(),
          ),

          // ── Top Action Buttons (top-right: timer + camera switch) ────────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: _buildTopActions(),
          ),

          // ── Tilt indicator (right edge) ──────────────────────────────────
          Positioned(
            right: 14,
            top: 0,
            bottom: 0,
            child: Center(
              child: TiltIndicatorWidget(
                tiltRatio: _tiltRatio,
                isLevel: _tiltOk,
              ),
            ),
          ),

          // ── Countdown Overlay (for Hands-Free Solo Scanning) ────────────
          if (_countdownSeconds > 0) _buildCountdownOverlay(),

          // ── Bottom controls ──────────────────────────────────────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 24,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PoseFeedbackBar(
                  poseStatus: _poseStatus,
                  tiltOk: _tiltOk,
                  canSnap: _canSnap,
                  countdownSeconds: _countdownSeconds,
                ),
                const SizedBox(height: 20),
                SnapButton(
                  enabled: _canSnap,
                  onSnap: _onSnap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview(Size size) {
    final controller = _cameraController!;
    var cameraAspect = controller.value.aspectRatio;
    if (cameraAspect > 1.0) {
      cameraAspect = 1.0 / cameraAspect;
    }

    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: 100,
            height: 100 / cameraAspect,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }

  Widget _buildPromptBar() {
    final isfront = _step == CaptureStep.front;
    final title = isfront ? 'POSITION: FRONT (1 of 2)' : 'POSITION: SIDE (2 of 2)';
    final sub = isfront
        ? 'Stand facing the camera — fit head to toe in frame'
        : 'Turn 90° sideways — keep head and feet in frame';

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 56),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 11,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Hands-Free Auto-Snap Toggle
        _buildAutoSnapToggle(),
        const SizedBox(width: 8),
        // Camera Flip Button (Back / Front)
        if (_cameras.length > 1) _buildCameraSwitchButton(),
      ],
    );
  }

  Widget _buildAutoSnapToggle() {
    final isActive = _autoSnapEnabled;
    return GestureDetector(
      onTap: () {
        setState(() {
          _autoSnapEnabled = !_autoSnapEnabled;
          if (!_autoSnapEnabled) _cancelCountdown();
        });
      },
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF44FF88).withValues(alpha: 0.18)
              : Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: isActive
                ? const Color(0xFF44FF88).withValues(alpha: 0.6)
                : Colors.white24,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timer_rounded,
              color: isActive ? const Color(0xFF44FF88) : Colors.white70,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              isActive ? 'AUTO 3s' : 'TIMER',
              style: TextStyle(
                color: isActive ? const Color(0xFF44FF88) : Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraSwitchButton() {
    final isFront = _currentLensDirection == CameraLensDirection.front;
    return GestureDetector(
      onTap: _toggleCamera,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isFront
              ? const Color(0xFF44AAFF).withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.55),
          border: Border.all(
            color: isFront ? const Color(0xFF44AAFF) : Colors.white24,
          ),
        ),
        child: Icon(
          Icons.flip_camera_ios_rounded,
          color: isFront ? const Color(0xFF44AAFF) : Colors.white,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildCountdownOverlay() {
    return Center(
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.75),
          border: Border.all(color: const Color(0xFF44FF88), width: 3),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF44FF88).withValues(alpha: 0.45),
              blurRadius: 28,
              spreadRadius: 8,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$_countdownSeconds',
              style: const TextStyle(
                color: Color(0xFF44FF88),
                fontSize: 56,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'HOLD STILL',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(null),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.55),
          border: Border.all(color: Colors.white24),
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 18),
      ),
    );
  }
}
