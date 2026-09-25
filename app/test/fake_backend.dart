import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

/// The Jobwalk API in memory, close enough to the real server (see
/// `server/`) to test sign-in, sync, and publishing against.
class FakeBackend {
  FakeBackend({DateTime Function()? clock})
    : _clock = clock ?? (() => DateTime.utc(2026, 9, 25, 15));

  final DateTime Function() _clock;

  static const code = '123456';
  static final token = 'jws_${'t' * 43}';

  /// Every request, as `METHOD /path`.
  final calls = <String>[];
  final bodies = <String, Object?>{};
  var offline = false;
  var signedOut = false;

  /// Runs once, right after the next 409 conflict is answered.
  void Function()? afterConflict;
  String? codeSentTo;

  Map<String, Object?> profile = const {'name': ''};
  Map<String, Object?> rates = Rates.forTrade(Trade.painting).toJson();
  var role = 'owner';
  var planId = 'trial';
  var draftsLeft = 25;
  var nextNumber = 1001;

  var _seq = 0;
  final quotes = <String, _Row>{};
  final photos = <String, Uint8List>{};

  // -- What other phones and customers do -----------------------------------

  Quote? quote(String id) => Quote.fromJson(quotes[id]?.data);

  void editElsewhere(String id, Quote Function(Quote) change) {
    final row = quotes[id]!;
    row
      ..data = _storable(change(Quote.fromJson(row.data)!))
      ..version += 1
      ..seq = ++_seq;
  }

  void deleteElsewhere(String id) {
    quotes[id]!
      ..deleted = true
      ..version += 1
      ..seq = ++_seq;
  }

  void customerApproves(String id, {String? option, String name = 'Dana'}) {
    final row = quotes[id]!;
    row
      ..response = CustomerResponse(
        views: 1,
        firstViewedAt: _clock(),
        lastViewedAt: _clock(),
        approvedAt: _clock(),
        approvedTierId: option,
        signature: name,
      )
      ..seq = ++_seq;
  }

  void depositPaid(String id, int cents) {
    quotes[id]!
      ..depositCents = cents
      ..seq = ++_seq;
  }

