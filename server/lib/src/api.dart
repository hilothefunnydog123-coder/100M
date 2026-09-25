import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'claude_client.dart';
import 'drafter.dart';
import 'limits.dart';
import 'pages.dart';
import 'prompt.dart';
import 'store.dart';

typedef LogSink = void Function(Map<String, Object?> event);

/// The HTTP API and the pages customers see.
///
/// Photos are drafted in memory and never stored or logged. Published
/// quotes store only what the customer sees ([PublicQuote]).
class JobwalkApi {
  JobwalkApi({
    required QuoteDrafter drafter,
    required this.quotes,
    required this.waitlist,
    required this.installLimiter,
    required this.ipLimiter,
    required this.concurrency,
    this.publicBaseUrl,
    this.corsOrigins = const ['*'],
    this.model = '',
    this.draftTimeout = const Duration(seconds: 170),
    LogSink? log,
    DateTime Function()? clock,
    Random? random,
  }) : _drafter = drafter,
       _log = log ?? _stdoutLog,
       _clock = clock ?? (() => DateTime.now().toUtc()),
       _random = random ?? Random.secure();

  /// Eight photos at the per-photo cap, base64-encoded, plus JSON overhead.
  static const maxDraftBodyBytes = 40 * 1024 * 1024;
  static const maxQuoteBodyBytes = 256 * 1024;
  static const maxFormBodyBytes = 16 * 1024;

  static final _installIdPattern = RegExp(r'^[A-Za-z0-9_-]{8,64}$');
  static final _publicIdPattern = RegExp(r'^[a-z0-9]{12,32}$');
  static final _emailPattern = RegExp(
    r'^[^\s@]{1,64}@[^\s@]{1,190}\.[^\s@]{2,}$',
  );
  static const _crewSizes = {'solo', '2-5', '6-10', '11+'};

  final QuoteDrafter _drafter;
  final QuoteStore quotes;
  final WaitlistStore waitlist;
  final RateLimiter installLimiter;
  final RateLimiter ipLimiter;
  final ConcurrencyLimiter concurrency;

  /// Origin for quote links. Defaults to each request's origin.
  final Uri? publicBaseUrl;
  final List<String> corsOrigins;
  final String model;

  /// Upper bound on one draft, so a phone never waits indefinitely.
  final Duration draftTimeout;

  final LogSink _log;
  final DateTime Function() _clock;
  final Random _random;
  final _locks = KeyedLock();

  Handler get handler {
    final router = Router(notFoundHandler: _notFound)
      ..get('/', _landing)
      ..get('/sample', _sample)
      ..post('/waitlist', _joinWaitlist)
      ..get('/healthz', _health)
      ..post('/v1/drafts', _createDraft)
      ..post('/v1/quotes', _publish)
      ..put('/v1/quotes/<id>', _update)
      ..get('/v1/quotes/<id>', _status)
      ..get('/q/<id>', _quotePage)
      ..post('/q/<id>/approve', _approve)
      ..post('/q/<id>/decline', _decline);
    return const Pipeline()
        .addMiddleware(_cors())
        .addMiddleware(_securityHeaders)
        .addHandler(router.call);
  }

  // -------------------------------------------------------------------------
  // Pages
  // -------------------------------------------------------------------------

  Response _landing(Request request) {
    final q = request.url.queryParameters;
    return _html(200, landingPage(joined: q['joined'] == '1'));
  }

  Response _sample(Request request) {
    final now = _clock();
    final profile = const BusinessProfile(
      name: 'Brightline Painting',
      trades: [Trade.painting],
      phone: '(512) 555-0142',
      email: 'hello@brightline.example',
    );
    final quote = QuoteBuilder.fromDraft(
      SampleJob.livingRoom.draft,
      id: 'sample',
      number: 1042,
      rates: Rates.forTrade(Trade.painting),
      now: now,
      customer: const Customer(name: 'Dana Ortiz'),
    );
    final record = QuoteRecord(
      id: 'sample',
      ownerTokenHash: '',
      createdAt: now,
      updatedAt: now,
      quote: PublicQuote.fromQuote(quote, profile, issuedAt: now),
    );
    return _html(200, quotePage(record, now: now, homeHref: '/', sample: true));
  }

