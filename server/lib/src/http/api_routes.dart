import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../common.dart';
import '../limits.dart';
import '../services/accounts.dart';
import '../services/billing.dart';
import '../services/drafts.dart';
import '../services/photos.dart';
import '../services/quotes.dart';
import 'respond.dart';

/// The app's API under `/v1`. Everything except sign-in needs a session:
/// `Authorization: Bearer <token>`.
class ApiRoutes {
  ApiRoutes({
    required this.accounts,
    required this.quotes,
    required this.photos,
    required this.drafts,
    required this.billing,
    required this.perUser,
    this.trustedProxies = 1,
  });

  final AccountService accounts;
  final QuoteService quotes;
  final PhotoService photos;
  final DraftService drafts;
  final BillingService billing;

  /// A per-account ceiling on all API calls, against runaway clients.
  final Limiter perUser;
  final int trustedProxies;

  /// Eight photos at the per-photo cap, base64-encoded, plus JSON.
  static const maxDraftBytes = 40 * 1024 * 1024;
  static const maxQuoteBytes = 512 * 1024;
  static const maxPhotoBytes = 10 * 1024 * 1024;

  Router get router => Router()
    // Sign-in
    ..post('/v1/auth/code', _requestCode)
    ..post('/v1/auth/verify', _verify)
    ..post('/v1/auth/sign-out', _auth(_signOut))
    // Account
    ..get(
      '/v1/me',
      _auth((r, a) async => jsonResponse(200, await accounts.me(a))),
    )
    ..put('/v1/me', _auth(_updateMe))
    ..put('/v1/business', _auth(_updateBusiness))
    ..post('/v1/business/numbers', _auth(_numbers))
    ..get('/v1/team', _auth(_team))
    ..post('/v1/team', _auth(_addMember))
    ..delete('/v1/team/<id>', _authWith(_removeMember))
    ..get('/v1/account/export', _auth(_export))
    ..delete('/v1/account', _auth(_deleteAccount))
    // Quotes
    ..get('/v1/quotes', _auth(_changes))
    ..get('/v1/quotes/<id>', _authWith(_getQuote))
    ..put('/v1/quotes/<id>', _authWith(_putQuote))
    ..delete('/v1/quotes/<id>', _authWith(_deleteQuote))
    ..post('/v1/quotes/<id>/publish', _authWith(_publish))
    ..get('/v1/activity', _auth(_activity))
    ..put('/v1/photos/<id>', _authWith(_putPhoto))
    ..get('/v1/photos/<id>', _authWith(_getPhoto))
    ..post('/v1/drafts', _auth(_draft))
    // Money
    ..post('/v1/billing/checkout', _auth(_checkout))
    ..post('/v1/billing/portal', _auth(_portal))
    ..get('/v1/payments', _auth(_payments))
    ..post('/v1/payments/connect', _auth(_connect))
    ..post('/v1/payments/dashboard', _auth(_dashboard));

  // ---------------------------------------------------------------------------

  Handler _auth(Future<Response> Function(Request, Account) fn) =>
      (request) async => fn(request, await _account(request));

  Function _authWith(Future<Response> Function(Request, Account, String) fn) =>
      (Request request, String id) async =>
          fn(request, await _account(request), id);

  Future<Account> _account(Request request) async {
    final account = await accounts.authenticate(bearerToken(request));
    if (account == null) throw ApiError.unauthorized();
    final wait = await perUser.acquire('api:${account.userId}');
    if (wait != null) throw ApiError.rateLimited(wait);
    return account;
  }

  String _ip(Request r) => clientIp(r, trustedProxies: trustedProxies);

  // ---------------------------------------------------------------------------

