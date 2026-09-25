import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:jobwalk_core/jobwalk_core.dart';

import 'api.dart';
import 'models.dart';

/// Someone else changed the quote since this phone last saw it.
class QuoteConflict implements Exception {
  const QuoteConflict(this.current);

  /// The server's copy.
  final SyncedQuote current;
}

/// The Jobwalk API (see `server/` and docs/API.md) for a signed-in phone.
class ServerClient implements JobwalkClient {
  ServerClient({
    required this.baseUrl,
    required String? Function() token,
    void Function()? onUnauthorized,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
    this.draftTimeout = const Duration(seconds: 190),
    this.draftPollEvery = const Duration(seconds: 3),
  }) : _token = token,
       _onUnauthorized = onUnauthorized ?? (() {}),
       _client = client ?? http.Client();

  final Uri baseUrl;
  final Duration timeout;
  final Duration draftTimeout;

  /// How often to ask about a draft whose request was cut off.
  final Duration draftPollEvery;
  final String? Function() _token;
  final void Function() _onUnauthorized;
  final http.Client _client;

  @override
  bool get isDemo => false;

  /// Keeps any path prefix on the base URL.
  Uri endpoint(String path, [Map<String, String>? query]) => baseUrl.replace(
    path: '${baseUrl.path.replaceAll(RegExp(r'/+$'), '')}$path',
    queryParameters: query,
  );

  // ---------------------------------------------------------------------------
  // Sign-in and account
  // ---------------------------------------------------------------------------

  Future<void> requestCode(String email) =>
      _json('POST', '/v1/auth/code', body: {'email': email}, auth: false);

  /// Returns the session token and the account.
  Future<(String, Account)> verifyCode(
    String email,
    String code, {
    String device = '',
  }) async {
    final json = await _json(
      'POST',
      '/v1/auth/verify',
      body: {'email': email, 'code': code, 'device': device},
      auth: false,
    );
    return (json['token']! as String, Account.fromJson(json));
  }

  Future<void> signOut({bool everywhere = false}) =>
      _json('POST', '/v1/auth/sign-out', body: {'everywhere': everywhere});

  Future<Account> me() async => Account.fromJson(await _json('GET', '/v1/me'));

  Future<Account> updateMe({String? name, bool? emailNotifications}) async =>
      Account.fromJson(
        await _json(
          'PUT',
          '/v1/me',
          body: {'name': ?name, 'email_notifications': ?emailNotifications},
        ),
      );

  Future<Account> updateBusiness({
    BusinessProfile? profile,
    Rates? rates,
  }) async => Account.fromJson(
    await _json(
      'PUT',
      '/v1/business',
      body: {'profile': ?profile?.toJson(), 'rates': ?rates?.toJson()},
    ),
  );

  Future<({int first, int count})> reserveNumbers(
    int count, {
    int atLeast = 0,
  }) async {
    final json = await _json(
      'POST',
      '/v1/business/numbers',
      body: {'count': count, 'at_least': atLeast},
    );
    return (
      first: (json['first']! as num).toInt(),
      count: (json['count']! as num).toInt(),
    );
  }

  Future<List<TeamMember>> team() async =>
      _members(await _json('GET', '/v1/team'));

  Future<List<TeamMember>> addMember(String email, {String name = ''}) async =>
      _members(
        await _json('POST', '/v1/team', body: {'email': email, 'name': name}),
      );

  Future<List<TeamMember>> removeMember(String userId) async =>
      _members(await _json('DELETE', '/v1/team/$userId'));

  static List<TeamMember> _members(Map<String, Object?> json) => [
    for (final m in (json['members'] as List?) ?? const [])
      TeamMember.fromJson(m),
  ];

  Future<void> deleteAccount() =>
      _json('DELETE', '/v1/account', body: {'confirm': 'DELETE'});

  // ---------------------------------------------------------------------------
  // Quotes and photos
  // ---------------------------------------------------------------------------

  Future<SyncPage> changes(int since, {int limit = 200}) async {
    final json = await _json(
      'GET',
      '/v1/quotes',
      query: {'since': '$since', 'limit': '$limit'},
    );
    return SyncPage(
      items: [
        for (final item in (json['items'] as List?) ?? const [])
          SyncedQuote.fromJson(item),
      ],
      cursor: (json['cursor'] as num?)?.toInt() ?? since,
      more: json['more'] == true,
    );
  }

  /// Creates or updates a quote. Throws [QuoteConflict] when the server's
  /// copy moved past [baseVersion], or was deleted.
  Future<SyncedQuote> putQuote(Quote quote, {required int baseVersion}) async {
    try {
      return SyncedQuote.fromJson(
        await _json(
          'PUT',
          '/v1/quotes/${quote.id}',
          body: {'quote': quote.toJson(), 'base_version': baseVersion},
        ),
      );
    } on ApiError catch (e) {
      if (e.status == 409 && (e.code == 'conflict' || e.code == 'deleted')) {
        throw QuoteConflict(SyncedQuote.fromJson(e.details['current']));
      }
      rethrow;
    }
  }

  Future<SyncedQuote> deleteQuote(String id) async =>
      SyncedQuote.fromJson(await _json('DELETE', '/v1/quotes/$id'));

  Future<SyncedQuote> publish(String id) async =>
      SyncedQuote.fromJson(await _json('POST', '/v1/quotes/$id/publish'));

