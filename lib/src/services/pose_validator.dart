import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../models/capture_step.dart';
import '../models/pose_status.dart';

/// Processes camera image frames through ML Kit Pose Detection
/// and evaluates whether the user's full body is correctly in frame.
///
/// Designed to be forgiving for everyday use while guaranteeing that the full body
/// (head to toe) is captured without clipping.
class PoseValidator {
  late final PoseDetector _detector;
  bool _isBusy = false;

  PoseValidator() {
    _detector = PoseDetector(
      options: PoseDetectorOptions(
        model: PoseDetectionModel.accurate,
        mode: PoseDetectionMode.stream,
      ),
    );
  }

  /// Processes a [CameraImage] and returns a [PoseStatus] based on landmark checks.
  ///
  /// [imageSize] — the Width × Height of the camera image in pixels.
  /// [rotationDegrees] — the sensor rotation from [CameraDescription.sensorOrientation].
  Future<PoseStatus> processFrame({
    required CameraImage image,
    required Size imageSize,
    required int rotationDegrees,
    required Size screenSize,
    CaptureStep step = CaptureStep.front,
  }) async {
    if (_isBusy) return PoseStatus.poor;
    _isBusy = true;

    try {
      final inputImage = _buildInputImage(image, imageSize, rotationDegrees);
      final poses = await _detector.processImage(inputImage);

      if (poses.isEmpty) return PoseStatus.poor;

      final isRotated = rotationDegrees == 90 || rotationDegrees == 270;
      final frameWidth = isRotated ? imageSize.height : imageSize.width;
      final frameHeight = isRotated ? imageSize.width : imageSize.height;

      final pose = poses.first;
      if (step == CaptureStep.front) {
        return _evaluateFront(pose, frameWidth, frameHeight);
      } else {
        return _evaluateSide(pose, frameWidth, frameHeight);
      }
    } catch (_) {
      return PoseStatus.poor;
    } finally {
      _isBusy = false;
    }
  }

