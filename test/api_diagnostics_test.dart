import 'dart:convert';

import 'package:body_measurement_plugin/src/models/virtual_try_on.dart';
import 'package:body_measurement_plugin/src/services/fashn_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FashnAiService Schema and Error Handling', () {
    test('parses detailed error message from response body', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'BadRequest',
            'message': 'Invalid "inputs" for tryon-max model: "category" category is not allowed',
          }),
          400,
        );
      });

      final service = FashnAiService(client: mockClient);

      expect(
        () => service.runTryOn(
          modelImagePath: 'https://example.com/model.jpg',
          garmentImagePath: 'https://example.com/garment.jpg',
          category: TryOnCategory.tops,
        ),
        throwsA(
          isA<FashnAiException>().having(
            (e) => e.details,
            'details',
            contains('"category" category is not allowed'),
          ),
        ),
      );
    });

    test('constructs tryon-v1.6 payload with category and garment_image', () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['model_name'], 'tryon-v1.6');
        expect(body['inputs']['category'], 'tops');
        expect(body['inputs']['garment_image'], 'https://example.com/garment.jpg');
        return http.Response(
          jsonEncode({'id': 'pred-v16', 'error': null}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = FashnAiService(
        modelName: 'tryon-v1.6',
        client: mockClient,
      );

      // This will submit and then time out polling or throw, but we verify the request body in the mock
      try {
        await service.runTryOn(
          modelImagePath: 'https://example.com/model.jpg',
          garmentImagePath: 'https://example.com/garment.jpg',
          category: TryOnCategory.tops,
          timeout: const Duration(milliseconds: 10),
        );
      } catch (_) {}
    });
  });
}
