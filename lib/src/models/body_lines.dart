/// The three torso levels that get a measurement line.
enum BodyLineKind { chest, waist, hips }

extension BodyLineKindInfo on BodyLineKind {
  /// Short label shown on the line badge.
  String get label => switch (this) {
        BodyLineKind.chest => 'CHEST',
        BodyLineKind.waist => 'WAIST',
        BodyLineKind.hips => 'HIPS',
      };
}

/// One horizontal line across the body, in the coordinate space of the
/// analysed photo ([BodyLinesView.width] x [BodyLinesView.height]).
///
/// In the FRONT photo the line spans the body width; in the SIDE photo it
/// spans the body depth (front to back).
class BodyLine {
  final BodyLineKind kind;

  /// Vertical position of the line.
  final double y;

  /// Left end of the line.
  final double xStart;

  /// Right end of the line.
  final double xEnd;

  const BodyLine({
    required this.kind,
    required this.y,
    required this.xStart,
    required this.xEnd,
  });

  BodyLine copyWith({double? y, double? xStart, double? xEnd}) => BodyLine(
        kind: kind,
        y: y ?? this.y,
        xStart: xStart ?? this.xStart,
        xEnd: xEnd ?? this.xEnd,
      );
}

/// Left/right body edges for every row of a vertical band.
///
/// It lets the UI re-snap a line to the body outline while the user drags it
/// up or down, without keeping the (very large) segmentation mask in memory.
class EdgeProfile {
  /// Image row that [left] / [right] index 0 belongs to.
  final int firstRow;

  /// Left edge per row, `double.nan` where no body was found.
  final List<double> left;

  /// Right edge per row, `double.nan` where no body was found.
  final List<double> right;

  const EdgeProfile({
    required this.firstRow,
    required this.left,
    required this.right,
  });

  /// Last image row covered by this profile.
  int get lastRow => firstRow + left.length - 1;

  /// The body edges at row [y], or `null` if [y] is outside the band or no
  /// body was found on that row.
  ({double start, double end})? edgesAt(double y) {
    final index = y.round() - firstRow;
    if (index < 0 || index >= left.length) return null;
    final start = left[index];
    final end = right[index];
    if (start.isNaN || end.isNaN || end <= start) return null;
    return (start: start, end: end);
  }
}

/// The three lines of ONE photo plus what is needed to re-snap them.
class BodyLinesView {
  /// Size of the analysed (upright) photo in pixels.
  final int width;
  final int height;

  /// Chest, waist and hips lines, in that order.
  final List<BodyLine> lines;

  /// Per-kind body edges used while dragging.
  final Map<BodyLineKind, EdgeProfile> profiles;

  const BodyLinesView({
    required this.width,
    required this.height,
    required this.lines,
    required this.profiles,
  });
}

/// Lines for both photos.
class BodyLinesResult {
  final BodyLinesView front;
  final BodyLinesView side;

  /// `true` when the side line heights could not be read from the side photo
  /// and were estimated from the front photo instead.
  final bool sideEstimated;

  const BodyLinesResult({
    required this.front,
    required this.side,
    this.sideEstimated = false,
  });
}

/// Thrown (with a user-facing message) when the body lines cannot be found.
class BodyLinesException implements Exception {
  final String message;

  const BodyLinesException(this.message);

  @override
  String toString() => 'BodyLinesException: $message';
}
