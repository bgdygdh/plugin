import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/body_lines.dart';
import 'torso_line_analyzer.dart';

/// Finds the chest, waist and hip lines on the FRONT photo (widths) and the
/// SIDE photo (depths).
///
/// Pipeline per photo: re-encode upright -> ML Kit pose (shoulders / hips) ->
/// ML Kit selfie segmentation mask -> [TorsoLineAnalyzer].
///
/// The front photo decides the anatomical heights; the side photo reuses
/// them relative to its own shoulders and hips.
class BodyLinesService {
  /// Front photo landmarks below this confidence are ignored.
  static const double _frontMinLikelihood = 0.5;

  /// Side photo landmarks are harder to see (one side hides the other), so a
  /// lower confidence is accepted.
  static const double _sideMinLikelihood = 0.3;

  const BodyLinesService();

  /// [frontHeadTopY] / [frontFeetBottomY] are the (possibly user-adjusted)
  /// head and feet positions in the front photo; they are only used to
  /// estimate the side line heights if the side pose cannot be detected.
  Future<BodyLinesResult> analyze({
    required String frontImagePath,
    required String sideImagePath,
    required double frontHeadTopY,
    required double frontFeetBottomY,
  }) async {
    final poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.single,
        model: PoseDetectionModel.accurate,
      ),
    );
    final segmenter = SelfieSegmenter(mode: SegmenterMode.single);

    try {
      final front = await _analyzeFront(
        imagePath: frontImagePath,
        poseDetector: poseDetector,
        segmenter: segmenter,
      );
      final side = await _analyzeSide(
        imagePath: sideImagePath,
        poseDetector: poseDetector,
        segmenter: segmenter,
        front: front,
        frontHeadTopY: frontHeadTopY,
        frontFeetBottomY: frontFeetBottomY,
      );
      return BodyLinesResult(
        front: front.analysis.view,
        side: side.view,
        sideEstimated: side.estimated,
      );
    } finally {
      try {
        await poseDetector.close();
      } catch (_) {}
      try {
        await segmenter.close();
      } catch (_) {}
    }
  }

  // ── Front ──────────────────────────────────────────────────────────────────

  Future<_FrontOutcome> _analyzeFront({
    required String imagePath,
    required PoseDetector poseDetector,
    required SelfieSegmenter segmenter,
  }) async {
    final photo = await _normalize(imagePath);
    try {
      final input = InputImage.fromFilePath(photo.file.path);

      final poses = await poseDetector.processImage(input);
      if (poses.isEmpty) {
        throw const BodyLinesException(
          'We could not detect a person in the front photo. Make sure your '
          'whole body is visible and well lit, then retake it.',
        );
      }
      final mask = await _segment(segmenter, input, 'front');
      final scaleX = mask.width / photo.width;
      final scaleY = mask.height / photo.height;

      PoseLandmark? visible(PoseLandmarkType type) =>
          _visible(poses.first, type, _frontMinLikelihood);
      final leftShoulder = visible(PoseLandmarkType.leftShoulder);
      final rightShoulder = visible(PoseLandmarkType.rightShoulder);
      final leftHip = visible(PoseLandmarkType.leftHip);
      final rightHip = visible(PoseLandmarkType.rightHip);
      if (leftShoulder == null ||
          rightShoulder == null ||
          leftHip == null ||
          rightHip == null) {
        throw const BodyLinesException(
          'We could not see both of your shoulders and hips in the front '
          'photo. Make sure your whole torso is visible, then retake it.',
        );
      }

      final shoulderPhotoY = (leftShoulder.y + rightShoulder.y) / 2;
      final hipPhotoY = (leftHip.y + rightHip.y) / 2;
      final torsoPhoto = hipPhotoY - shoulderPhotoY;
      final torsoCenterPhotoX =
          (leftShoulder.x + rightShoulder.x + leftHip.x + rightHip.x) / 4;

      // Extract innermost hand / wrist landmarks around hip height to prevent
      // the hip caliper line from bridging into the arms / hands.
      final armTypes = [
        PoseLandmarkType.leftWrist,
        PoseLandmarkType.rightWrist,
        PoseLandmarkType.leftThumb,
        PoseLandmarkType.rightThumb,
        PoseLandmarkType.leftIndex,
        PoseLandmarkType.rightIndex,
        PoseLandmarkType.leftPinky,
        PoseLandmarkType.rightPinky,
      ];
      final hipMinY = hipPhotoY - 0.25 * torsoPhoto;
      final hipMaxY = hipPhotoY + 0.35 * torsoPhoto;

      double? leftArmInnerX;
      double? rightArmInnerX;

      for (final type in armTypes) {
        final lm = visible(type);
        if (lm == null || lm.y < hipMinY || lm.y > hipMaxY) continue;
        final maskX = lm.x * scaleX;
        if (lm.x < torsoCenterPhotoX) {
          // On screen-left of the torso: innermost edge is the highest X
          if (leftArmInnerX == null || maskX > leftArmInnerX) {
            leftArmInnerX = maskX;
          }
        } else {
          // On screen-right of the torso: innermost edge is the lowest X
          if (rightArmInnerX == null || maskX < rightArmInnerX) {
            rightArmInnerX = maskX;
          }
        }
      }

      final analysis = const TorsoLineAnalyzer().analyzeFront(
        confidences: mask.confidences,
        width: mask.width,
        height: mask.height,
        landmarks: TorsoLandmarks(
          shoulderCenterX: (leftShoulder.x + rightShoulder.x) / 2 * scaleX,
          shoulderY: shoulderPhotoY * scaleY,
          shoulderWidth: (leftShoulder.x - rightShoulder.x).abs() * scaleX,
          hipCenterX: (leftHip.x + rightHip.x) / 2 * scaleX,
          hipY: hipPhotoY * scaleY,
          hipSpan: (leftHip.x - rightHip.x).abs() * scaleX,
          leftArmInnerX: leftArmInnerX,
          rightArmInnerX: rightArmInnerX,
        ),
      );
      return _FrontOutcome(
        analysis: analysis,
        shoulderPhotoY: shoulderPhotoY,
        hipPhotoY: hipPhotoY,
      );
    } finally {
      try {
        await photo.file.delete();
      } catch (_) {}
    }
  }

  // ── Side ───────────────────────────────────────────────────────────────────

  Future<_SideOutcome> _analyzeSide({
    required String imagePath,
    required PoseDetector poseDetector,
    required SelfieSegmenter segmenter,
    required _FrontOutcome front,
    required double frontHeadTopY,
    required double frontFeetBottomY,
  }) async {
    final photo = await _normalize(imagePath);
    try {
      final input = InputImage.fromFilePath(photo.file.path);

      final poses = await poseDetector.processImage(input);
      final mask = await _segment(segmenter, input, 'side');
      final scaleY = mask.height / photo.height;
      const analyzer = TorsoLineAnalyzer();

      // Shoulder / hip heights from the side pose (any visible side counts).
      double? shoulderPhotoY;
      double? hipPhotoY;
      if (poses.isNotEmpty) {
        final pose = poses.first;
        final shoulders = <double>[
          for (final type in [
            PoseLandmarkType.leftShoulder,
            PoseLandmarkType.rightShoulder,
          ])
            ?_visible(pose, type, _sideMinLikelihood)?.y,
        ];
        final hips = <double>[
          for (final type in [
            PoseLandmarkType.leftHip,
            PoseLandmarkType.rightHip,
          ])
            ?_visible(pose, type, _sideMinLikelihood)?.y,
        ];
        if (shoulders.isNotEmpty && hips.isNotEmpty) {
          shoulderPhotoY = _average(shoulders);
          hipPhotoY = _average(hips);
          if (hipPhotoY - shoulderPhotoY < photo.height * 0.08) {
            // Implausible torso length: do not trust this pose.
            shoulderPhotoY = null;
            hipPhotoY = null;
          }
        }
      }

      var estimated = false;
      if (shoulderPhotoY == null || hipPhotoY == null) {
        // Fallback: place the torso inside the visible person using the same
        // proportions (fractions of head-to-feet) measured on the front photo.
        estimated = true;
        final extent = analyzer.personRowExtent(
          confidences: mask.confidences,
          width: mask.width,
          height: mask.height,
        );
        final frontHeight = frontFeetBottomY - frontHeadTopY;
        if (extent == null || !(frontHeight > 0)) {
          throw const BodyLinesException(
            'We could not find you in the side photo. Make sure your whole '
            'body is visible and well lit, then retake it.',
          );
        }
        final shoulderFraction =
            (front.shoulderPhotoY - frontHeadTopY) / frontHeight;
        final hipFraction = (front.hipPhotoY - frontHeadTopY) / frontHeight;
        final top = extent.top / scaleY;
        final bottom = (extent.bottom + 1) / scaleY;
        shoulderPhotoY = top + shoulderFraction * (bottom - top);
        hipPhotoY = top + hipFraction * (bottom - top);
      }

      final view = analyzer.analyzeSide(
        confidences: mask.confidences,
        width: mask.width,
        height: mask.height,
        shoulderY: shoulderPhotoY * scaleY,
        hipY: hipPhotoY * scaleY,
        fractions: front.analysis.fractions,
      );
      return _SideOutcome(view: view, estimated: estimated);
    } finally {
      try {
        await photo.file.delete();
      } catch (_) {}
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  PoseLandmark? _visible(Pose pose, PoseLandmarkType type, double minLikelihood) {
    final landmark = pose.landmarks[type];
    if (landmark == null || landmark.likelihood < minLikelihood) return null;
    return landmark;
  }

  double _average(List<double> values) =>
      values.reduce((a, b) => a + b) / values.length;

  Future<SegmentationMask> _segment(
    SelfieSegmenter segmenter,
    InputImage input,
    String which,
  ) async {
    final mask = await segmenter.processImage(input);
    if (mask == null || mask.width <= 0 || mask.height <= 0) {
      throw BodyLinesException(
        'We could not separate you from the background in the $which photo. '
        'Please retake it in better light.',
      );
    }
    return mask;
  }

  /// Decodes [path] with Flutter's decoder (which applies the photo's EXIF
  /// rotation, exactly like `Image.file`) and writes an upright PNG copy.
  Future<_NormalizedPhoto> _normalize(String path) async {
    ui.Codec? codec;
    ui.Image? image;
    try {
      final bytes = await File(path).readAsBytes();
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;

      final width = image.width;
      final height = image.height;
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || width <= 0 || height <= 0) {
        throw const BodyLinesException(
          'A photo could not be read. Please retake the photos.',
        );
      }

      final dir = await getTemporaryDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        'bm_lines_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return _NormalizedPhoto(file: file, width: width, height: height);
    } on BodyLinesException {
      rethrow;
    } catch (_) {
      throw const BodyLinesException(
        'A photo could not be read. Please retake the photos.',
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }
}

class _NormalizedPhoto {
  final File file;
  final int width;
  final int height;

  const _NormalizedPhoto({
    required this.file,
    required this.width,
    required this.height,
  });
}

class _FrontOutcome {
  final FrontLinesAnalysis analysis;

  /// Average shoulder / hip height in front-photo pixels.
  final double shoulderPhotoY;
  final double hipPhotoY;

  const _FrontOutcome({
    required this.analysis,
    required this.shoulderPhotoY,
    required this.hipPhotoY,
  });
}

class _SideOutcome {
  final BodyLinesView view;
  final bool estimated;

  const _SideOutcome({required this.view, required this.estimated});
}
