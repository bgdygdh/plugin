/// Represents the user's pose alignment quality.
enum PoseStatus {
  /// Not enough landmarks detected or key zones not satisfied.
  poor,

  /// Some zones are satisfied, but not all.
  fair,

  /// All landmark checks pass — shutter unlocked (combined with tilt check).
  ready,
}
