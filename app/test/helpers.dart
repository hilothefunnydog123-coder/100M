import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobwalk/app.dart';
import 'package:jobwalk/config.dart';
import 'package:jobwalk/data/blob_store.dart';
import 'package:jobwalk/data/settings.dart';
import 'package:jobwalk/services/api.dart';
import 'package:jobwalk/services/photos.dart';
import 'package:jobwalk/state/providers.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

final testNow = DateTime.utc(2026, 9, 25, 15);

/// Last text the app copied.
String? clipboard;

AppSettings testSettings({bool setupDone = true}) => AppSettings(
  installId: 'inst_test',
  setupDone: setupDone,
  profile: setupDone
      ? const BusinessProfile(
          name: 'Brightline Painting',
          trades: [Trade.painting],
        )
      : const BusinessProfile(name: ''),
  rates: Rates.forTrade(Trade.painting),
);

/// The demo client, plus switches to fail a draft or return bad photos.
class TestClient extends DemoJobwalkClient {
  TestClient(BlobStore store)
    : super(store: store, draftDelay: Duration.zero, clock: () => testNow);

  final draftRequests = <DraftRequest>[];

  /// Thrown by the next draft, then cleared.
  ApiError? failNext;
  AiDraft? nextDraft;

  @override
  Future<DraftResult> draft(DraftRequest request, {SampleJob? sample}) async {
    draftRequests.add(request);
    final error = failNext;
    if (error != null) {
      failNext = null;
      throw error;
    }
    final canned = nextDraft;
    if (canned != null) {
      nextDraft = null;
      return DraftResult(draft: canned, model: 'test');
    }
    return super.draft(request, sample: sample);
  }
}

class FakePhotoSource implements PhotoSource {
  @override
  Future<List<Uint8List>> pick(PhotoOrigin origin, {int max = 8}) async => [
    Uint8List.fromList(tinyJpeg),
  ];
}

Future<JobPhotoFile> fakeProcess(Uint8List bytes) async =>
    JobPhotoFile(jpeg: bytes, preview: bytes);

class TestApp {
  TestApp(this.container, this.client);

  final ProviderContainer container;
  final TestClient client;

  AppSettings get settings => container.read(settingsProvider);
  List<Quote> get quotes => container.read(quotesProvider);
}

/// Pumps the whole app on a phone-sized screen.
Future<TestApp> pumpApp(
  WidgetTester tester, {
  AppSettings? settings,
  List<Quote> quotes = const [],
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  // The test environment has no clipboard; accept and remember writes.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    },
  );

  final store = MemoryBlobStore();
  final client = TestClient(store);
  final container = ProviderContainer(
    overrides: [
      configProvider.overrideWithValue(const AppConfig()),
      blobStoreProvider.overrideWithValue(store),
      initialSettingsProvider.overrideWithValue(settings ?? testSettings()),
      initialQuotesProvider.overrideWithValue(quotes),
      clientProvider.overrideWithValue(client),
      clockProvider.overrideWithValue(() => testNow),
      photoSourceProvider.overrideWithValue(FakePhotoSource()),
      photoProcessorProvider.overrideWithValue(fakeProcess),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const JobwalkApp()),
  );
  await tester.pumpAndSettle();
  return TestApp(container, client);
}

/// The vertical list on top: a sheet's list if one is open, else the page's.
Finder get topList => find
    .byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    )
    .last;

/// Scrolls the topmost vertical list until [finder] is on screen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: topList,
      maxScrolls: 60,
    );
  }
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  await scrollTo(tester, find.text(text));
  final target = find.text(text).hitTestable();
  expect(target, findsWidgets, reason: 'No tappable "$text"');
  await tester.tap(target.first);
  await tester.pumpAndSettle();
}

/// A 1x1 JPEG.
const tinyJpeg = [
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, //
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
  0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
  0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
  0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
  0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
  0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
  0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
  0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x1F, 0x00, 0x00,
  0x01, 0x05, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
  0x09, 0x0A, 0x0B, 0xFF, 0xC4, 0x00, 0xB5, 0x10, 0x00, 0x02, 0x01, 0x03,
  0x03, 0x02, 0x04, 0x03, 0x05, 0x05, 0x04, 0x04, 0x00, 0x00, 0x01, 0x7D,
  0x01, 0x02, 0x03, 0x00, 0x04, 0x11, 0x05, 0x12, 0x21, 0x31, 0x41, 0x06,
  0x13, 0x51, 0x61, 0x07, 0x22, 0x71, 0x14, 0x32, 0x81, 0x91, 0xA1, 0x08,
  0x23, 0x42, 0xB1, 0xC1, 0x15, 0x52, 0xD1, 0xF0, 0x24, 0x33, 0x62, 0x72,
  0x82, 0x09, 0x0A, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x25, 0x26, 0x27, 0x28,
  0x29, 0x2A, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x43, 0x44, 0x45,
  0x46, 0x47, 0x48, 0x49, 0x4A, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59,
  0x5A, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x73, 0x74, 0x75,
  0x76, 0x77, 0x78, 0x79, 0x7A, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89,
  0x8A, 0x92, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0xA2, 0xA3,
  0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0xA9, 0xAA, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6,
  0xB7, 0xB8, 0xB9, 0xBA, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8, 0xC9,
  0xCA, 0xD2, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xE1, 0xE2,
  0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xF1, 0xF2, 0xF3, 0xF4,
  0xF5, 0xF6, 0xF7, 0xF8, 0xF9, 0xFA, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01,
  0x00, 0x00, 0x3F, 0x00, 0xFB, 0xD3, 0xFF, 0xD9,
];