  Future<Response> _quotePage(Request request, String id) async {
    if (!_publicIdPattern.hasMatch(id)) return _notFound(request);
    final params = request.url.queryParameters;
    final countView =
        request.method == 'GET' &&
        params['preview'] != '1' &&
        !_looksLikeBot(request.headers['user-agent'] ?? '');
    final record = await _locks.run(id, () async {
      final r = await quotes.get(id);
      if (r == null || !countView) return r;
      final now = _clock();
      final updated = r.copyWith(
        response: _withView(r.response, now),
        updatedAt: now,
      );
      await quotes.put(updated);
      return updated;
    });
    if (record == null) return _notFound(request);
    return _html(
      200,
      quotePage(
        record,
        now: _clock(),
        homeHref: _baseUrl(request).toString(),
        flash: params['done'],
        error: switch (params['error']) {
          'name' => 'Type your name to approve the quote.',
          'agree' => 'Check the box to approve the quote.',
          'option' => 'Choose one of the options.',
          _ => null,
        },
      ),
      headers: {'referrer-policy': 'no-referrer'},
    );
  }

  static CustomerResponse _withView(CustomerResponse r, DateTime now) =>
      CustomerResponse(
        views: r.views + 1,
        firstViewedAt: r.firstViewedAt ?? now,
        lastViewedAt: now,
        approvedAt: r.approvedAt,
        approvedTierId: r.approvedTierId,
        signature: r.signature,
        declinedAt: r.declinedAt,
        declineReason: r.declineReason,
      );

  /// Link previews in messaging apps fetch the page; they aren't views.
  static bool _looksLikeBot(String userAgent) => RegExp(
    r'bot|crawl|spider|preview|facebookexternalhit|whatsapp|telegram|slack|'
    r'discord|skype|embedly|curl|wget|python-requests|headless',
    caseSensitive: false,
  ).hasMatch(userAgent);

  Future<Response> _approve(Request request, String id) async {
    if (!_publicIdPattern.hasMatch(id)) return _notFound(request);
    final limited = _limitIp(request);
    if (limited != null) return limited;
    final Map<String, String> form;
    try {
      form = await _readForm(request);
    } on _BodyTooLarge {
      return _error(413, 'too_large', 'The form is too large.');
    }
    final name = form['name']?.trim() ?? '';
    final option = form['option'] ?? '';

    final outcome = await _locks.run(id, () async {
      final r = await quotes.get(id);
      if (r == null) return 'missing';
      if (r.response.approvedAt != null) return 'done';
      if (_clock().isAfter(r.quote.validUntil)) return 'expired';
      final chosen = r.quote.options.length == 1
          ? r.quote.options.single
          : r.quote.option(option);
      if (chosen == null) return 'option';
      if (name.isEmpty || name.length > 80) return 'name';
      if (form['agree'] != 'yes') return 'agree';
      final now = _clock();
      final old = r.response;
      await quotes.put(
        r.copyWith(
          updatedAt: now,
          response: CustomerResponse(
            views: old.views,
            firstViewedAt: old.firstViewedAt,
            lastViewedAt: old.lastViewedAt,
            approvedAt: now,
            approvedTierId: chosen.id,
            signature: name,
          ),
        ),
      );
      _log({'event': 'approved', 'quote': id, 'revision': r.revision});
      return 'done';
    });

    return switch (outcome) {
      'missing' => _notFound(request),
      'done' || 'expired' => _redirect('/q/$id?preview=1&done=approved'),
      final error => _redirect('/q/$id?preview=1&error=$error#approve'),
    };
  }

  Future<Response> _decline(Request request, String id) async {
    if (!_publicIdPattern.hasMatch(id)) return _notFound(request);
    final limited = _limitIp(request);
    if (limited != null) return limited;
    final Map<String, String> form;
    try {
      form = await _readForm(request);
    } on _BodyTooLarge {
      return _error(413, 'too_large', 'The form is too large.');
    }
    final reason = (form['reason'] ?? '').trim();
    final found = await _locks.run(id, () async {
      final r = await quotes.get(id);
      if (r == null) return false;
      if (r.response.approvedAt != null) return true;
      final now = _clock();
      final old = r.response;
      await quotes.put(
        r.copyWith(
          updatedAt: now,
          response: CustomerResponse(
            views: old.views,
            firstViewedAt: old.firstViewedAt,
            lastViewedAt: old.lastViewedAt,
            declinedAt: now,
            declineReason: reason.length > 500
                ? reason.substring(0, 500)
                : reason,
          ),
        ),
      );
      _log({'event': 'declined', 'quote': id});
      return true;
    });
    if (!found) return _notFound(request);
    return _redirect('/q/$id?preview=1&done=declined');
  }

