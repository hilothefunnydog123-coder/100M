import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:jobwalk_core/jobwalk_core.dart';

import '../data/blob_store.dart';

class DraftResult {
  const DraftResult({required this.draft, this.model = '', this.demo = false});

  final AiDraft draft;
  final String model;
  final bool demo;
}

class ShareResult {
  const ShareResult({
    required this.id,
    required this.url,
    required this.ownerToken,
    this.revision = 1,
  });

  final String id;
  final String url;
  final String ownerToken;
  final int revision;
}

/// A failure the UI can explain to the contractor.
class ApiError implements Exception {
  const ApiError(this.message, {this.retryable = true, this.code = ''});

  final String message;
  final bool retryable;
  final String code;

  @override
  String toString() => message;
}

/// Everything the app asks of the Jobwalk server.
abstract interface class JobwalkClient {
  /// Sample drafts and on-device links instead of the real server.
  bool get isDemo;

  /// Drafts a quote from photos. In demo mode, [sample] picks the canned
  /// draft; the real server always looks at the photos.
  Future<DraftResult> draft(DraftRequest request, {SampleJob? sample});

  Future<ShareResult> publish(PublicQuote quote);

  /// Replaces a sent quote with a revision. Returns the new revision.
  Future<int> update(String id, String ownerToken, PublicQuote quote);

  Future<CustomerResponse> status(String id, String ownerToken);
}

/// Talks to the Jobwalk API (see `server/`).
class HttpJobwalkClient implements JobwalkClient {
  HttpJobwalkClient({
    required this.baseUrl,
    required this.installId,
    http.Client? client,
    this.draftTimeout = const Duration(seconds: 190),
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final String installId;
  final Duration draftTimeout;
  final Duration timeout;
  final http.Client _client;

  @override
  bool get isDemo => false;

  /// Keeps any path prefix on the base URL.
  Uri endpoint(String path) => baseUrl.replace(
    path: '${baseUrl.path.replaceAll(RegExp(r'/+$'), '')}$path',
  );

  Map<String, String> _headers({String? token}) => {
    'content-type': 'application/json',
    'x-install-id': installId,
    if (token != null) 'authorization': 'Bearer $token',
  };

  @override
  Future<DraftResult> draft(DraftRequest request, {SampleJob? sample}) async {
    final json = await _send(
      () => _client.post(
        endpoint('/v1/drafts'),
        headers: _headers(),
        body: jsonEncode(request.toJson()),
      ),
      timeout: draftTimeout,
    );
    return DraftResult(
      draft: AiDraft.fromJson(json['draft'] as Map<String, Object?>),
      model: json['model'] as String? ?? '',
      demo: json['demo'] == true,
    );
  }

  @override
  Future<ShareResult> publish(PublicQuote quote) async {
    final json = await _send(
      () => _client.post(
        endpoint('/v1/quotes'),
        headers: _headers(),
        body: jsonEncode({'quote': quote.toJson()}),
      ),
    );
    return ShareResult(
      id: json['id']! as String,
      url: json['url']! as String,
      ownerToken: json['owner_token']! as String,
      revision: (json['revision'] as num?)?.toInt() ?? 1,
    );
  }

  @override
  Future<int> update(String id, String ownerToken, PublicQuote quote) async {
    final json = await _send(
      () => _client.put(
        endpoint('/v1/quotes/$id'),
        headers: _headers(token: ownerToken),
        body: jsonEncode({'quote': quote.toJson()}),
      ),
    );
    return (json['revision'] as num?)?.toInt() ?? 1;
  }

  @override
  Future<CustomerResponse> status(String id, String ownerToken) async {
    final json = await _send(
      () => _client.get(
        endpoint('/v1/quotes/$id'),
        headers: _headers(token: ownerToken),
      ),
    );
    return CustomerResponse.fromJson(json['response']);
  }

  Future<Map<String, Object?>> _send(
    Future<http.Response> Function() request, {
    Duration? timeout,
  }) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout ?? this.timeout);
    } on TimeoutException {
      throw const ApiError(
        'This is taking longer than usual. Check your signal and try again.',
      );
    } on http.ClientException {
      throw const ApiError(
        "Can't reach Jobwalk. Check your signal and try again.",
      );
    }
    Map<String, Object?>? body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) body = decoded;
    } on FormatException {
      body = null;
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body == null) {
        throw const ApiError('Got an unexpected response. Try again.');
      }
      return body;
    }
    final error = body?['error'];
    final message = error is Map ? error['message'] as String? : null;
    final code = error is Map ? error['code'] as String? ?? '' : '';
    throw switch (response.statusCode) {
      400 || 413 || 422 => ApiError(
        message ?? 'Something about that request was off.',
        retryable: false,
        code: code,
      ),
      404 => ApiError(
        message ?? "That quote isn't on the server anymore.",
        retryable: false,
        code: code,
      ),
      409 => ApiError(
        message ?? 'The customer already approved this quote.',
        retryable: false,
        code: code,
      ),
      429 => ApiError(
        message ?? 'Too many requests. Try again in a minute.',
        code: code,
      ),
      _ => ApiError(
        message ?? 'Jobwalk had a problem. Please try again.',
        code: code,
      ),
    };
  }
}