  Future<Response> _requestCode(Request r) async {
    final body = await readJson(r);
    await accounts.requestCode(body['email'], ip: _ip(r));
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _verify(Request r) async {
    final body = await readJson(r);
    final device = body['device'];
    final signIn = await accounts.verifyCode(
      body['email'],
      body['code'],
      ip: _ip(r),
      device: device is String ? device : '',
    );
    return jsonResponse(200, {
      'token': signIn.token,
      'created': signIn.created,
      ...await accounts.me(signIn.account),
    });
  }

  Future<Response> _signOut(Request r, Account a) async {
    final body = await readJson(r);
    await accounts.signOut(a, everywhere: body['everywhere'] == true);
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _updateMe(Request r, Account a) async =>
      jsonResponse(200, await accounts.updateUser(a, await readJson(r)));

  Future<Response> _updateBusiness(Request r, Account a) async =>
      jsonResponse(200, await accounts.updateBusiness(a, await readJson(r)));

  Future<Response> _numbers(Request r, Account a) async {
    final body = await readJson(r);
    final reserved = await accounts.reserveNumbers(
      a,
      count: asInt(body['count']) ?? 1,
      atLeast: asInt(body['at_least']) ?? 0,
    );
    return jsonResponse(200, {
      'first': reserved.first,
      'count': reserved.count,
    });
  }

  Future<Response> _team(Request r, Account a) async =>
      jsonResponse(200, {'members': await accounts.team(a)});

  Future<Response> _addMember(Request r, Account a) async => jsonResponse(201, {
    'members': await accounts.addMember(a, await readJson(r)),
  });

  Future<Response> _removeMember(Request r, Account a, String id) async =>
      jsonResponse(200, {'members': await accounts.removeMember(a, id)});

  Future<Response> _export(Request r, Account a) async => jsonResponse(
    200,
    await accounts.export(a),
    headers: {
      'content-disposition': 'attachment; filename="jobwalk-export.json"',
    },
  );

  Future<Response> _deleteAccount(Request r, Account a) async {
    final body = await readJson(r);
    await accounts.deleteAccount(a, confirm: body['confirm']);
    return jsonResponse(200, {'ok': true});
  }

  Future<Response> _changes(Request r, Account a) async => jsonResponse(
    200,
    await quotes.changes(
      a,
      since: queryInt(r, 'since') ?? 0,
      limit: queryInt(r, 'limit') ?? 100,
    ),
  );

  Future<Response> _getQuote(Request r, Account a, String id) async =>
      jsonResponse(200, await quotes.get(a, id));

  Future<Response> _putQuote(Request r, Account a, String id) async {
    final body = await readJson(r, maxBytes: maxQuoteBytes);
    return jsonResponse(200, await quotes.put(a, id, body));
  }

  Future<Response> _deleteQuote(Request r, Account a, String id) async =>
      jsonResponse(200, await quotes.delete(a, id));

  Future<Response> _publish(Request r, Account a, String id) async =>
      jsonResponse(200, await quotes.publish(a, id));

  Future<Response> _activity(Request r, Account a) async => jsonResponse(
    200,
    await quotes.activity(
      a,
      before: queryInt(r, 'before'),
      limit: queryInt(r, 'limit') ?? 50,
    ),
  );

  Future<Response> _putPhoto(Request r, Account a, String id) async {
    final bytes = await readBytes(r, maxPhotoBytes);
    return jsonResponse(201, await photos.put(a, id, bytes));
  }

  Future<Response> _getPhoto(Request r, Account a, String id) async {
    final photo = await photos.get(a, id);
    final redirect = photo.redirect;
    if (redirect != null) {
      return Response.found(
        redirect,
        headers: {'cache-control': 'private, max-age=300'},
      );
    }
    return Response.ok(
      photo.bytes,
      headers: {
        'content-type': photo.contentType,
        // Photos never change under an id.
        'cache-control': 'private, max-age=31536000, immutable',
      },
    );
  }

  Future<Response> _draft(Request r, Account a) async {
    final body = await readJson(r, maxBytes: maxDraftBytes);
    final DraftRequest request;
    try {
      request = DraftRequest.fromJson(body);
    } on InvalidDraftRequest catch (e) {
      throw ApiError.badRequest('invalid_request', e.message);
    }
    final draft = await drafts.create(
      a,
      request,
      idempotencyKey: r.headers['idempotency-key'],
    );
    return jsonResponse(200, draft);
  }

  Future<Response> _checkout(Request r, Account a) async {
    final body = await readJson(r);
    return jsonResponse(200, await billing.checkout(a, body['plan']));
  }

  Future<Response> _portal(Request r, Account a) async =>
      jsonResponse(200, await billing.portal(a));

  Future<Response> _payments(Request r, Account a) async =>
      jsonResponse(200, await billing.payments(a));

  Future<Response> _connect(Request r, Account a) async =>
      jsonResponse(200, await billing.connect(a));

  Future<Response> _dashboard(Request r, Account a) async =>
      jsonResponse(200, await billing.dashboard(a));
}