  /// Builds an [InputImage] from a raw [CameraImage] (YUV_420_888 on Android).
  InputImage _buildInputImage(
    CameraImage image,
    Size imageSize,
    int rotationDegrees,
  ) {
    final rotation = _rotationFromDegrees(rotationDegrees);

    final bytes = _concatenatePlanes(image.planes);

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: Platform.isAndroid
            ? InputImageFormat.nv21
            : InputImageFormat.bgra8888,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  /// Evaluates front-facing pose.
  PoseStatus _evaluateFront(Pose pose, double frameWidth, double frameHeight) {
    final lm = pose.landmarks;

    double? normX(PoseLandmarkType type) {
      final l = lm[type];
      return l == null ? null : (l.x / frameWidth).clamp(0.0, 1.0);
    }

    double? normY(PoseLandmarkType type) {
      final l = lm[type];
      return l == null ? null : (l.y / frameHeight).clamp(0.0, 1.0);
    }

    int checks = 0;

    // 1. Head / Face in upper section
    final headY = [
      normY(PoseLandmarkType.nose),
      normY(PoseLandmarkType.leftEye),
      normY(PoseLandmarkType.rightEye),
      normY(PoseLandmarkType.leftEar),
      normY(PoseLandmarkType.rightEar),
    ].whereType<double>().toList();
    if (headY.isNotEmpty && headY.any((y) => y > 0.02 && y < 0.38)) {
      checks++;
    }

    // 2. Lower body in lower section (ankles, heels, or knees)
    final lowerY = [
      normY(PoseLandmarkType.leftAnkle),
      normY(PoseLandmarkType.rightAnkle),
      normY(PoseLandmarkType.leftHeel),
      normY(PoseLandmarkType.rightHeel),
      normY(PoseLandmarkType.leftKnee),
      normY(PoseLandmarkType.rightKnee),
    ].whereType<double>().toList();
    if (lowerY.isNotEmpty && lowerY.any((y) => y > 0.60 && y < 0.99)) {
      checks++;
    }

    // 3. Torso detected (at least one shoulder and at least one hip)
    final hasShoulder = normY(PoseLandmarkType.leftShoulder) != null ||
        normY(PoseLandmarkType.rightShoulder) != null;
    final hasHip = normY(PoseLandmarkType.leftHip) != null ||
        normY(PoseLandmarkType.rightHip) != null;
    if (hasShoulder && hasHip) {
      checks++;
    }

    // 4. Centered in frame horizontally
    final leftShoulderX = normX(PoseLandmarkType.leftShoulder);
    final rightShoulderX = normX(PoseLandmarkType.rightShoulder);
    final leftHipX = normX(PoseLandmarkType.leftHip);
    final rightHipX = normX(PoseLandmarkType.rightHip);
    final allX = [leftShoulderX, rightShoulderX, leftHipX, rightHipX]
        .whereType<double>()
        .toList();
    if (allX.isNotEmpty) {
      final minX = allX.reduce((a, b) => a < b ? a : b);
      final maxX = allX.reduce((a, b) => a > b ? a : b);
      if (minX > 0.04 && maxX < 0.96) {
        checks++;
      }
    }

    if (checks >= 3) return PoseStatus.ready;
    if (checks >= 2) return PoseStatus.fair;
    return PoseStatus.poor;
  }

  /// Evaluates side-profile pose (tolerant of self-occlusion).
  PoseStatus _evaluateSide(Pose pose, double frameWidth, double frameHeight) {
    final lm = pose.landmarks;

    double? normY(PoseLandmarkType type) {
      final l = lm[type];
      return l == null ? null : (l.y / frameHeight).clamp(0.0, 1.0);
    }

    int checks = 0;

    // 1. Head / Face visible in upper section (nose, ear, or eye)
    final headY = [
      normY(PoseLandmarkType.nose),
      normY(PoseLandmarkType.leftEar),
      normY(PoseLandmarkType.rightEar),
      normY(PoseLandmarkType.leftEye),
      normY(PoseLandmarkType.rightEye),
    ].whereType<double>().toList();
    if (headY.isNotEmpty && headY.any((y) => y > 0.02 && y < 0.40)) {
      checks++;
    }

    // 2. Lower body visible in lower half (at least one ankle, heel, or knee)
    final lowerY = [
      normY(PoseLandmarkType.leftAnkle),
      normY(PoseLandmarkType.rightAnkle),
      normY(PoseLandmarkType.leftHeel),
      normY(PoseLandmarkType.rightHeel),
      normY(PoseLandmarkType.leftKnee),
      normY(PoseLandmarkType.rightKnee),
    ].whereType<double>().toList();
    if (lowerY.isNotEmpty && lowerY.any((y) => y > 0.58 && y < 0.99)) {
      checks++;
    }

    // 3. Side torso presence (at least one shoulder and at least one hip)
    final hasShoulder = normY(PoseLandmarkType.leftShoulder) != null ||
        normY(PoseLandmarkType.rightShoulder) != null;
    final hasHip = normY(PoseLandmarkType.leftHip) != null ||
        normY(PoseLandmarkType.rightHip) != null;
    if (hasShoulder && hasHip) {
      checks++;
    }

    // 4. Centered in frame horizontally
    final allX = lm.values.map((l) => (l.x / frameWidth).clamp(0.0, 1.0)).toList();
    if (allX.isNotEmpty) {
      final avgX = allX.reduce((a, b) => a + b) / allX.length;
      if (avgX > 0.08 && avgX < 0.92) {
        checks++;
      }
    }

    if (checks >= 3) return PoseStatus.ready;
    if (checks >= 2) return PoseStatus.fair;
    return PoseStatus.poor;
  }

  InputImageRotation _rotationFromDegrees(int degrees) {
    switch (degrees) {
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final allBytes = <int>[];
    for (final plane in planes) {
      allBytes.addAll(plane.bytes);
    }
    return Uint8List.fromList(allBytes);
  }

  Future<void> dispose() async {
    await _detector.close();
  }
}
