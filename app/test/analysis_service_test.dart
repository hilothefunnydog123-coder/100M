import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotcheck/services/analysis_service.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

final request = CheckRequest(
  site: BodySite.arm,
  answers: IntakeAnswers.fromJson({
    'skin_kind': ['rash'],
  }),
  photos: [
    CheckPhoto(
      bytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
      mediaType: 'image/jpeg',
    ),
  ],
);

void main() {
  test('posts the check with the install id and parses the result', () async {
    late http.Request seen;
    final result = Triage.merge(
      id: 'chk_1',
      assessment: demoAssessmentFor(BodySite.arm, request.answers),
      safety: SafetyRules.evaluate(BodySite.arm, request.answers),
      createdAt: DateTime.utc(2026, 9, 25),
    );
    final service = HttpAnalysisService(
      baseUrl: Uri.parse('https://api.example/spotcheck/'),
      installId: 'inst_abc12345',
      client: MockClient((r) async {
        seen = r;
        return http.Response(jsonEncode(result.toJson()), 200);
      }),
    );
    final parsed = await service.analyze(request);
    expect(seen.url.toString(), 'https://api.example/spotcheck/v1/checks');
    expect(seen.headers['x-install-id'], 'inst_abc12345');
    expect((jsonDecode(seen.body) as Map)['site'], 'arm');
    expect(parsed.id, 'chk_1');
    expect(parsed.urgency, result.urgency);
  });

  test('surfaces the server message for rate limits', () async {
    final service = HttpAnalysisService(
      baseUrl: Uri.parse('https://api.example'),
      installId: 'inst_abc12345',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'rate_limited', 'message': 'Slow down a bit.'},
          }),
          429,
        ),
      ),
    );
    await expectLater(
      service.analyze(request),
      throwsA(
        isA<AnalysisError>()
            .having((e) => e.message, 'message', 'Slow down a bit.')
            .having((e) => e.retryable, 'retryable', isTrue),
      ),
    );
  });

  test('invalid requests are not retryable', () async {
    final service = HttpAnalysisService(
      baseUrl: Uri.parse('https://api.example'),
      installId: 'inst_abc12345',
      client: MockClient((_) async => http.Response('nope', 400)),
    );
    await expectLater(
      service.analyze(request),
      throwsA(isA<AnalysisError>().having((e) => e.retryable, 'r', isFalse)),
    );
  });

  test('network failures become a friendly error', () async {
    final service = HttpAnalysisService(
      baseUrl: Uri.parse('https://api.example'),
      installId: 'inst_abc12345',
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      service.analyze(request),
      throwsA(
        isA<AnalysisError>().having(
          (e) => e.message,
          'message',
          contains('internet connection'),
        ),
      ),
    );
  });
}
