import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotcheck/app.dart';
import 'package:spotcheck/config.dart';
import 'package:spotcheck/data/blob_store.dart';
import 'package:spotcheck/data/models.dart';
import 'package:spotcheck/services/analysis_service.dart';
import 'package:spotcheck/state/check_flow.dart';
import 'package:spotcheck/state/providers.dart';
import 'package:spotcheck_core/photo_pipeline.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

/// Returns a canned result, or throws, and records what it was asked.
class FakeAnalysisService implements AnalysisService {
  FakeAnalysisService({this.error});

  final AnalysisError? error;
  final requests = <CheckRequest>[];

  @override
  Future<CheckResult> analyze(CheckRequest request) async {
    requests.add(request);
    if (error != null) throw error!;
    return Triage.merge(
      id: newId('chk'),
      assessment: demoAssessmentFor(request.site, request.answers),
      safety: SafetyRules.evaluate(request.site, request.answers),
      createdAt: DateTime.now().toUtc(),
      model: 'test',
    );
  }
}

AppSettings testSettings({
  bool onboarded = true,
  int checksUsed = 0,
  bool pro = false,
  Map<String, List<String>> profile = const {
    'age_band': ['18_39'],
  },
}) => AppSettings(
  installId: 'inst_test',
  onboarded: onboarded,
  checksUsed: checksUsed,
  pro: pro,
  profile: profile,
);

DraftPhoto testPhoto({PhotoKind kind = PhotoKind.closeUp}) => DraftPhoto(
  // A 1x1 JPEG; the UI only needs decodable bytes.
  jpeg: Uint8List.fromList(_tinyJpeg),
  kind: kind,
  quality: const PhotoQuality(
    width: 1200,
    height: 1200,
    brightness: 0.55,
    sharpness: 80,
    glare: 0,
  ),
);

class TestApp {
  TestApp(this.container, this.analysis);

  final ProviderContainer container;
  final FakeAnalysisService analysis;
}

/// Pumps the whole app on a phone-sized screen.
Future<TestApp> pumpApp(
  WidgetTester tester, {
  AppSettings? settings,
  List<CheckRecord> history = const [],
  FakeAnalysisService? analysis,
  int freeChecks = 3,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final service = analysis ?? FakeAnalysisService();
  final container = ProviderContainer(
    overrides: [
      configProvider.overrideWithValue(AppConfig(freeChecks: freeChecks)),
      blobStoreProvider.overrideWithValue(MemoryBlobStore()),
      initialSettingsProvider.overrideWithValue(settings ?? testSettings()),
      initialHistoryProvider.overrideWithValue(history),
      analysisServiceProvider.overrideWithValue(service),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const SpotCheckApp(),
    ),
  );
  await tester.pumpAndSettle();
  return TestApp(container, service);
}

/// Scrolls the current page until [text] is on screen. Returns false if it
/// never appears.
Future<bool> scrollToText(WidgetTester tester, String text) async {
  var target = find.text(text).hitTestable();
  if (target.evaluate().isNotEmpty) return true;
  // The page body is the lowest scrollable on screen.
  final scrollable = find
      .descendant(
        of: find.byType(Scaffold).last,
        matching: find.byType(Scrollable),
      )
      .first;
  for (var dy in [-250.0, 250.0]) {
    for (var i = 0; i < 30 && target.evaluate().isEmpty; i++) {
      final before = find.byType(Text).hitTestable().evaluate().length;
      await tester.drag(scrollable, Offset(0, dy));
      await tester.pumpAndSettle();
      target = find.text(text).hitTestable();
      final after = find.byType(Text).hitTestable().evaluate().length;
      if (i > 2 && before == after && target.evaluate().isEmpty) break;
    }
    if (target.evaluate().isNotEmpty) return true;
  }
  return false;
}

/// Taps the widget with [text], scrolling it into view first.
Future<void> tapText(WidgetTester tester, String text) async {
  if (!await scrollToText(tester, text)) {
    final visible = find
        .byType(Text)
        .hitTestable()
        .evaluate()
        .map((e) => (e.widget as Text).data)
        .whereType<String>()
        .toList();
    fail('No tappable "$text". Visible: $visible');
  }
  await tester.tap(find.text(text).hitTestable().first);
  await tester.pumpAndSettle();
}

const _tinyJpeg = [
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, //
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xDB, 0x00, 0x43,
  0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
  0x09, 0x08, 0x0A, 0x0C, 0x14, 0x0D, 0x0C, 0x0B, 0x0B, 0x0C, 0x19, 0x12,
  0x13, 0x0F, 0x14, 0x1D, 0x1A, 0x1F, 0x1E, 0x1D, 0x1A, 0x1C, 0x1C, 0x20,
  0x24, 0x2E, 0x27, 0x20, 0x22, 0x2C, 0x23, 0x1C, 0x1C, 0x28, 0x37, 0x29,
  0x2C, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1F, 0x27, 0x39, 0x3D, 0x38, 0x32,
  0x3C, 0x2E, 0x33, 0x34, 0x32, 0xFF, 0xC0, 0x00, 0x0B, 0x08, 0x00, 0x01,
  0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xFF, 0xC4, 0x00, 0x14, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x09, 0xFF, 0xC4, 0x00, 0x14, 0x10, 0x01, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0xFF, 0xDA, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3F,
  0x00, 0xD2, 0xCF, 0x20, 0xFF, 0xD9,
];
