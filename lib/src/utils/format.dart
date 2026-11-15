// Small number-formatting helpers shared by the models and the UI.

/// Formats [value] with thousands separators, e.g. `1400` -> `1,400`.
String formatThousands(num value, {int decimals = 0}) {
  final fixed = value.toStringAsFixed(decimals);
  final parts = fixed.split('.');
  var intPart = parts[0];
  var sign = '';
  if (intPart.startsWith('-')) {
    sign = '-';
    intPart = intPart.substring(1);
  }
  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
    buffer.write(intPart[i]);
  }
  final fraction = parts.length > 1 ? '.${parts[1]}' : '';
  return '$sign$buffer$fraction';
}

/// Formats a pixel count: whole numbers without decimals, otherwise 1 decimal.
String formatPixels(double value) {
  return value == value.roundToDouble()
      ? formatThousands(value)
      : formatThousands(value, decimals: 1);
}

/// Formats a centimetre value: `175.0` -> `175`, `175.5` -> `175.5`.
String formatCm(double value) {
  return value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}