  Future<void> putPhoto(String id, Uint8List bytes) async {
    await _send(
      () => _client.put(
        endpoint('/v1/photos/$id'),
        headers: {..._headers(), 'content-type': 'image/jpeg'},
        body: bytes,
      ),
    );
  }

  /// The photo, or null when the server doesn't have it. Signed storage
  /// links are followed without our credentials.
  Future<Uint8List?> getPhoto(String id) async {
    final request = http.Request('GET', endpoint('/v1/photos/$id'))
      ..followRedirects = false
      ..headers.addAll(_headers());
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(timeout);
    } on Object {
      return null;
    }
    if (response.statusCode == 200) return response.bodyBytes;
    final location = response.headers['location'];
    final redirect = response.statusCode >= 300 && response.statusCode < 400;
    if (redirect && location != null) {
      try {
        final signed = await _client.get(Uri.parse(location)).timeout(timeout);
        return signed.statusCode == 200 ? signed.bodyBytes : null;
      } on Object {
        return null;
      }
    }
    if (response.statusCode == 401) _onUnauthorized();
    return null;
  }

  // ---------------------------------------------------------------------------
  // Drafts
  // ---------------------------------------------------------------------------

  @override
  Future<DraftResult> draft(
    DraftRequest request, {
    SampleJob? sample,
    String? idempotencyKey,
  }) async {
    final started = DateTime.now();
    Map<String, Object?> json;
    try {
      json = await _json(
        'POST',
        '/v1/drafts',
        body: request.toJson(),
        headers: {'idempotency-key': ?idempotencyKey},
        timeout: draftTimeout,
      );
    } on ApiError catch (e) {
      // Load balancers cut requests that stay quiet for a minute or two,
      // and a phone can lose signal while it waits. The draft carries on
      // on the server; ask for it by its key instead of starting over.
      final lost =
          e.offline ||
          e.code == 'in_progress' ||
          (e.code.isEmpty && (e.status == 502 || e.status == 504));
      if (idempotencyKey == null || !lost) rethrow;
      json = await _awaitDraft(
        idempotencyKey,
        deadline: started.add(draftTimeout + const Duration(seconds: 60)),
        original: e,
      );
    }
    return DraftResult(
      draft: AiDraft.fromJson(json['draft'] as Map<String, Object?>),
      model: json['model'] as String? ?? '',
      demo: json['demo'] == true,
    );
  }

  Future<Map<String, Object?>> _awaitDraft(
    String key, {
    required DateTime deadline,
    required ApiError original,
  }) async {
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(draftPollEvery);
      final Map<String, Object?> status;
      try {
        status = await _json('GET', '/v1/drafts/$key');
      } on ApiError catch (e) {
        // Never reached the server: the original error says why.
        if (e.status == 404) throw original;
        if (e.offline) continue;
        rethrow;
      }
      switch (status['state']) {
        case 'done':
          return status;
        case 'failed':
          throw const ApiError(
            "We couldn't finish this draft. Please try again.",
          );
      }
    }
    throw original;
  }

  // ---------------------------------------------------------------------------
  // Money
  // ---------------------------------------------------------------------------

  Future<Uri> checkout(String plan) async => Uri.parse(
    (await _json('POST', '/v1/billing/checkout', body: {'plan': plan}))['url']!
        as String,
  );

  Future<Uri> billingPortal() async =>
      Uri.parse((await _json('POST', '/v1/billing/portal'))['url']! as String);

  Future<Payments> payments() async =>
      Payments.fromJson(await _json('GET', '/v1/payments'));

  Future<Uri> connectPayments() async => Uri.parse(
    (await _json('POST', '/v1/payments/connect'))['url']! as String,
  );

  Future<Uri> paymentsDashboard() async => Uri.parse(
    (await _json('POST', '/v1/payments/dashboard'))['url']! as String,
  );

  // ---------------------------------------------------------------------------

  Map<String, String> _headers({bool auth = true}) {
    final token = auth ? _token() : null;
    return {'authorization': ?(token == null ? null : 'Bearer $token')};
  }

  Future<Map<String, Object?>> _json(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String> headers = const {},
    bool auth = true,
    Duration? timeout,
  }) => _send(() {
    final request = http.Request(method, endpoint(path, query))
      ..headers.addAll({
        ..._headers(auth: auth),
        'content-type': 'application/json',
        ...headers,
      });
    if (body != null) request.body = jsonEncode(body);
    return _client.send(request).then(http.Response.fromStream);
  }, timeout: timeout);

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
        offline: true,
      );
    } on http.ClientException {
      throw const ApiError(
        "Can't reach Jobwalk. Check your signal and try again.",
        offline: true,
      );
    }
    Map<String, Object?>? body;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, Object?>) body = decoded;
    } on FormatException {
      body = null;
    }
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      if (body == null) {
        throw const ApiError('Got an unexpected response. Try again.');
      }
      return body;
    }
    if (status == 401) _onUnauthorized();
    final error = body?['error'];
    final message = error is Map ? error['message'] as String? : null;
    final code = error is Map ? error['code'] as String? ?? '' : '';
    final details = {...?body}..remove('error');
    throw ApiError(
      message ??
          switch (status) {
            401 => 'Sign in again to continue.',
            404 => "That isn't on the server anymore.",
            429 => 'Too many requests. Try again in a minute.',
            _ => 'Jobwalk had a problem. Please try again.',
          },
      retryable:
          status == 408 ||
          status == 429 ||
          status >= 500 ||
          code == 'in_progress',
      code: code,
      status: status,
      details: details,
    );
  }
}