  // -- HTTP -------------------------------------------------------------------

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request r) async {
    final path = r.url.path;
    calls.add('${r.method} $path');
    if (offline) throw http.ClientException('offline', r.url);
    final isJson = (r.headers['content-type'] ?? '').contains('json');
    final body = isJson && r.bodyBytes.isNotEmpty ? jsonDecode(r.body) : null;
    bodies['${r.method} $path'] = body;
    final json = body is Map
        ? body.cast<String, Object?>()
        : <String, Object?>{};
    final segments = r.url.pathSegments;

    if (path == '/v1/auth/code') {
      codeSentTo = json['email'] as String?;
      return _ok({'ok': true});
    }
    if (path == '/v1/auth/verify') {
      if (json['code'] != code) {
        return _error(400, 'invalid_code', 'That code is wrong or expired.');
      }
      signedOut = false;
      return _ok({'token': token, 'created': true, ..._me()});
    }
    if (r.headers['authorization'] != 'Bearer $token' || signedOut) {
      return _error(401, 'unauthorized', 'Sign in again to continue.');
    }
    switch ((r.method, path)) {
      case ('POST', '/v1/auth/sign-out'):
        signedOut = true;
        return _ok({'ok': true});
      case ('GET', '/v1/me'):
        return _ok(_me());
      case ('PUT', '/v1/business'):
        if (role != 'owner') return _error(403, 'forbidden', 'Owners only.');
        if (json['profile'] != null) {
          profile = json['profile']! as Map<String, Object?>;
        }
        if (json['rates'] != null) {
          rates = json['rates']! as Map<String, Object?>;
        }
        return _ok(_me());
      case ('POST', '/v1/business/numbers'):
        final count = (json['count']! as num).toInt();
        final atLeast = (json['at_least'] as num? ?? 0).toInt();
        final first = nextNumber > atLeast ? nextNumber : atLeast;
        nextNumber = first + count;
        return _ok({'first': first, 'count': count});
      case ('GET', '/v1/quotes'):
        final since = int.parse(r.url.queryParameters['since'] ?? '0');
        final rows = quotes.values.where((q) => q.seq > since).toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));
        return _ok({
          'items': [for (final row in rows) _present(row)],
          'cursor': rows.isEmpty ? since : rows.last.seq,
          'more': false,
        });
      case ('POST', '/v1/drafts'):
        if (draftsLeft == 0) {
          return _error(
            402,
            'upgrade_required',
            "You've used your 25 free AI drafts. Upgrade to keep drafting.",
          );
        }
        draftsLeft--;
        final request = DraftRequest.fromJson(json);
        return _ok({
          'draft': SampleJob.forTrade(
            request.profile.primaryTrade,
          ).draft.toJson(),
          'model': 'claude-opus-5-5',
          'demo': false,
        });
      case ('POST', '/v1/billing/checkout'):
        return _ok({'url': 'https://checkout.stripe.com/c/pay/cs_test'});
      case ('GET', '/v1/payments'):
        return _ok({
          'enabled': true,
          'connected': false,
          'ready': false,
          'fee': {'description': '3.9% + 30¢ per deposit'},
        });
      case ('GET', '/v1/team'):
        return _ok({
          'members': [
            {
              'id': 'u_1',
              'email': 'dana@example.com',
              'role': role,
              'you': true,
            },
          ],
        });
    }
    if (segments.length == 3 && segments[1] == 'quotes') {
      final id = segments[2];
      final row = quotes[id];
      if (r.method == 'PUT') {
        final incoming = Quote.fromJson(json['quote']);
        final base = (json['base_version'] as num? ?? 0).toInt();
        if (incoming == null) return _error(400, 'invalid_quote', 'Bad quote.');
        if (row == null) {
          quotes[id] = _Row(id, _storable(incoming), version: 1, seq: ++_seq);
          return _ok(_present(quotes[id]!));
        }
        if (row.deleted) {
          return _error(409, 'deleted', 'Deleted elsewhere.', {
            'current': _present(row),
          });
        }
        if (row.version != base) {
          final response = _error(409, 'conflict', 'Changed elsewhere.', {
            'current': _present(row),
          });
          final hook = afterConflict;
          afterConflict = null;
          hook?.call();
          return response;
        }
        row
          ..data = _storable(incoming)
          ..version += 1
          ..seq = ++_seq;
        return _ok(_present(row));
      }
      if (r.method == 'DELETE') {
        if (row == null) return _error(404, 'not_found', 'No such quote.');
        row
          ..deleted = true
          ..version += 1
          ..seq = ++_seq;
        return _ok(_present(row));
      }
      if (r.method == 'GET' && row != null) return _ok(_present(row));
    }
    if (segments.length == 4 && segments[3] == 'publish') {
      final row = quotes[segments[2]];
      if (row == null || row.deleted) {
        return _error(404, 'not_found', 'No such quote.');
      }
      row
        ..publicId ??= 'pub${segments[2].hashCode.abs()}abcdefgh'.substring(
          0,
          16,
        )
        ..revision = row.sentAt == null ? 1 : row.revision + 1
        ..sentAt = _clock()
        ..seq = ++_seq;
      return _ok({..._present(row), 'changed': true});
    }
    if (segments.length == 3 && segments[1] == 'photos') {
      if (r.method == 'PUT') {
        photos[segments[2]] = r.bodyBytes;
        return http.Response(jsonEncode({'id': segments[2]}), 201);
      }
      final bytes = photos[segments[2]];
      return bytes == null
          ? _error(404, 'not_found', 'No such photo.')
          : http.Response.bytes(
              bytes,
              200,
              headers: {'content-type': 'image/jpeg'},
            );
    }
    return _error(404, 'not_found', 'Not found.');
  }

  Map<String, Object?> _me() => {
    'user': {
      'id': 'u_1',
      'email': 'dana@example.com',
      'name': '',
      'role': role,
      'email_notifications': true,
    },
    'business': {
      'id': 'b_1',
      'profile': profile,
      'rates': rates,
      'setup_complete': (profile['name'] as String? ?? '').isNotEmpty,
      'plan': {
        'id': planId,
        'status': planId == 'trial' ? 'trialing' : 'active',
        'paid': planId != 'trial',
        'trial_drafts_included': 25,
        'trial_drafts_left': planId == 'trial' ? draftsLeft : null,
        'max_users': 3,
      },
      'payments': {'connected': false, 'ready': false},
    },
  };

  Map<String, Object?> _present(_Row row) {
    if (row.deleted) {
      return {'id': row.id, 'version': row.version, 'deleted': true};
    }
    var q = Quote.fromJson(row.data)!;
    if (row.publicId != null) {
      q = q
          .copyWith(
            status: q.status == QuoteStatus.draft ? QuoteStatus.sent : null,
            share: ShareInfo(
              publicId: row.publicId!,
              url: 'https://jobwalk.test/q/${row.publicId}',
              ownerToken: '',
              sentAt: row.sentAt!,
              revision: row.revision,
            ),
          )
          .applyResponse(row.response);
    }
    return {
      'id': row.id,
      'version': row.version,
      'deleted': false,
      'quote': q.toJson(),
      'deposit': row.publicId == null
          ? null
          : {
              'status': row.depositCents == null ? 'none' : 'paid',
              'paid_cents': row.depositCents,
            },
    };
  }

  static Map<String, Object?> _storable(Quote q) => q.toJson()
    ..remove('share')
    ..remove('response');

  static http.Response _ok(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );

  static http.Response _error(
    int status,
    String code,
    String message, [
    Map<String, Object?> extra = const {},
  ]) => http.Response(
    jsonEncode({
      'error': {'code': code, 'message': message},
      ...extra,
    }),
    status,
    headers: {'content-type': 'application/json'},
  );
}

class _Row {
  _Row(this.id, this.data, {required this.version, required this.seq});

  final String id;
  Map<String, Object?> data;
  int version;
  int seq;
  bool deleted = false;
  String? publicId;
  int revision = 1;
  DateTime? sentAt;
  CustomerResponse response = const CustomerResponse();
  int? depositCents;
}
