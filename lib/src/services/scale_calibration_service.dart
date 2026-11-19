import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/scale_calibration_exception.dart';
import '../models/scale_calibration_result.dart';
import 'body_anchor_builder.dart';
import 'person_mask_analyzer.dart';
import 'photo_normalizer.dart';
import 'scale_calculator.dart';

/// Turns the two captured photos + the user's real height into the ONE final
/// scale (cm per pixel).
///
/// Pipeline for each photo:
///  1. Re-encode the photo as an upright PNG using Flutter's own decoder, so
///     the pixels ML Kit sees are exactly the pixels Flutter displays (no
///     EXIF-rotation ambiguity).
///  2. ML Kit Pose Detection  -> landmarks (nose, shoulders, ankles, heels, toes)
///  3. ML Kit Selfie Segmentation -> per-pixel "person" mask
///  4. [PersonMaskAnalyzer] walks outward from the landmarks to find the exact
///     top of the head and bottom of the feet in the mask.
///  5. [ScaleCalculator]: cmPerPixel = userHeightCm / (feetBottomY - headTopY)
///
/// The FRONT photo defines the final scale. The side photo is measured only
/// as a sanity check (best effort — a failure there never blocks the result).
class ScaleCalibrationService {
  /// Nose-to-ankle is about 88% of full height, so full height divided by the
  /// nose-to-ankle distance should be about 1.15. Outside the hard range the
  /// measurement is rejected; outside the soft range a warning is added.
  static const double _hardRatioMin = 1.02;
  static const double _hardRatioMax = 1.35;
  static const double _softRatioMin = 1.08;
  static const double _softRatioMax = 1.22;

  /// Side vs front height difference (fraction) that triggers a warning.
  static const double _sideMismatchWarning = 0.05;

  const ScaleCalibrationService();

