import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';

/// Normalized upright photo prepared for ML Kit pose & segmentation analysis.
class NormalizedPhoto {
  final File file;
  final int width;
  final int height;
  final Uint8List? rawRgba;

  const NormalizedPhoto({
    required this.file,
    required this.width,
    required this.height,
    this.rawRgba,
  });
}

/// Decodes and normalizes a captured/picked photo for ML Kit without failing
/// when Android GPU readback (`ui.Image.toByteData`) cannot encode a full-size
/// camera texture in release builds.
class PhotoNormalizer {
  const PhotoNormalizer._();

  static const int _fallbackMaxDimension = 1080;

  static Future<NormalizedPhoto> normalize(
    String path, {
    required String prefix,
    bool extractRawRgba = false,
  }) async {
    final sourceFile = File(path);
    if (!await sourceFile.exists()) {
      throw FileSystemException('Photo file does not exist', path);
    }

    final bytes = await sourceFile.readAsBytes();
    if (bytes.isEmpty) {
      throw const FormatException('Photo file is empty.');
    }

    ui.Codec? codec;
    ui.Image? image;
    int width = 0;
    int height = 0;

    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
      width = image.width;
      height = image.height;
      if (width <= 0 || height <= 0) {
        throw const FormatException('Photo has invalid dimensions.');
      }

      // 1. Try full-resolution upright PNG re-encode first.
      ByteData? pngData;
      try {
        pngData = await image.toByteData(format: ui.ImageByteFormat.png);
      } catch (_) {
        pngData = null;
      }

      if (pngData != null) {
        final rawRgba = extractRawRgba ? await _tryReadRawRgba(image) : null;
        final file = await _writeTempFile(
          prefix: prefix,
          extension: 'png',
          bytes: pngData.buffer.asUint8List(
            pngData.offsetInBytes,
            pngData.lengthInBytes,
          ),
          fallbackDir: sourceFile.parent,
        );
        return NormalizedPhoto(
          file: file,
          width: width,
          height: height,
          rawRgba: rawRgba,
        );
      }

      // 2. Full-res GPU PNG readback failed (common on Android Impeller with
      //    high-MP camera photos). Dispose full image and retry downscaled.
      image.dispose();
      image = null;
      codec.dispose();
      codec = null;

      final bool needsScale =
          width > _fallbackMaxDimension || height > _fallbackMaxDimension;
      if (needsScale) {
        final bool landscape = width >= height;
        codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: landscape ? _fallbackMaxDimension : null,
          targetHeight: landscape ? null : _fallbackMaxDimension,
        );
        final scaledFrame = await codec.getNextFrame();
        image = scaledFrame.image;
        final scaledWidth = image.width;
        final scaledHeight = image.height;

        ByteData? scaledPng;
        try {
          scaledPng = await image.toByteData(format: ui.ImageByteFormat.png);
        } catch (_) {
          scaledPng = null;
        }

        if (scaledPng != null && scaledWidth > 0 && scaledHeight > 0) {
          final rawRgba = extractRawRgba ? await _tryReadRawRgba(image) : null;
          final file = await _writeTempFile(
            prefix: prefix,
            extension: 'png',
            bytes: scaledPng.buffer.asUint8List(
              scaledPng.offsetInBytes,
              scaledPng.lengthInBytes,
            ),
            fallbackDir: sourceFile.parent,
          );
          return NormalizedPhoto(
            file: file,
            width: scaledWidth,
            height: scaledHeight,
            rawRgba: rawRgba,
          );
        }
      }

      // 3. Final fallback: copy raw camera bytes so ML Kit reads EXIF directly.
      final ext = _extensionOf(path);
      final file = await _writeTempFile(
        prefix: prefix,
        extension: ext,
        bytes: bytes,
        fallbackDir: sourceFile.parent,
      );
      return NormalizedPhoto(
        file: file,
        width: width,
        height: height,
      );
    } finally {
      image?.dispose();
      codec?.dispose();
    }
  }

  static Future<Uint8List?> _tryReadRawRgba(ui.Image image) async {
    try {
      final rawData =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (rawData == null) return null;
      return rawData.buffer.asUint8List(
        rawData.offsetInBytes,
        rawData.lengthInBytes,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<File> _writeTempFile({
    required String prefix,
    required String extension,
    required Uint8List bytes,
    required Directory fallbackDir,
  }) async {
    Directory dir;
    try {
      dir = await getTemporaryDirectory();
    } catch (_) {
      dir = fallbackDir;
    }

    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot != -1 && dot < path.length - 1) {
      final ext = path.substring(dot + 1).toLowerCase();
      if (ext.length <= 5 && RegExp(r'^[a-z0-9]+$').hasMatch(ext)) {
        return ext;
      }
    }
    return 'jpg';
  }
}
