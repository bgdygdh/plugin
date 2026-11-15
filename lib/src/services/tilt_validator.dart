import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';

/// Listens to the device accelerometer and determines if the phone
/// is held sufficiently perpendicular (portrait, face-towards-user).
///
/// Level condition: |Z acceleration| < [maxZThreshold] m/s²
/// (phone flat = Z ≈ 9.8, phone perfectly upright = Z ≈ 0)
class TiltValidator {
  final double maxZThreshold;

  StreamSubscription<AccelerometerEvent>? _subscription;

  /// Raw Z-axis value in m/s² (updated continuously).
  double _zValue = 9.8;

  /// Smoothed Z value using exponential moving average.
  double _smoothedZ = 9.8;

  TiltValidator({this.maxZThreshold = 2.8});

  /// Returns true when the device tilt is within acceptable range.
  bool get isLevel => _smoothedZ.abs() < maxZThreshold;

  /// Normalised tilt ratio in [-1.0, 1.0] for the bubble indicator.
  /// 0.0 = perfectly level. Positive = tilted toward user, negative = away.
  double get tiltRatio => (_smoothedZ / 9.8).clamp(-1.0, 1.0);

  /// Start listening to accelerometer events.
  void start(void Function(bool isLevel, double tiltRatio) onUpdate) {
    _subscription = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((event) {
      _zValue = event.z;
      // Exponential moving average for smoothing (alpha = 0.12)
      _smoothedZ = _smoothedZ * 0.88 + _zValue * 0.12;
      onUpdate(isLevel, tiltRatio);
    });
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }
}
