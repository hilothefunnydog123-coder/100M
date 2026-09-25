import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:spotcheck_core/spotcheck_core.dart';

abstract interface class AnalysisService {
  Future<CheckResult> analyze(CheckRequest request);
}

/// A failure the UI can explain to the person.
class AnalysisError implements Exception {
  const AnalysisError(this.message, {this.retryable = true});

  final String message;
  final bool retryable;

  @override
  String toString() => message;
}

/// Talks to the SpotCheck API (see `server/`).
class HttpAnalysisService implements AnalysisService {
  HttpAnalysisService({
    required this.baseUrl,
    required this.installId,
    http.Client? client,
    this.timeout = const Duration(seconds: 180),
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final String installId;
  final Duration timeout;
  final http.Client _client;

  @override
  Future<CheckResult> analyze(CheckRequest request) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            baseUrl.resolve('/v1/checks'),
            headers: {
              'content-type': 'application/json',
              'x-install-id': installId,
            },
            body: jsonEncode(request.toJson()),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const AnalysisError(
        'This is taking longer than usual. Check your connection and try '
        'again.',
      );
    } on http.ClientException {
      throw const AnalysisError(
        "We couldn't reach SpotCheck. Check your internet connection and try "
        'again.',
      );
    }

    if (response.statusCode == 200) {
      try {
        return CheckResult.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, Object?>,
        );
      } on Object {
        throw const AnalysisError('We got an unexpected response. Try again.');
      }
    }

    String? serverMessage;
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      serverMessage = ((body as Map)['error'] as Map)['message'] as String?;
    } on Object {
      serverMessage = null;
    }
    throw switch (response.statusCode) {
      400 || 413 => AnalysisError(
        serverMessage ?? 'Something was wrong with the photos. Try again.',
        retryable: false,
      ),
      429 => AnalysisError(
        serverMessage ?? "You've run several checks quickly. Try again soon.",
      ),
      _ => AnalysisError(
        serverMessage ?? 'SpotCheck had a problem. Please try again.',
      ),
    };
  }
}

/// Canned, clearly labeled results for demos and development.
class DemoAnalysisService implements AnalysisService {
  DemoAnalysisService({this.delay = const Duration(seconds: 7)});

  final Duration delay;

  @override
  Future<CheckResult> analyze(CheckRequest request) async {
    await Future<void>.delayed(delay);
    return Triage.merge(
      id: newId('chk'),
      assessment: demoAssessmentFor(request.site, request.answers),
      safety: SafetyRules.evaluate(request.site, request.answers),
      createdAt: DateTime.now().toUtc(),
      model: 'demo',
      demo: true,
    );
  }
}
