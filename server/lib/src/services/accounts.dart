import 'package:jobwalk_core/jobwalk_core.dart';

import '../common.dart';
import '../db/database.dart';
import '../integrations/stripe.dart' show constantTimeEquals;
import '../limits.dart';
import 'outbox.dart';
import 'plans.dart';

/// The signed-in person behind a request.
class Account {
  const Account({
    required this.userId,
    required this.businessId,
    required this.email,
    required this.name,
    required this.role,
    required this.sessionHash,
  });

  final String userId;
  final String businessId;
  final String email;
  final String name;

  /// `owner` or `member`.
  final String role;
  final String sessionHash;

  bool get isOwner => role == 'owner';

  void requireOwner() {
    if (!isOwner) throw ApiError.forbidden();
  }
}

class SignIn {
  const SignIn({
    required this.token,
    required this.account,
    required this.created,
  });

  /// The session token. Only its hash is stored.
  final String token;
  final Account account;

  /// A new account was created by this sign-in.
  final bool created;
}

class AccountSettings {
  const AccountSettings({
    required this.secret,
    this.codeTtl = const Duration(minutes: 10),
    this.maxCodeAttempts = 5,
    this.sessionTtl = const Duration(days: 90),
    this.reviewEmail,
    this.reviewCode,
    this.plans = const PlanRules(),
  });

  /// Keys the sign-in code hashes, so a database dump can't be brute-forced
  /// offline.
  final String secret;
  final Duration codeTtl;
  final int maxCodeAttempts;

  /// Sessions slide: each day of use extends them by this much.
  final Duration sessionTtl;

  /// An address that signs in with [reviewCode] and gets no email, for app
  /// store review. Off unless both are set.
  final String? reviewEmail;
  final String? reviewCode;
  final PlanRules plans;
}

/// Sign-in with emailed codes, sessions, the business profile, and team.
class AccountService {
  AccountService({
    required Db db,
    required Outbox outbox,
    required this.settings,
    required Limiter codePerEmail,
    required Limiter codePerIp,
    required Limiter verifyPerIp,
    Clock clock = systemClock,
    LogSink? log,
  }) : _db = db,
       _outbox = outbox,
       _codePerEmail = codePerEmail,
       _codePerIp = codePerIp,
       _verifyPerIp = verifyPerIp,
       _clock = clock,
       _log = log ?? ((_) {});

  final AccountSettings settings;
  final Db _db;
  final Outbox _outbox;
  final Limiter _codePerEmail;
  final Limiter _codePerIp;
  final Limiter _verifyPerIp;
  final Clock _clock;
  final LogSink _log;

  static final _codePattern = RegExp(r'^\d{6}$');
  static final _tokenPattern = RegExp(r'^jws_[A-Za-z0-9_-]{43}$');
  static const _touchEvery = Duration(hours: 1);

  // ---------------------------------------------------------------------------
  // Sign-in
  // ---------------------------------------------------------------------------

  /// Emails a six-digit code. Succeeds whether or not an account exists,
  /// so the endpoint can't be used to discover who uses Jobwalk.
  Future<void> requestCode(Object? emailInput, {required String ip}) async {
    final email = _email(emailInput);
    final ipWait = await _codePerIp.acquire('code:ip:$ip');
    if (ipWait != null) throw ApiError.rateLimited(ipWait);
    final emailWait = await _codePerEmail.acquire('code:email:$email');
    if (emailWait != null) {
      throw ApiError.rateLimited(
        emailWait,
        'We already sent codes to that address. Check your inbox and spam '
        'folder, or try again in a few minutes.',
      );
    }
    if (_isReviewEmail(email)) return;

    final code = randomDigits(6);
    final now = _clock();
    await _db.tx((tx) async {
      await tx.execute(
        '''
        INSERT INTO sign_in_codes (email, code_hash, expires_at, attempts, created_at)
        VALUES (@e, @h, @exp:timestamptz, 0, @now:timestamptz)
        ON CONFLICT (email) DO UPDATE SET
          code_hash = EXCLUDED.code_hash,
          expires_at = EXCLUDED.expires_at,
          attempts = 0,
          created_at = EXCLUDED.created_at''',
        {
          'e': email,
          'h': _hashCode(email, code),
          'exp': now.add(settings.codeTtl),
          'now': now,
        },
      );
      // Retries past the code's lifetime would be pointless.
      await _outbox.email(
        tx,
        _outbox.templates.signInCode(email, code),
        maxAttempts: 3,
      );
    });
    _log({'event': 'sign_in_code', 'email': maskEmail(email)});
  }

