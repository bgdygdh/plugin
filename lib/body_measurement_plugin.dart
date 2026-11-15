export 'src/models/body_capture_result.dart';
export 'src/models/body_lines.dart' show BodyLineKind;
export 'src/models/body_part_measurement.dart';
export 'src/models/capture_step.dart';
export 'src/models/pose_status.dart';
export 'src/models/scale_calibration_exception.dart';
export 'src/models/scale_calibration_result.dart';
export 'src/models/size_recommendation.dart';
export 'src/models/virtual_try_on.dart';
export 'src/services/circumference_calculator.dart';
export 'src/services/fashn_ai_service.dart';
export 'src/services/size_recommendation_service.dart';
export 'src/ui/size_recommendation_page.dart';
export 'src/ui/virtual_try_on_page.dart';
export 'package:camera/camera.dart' show CameraLensDirection;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'src/camera_capture_page.dart';
import 'src/models/body_capture_result.dart';
import 'src/models/size_recommendation.dart';
import 'src/models/virtual_try_on.dart';
import 'src/services/scale_calculator.dart';
import 'src/ui/height_input_page.dart';

/// Body Measurement Plugin.
///
/// Entry point for the host application. Call [startCapture] to launch
/// the guided flow:
///
///  1. Height input (skipped if you pass [startCapture]'s `userHeightCm`)
///  2. Full-screen camera: front photo, then side photo
///  3. Review of both photos
///  4. Scale calibration: the user's real height is divided by their
///     head-to-toe height in pixels to get the ONE final scale (cm per pixel)
class BodyMeasurementPlugin {
  /// Launches the full guided flow.
  ///
  /// [initialCamera] allows selecting [CameraLensDirection.front] or [CameraLensDirection.back].
  /// The user can also toggle between cameras on-screen at any time.
  ///
  /// [userHeightCm] — if you already know the user's height, pass it (between
  /// 100 and 250 cm).
  ///
  /// [userGender] — if you already know the user's gender, pass it ([Gender.male]
  /// or [Gender.female]). If either [userHeightCm] or [userGender] is omitted,
  /// the plugin prompts the user on the setup screen.
  ///
  /// Returns a [BodyCaptureResult] (both image paths plus the calibrated scale,
  /// measurements, and recommended size) after the user accepts the result,
  /// or `null` if the user cancels.
  Future<BodyCaptureResult?> startCapture(
    BuildContext context, {
    CameraLensDirection initialCamera = CameraLensDirection.back,
    double? userHeightCm,
    Gender? userGender,
    GarmentType? initialGarmentType,
    TryOnCategory? tryOnCategory,
    String? garmentImageUrl,
    String? fashnApiKey,
  }) async {
    final navigator = Navigator.of(context);

    double? heightCm = userHeightCm;
    Gender? gender = userGender;

    if (heightCm != null) {
      if (!heightCm.isFinite ||
          heightCm < ScaleCalculator.minUserHeightCm ||
          heightCm > ScaleCalculator.maxUserHeightCm) {
        throw ArgumentError.value(
          userHeightCm,
          'userHeightCm',
          'Must be between ${ScaleCalculator.minUserHeightCm.toStringAsFixed(0)} '
              'and ${ScaleCalculator.maxUserHeightCm.toStringAsFixed(0)} cm.',
        );
      }
    }

    if (heightCm == null || gender == null) {
      final bio = await navigator.push<UserBioProfile>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => HeightInputPage(
            initialHeightCm: heightCm ?? 170,
            initialGender: gender ?? Gender.male,
          ),
        ),
      );

      // The user backed out of the setup screen.
      if (bio == null) return null;
      heightCm = bio.heightCm;
      gender = bio.gender;
    }

    final confirmedHeightCm = heightCm;
    final confirmedGender = gender;

    return navigator.push<BodyCaptureResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CameraCapturePage(
          initialLensDirection: initialCamera,
          userHeightCm: confirmedHeightCm,
          userGender: confirmedGender,
          initialGarmentType: initialGarmentType,
          tryOnCategory: tryOnCategory,
          garmentImageUrl: garmentImageUrl,
          fashnApiKey: fashnApiKey,
        ),
      ),
    );
  }
}
