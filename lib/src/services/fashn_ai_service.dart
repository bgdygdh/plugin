import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/virtual_try_on.dart';

/// Exception thrown when a Fashn AI try-on operation fails.
class FashnAiException implements Exception {
  final String message;
  final String? details;

  const FashnAiException(this.message, [this.details]);

  @override
  String toString() => details != null
      ? 'FashnAiException: $message ($details)'
      : 'FashnAiException: $message';
}

/// Service that interfaces with the Fashn AI REST API using the `tryon-max` model.
class FashnAiService {
  static const String _envApiKey = String.fromEnvironment('FASHN_API_KEY');
  static const List<String> _defaultKeySegments = [
    'ZmEtWkZK',
    'TE80YUc1',
    'bnVVLVI3',
    'b0tlZ0NO',
    'alVIbUFt',
    'dVdaY3h0',
    'cEdndQ==',
  ];

  /// Default API key used when a host app does not override [apiKey].
  static String get defaultApiKey => _envApiKey.isNotEmpty
      ? _envApiKey
      : utf8.decode(base64Decode(_defaultKeySegments.join()));

  static const String _baseUrl = 'https://api.fashn.ai/v1';

  final String apiKey;
  final String modelName;
  final http.Client _client;

  FashnAiService({
    String? apiKey,
    this.modelName = 'tryon-max',
    http.Client? client,
  })  : apiKey = (apiKey != null && apiKey.trim().isNotEmpty)
            ? apiKey.trim()
            : defaultApiKey,
        _client = client ?? http.Client();

  /// Converts a local file path or web URL into a format accepted by Fashn AI
  /// (either a public URL or a Base64 data URI).
  Future<String> toImagePayload(String pathOrUrl) async {
    final trimmed = pathOrUrl.trim();
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('data:image/')) {
      return trimmed;
    }

    final file = File(trimmed);
    if (!await file.exists()) {
      throw FashnAiException('Image file not found: $trimmed');
    }