  /// Computes the calibration. Throws [ScaleCalibrationException] (with a
  /// user-friendly message) if the FRONT photo cannot be measured reliably.
  Future<ScaleCalibrationResult> calibrate({
    required String frontImagePath,
    required String sideImagePath,
    required double userHeightCm,
  }) async {
    ScaleCalculator.validateUserHeight(userHeightCm);

    final poseDetector = PoseDetector(
      options: PoseDetectorOptions(
        mode: PoseDetectionMode.single,
        model: PoseDetectionModel.accurate,
      ),
    );
    final segmenter = SelfieSegmenter(mode: SegmenterMode.single);

    try {
      final front = await _measure(
        imagePath: frontImagePath,
        poseDetector: poseDetector,
        segmenter: segmenter,
        generateCutout: true,
      );
      final warnings = <String>[...front.warnings];

      double? sidePixelHeight;
      try {
        final side = await _measure(
          imagePath: sideImagePath,
          poseDetector: poseDetector,
          segmenter: segmenter,
          generateCutout: false,
        );
        sidePixelHeight = side.pixelHeight;
      } on ScaleCalibrationException {
        warnings.add(
          'Side photo height check skipped (your full body could not be '
          'detected in the side view). The front photo is still used.',
        );
      } catch (_) {
        warnings.add('Side photo height check skipped (analysis failed).');
      }

      if (sidePixelHeight != null) {
        final diff = (sidePixelHeight - front.pixelHeight) / front.pixelHeight;
        if (diff.abs() > _sideMismatchWarning) {
          final percent = (diff.abs() * 100).toStringAsFixed(1);
          final direction = diff > 0 ? 'larger' : 'smaller';
          warnings.add(
            'In the side photo you appear $percent% $direction than in the '
            'front photo (you probably stood closer or farther away). '
            'The final scale uses the FRONT photo.',
          );
        }
      }

      return ScaleCalculator.calculate(
        userHeightCm: userHeightCm,
        headTopY: front.headTopY,
        feetBottomY: front.feetBottomY,
        imageWidth: front.imageWidth,
        imageHeight: front.imageHeight,
        sidePixelHeight: sidePixelHeight,
        cutoutImagePath: front.cutoutImagePath,
        warnings: warnings,
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

  // ── One photo ──────────────────────────────────────────────────────────────

  Future<_Measurement> _measure({
    required String imagePath,
    required PoseDetector poseDetector,
    required SelfieSegmenter segmenter,
    bool generateCutout = false,
  }) async {
    final photo = await _normalize(imagePath, extractRawRgba: generateCutout);
    try {
      final input = InputImage.fromFilePath(photo.file.path);

      final poses = await poseDetector.processImage(input);
      if (poses.isEmpty) {
        throw const ScaleCalibrationException(
          'We could not detect a person in the photo. Make sure your whole '
          'body is visible and well lit, then retake it.',
        );
      }

      final mask = await segmenter.processImage(input);
      if (mask == null || mask.width <= 0 || mask.height <= 0) {
        throw const ScaleCalibrationException(
          'We could not separate you from the background. Please retake the '
          'photo in better light.',
        );
      }

      // The mask normally has the same size as the photo (scale = 1.0). If it
      // ever differs, convert between photo space and mask space.
      final scaleX = mask.width / photo.width;
      final scaleY = mask.height / photo.height;

      final anchors = _buildAnchors(poses.first, scaleX, scaleY);
      final extent = const PersonMaskAnalyzer().measure(
        confidences: mask.confidences,
        width: mask.width,
        height: mask.height,
        anchors: anchors,
      );

      if (extent.topTouchesImageEdge) {
        throw const ScaleCalibrationException(
          'Your head is cut off at the top of the photo. Step back so there is '
          'space above your head, then retake it.',
        );
      }
      if (extent.bottomTouchesImageEdge) {
        throw const ScaleCalibrationException(
          'Your feet are cut off at the bottom of the photo. Step back so '
          'your feet are fully visible, then retake it.',
        );
      }

      final headTopY = extent.topRow / scaleY;
      final feetBottomY = extent.bottomRowExclusive / scaleY;
      final pixelHeight = feetBottomY - headTopY;

      final bodyScaleInPhoto = anchors.bodyScale / scaleY;
      final ratio = pixelHeight / bodyScaleInPhoto;
      if (!ratio.isFinite || ratio < _hardRatioMin || ratio > _hardRatioMax) {
        throw const ScaleCalibrationException(
          'We could not reliably measure your head-to-toe height. Stand '
          'straight against a plain background with your whole body in the '
          'frame, then retake the photo.',
        );
      }

      final warnings = <String>[];
      if (ratio < _softRatioMin || ratio > _softRatioMax) {
        warnings.add(
          'Your body proportions in the photo look unusual. Check that the '
          'head and feet lines are in the right place.',
        );
      }
      if (extent.headSearchLimited) {
        warnings.add(
          'The top of your head could not be pinned down exactly (hair, a hat '
          'or the background may be merging with it).',
        );
      }
      if (extent.feetSearchLimited) {
        warnings.add(
          'The bottom of your feet could not be pinned down exactly (a floor '
          'shadow or reflection may be merging with them).',
        );
      }

      String? cutoutImagePath;
      if (generateCutout && photo.rawRgba != null) {
        cutoutImagePath = await _createCutout(
          rawRgba: photo.rawRgba!,
          width: photo.width,
          height: photo.height,
          mask: mask,
        );
      }

      return _Measurement(
        headTopY: headTopY,
        feetBottomY: feetBottomY,
        imageWidth: photo.width,
        imageHeight: photo.height,
        warnings: warnings,
        cutoutImagePath: cutoutImagePath,
      );
    } finally {
      try {
        await photo.file.delete();
      } catch (_) {}
    }
  }

  /// Generates a PNG of the person with the background made transparent
  /// using the segmentation mask.
  Future<String?> _createCutout({
    required Uint8List rawRgba,
    required int width,
    required int height,
    required SegmentationMask mask,
  }) async {
    try {
      final scaleX = mask.width / width;
      final scaleY = mask.height / height;
      final totalPixels = width * height;
      final cutout = Uint8List(totalPixels * 4);

      for (var y = 0; y < height; y++) {
        final maskY = (y * scaleY).clamp(0, mask.height - 1).toInt();
        final rowOffset = y * width;
        final maskRowOffset = maskY * mask.width;

        for (var x = 0; x < width; x++) {
          final maskX = (x * scaleX).clamp(0, mask.width - 1).toInt();
          final conf = mask.confidences[maskRowOffset + maskX];
          final i = (rowOffset + x) * 4;

          cutout[i] = rawRgba[i];
          cutout[i + 1] = rawRgba[i + 1];
          cutout[i + 2] = rawRgba[i + 2];

          // Soft edge blending based on person confidence
          if (conf >= 0.65) {
            cutout[i + 3] = rawRgba[i + 3];
          } else if (conf <= 0.25) {
            cutout[i + 3] = 0;
          } else {
            final alphaFraction = (conf - 0.25) / 0.40;
            cutout[i + 3] =
                (rawRgba[i + 3] * alphaFraction).round().clamp(0, 255);
          }
        }
      }

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        cutout,
        width,
        height,
        ui.PixelFormat.rgba8888,
        completer.complete,
      );
      final cutoutImage = await completer.future;
      final pngData =
          await cutoutImage.toByteData(format: ui.ImageByteFormat.png);
      cutoutImage.dispose();

      if (pngData == null) return null;

      final dir = await getTemporaryDirectory();
      final cutoutFile = File(
        '${dir.path}${Platform.pathSeparator}'
        'bm_cutout_${DateTime.now().microsecondsSinceEpoch}.png',
      );
      await cutoutFile.writeAsBytes(
        pngData.buffer.asUint8List(pngData.offsetInBytes, pngData.lengthInBytes),
        flush: true,
      );
      return cutoutFile.path;
    } catch (_) {
      return null;
    }
  }

  /// Converts pose landmarks (photo pixels) into mask-space [BodyAnchors].
  BodyAnchors _buildAnchors(Pose pose, double scaleX, double scaleY) =>
      BodyAnchorBuilder.build(pose, scaleX, scaleY);

  Future<NormalizedPhoto> _normalize(
    String path, {
    bool extractRawRgba = false,
  }) async {
    try {
      return await PhotoNormalizer.normalize(
        path,
        prefix: 'bm_calibration',
        extractRawRgba: extractRawRgba,
      );
    } on ScaleCalibrationException {
      rethrow;
    } catch (e) {
      throw ScaleCalibrationException(
        'The photo could not be read. Please retake it. ($e)',
      );
    }
  }
}

class _Measurement {
  final double headTopY;
  final double feetBottomY;
  final int imageWidth;
  final int imageHeight;
  final List<String> warnings;
  final String? cutoutImagePath;

  const _Measurement({
    required this.headTopY,
    required this.feetBottomY,
    required this.imageWidth,
    required this.imageHeight,
    required this.warnings,
    this.cutoutImagePath,
  });

  double get pixelHeight => feetBottomY - headTopY;
}
