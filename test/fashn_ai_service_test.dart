import 'dart:convert';
import 'dart:io';

import 'package:body_measurement_plugin/src/models/virtual_try_on.dart';
import 'package:body_measurement_plugin/src/services/fashn_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FashnAiService', () {
    test('toImagePayload preserves remote http and https URLs', () async {
      final service = FashnAiService();
      expect(
        await service.toImagePayload('https://example.com/garment.jpg'),
        'https://example.com/garment.jpg',
      );
      expect(
        await service.toImagePayload('http://example.com/photo.png'),
        'http://example.com/photo.png',
      );
    });

    test('toImagePayload preserves existing data URIs', () async {
      final service = FashnAiService();
      const dataUri = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD...';
      expect(await service.toImagePayload(dataUri), dataUri);
    });

    test('toImagePayload converts local file to Base64 data URI', () async {
      final service = FashnAiService();
      final tempDir = await Directory.systemTemp.createTemp('fashn_test_');
      final tempFile = File('${tempDir.path}/test_img.jpg');
      await tempFile.writeAsBytes([1, 2, 3, 4, 5]);

      final payload = await service.toImagePayload(tempFile.path);
      expect(payload, startsWith('data:image/jpeg;base64,'));
      expect(payload, contains(base64Encode([1, 2, 3, 4, 5])));

      await tempDir.delete(recursive: true);
    });

    test('runTryOn submits request with tryon-max, balanced 1k, and polls until completed',
        () async {
      int pollCount = 0;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/run') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model_name'], 'tryon-max');
          expect(body['inputs']['generation_mode'], 'balanced');
          expect(body['inputs']['resolution'], '1k');
          expect(body['inputs']['product_image'], 'https://example.com/garment.jpg');
          expect(body['inputs']['model_image'], 'https://example.com/model.jpg');
          expect(body['inputs'].containsKey('category'), isFalse);

          return http.Response(
            jsonEncode({'id': 'pred-abc-123', 'error': null}),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        if (request.url.path == '/v1/status/pred-abc-123') {
          pollCount++;
          if (pollCount == 1) {
            return http.Response(
              jsonEncode({
                'id': 'pred-abc-123',
                'status': 'in_progress',
                'output': null,
              }),
              200,
            );
          } else {
            return http.Response(
              jsonEncode({
                'id': 'pred-abc-123',
                'status': 'completed',
                'output': ['https://cdn.fashn.ai/pred-abc-123/result.jpg'],
              }),
              200,
            );
          }
        }

        if (request.url.host == 'cdn.fashn.ai') {
          return http.Response.bytes([10, 20, 30], 200);
        }

        return http.Response('Not found', 404);
      });

      final service = FashnAiService(client: mockClient);
      final updates = <TryOnSessionStatus>[];

      final result = await service.runTryOn(
        modelImagePath: 'https://example.com/model.jpg',
        garmentImagePath: 'https://example.com/garment.jpg',
        category: TryOnCategory.tops,
        pollingInterval: const Duration(milliseconds: 10),
        onStatusUpdate: (status, _) => updates.add(status),
      );

      expect(result.tryOnImageUrl, 'https://cdn.fashn.ai/pred-abc-123/result.jpg');
      expect(result.category, TryOnCategory.tops);
      expect(updates, contains(TryOnSessionStatus.submitting));
      expect(updates, contains(TryOnSessionStatus.inProgress));
      expect(updates, contains(TryOnSessionStatus.completed));
    });

    test('runTryOn throws FashnAiException when API returns error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'Invalid API Key'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = FashnAiService(client: mockClient);

      expect(
        () => service.runTryOn(
          modelImagePath: 'https://example.com/model.jpg',
          garmentImagePath: 'https://example.com/garment.jpg',
          category: TryOnCategory.bottoms,
        ),
        throwsA(isA<FashnAiException>().having(
            (e) => e.message, 'message', contains('Failed to start try-on'))),
      );
    });

    test('runTryOn throws FashnAiException when generation fails on server', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path == '/v1/run') {
          return http.Response(
            jsonEncode({'id': 'pred-fail', 'error': null}),
            200,
          );
        }
        if (request.url.path == '/v1/status/pred-fail') {
          return http.Response(
            jsonEncode({
              'id': 'pred-fail',
              'status': 'failed',
              'error': 'Garment could not be detected',
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final service = FashnAiService(client: mockClient);

      expect(
        () => service.runTryOn(
          modelImagePath: 'https://example.com/model.jpg',
          garmentImagePath: 'https://example.com/garment.jpg',
          category: TryOnCategory.onePieces,
          pollingInterval: const Duration(milliseconds: 10),
        ),
        throwsA(isA<FashnAiException>().having((e) => e.details, 'details',
            contains('Garment could not be detected'))),
      );
    });
  });
}