  /// Checks a code and starts a session, creating the account on first
  /// sign-in. Five wrong guesses burn the code.
  Future<SignIn> verifyCode(
    Object? emailInput,
    Object? codeInput, {
    required String ip,
    String device = '',
  }) async {
    final email = _email(emailInput);
    final code = (codeInput is String ? codeInput : '').replaceAll(
      RegExp(r'[\s-]'),
      '',
    );
    final wait = await _verifyPerIp.acquire('verify:ip:$ip');
    if (wait != null) throw ApiError.rateLimited(wait);
    if (!_codePattern.hasMatch(code)) throw _wrongCode();

    if (_isReviewEmail(email)) {
      if (!constantTimeEquals(code, settings.reviewCode!)) throw _wrongCode();
      return _startSession(email, device);
    }

    final ok = await _db.tx((tx) async {
      final row = await tx.one(
        'SELECT code_hash, expires_at, attempts FROM sign_in_codes '
        'WHERE email = @e FOR UPDATE',
        {'e': email},
      );
      if (row == null) return false;
      final expired = !(row['expires_at'] as DateTime).isAfter(_clock());
      if (expired || (row['attempts'] as int) >= settings.maxCodeAttempts) {
        await tx.execute('DELETE FROM sign_in_codes WHERE email = @e', {
          'e': email,
        });
        return false;
      }
      if (!constantTimeEquals(
        row['code_hash'] as String,
        _hashCode(email, code),
      )) {
        await tx.execute(
          'UPDATE sign_in_codes SET attempts = attempts + 1 WHERE email = @e',
          {'e': email},
        );
        return false;
      }
      await tx.execute('DELETE FROM sign_in_codes WHERE email = @e', {
        'e': email,
      });
      return true;
    });
    if (!ok) {
      _log({'event': 'sign_in_failed', 'email': maskEmail(email)});
      throw _wrongCode();
    }
    return _startSession(email, device);
  }

  Future<SignIn> _startSession(String email, String device) async {
    for (var attempt = 0; ; attempt++) {
      try {
        final result = await _db.tx((tx) async {
          final now = _clock();
          var user = await tx.one(
            'SELECT id, business_id, email, name, role FROM users '
            'WHERE lower(email) = @e',
            {'e': email},
          );
          var created = false;
          if (user == null) {
            final businessId = newId('b');
            final userId = newId('u');
            await tx.execute(
              'INSERT INTO businesses (id, created_at, updated_at) '
              'VALUES (@id, @now:timestamptz, @now:timestamptz)',
              {'id': businessId, 'now': now},
            );
            await tx.execute(
              '''
              INSERT INTO users (id, business_id, email, role, created_at)
              VALUES (@id, @b, @e, 'owner', @now:timestamptz)''',
              {'id': userId, 'b': businessId, 'e': email, 'now': now},
            );
            user = {
              'id': userId,
              'business_id': businessId,
              'email': email,
              'name': '',
              'role': 'owner',
            };
            created = true;
          }
          final token = 'jws_${randomToken()}';
          final hash = sha256Hex(token);
          await tx.execute(
            '''
            INSERT INTO sessions
              (token_hash, user_id, device, created_at, last_used_at, expires_at)
            VALUES (@h, @u, @d, @now:timestamptz, @now:timestamptz,
              @exp:timestamptz)''',
            {
              'h': hash,
              'u': user['id'],
              'd': device.length > 80 ? device.substring(0, 80) : device,
              'now': now,
              'exp': now.add(settings.sessionTtl),
            },
          );
          await tx.execute(
            'UPDATE users SET last_seen_at = @now:timestamptz WHERE id = @u',
            {'now': now, 'u': user['id']},
          );
          return SignIn(
            token: token,
            account: _account(user, hash),
            created: created,
          );
        });
        _log({
          'event': result.created ? 'sign_up' : 'sign_in',
          'user': result.account.userId,
          'business': result.account.businessId,
        });
        return result;
      } on Object catch (e) {
        // Two sign-ins racing to create the same account: the loser
        // retries and finds the winner's.
        if (attempt == 0 && isUniqueViolation(e)) continue;
        rethrow;
      }
    }
  }

