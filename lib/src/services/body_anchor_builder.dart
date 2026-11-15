import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../models/scale_calibration_exception.dart';
import 'person_mask_analyzer.dart';

/// Converts ML Kit pose landmarks (photo pixels) into mask-space
/// [BodyAnchors] used by [PersonMaskAnalyzer].
///
/// Shared by the scale calibration and the body-lines analysis so both look
/// at the person in exactly the same way.
class BodyAnchorBuilder {
  /// Landmarks below this confidence are ignored.
  static const double minLikelihood = 0.5;

  const BodyAnchorBuilder._();

  static BodyAnchors build(Pose pose, double scaleX, double scaleY) {
    PoseLandmark? visible(PoseLandmarkType type) {
      final landmark = pose.landmarks[type];
      if (landmark == null || landmark.likelihood < minLikelihood) return null;
      return landmark;
    }

    // Head reference: nose, or the average of eyes/ears if the nose is missing.
    double headX;
    double headY;
    final nose = visible(PoseLandmarkType.nose);
    if (nose != null) {
      headX = nose.x;
      headY = nose.y;
    } else {
      final facePoints = <PoseLandmark>[
        for (final type in [
          PoseLandmarkType.leftEye,
          PoseLandmarkType.rightEye,
          PoseLandmarkType.leftEar,
          PoseLandmarkType.rightEar,
        ])
          ?visible(type),
      ];
      if (facePoints.isEmpty) {
        throw const ScaleCalibrationException(
          'We could not see your face. Please face the camera and retake the '
          'photo.',
        );
      }
      headX =
          facePoints.map((p) => p.x).reduce((a, b) => a + b) / facePoints.length;
      headY =
          facePoints.map((p) => p.y).reduce((a, b) => a + b) / facePoints.length;
    }

    final ankles = <PoseLandmark>[
      ?visible(PoseLandmarkType.leftAnkle),
      ?visible(PoseLandmarkType.rightAnkle),
    ];
    if (ankles.isEmpty) {
      throw const ScaleCalibrationException(
        'We could not see your ankles. Step back so your whole body, head to '
        'toe, is in the frame, then retake the photo.',
      );
    }

    final footPoints = <PoseLandmark>[
      ...ankles,
      ?visible(PoseLandmarkType.leftHeel),
      ?visible(PoseLandmarkType.rightHeel),
      ?visible(PoseLandmarkType.leftFootIndex),
      ?visible(PoseLandmarkType.rightFootIndex),
    ];

    double? shoulderWidth;
    final leftShoulder = visible(PoseLandmarkType.leftShoulder);
    final rightShoulder = visible(PoseLandmarkType.rightShoulder);
    if (leftShoulder != null && rightShoulder != null) {
      shoulderWidth = (leftShoulder.x - rightShoulder.x).abs() * scaleX;
    }

    return BodyAnchors(
      noseX: headX * scaleX,
      noseY: headY * scaleY,
      shoulderWidth: shoulderWidth,
      footXs: [for (final p in footPoints) p.x * scaleX],
      lowestFootY: footPoints.map((p) => p.y).reduce((a, b) => a > b ? a : b) *
          scaleY,
      lowestAnkleY: ankles.map((p) => p.y).reduce((a, b) => a > b ? a : b) *
          scaleY,
    );
  }
}
