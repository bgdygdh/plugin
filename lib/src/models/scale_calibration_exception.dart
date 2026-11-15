/// Thrown when the height-to-scale calibration cannot produce a trustworthy
/// result (person not found, head/feet cut off, invalid height, ...).
///
/// [message] is written for end users and is safe to show on screen.
class ScaleCalibrationException implements Exception {
  final String message;

  const ScaleCalibrationException(this.message);

  @override
  String toString() => 'ScaleCalibrationException: $message';
}