  /// The account for a bearer token, or null if it's unknown or expired.
  Future<Account?> authenticate(String? token) async {
    if (token == null || !_tokenPattern.hasMatch(token)) return null;
    final hash = sha256Hex(token);
    final now = _clock();
    final row = await _db.one(
      '''
      SELECT s.last_used_at, u.id, u.business_id, u.email, u.name, u.role
      FROM sessions s JOIN users u ON u.id = s.user_id
      WHERE s.token_hash = @h AND s.expires_at > @now:timestamptz''',
      {'h': hash, 'now': now},
    );
    if (row == null) return null;
    if (now.difference(row['last_used_at'] as DateTime) > _touchEvery) {
      await _db.execute(
        '''
        UPDATE sessions SET last_used_at = @now:timestamptz,
          expires_at = @exp:timestamptz
        WHERE token_hash = @h''',
        {'now': now, 'exp': now.add(settings.sessionTtl), 'h': hash},
      );
      await _db.execute(
        'UPDATE users SET last_seen_at = @now:timestamptz WHERE id = @u',
        {'now': now, 'u': row['id']},
      );
    }
    return _account(row, hash);
  }

  Future<void> signOut(Account a, {bool everywhere = false}) async {
    if (everywhere) {
      await _db.execute('DELETE FROM sessions WHERE user_id = @u', {
        'u': a.userId,
      });
    } else {
      await _db.execute('DELETE FROM sessions WHERE token_hash = @h', {
        'h': a.sessionHash,
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  /// Who's signed in and everything the app needs about their business.
  Future<Map<String, Object?>> me(Account a) async {
    final user = await _db.one(
      'SELECT id, email, name, role, email_notifications FROM users '
      'WHERE id = @u',
      {'u': a.userId},
    );
    final business = await _business(_db, a.businessId);
    if (user == null || business == null) throw ApiError.unauthorized();
    return {
      'user': {
        'id': user['id'],
        'email': user['email'],
        'name': user['name'],
        'role': user['role'],
        'email_notifications': user['email_notifications'],
      },
      'business': businessJson(business),
    };
  }

  Map<String, Object?> businessJson(Row b) {
    final profile = BusinessProfile.fromJson(b['profile']);
    return {
      'id': b['id'],
      'profile': profile.toJson(),
      'rates': Rates.fromJson(b['rates']).toJson(),
      'setup_complete': profile.name.isNotEmpty,
      'next_quote_number': b['next_quote_number'],
      'plan': BusinessPlan.fromRow(b, settings.plans).toJson(),
      'payments': {
        'connected': b['stripe_account_id'] != null,
        'ready': b['stripe_account_ready'],
      },
      'created_at': (b['created_at'] as DateTime).toIso8601String(),
    };
  }

  Future<Map<String, Object?>> updateBusiness(
    Account a,
    Map<String, Object?> body,
  ) async {
    a.requireOwner();
    final profile = body['profile'] == null
        ? null
        : BusinessProfile.fromJson(body['profile']);
    final rates = body['rates'] == null ? null : Rates.fromJson(body['rates']);
    if (profile == null && rates == null) {
      throw ApiError.badRequest('invalid_request', 'Send a profile or rates.');
    }
    if (profile != null && profile.name.isEmpty) {
      throw ApiError.badRequest('invalid_profile', 'Add your business name.');
    }
    await _db.execute(
      '''
      UPDATE businesses SET
        profile = COALESCE(@p:jsonb, profile),
        rates = COALESCE(@r:jsonb, rates),
        updated_at = @now:timestamptz
      WHERE id = @b''',
      {
        'p': profile?.toJson(),
        'r': rates?.toJson(),
        'now': _clock(),
        'b': a.businessId,
      },
    );
    _log({'event': 'business_updated', 'business': a.businessId});
    return me(a);
  }

  Future<Map<String, Object?>> updateUser(
    Account a,
    Map<String, Object?> body,
  ) async {
    final name = body['name'];
    final notify = body['email_notifications'];
    if (name != null && (name is! String || name.trim().length > 80)) {
      throw ApiError.badRequest('invalid_name', 'Names are up to 80 letters.');
    }
    if (notify != null && notify is! bool) {
      throw ApiError.badRequest(
        'invalid_request',
        'email_notifications must be true or false.',
      );
    }
    await _db.execute(
      '''
      UPDATE users SET name = COALESCE(@n, name),
        email_notifications = COALESCE(@notify, email_notifications)
      WHERE id = @u''',
      {'n': (name as String?)?.trim(), 'notify': notify, 'u': a.userId},
    );
    return me(a);
  }

  /// Reserves [count] quote numbers so phones can number quotes offline
  /// without clashing. [atLeast] lets a phone that numbered quotes before
  /// signing in move the counter past its own.
  Future<({int first, int count})> reserveNumbers(
    Account a, {
    int count = 1,
    int atLeast = 0,
  }) async {
    final n = count.clamp(1, 50);
    final row = await _db.one(
      '''
      UPDATE businesses SET
        next_quote_number = GREATEST(next_quote_number, @min:int4) + @n:int4,
        updated_at = @now:timestamptz
      WHERE id = @b
      RETURNING next_quote_number - @n:int4 AS first''',
      {
        'min': atLeast.clamp(0, 90000000),
        'n': n,
        'now': _clock(),
        'b': a.businessId,
      },
    );
    return (first: row!['first'] as int, count: n);
  }

  // ---------------------------------------------------------------------------
  // Team
  // ---------------------------------------------------------------------------

  Future<List<Map<String, Object?>>> team(Account a) async => [
    for (final u in await _db.query(
      '''
      SELECT id, email, name, role, created_at, last_seen_at FROM users
      WHERE business_id = @b ORDER BY created_at, id''',
      {'b': a.businessId},
    ))
      {
        'id': u['id'],
        'email': u['email'],
        'name': u['name'],
        'role': u['role'],
        'you': u['id'] == a.userId,
        'created_at': (u['created_at'] as DateTime).toIso8601String(),
        'last_seen_at': (u['last_seen_at'] as DateTime?)?.toIso8601String(),
      },
  ];

  /// Adds someone to the business. They sign in with their own email.
  Future<List<Map<String, Object?>>> addMember(
    Account a,
    Map<String, Object?> body,
  ) async {
    a.requireOwner();
    final email = _email(body['email']);
    final nameInput = body['name'];
    final name = nameInput is String ? nameInput.trim() : '';
    if (name.length > 80) {
      throw ApiError.badRequest('invalid_name', 'Names are up to 80 letters.');
    }
    try {
      await _db.tx((tx) async {
        // Locks the business so two adds can't both squeeze under the cap.
        final b = (await tx.one(
          'SELECT * FROM businesses WHERE id = @b FOR UPDATE',
          {'b': a.businessId},
        ))!;
        final plan = BusinessPlan.fromRow(b, settings.plans);
        final users =
            (await tx.one(
                  'SELECT count(*)::int AS n FROM users WHERE business_id = @b',
                  {'b': a.businessId},
                ))!['n']
                as int;
        if (users >= plan.maxUsers) {
          throw ApiError(
            402,
            'upgrade_required',
            'Your plan includes up to ${plan.maxUsers} people. Upgrade to '
                'add more.',
          );
        }
        final taken = await tx.one(
          'SELECT 1 FROM users WHERE lower(email) = @e',
          {'e': email},
        );
        if (taken != null) throw _emailTaken();
        await tx.execute(
          '''
          INSERT INTO users (id, business_id, email, name, role, created_at)
          VALUES (@id, @b, @e, @n, 'member', @now:timestamptz)''',
          {
            'id': newId('u'),
            'b': a.businessId,
            'e': email,
            'n': name,
            'now': _clock(),
          },
        );
        final business = BusinessProfile.fromJson(b['profile']).name;
        await _outbox.email(
          tx,
          _outbox.templates.memberAdded(
            email,
            business: business.isEmpty ? 'a crew' : business,
          ),
        );
      });
    } on Object catch (e) {
      if (isUniqueViolation(e)) throw _emailTaken();
      rethrow;
    }
    _log({'event': 'member_added', 'business': a.businessId});
    return team(a);
  }

  Future<List<Map<String, Object?>>> removeMember(
    Account a,
    String userId,
  ) async {
    a.requireOwner();
    if (userId == a.userId) {
      throw ApiError.badRequest(
        'cannot_remove_self',
        "You can't remove yourself. To close the account, delete it in "
            'settings.',
      );
    }
    final n = await _db.execute(
      'DELETE FROM users WHERE id = @u AND business_id = @b',
      {'u': userId, 'b': a.businessId},
    );
    if (n == 0) throw ApiError.notFound('No such team member.');
    _log({'event': 'member_removed', 'business': a.businessId});
    return team(a);
  }

  // ---------------------------------------------------------------------------
  // Your data
  // ---------------------------------------------------------------------------

  /// Everything stored about the business, as JSON.
  Future<Map<String, Object?>> export(Account a) async {
    a.requireOwner();
    final b = {'b': a.businessId};
    String? iso(Object? d) => (d as DateTime?)?.toIso8601String();
    final business = await _business(_db, a.businessId);
    return {
      'exported_at': _clock().toIso8601String(),
      'business': businessJson(business!),
      'users': [
        for (final u in await _db.query(
          'SELECT * FROM users WHERE business_id = @b ORDER BY created_at',
          b,
        ))
          {
            'id': u['id'],
            'email': u['email'],
            'name': u['name'],
            'role': u['role'],
            'created_at': iso(u['created_at']),
            'last_seen_at': iso(u['last_seen_at']),
          },
      ],
      'quotes': [
        for (final q in await _db.query(
          'SELECT * FROM quotes WHERE business_id = @b AND NOT deleted '
          'ORDER BY created_at',
          b,
        ))
          {'version': q['version'], 'quote': q['data']},
      ],
      'publications': [
        for (final p in await _db.query(
          'SELECT * FROM publications WHERE business_id = @b ORDER BY sent_at',
          b,
        ))
          {
            'public_id': p['public_id'],
            'quote_id': p['quote_id'],
            'revision': p['revision'],
            'sent_at': iso(p['sent_at']),
            'content': p['content'],
            'response': p['response'],
            'deposit_status': p['deposit_status'],
            'deposit_paid_cents': p['deposit_paid_cents'],
            'deposit_paid_at': iso(p['deposit_paid_at']),
          },
      ],
      'events': [
        for (final e in await _db.query(
          'SELECT * FROM quote_events WHERE business_id = @b ORDER BY id',
          b,
        ))
          {
            'quote_id': e['quote_id'],
            'public_id': e['public_id'],
            'kind': e['kind'],
            'data': e['data'],
            'at': iso(e['created_at']),
          },
      ],
      'photos': [
        for (final p in await _db.query(
          'SELECT id, content_type, bytes, created_at FROM photos '
          'WHERE business_id = @b ORDER BY created_at',
          b,
        ))
          {
            'id': p['id'],
            'content_type': p['content_type'],
            'bytes': p['bytes'],
            'created_at': iso(p['created_at']),
          },
      ],
    };
  }

  /// An owner deletes the whole business; a member deletes only themself.
  Future<void> deleteAccount(Account a, {required Object? confirm}) async {
    if (confirm != 'DELETE') {
      throw ApiError.badRequest(
        'confirmation_required',
        'Confirm by sending {"confirm": "DELETE"}.',
      );
    }
    if (!a.isOwner) {
      await _db.execute('DELETE FROM users WHERE id = @u', {'u': a.userId});
      _log({'event': 'user_deleted', 'business': a.businessId});
      return;
    }
    await _db.tx((tx) async {
      final b = await tx.one(
        'SELECT stripe_subscription_id FROM businesses WHERE id = @b '
        'FOR UPDATE',
        {'b': a.businessId},
      );
      if (b == null) return;
      final keys = [
        for (final r in await tx.query(
          'SELECT object_key FROM photos WHERE business_id = @b',
          {'b': a.businessId},
        ))
          r['object_key'] as String,
      ];
      await tx.execute('DELETE FROM businesses WHERE id = @b', {
        'b': a.businessId,
      });
      for (var i = 0; i < keys.length; i += 200) {
        await _outbox.add(tx, 'storage.delete', {
          'keys': keys.sublist(
            i,
            i + 200 > keys.length ? keys.length : i + 200,
          ),
        });
      }
      final subscription = b['stripe_subscription_id'] as String?;
      if (subscription != null) {
        await _outbox.add(tx, 'stripe.cancel_subscription', {
          'subscription_id': subscription,
        });
      }
    });
    _log({'event': 'business_deleted', 'business': a.businessId});
  }

  // ---------------------------------------------------------------------------

  static Future<Row?> _business(Db db, String id) =>
      db.one('SELECT * FROM businesses WHERE id = @b', {'b': id});

  String _email(Object? input) =>
      normalizeEmail(input) ??
      (throw ApiError.badRequest(
        'invalid_email',
        'Enter a valid email address.',
      ));

  bool _isReviewEmail(String email) =>
      settings.reviewEmail != null &&
      settings.reviewCode != null &&
      email == settings.reviewEmail!.toLowerCase();

  String _hashCode(String email, String code) =>
      hmacHex(settings.secret, 'sign-in:$email:$code');

  static Account _account(Row user, String sessionHash) => Account(
    userId: user['id'] as String,
    businessId: user['business_id'] as String,
    email: user['email'] as String,
    name: user['name'] as String,
    role: user['role'] as String,
    sessionHash: sessionHash,
  );

  static ApiError _wrongCode() => ApiError.badRequest(
    'invalid_code',
    'That code is wrong or has expired. Check the latest email, or ask for '
        'a new code.',
  );

  static ApiError _emailTaken() => ApiError(
    409,
    'email_taken',
    'That email already has a Jobwalk account. Use a different address.',
  );
}