  Future<Response> _joinWaitlist(Request request) async {
    final limited = _limitIp(request);
    if (limited != null) return limited;
    final isForm = !(request.mimeType ?? '').contains('json');
    final Map<String, String> data;
    try {
      data = isForm
          ? await _readForm(request)
          : _stringMap(jsonDecode(await _readBody(request, maxFormBodyBytes)));
    } on _BodyTooLarge {
      return _error(413, 'too_large', 'The form is too large.');
    } on FormatException {
      return _error(400, 'invalid_json', 'The request body is not valid JSON.');
    }
    final email = (data['email'] ?? '').trim().toLowerCase();
    if (!_emailPattern.hasMatch(email) || email.length > 120) {
      return isForm
          ? _html(400, landingPage(error: 'Enter a valid email address.'))
          : _error(400, 'invalid_email', 'Enter a valid email address.');
    }
    final trade = Trade.values.any((t) => t.id == data['trade'])
        ? data['trade']!
        : '';
    final crew = _crewSizes.contains(data['crew']) ? data['crew']! : '';
    await waitlist.add(
      WaitlistEntry(email: email, trade: trade, crew: crew, at: _clock()),
    );
    _log({'event': 'waitlist', 'trade': trade, 'crew': crew});
    return isForm ? _redirect('/?joined=1#join') : _json(200, {'ok': true});
  }

  Response _notFound(Request request) => _html(
    404,
    messagePage(
      'Quote not found',
      'This link may be mistyped or the quote was removed. Ask the '
          'contractor who sent it for a new link.',
      homeHref: '/',
    ),
  );

  // -------------------------------------------------------------------------
  // API
  // -------------------------------------------------------------------------

  Response _health(Request request) =>
      _json(200, {'ok': true, 'prompt_version': promptVersion, 'model': model});

  Future<Response> _createDraft(Request request) async {
    final watch = Stopwatch()..start();
    final installId = request.headers['x-install-id'] ?? '';
    if (!_installIdPattern.hasMatch(installId)) {
      return _error(
        400,
        'missing_install_id',
        'Send a random install id in the X-Install-Id header.',
      );
    }
    final wait = installLimiter.tryAcquire('install:$installId');
    if (wait != null) {
      _log({'event': 'rate_limited', 'scope': 'install'});
      return _error(
        429,
        'rate_limited',
        "You've drafted several quotes in a short time. Try again in a few "
            'minutes.',
        headers: {'retry-after': '${wait.inSeconds + 1}'},
      );
    }
    final limited = _limitIp(request);
    if (limited != null) return limited;

    final length = request.contentLength;
    if (length != null && length > maxDraftBodyBytes) {
      return _error(413, 'too_large', 'The photos are too large.');
    }
    final DraftRequest draftRequest;
    try {
      draftRequest = DraftRequest.fromJson(
        jsonDecode(await _readBody(request, maxDraftBodyBytes)),
      );
    } on _BodyTooLarge {
      return _error(413, 'too_large', 'The photos are too large.');
    } on FormatException {
      return _error(400, 'invalid_json', 'The request body is not valid JSON.');
    } on InvalidDraftRequest catch (e) {
      return _error(400, 'invalid_request', e.message);
    }

    try {
      final draft = await concurrency
          .run(() => _drafter.draft(draftRequest, userId: installId))
          .timeout(draftTimeout);
      // Operational metadata only: no photos, notes, or quote contents.
      _log({
        'event': 'draft',
        'usable': draft.draft.isUsable,
        'lines': draft.draft.items.length,
        'tiers': draft.draft.tiers.length,
        'photos': draftRequest.photos.length,
        'trade': draftRequest.profile.primaryTrade.id,
        'ms': watch.elapsedMilliseconds,
        ...draft.stats.toJson(),
      });
      return _json(200, draft.toJson());
    } on Overloaded {
      _log({'event': 'overloaded', 'queued': concurrency.queued});
      return _busy();
    } on TimeoutException {
      _log({'event': 'timeout', 'ms': watch.elapsedMilliseconds});
      return _error(504, 'timeout', 'The draft took too long. Try again.');
    } on DraftFailed catch (e) {
      final cause = e.cause;
      _log({
        'event': 'draft_failed',
        'refused': e.refused,
        'cause': cause is ClaudeApiException
            ? '${cause.statusCode} ${cause.type} ${cause.requestId ?? ''}'
            : '${cause?.runtimeType}',
        'ms': watch.elapsedMilliseconds,
      });
      if (e.refused) {
        return _error(
          422,
          'refused',
          "We can't draft a quote from these photos. Try photos of the job "
              'itself.',
        );
      }
      if (cause is ClaudeApiException && cause.isTransient) return _busy();
      return _error(
        502,
        'draft_failed',
        "We couldn't finish this draft. Please try again.",
      );
    }
  }

