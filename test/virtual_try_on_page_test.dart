import 'dart:async';
import 'dart:io';

import 'package:body_measurement_plugin/src/models/size_recommendation.dart';
import 'package:body_measurement_plugin/src/models/virtual_try_on.dart';
import 'package:body_measurement_plugin/src/services/fashn_ai_service.dart';
import 'package:body_measurement_plugin/src/ui/virtual_try_on_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final List<int> _kTransparentImage = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
  0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
  0x60, 0x82,
];

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return _FakeHttpClient();
  }
}

class _FakeHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return _FakeHttpClientRequest();
  }

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    return _FakeHttpClientRequest();
  }
}

class _FakeHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async {
    return _FakeHttpClientResponse();
  }
}

class _FakeHttpHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _FakeHttpClientResponse extends Fake implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => _kTransparentImage.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_kTransparentImage).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class FakeFashnAiService extends FashnAiService {
  @override
  Future<VirtualTryOnResult> runTryOn({
    required String modelImagePath,
    required String garmentImagePath,
    required TryOnCategory category,
    String resolution = '1k',
    String generationMode = 'balanced',
    void Function(TryOnSessionStatus status, String message)? onStatusUpdate,
    Duration pollingInterval = const Duration(milliseconds: 10),
    Duration timeout = const Duration(seconds: 10),
  }) async {
    onStatusUpdate?.call(TryOnSessionStatus.submitting, 'Submitting...');
    onStatusUpdate?.call(TryOnSessionStatus.inProgress, 'Fitting...');
    return VirtualTryOnResult(
      category: category,
      garmentSource: garmentImagePath,
      tryOnImageUrl: 'https://cdn.fashn.ai/test_out.jpg',
      localTryOnImagePath: modelImagePath, // Reuse local file for display in widget test
      timestamp: DateTime.now(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = _MockHttpOverrides();
  });

  late File dummyPhoto;

  setUp(() async {
    final tempDir = await Directory.systemTemp.createTemp('tryon_page_test_');
    dummyPhoto = File('${tempDir.path}/dummy_front.jpg');
    await dummyPhoto.writeAsBytes([1, 2, 3, 4]);
  });

  tearDown(() async {
    try {
      await dummyPhoto.parent.delete(recursive: true);
    } catch (_) {}
  });

  group('VirtualTryOnPage', () {
    testWidgets('renders category toggles and defaults from recommendation',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: VirtualTryOnPage(
            frontImagePath: dummyPhoto.path,
            recommendation: const SizeRecommendationResult(
              gender: Gender.female,
              garment: GarmentType.dress,
              recommendedSize: 'M',
              partAssessments: [],
              fitSummary: 'Fits M',
              fullChart: [],
            ),
          ),
        ),
      );

      // Verify category tabs exist
      expect(find.byKey(const Key('tryon_cat_tops')), findsOneWidget);
      expect(find.byKey(const Key('tryon_cat_bottoms')), findsOneWidget);
      expect(find.byKey(const Key('tryon_cat_one-pieces')), findsOneWidget);

      // Switch category to tops
      await tester.tap(find.byKey(const Key('tryon_cat_tops')));
      await tester.pumpAndSettle();

      expect(find.text('START VIRTUAL TRY-ON'), findsOneWidget);
    });

    testWidgets('shows error when submitting without garment',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: VirtualTryOnPage(
            frontImagePath: dummyPhoto.path,
            fashnService: FakeFashnAiService(),
          ),
        ),
      );

      // Verify no credits banner
      expect(find.textContaining('Credits'), findsNothing);

      // Tap start without garment
      await tester.tap(find.text('START VIRTUAL TRY-ON'));
      await tester.pump();

      expect(find.textContaining('Please select or upload a garment'), findsOneWidget);
    });

    testWidgets('completes try-on and returns VirtualTryOnResult when accepted',
        (WidgetTester tester) async {
      VirtualTryOnResult? outcome;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  outcome = await Navigator.of(context).push<VirtualTryOnResult>(
                    MaterialPageRoute(
                      builder: (_) => VirtualTryOnPage(
                        frontImagePath: dummyPhoto.path,
                        initialGarmentPath: dummyPhoto.path,
                        fashnService: FakeFashnAiService(),
                      ),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Ensure credits banner is NOT present on input page
      expect(find.textContaining('Credits'), findsNothing);

      // Now start virtual try-on
      await tester.tap(find.byKey(const Key('tryon_submit_button')));
      await tester.pumpAndSettle();

      // Ensure credits banner is NOT present on result display page
      expect(find.textContaining('Credits'), findsNothing);

      // Expect result view with ACCEPT & FINISH
      expect(find.byKey(const Key('tryon_finish_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('tryon_finish_button')));
      await tester.pumpAndSettle();

      expect(outcome, isNotNull);
      expect(outcome!.tryOnImageUrl, 'https://cdn.fashn.ai/test_out.jpg');
    });
  });
}
