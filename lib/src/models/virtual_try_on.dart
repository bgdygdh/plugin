/// Garment categories supported by Fashn AI tryon-max.
enum TryOnCategory {
  tops('tops', 'Tops / Shirts'),
  bottoms('bottoms', 'Bottoms / Pants'),
  onePieces('one-pieces', 'One-Pieces / Dresses');

  final String apiValue;
  final String label;

  const TryOnCategory(this.apiValue, this.label);

  static TryOnCategory fromApiValue(String val) => switch (val) {
        'bottoms' => TryOnCategory.bottoms,
        'one-pieces' => TryOnCategory.onePieces,
        _ => TryOnCategory.tops,
      };
}

/// The state of a virtual try-on session.
enum TryOnSessionStatus {
  idle,
  encoding,
  submitting,
  inProgress,
  completed,
  failed;

  bool get isProcessing =>
      this == encoding || this == submitting || this == inProgress;
}

/// Result returned when a virtual try-on is successfully generated.
class VirtualTryOnResult {
  /// The garment category used ('tops', 'bottoms', 'one-pieces').
  final TryOnCategory category;

  /// The original garment image path or URL.
  final String garmentSource;

  /// The CDN image URL returned by Fashn AI.
  final String tryOnImageUrl;

  /// Local cached file path of the downloaded try-on result, if saved.
  final String? localTryOnImagePath;

  /// The timestamp of when the try-on was completed.
  final DateTime timestamp;

  const VirtualTryOnResult({
    required this.category,
    required this.garmentSource,
    required this.tryOnImageUrl,
    this.localTryOnImagePath,
    required this.timestamp,
  });

  @override
  String toString() =>
      'VirtualTryOnResult(category: ${category.apiValue}, url: $tryOnImageUrl)';
}