  Future<Response> _publish(Request request) async {
    final limited = _limitIp(request);
    if (limited != null) return limited;
    final PublicQuote quote;
    try {
      quote = await _readQuote(request);
    } on _Rejected catch (e) {
      return e.response;
    }
    final now = _clock();
    final id = _token(16);
    final token = _token(40);
    await quotes.put(
      QuoteRecord(
        id: id,
        ownerTokenHash: hashToken(token),
        createdAt: now,
        updatedAt: now,
        quote: quote,
      ),
    );
    _log({'event': 'published', 'quote': id, 'options': quote.options.length});
    return _json(201, {
      'id': id,
      'url': _quoteUrl(request, id),
      'owner_token': token,
      'revision': 1,
    });
  }

  Future<Response> _update(Request request, String id) async {
    final limited = _limitIp(request);
    if (limited != null) return limited;
    final PublicQuote quote;
    try {
      quote = await _readQuote(request);
    } on _Rejected catch (e) {
      return e.response;
    }
    final token = _bearer(request);
    final result = await _locks.run(id, () async {
      final r = await quotes.get(id);
      if (r == null || token == null || !r.ownedBy(token)) return null;
      if (r.response.approvedAt != null) return (r, false);
      final now = _clock();
      final old = r.response;
      final updated = r.copyWith(
        updatedAt: now,
        revision: r.revision + 1,
        quote: quote,
        // A revision is a new offer: an old decline no longer applies.
        response: CustomerResponse(
          views: old.views,
          firstViewedAt: old.firstViewedAt,
          lastViewedAt: old.lastViewedAt,
        ),
      );
      await quotes.put(updated);
      return (updated, true);
    });
    if (result == null) {
      return _error(404, 'not_found', 'No quote with that id and token.');
    }
    final (record, changed) = result;
    if (!changed) {
      return _error(
        409,
        'already_approved',
        'The customer already approved this quote. Send a new quote for '
            'changes.',
      );
    }
    _log({'event': 'updated', 'quote': id, 'revision': record.revision});
    return _json(200, {
      'id': id,
      'url': _quoteUrl(request, id),
      'revision': record.revision,
    });
  }

  Future<Response> _status(Request request, String id) async {
    final token = _bearer(request);
    final r = await quotes.get(id);
    if (r == null || token == null || !r.ownedBy(token)) {
      return _error(404, 'not_found', 'No quote with that id and token.');
    }
    return _json(200, {
      'id': id,
      'revision': r.revision,
      'response': r.response.toJson(),
    });
  }