/// Demo mode: sample drafts, and quote links that live on this device so
/// the whole loop (send, customer approves, won) can be tried offline.
class DemoJobwalkClient implements JobwalkClient {
  DemoJobwalkClient({
    required BlobStore store,
    this.draftDelay = const Duration(seconds: 4),
    DateTime Function()? clock,
  }) : _store = store,
       _clock = clock ?? (() => DateTime.now().toUtc());

  static const _key = 'demo_links.json';
  final BlobStore _store;
  final Duration draftDelay;
  final DateTime Function() _clock;
  final _random = Random();
  Map<String, CustomerResponse>? _responses;

  @override
  bool get isDemo => true;

  @override
  Future<DraftResult> draft(DraftRequest request, {SampleJob? sample}) async {
    await Future<void>.delayed(draftDelay);
    final job = sample ?? SampleJob.forTrade(request.profile.primaryTrade);
    return DraftResult(draft: job.draft, model: 'demo', demo: true);
  }

  @override
  Future<ShareResult> publish(PublicQuote quote) async {
    final id = List.generate(
      16,
      (_) => 'abcdefghijkmnpqrstuvwxyz23456789'[_random.nextInt(32)],
    ).join();
    final responses = await _load();
    responses[id] = const CustomerResponse();
    await _save();
    return ShareResult(
      id: id,
      url: 'https://jobwalk.app/q/$id',
      ownerToken: 'demo',
    );
  }

  @override
  Future<int> update(String id, String ownerToken, PublicQuote quote) async {
    final responses = await _load();
    final r = responses[id] ?? const CustomerResponse();
    if (r.approvedAt != null) {
      throw const ApiError(
        'The customer already approved this quote. Duplicate it to make '
        'changes.',
        retryable: false,
        code: 'already_approved',
      );
    }
    responses[id] = CustomerResponse(
      views: r.views,
      firstViewedAt: r.firstViewedAt,
      lastViewedAt: r.lastViewedAt,
    );
    await _save();
    return 2;
  }

  @override
  Future<CustomerResponse> status(String id, String ownerToken) async =>
      (await _load())[id] ?? const CustomerResponse();

  /// Plays the customer opening the link.
  Future<void> recordView(String id) => _change(id, (r, now) {
    return CustomerResponse(
      views: r.views + 1,
      firstViewedAt: r.firstViewedAt ?? now,
      lastViewedAt: now,
      approvedAt: r.approvedAt,
      approvedTierId: r.approvedTierId,
      signature: r.signature,
      declinedAt: r.declinedAt,
      declineReason: r.declineReason,
    );
  });

  /// Plays the customer approving an option.
  Future<void> approve(String id, {String? optionId, required String name}) =>
      _change(
        id,
        (r, now) => CustomerResponse(
          views: r.views,
          firstViewedAt: r.firstViewedAt,
          lastViewedAt: r.lastViewedAt,
          approvedAt: now,
          approvedTierId: optionId,
          signature: name,
        ),
      );

  Future<void> _change(
    String id,
    CustomerResponse Function(CustomerResponse, DateTime) change,
  ) async {
    final responses = await _load();
    responses[id] = change(responses[id] ?? const CustomerResponse(), _clock());
    await _save();
  }

  Future<Map<String, CustomerResponse>> _load() async {
    if (_responses != null) return _responses!;
    final map = <String, CustomerResponse>{};
    final raw = await _store.readText(_key);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, Object?>;
        for (final e in json.entries) {
          map[e.key] = CustomerResponse.fromJson(e.value);
        }
      } on Object {
        // Start over if the demo state is unreadable.
      }
    }
    return _responses = map;
  }

  Future<void> _save() => _store.writeText(
    _key,
    jsonEncode({for (final e in _responses!.entries) e.key: e.value.toJson()}),
  );
}