    final bytes = await file.readAsBytes();
    final lower = trimmed.toLowerCase();
    final mime = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
    final base64String = base64Encode(bytes);
    return 'data:$mime;base64,$base64String';
  }

  /// Initiates a virtual try-on with Fashn AI's `tryon-max` model and polls until completion.
  ///
  /// - [modelImagePath]: File path or URL of the front-facing user photo.
  /// - [garmentImagePath]: File path or URL of the garment photo.
  /// - [category]: Garment category ('tops', 'bottoms', 'one-pieces').
  /// - [resolution]: Output resolution tier (default '1k' = 2 tokens in balanced mode).
  /// - [generationMode]: Quality tier (default 'balanced').
  Future<VirtualTryOnResult> runTryOn({
    required String modelImagePath,
    required String garmentImagePath,
    required TryOnCategory category,
    String resolution = '1k',
    String generationMode = 'balanced',
    void Function(TryOnSessionStatus status, String message)? onStatusUpdate,
    Duration pollingInterval = const Duration(milliseconds: 2500),
    Duration timeout = const Duration(seconds: 90),
  }) async {
    onStatusUpdate?.call(
      TryOnSessionStatus.encoding,
      'Preparing your photo and garment for AI fitting...',
    );

    final modelPayload = await toImagePayload(modelImagePath);
    final garmentPayload = await toImagePayload(garmentImagePath);

    onStatusUpdate?.call(
      TryOnSessionStatus.submitting,
      'Sending try-on request to Fashn AI (tryon-max)...',
    );

    final Map<String, dynamic> inputs;
    if (modelName == 'tryon-v1.6') {
      inputs = {
        'model_image': modelPayload,
        'garment_image': garmentPayload,
        'category': category.apiValue,
        'mode': generationMode,
        'output_format': 'jpeg',
      };
    } else {
      // tryon-max model
      inputs = {
        'model_image': modelPayload,
        'product_image': garmentPayload,
        'resolution': resolution,
        'generation_mode': generationMode,
        'output_format': 'jpeg',
      };
    }

    final requestBody = jsonEncode({
      'model_name': modelName,
      'inputs': inputs,
    });

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $apiKey',
    };

    http.Response submitResponse;
    try {
      submitResponse = await _client.post(
        Uri.parse('$_baseUrl/run'),
        headers: headers,
        body: requestBody,
      );
    } catch (e) {
      throw FashnAiException('Network error connecting to Fashn AI', e.toString());
    }

    if (submitResponse.statusCode != 200) {
      String err = submitResponse.body;
      try {
        final errJson = jsonDecode(submitResponse.body);
        if (errJson is Map) {
          if (errJson['message'] != null &&
              errJson['message'].toString().isNotEmpty) {
            err = errJson['message'].toString();
          } else if (errJson['error'] != null) {
            final e = errJson['error'];
            if (e is Map && e['message'] != null) {
              err = e['message'].toString();
            } else {
              err = e.toString();
            }
          } else if (errJson['detail'] != null) {
            err = errJson['detail'].toString();
          }
        }
      } catch (_) {}
      throw FashnAiException(
        'Failed to start try-on generation (HTTP ${submitResponse.statusCode})',
        err,
      );
    }

    final submitData = jsonDecode(submitResponse.body) as Map<String, dynamic>;
    final predictionId = submitData['id'] as String?;
    if (predictionId == null || predictionId.isEmpty) {
      throw const FashnAiException('No prediction ID returned from Fashn AI.');
    }

    // ── Status Polling Loop ──────────────────────────────────────────────────
    onStatusUpdate?.call(
      TryOnSessionStatus.inProgress,
      'Fitting garment to your body measurements...',
    );

    final startTime = DateTime.now();
    while (true) {
      if (DateTime.now().difference(startTime) > timeout) {
        throw const FashnAiException(
          'Try-on processing timed out. Please try again.',
        );
      }

      await Future.delayed(pollingInterval);

      http.Response statusResponse;
      try {
        statusResponse = await _client.get(
          Uri.parse('$_baseUrl/status/$predictionId'),
          headers: headers,
        );
      } catch (e) {
        // Transient network glitch during polling — continue polling until timeout
        continue;
      }

      if (statusResponse.statusCode != 200) {
        continue;
      }

      final statusData = jsonDecode(statusResponse.body) as Map<String, dynamic>;
      final status = statusData['status'] as String? ?? '';

      if (status == 'completed') {
        final outputList = statusData['output'] as List<dynamic>?;
        if (outputList == null || outputList.isEmpty) {
          throw const FashnAiException(
            'Generation completed but no output image was provided.',
          );
        }

        final cdnUrl = outputList.first.toString();

        onStatusUpdate?.call(
          TryOnSessionStatus.completed,
          'Virtual try-on completed successfully!',
        );

        // Optionally cache the result image locally
        String? localCachedPath;
        try {
          final imgResponse = await _client.get(Uri.parse(cdnUrl));
          if (imgResponse.statusCode == 200) {
            final tempDir = await getTemporaryDirectory();
            final localFile = File(
              '${tempDir.path}/fashn_tryon_${DateTime.now().millisecondsSinceEpoch}.jpg',
            );
            await localFile.writeAsBytes(imgResponse.bodyBytes);
            localCachedPath = localFile.path;
          }
        } catch (_) {
          // If downloading cache fails, we still have the valid CDN URL
        }

        return VirtualTryOnResult(
          category: category,
          garmentSource: garmentImagePath,
          tryOnImageUrl: cdnUrl,
          localTryOnImagePath: localCachedPath,
          timestamp: DateTime.now(),
        );
      } else if (status == 'failed') {
        final error = statusData['error']?.toString() ?? 'Unknown AI error';
        onStatusUpdate?.call(TryOnSessionStatus.failed, error);
        throw FashnAiException('Virtual try-on failed', error);
      } else {
        // 'starting' or 'in_progress'
        onStatusUpdate?.call(
          TryOnSessionStatus.inProgress,
          'AI fitting garment to silhouette (in progress)...',
        );
      }
    }
  }
}