  Future<PublicQuote> _readQuote(Request request) async {
    final Object? body;
    try {
      body = jsonDecode(await _readBody(request, maxQuoteBodyBytes));
    } on _BodyTooLarge {
      throw _Rejected(_error(413, 'too_large', 'The quote is too large.'));
    } on FormatException {
      throw _Rejected(
        _error(400, 'invalid_json', 'The request body is not valid JSON.'),
      );
    }
    final quote = PublicQuote.fromJson(
      body is Map<String, Object?> ? body['quote'] : null,
    );
    final problem = quote.validate();
    if (problem != null) {
      throw _Rejected(_error(400, 'invalid_quote', problem));
    }
    return quote;
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Response? _limitIp(Request request) {
    final wait = ipLimiter.tryAcquire('ip:${_clientIp(request)}');
    if (wait == null) return null;
    _log({'event': 'rate_limited', 'scope': 'ip'});
    return _error(
      429,
      'rate_limited',
      'Too many requests. Please try again shortly.',
      headers: {'retry-after': '${wait.inSeconds + 1}'},
    );
  }

  Response _busy() => _error(
    503,
    'busy',
    'Jobwalk is very busy right now. Please try again in a minute.',
    headers: {'retry-after': '30'},
  );

  Uri _baseUrl(Request request) {
    final configured = publicBaseUrl;
    if (configured != null) return configured.replace(path: '/');
    final proto = request.headers['x-forwarded-proto']?.split(',').first.trim();
    final origin = request.requestedUri;
    return Uri(
      scheme: proto == 'https' || proto == 'http' ? proto : origin.scheme,
      host: origin.host,
      port: origin.hasPort ? origin.port : null,
      path: '/',
    );
  }

  String _quoteUrl(Request request, String id) =>
      _baseUrl(request).replace(path: '/q/$id').toString();

  String _token(int length) {
    const alphabet = 'abcdefghijkmnpqrstuvwxyz23456789';
    return List.generate(
      length,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }

  static String? _bearer(Request request) {
    final header = request.headers['authorization'] ?? '';
    const prefix = 'Bearer ';
    if (!header.startsWith(prefix)) return null;
    final token = header.substring(prefix.length).trim();
    return token.isEmpty || token.length > 128 ? null : token;
  }

  String _clientIp(Request request) {
    // Behind a load balancer the client is the first forwarded address.
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null && forwarded.isNotEmpty) {
      return forwarded.split(',').first.trim();
    }
    final info = request.context['shelf.io.connection_info'];
    return info is HttpConnectionInfo ? info.remoteAddress.address : 'unknown';
  }

  Future<String> _readBody(Request request, int maxBytes) async {
    final length = request.contentLength;
    if (length != null && length > maxBytes) throw _BodyTooLarge();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in request.read()) {
      bytes.add(chunk);
      if (bytes.length > maxBytes) throw _BodyTooLarge();
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  Future<Map<String, String>> _readForm(Request request) async {
    final body = await _readBody(request, maxFormBodyBytes);
    try {
      return Uri.splitQueryString(body);
    } on Object {
      // Malformed percent-encoding: treat it as an empty form.
      return const {};
    }
  }

  static Map<String, String> _stringMap(Object? json) => {
    if (json is Map)
      for (final e in json.entries)
        if (e.key is String && e.value is String)
          e.key as String: e.value as String,
  };

  Middleware _cors() =>
      (inner) => (request) async {
        final origin = request.headers['origin'];
        final allowed =
            origin != null &&
            (corsOrigins.contains('*') || corsOrigins.contains(origin));
        final headers = {
          if (allowed && request.url.path.startsWith('v1/')) ...{
            'access-control-allow-origin': corsOrigins.contains('*')
                ? '*'
                : origin,
            'access-control-allow-methods': 'GET, POST, PUT, OPTIONS',
            'access-control-allow-headers':
                'content-type, x-install-id, authorization',
            'access-control-max-age': '600',
            'vary': 'origin',
          },
        };
        if (request.method == 'OPTIONS') {
          return Response(headers.isEmpty ? 403 : 204, headers: headers);
        }
        final response = await inner(request);
        return response.change(headers: headers);
      };

  static Handler _securityHeaders(Handler inner) => (request) async {
    final response = await inner(request);
    final html = (response.mimeType ?? '') == 'text/html';
    return response.change(
      headers: {
        'cache-control': 'no-store',
        'x-content-type-options': 'nosniff',
        if (html) ...{
          'content-security-policy':
              "default-src 'none'; style-src 'unsafe-inline'; img-src 'self' "
              "data:; form-action 'self'; base-uri 'none'; "
              "frame-ancestors 'none'",
          'x-frame-options': 'DENY',
        },
      },
    );
  };

  static Response _redirect(String location) =>
      Response(303, headers: {'location': location});

  static Response _html(
    int status,
    String body, {
    Map<String, String> headers = const {},
  }) => Response(
    status,
    body: body,
    headers: {'content-type': 'text/html; charset=utf-8', ...headers},
  );

  static Response _json(
    int status,
    Object body, {
    Map<String, String> headers = const {},
  }) => Response(
    status,
    body: jsonEncode(body),
    headers: {'content-type': 'application/json; charset=utf-8', ...headers},
  );

  static Response _error(
    int status,
    String code,
    String message, {
    Map<String, String> headers = const {},
  }) => _json(status, {
    'error': {'code': code, 'message': message},
  }, headers: headers);

  static void _stdoutLog(Map<String, Object?> event) {
    stdout.writeln(
      jsonEncode({'ts': DateTime.now().toUtc().toIso8601String(), ...event}),
    );
  }
}

class _BodyTooLarge implements Exception {}

class _Rejected implements Exception {
  _Rejected(this.response);

  final Response response;
}
