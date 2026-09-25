import 'package:jobwalk_server/src/common.dart';
import 'package:jobwalk_server/src/limits.dart';
import 'package:jobwalk_server/src/services/accounts.dart';
import 'package:jobwalk_server/src/services/plans.dart';
import 'package:test/test.dart';

import 'support/harness.dart';
import 'support/test_db.dart';

void main() {
  withDb((testDb) {
    late Harness h;
    setUp(() => h = Harness(testDb()));

    group('sign-in codes', () {
      test('first sign-in creates a business and an owner', () async {
        await h.accounts.requestCode(' Dana@Example.com ', ip: '1.1.1.1');
        expect(await h.runJobs(), 1);
        final mail = h.emails.sent.single;
        expect(mail.to, 'dana@example.com');
        expect(mail.subject, matches(RegExp(r'^Your Jobwalk code: \d{6}$')));
        expect(mail.text, contains('expires in 10 minutes'));

        final s = await h.accounts.verifyCode(
          'dana@example.com',
          h.lastCode('dana@example.com'),
          ip: '1.1.1.1',
          device: 'iPhone 15',
        );
        expect(s.created, isTrue);
        expect(s.token, startsWith('jws_'));
        expect(s.account.isOwner, isTrue);
        expect(s.account.businessId, startsWith('b_'));

        final me = await h.accounts.me(s.account);
        final business = me['business']! as Map;
        expect(business['setup_complete'], isFalse);
        expect((business['plan'] as Map)['id'], 'trial');
        expect((business['plan'] as Map)['trial_drafts_left'], 25);

        // The token is stored hashed.
        final session = await h.db.one('SELECT * FROM sessions');
        expect(session!['token_hash'], isNot(contains(s.token)));
        expect(session['device'], 'iPhone 15');
      });

      test('signing in again finds the same account', () async {
        final first = await h.signIn('dana@example.com');
        final second = await h.signIn('DANA@example.com');
        expect(second.created, isFalse);
        expect(second.account.userId, first.account.userId);
        expect(second.token, isNot(first.token));
      });

      test('codes are single use', () async {
        await h.accounts.requestCode('dana@example.com', ip: '1.1.1.1');
        await h.runJobs();
        final code = h.lastCode('dana@example.com');
        await h.accounts.verifyCode('dana@example.com', code, ip: '1.1.1.1');
        final e = await apiError(
          () => h.accounts.verifyCode('dana@example.com', code, ip: '1.1.1.1'),
        );
        expect(e.code, 'invalid_code');
      });

      test('codes expire', () async {
        await h.accounts.requestCode('dana@example.com', ip: '1.1.1.1');
        await h.runJobs();
        h.advance(const Duration(minutes: 11));
        final e = await apiError(
          () => h.accounts.verifyCode(
            'dana@example.com',
            h.lastCode('dana@example.com'),
            ip: '1.1.1.1',
          ),
        );
        expect(e.status, 400);
        expect(e.code, 'invalid_code');
      });

      test('five wrong guesses burn the code', () async {
        await h.accounts.requestCode('dana@example.com', ip: '1.1.1.1');
        await h.runJobs();
        final code = h.lastCode('dana@example.com');
        final wrong = code == '000000' ? '111111' : '000000';
        for (var i = 0; i < 5; i++) {
          final e = await apiError(
            () =>
                h.accounts.verifyCode('dana@example.com', wrong, ip: '1.1.1.1'),
          );
          expect(e.code, 'invalid_code');
        }
        final e = await apiError(
          () => h.accounts.verifyCode('dana@example.com', code, ip: '1.1.1.1'),
        );
        expect(e.code, 'invalid_code', reason: 'the right code is burned');
      });

      test('a new code replaces the old one', () async {
        await h.accounts.requestCode('dana@example.com', ip: '1.1.1.1');
        await h.runJobs();
        final old = h.lastCode('dana@example.com');
        await h.accounts.requestCode('dana@example.com', ip: '1.1.1.1');
        await h.runJobs();
        final fresh = h.lastCode('dana@example.com');
        if (old != fresh) {
          await expectLater(
            h.accounts.verifyCode('dana@example.com', old, ip: '1.1.1.1'),
            throwsA(isA<ApiError>()),
          );
        }
        final s = await h.accounts.verifyCode(
          'dana@example.com',
          fresh,
          ip: '1.1.1.1',
        );
        expect(s.created, isTrue);
      });

      test('codes tolerate spaces and dashes', () async {
        await h.accounts.requestCode('dana@example.com', ip: '1.1.1.1');
        await h.runJobs();
        final code = h.lastCode('dana@example.com');
        final spaced = '${code.substring(0, 3)} - ${code.substring(3)}';
        final s = await h.accounts.verifyCode(
          'dana@example.com',
          spaced,
          ip: '1.1.1.1',
        );
        expect(s.account.email, 'dana@example.com');
      });

      test('rejects bad emails and malformed codes', () async {
        expect(
          (await apiError(
            () => h.accounts.requestCode('not an email', ip: '1.1.1.1'),
          )).code,
          'invalid_email',
        );
        expect(
          (await apiError(
            () => h.accounts.verifyCode('a@b.co', '12', ip: '1.1.1.1'),
          )).code,
          'invalid_code',
        );
      });

      test('rate limits requests per address', () async {
        final strict = AccountService(
          db: h.db,
          outbox: h.outbox,
          settings: AccountSettings(secret: 'x' * 32),
          codePerEmail: MemoryLimiter(
            RateLimiter(
              capacity: 2,
              refillEvery: const Duration(minutes: 10),
              clock: h.clock,
            ),
          ),
          codePerIp: h.generous(),
          verifyPerIp: h.generous(),
          clock: h.clock,
        );
        await strict.requestCode('dana@example.com', ip: '1.1.1.1');
        await strict.requestCode('dana@example.com', ip: '1.1.1.1');
        final e = await apiError(
          () => strict.requestCode('dana@example.com', ip: '1.1.1.1'),
        );
        expect(e.status, 429);
        expect(e.retryAfter, isNotNull);
        // Another address is unaffected.
        await strict.requestCode('lee@example.com', ip: '1.1.1.1');
      });

      test('the review account signs in with a fixed code', () async {
        await h.accounts.requestCode('review@jobwalk.test', ip: '1.1.1.1');
        await h.runJobs();
        expect(h.emails.sent, isEmpty);
        final s = await h.accounts.verifyCode(
          'review@jobwalk.test',
          '424242',
          ip: '1.1.1.1',
        );
        expect(s.created, isTrue);
        await expectLater(
          h.accounts.verifyCode('review@jobwalk.test', '000000', ip: '1.1.1.1'),
          throwsA(isA<ApiError>()),
        );
      });
    });

    group('sessions', () {
      test('tokens authenticate until signed out', () async {
        final s = await h.signIn('dana@example.com');
        final a = await h.accounts.authenticate(s.token);
        expect(a!.userId, s.account.userId);
        expect(await h.accounts.authenticate('jws_${'x' * 43}'), isNull);
        expect(await h.accounts.authenticate('garbage'), isNull);
        expect(await h.accounts.authenticate(null), isNull);

        await h.accounts.signOut(a);
        expect(await h.accounts.authenticate(s.token), isNull);
      });

      test('sign out everywhere ends every session', () async {
        final one = await h.signIn('dana@example.com');
        final two = await h.signIn('dana@example.com');
        await h.accounts.signOut(one.account, everywhere: true);
        expect(await h.accounts.authenticate(one.token), isNull);
        expect(await h.accounts.authenticate(two.token), isNull);
      });

      test('sessions expire when unused and slide when used', () async {
        final s = await h.signIn('dana@example.com');
        h.advance(const Duration(days: 80));
        expect(await h.accounts.authenticate(s.token), isNotNull);
        h.advance(const Duration(days: 80));
        expect(
          await h.accounts.authenticate(s.token),
          isNotNull,
          reason: 'use on day 80 extended it',
        );
        h.advance(const Duration(days: 91));
        expect(await h.accounts.authenticate(s.token), isNull);
      });
    });

    group('business', () {
      test('owners update the profile and rates', () async {
        final s = await h.signIn('dana@example.com');
        final me = await h.accounts.updateBusiness(s.account, {
          'profile': {
            'name': 'Brightline Painting',
            'trades': ['painting'],
            'zip': '78704',
          },
          'rates': {'labor_rate_cents': 7200, 'deposit_pct': 30},
        });
        final business = me['business']! as Map;
        expect(business['setup_complete'], isTrue);
        expect((business['profile'] as Map)['name'], 'Brightline Painting');
        expect((business['rates'] as Map)['labor_rate_cents'], 7200);

        // Rates alone leave the profile as it was.
        final again = await h.accounts.updateBusiness(s.account, {
          'rates': {'labor_rate_cents': 8000},
        });
        final b2 = again['business']! as Map;
        expect((b2['profile'] as Map)['zip'], '78704');
        expect((b2['rates'] as Map)['labor_rate_cents'], 8000);
      });

      test('requires a business name', () async {
        final s = await h.signIn('dana@example.com');
        final e = await apiError(
          () => h.accounts.updateBusiness(s.account, {
            'profile': {'name': ''},
          }),
        );
        expect(e.code, 'invalid_profile');
      });

      test('users set their name and notification preference', () async {
        final s = await h.signIn('dana@example.com');
        final me = await h.accounts.updateUser(s.account, {
          'name': ' Dana Ortiz ',
          'email_notifications': false,
        });
        final user = me['user']! as Map;
        expect(user['name'], 'Dana Ortiz');
        expect(user['email_notifications'], isFalse);
      });

      test('quote numbers are reserved without overlap', () async {
        final s = await h.signIn('dana@example.com');
        final a = await h.accounts.reserveNumbers(s.account, count: 5);
        final b = await h.accounts.reserveNumbers(s.account, count: 5);
        expect(a.first, 1001);
        expect(b.first, 1006);
        // A phone that already used numbers up to 1041 moves the counter.
        final c = await h.accounts.reserveNumbers(s.account, atLeast: 1042);
        expect(c.first, 1042);
        final d = await h.accounts.reserveNumbers(s.account, atLeast: 1000);
        expect(d.first, 1043);
        final many = await h.accounts.reserveNumbers(s.account, count: 999);
        expect(many.count, 50);
      });
    });

    group('team', () {
      test('owners add members, who sign in to the same business', () async {
        final owner = await h.owner('dana@example.com');
        final team = await h.accounts.addMember(owner.account, {
          'email': 'Lee@Example.com',
          'name': 'Lee',
        });
        expect(team, hasLength(2));
        expect(
          team.firstWhere((u) => u['email'] == 'lee@example.com')['role'],
          'member',
        );
        await h.runJobs();
        expect(
          h.emails.sent.last.subject,
          'You were added to Brightline Painting on Jobwalk',
        );

        final lee = await h.signIn('lee@example.com');
        expect(lee.created, isFalse);
        expect(lee.account.businessId, owner.account.businessId);
        expect(lee.account.isOwner, isFalse);

        // Members can't manage the team or the business.
        expect(
          (await apiError(
            () => h.accounts.addMember(lee.account, {'email': 'x@y.co'}),
          )).status,
          403,
        );
        expect(
          (await apiError(
            () => h.accounts.updateBusiness(lee.account, {
              'rates': {'labor_rate_cents': 1},
            }),
          )).status,
          403,
        );
        expect(
          (await apiError(() => h.accounts.export(lee.account))).status,
          403,
        );
      });

      test('an email can belong to only one business', () async {
        final owner = await h.owner('dana@example.com');
        await h.signIn('lee@example.com');
        final e = await apiError(
          () =>
              h.accounts.addMember(owner.account, {'email': 'lee@example.com'}),
        );
        expect(e.status, 409);
        expect(e.code, 'email_taken');
      });

      test('the plan caps the team size', () async {
        final owner = await h.owner('dana@example.com');
        await h.accounts.addMember(owner.account, {'email': 'a@example.com'});
        await h.accounts.addMember(owner.account, {'email': 'b@example.com'});
        final e = await apiError(
          () => h.accounts.addMember(owner.account, {'email': 'c@example.com'}),
        );
        expect(e.status, 402);
        expect(e.code, 'upgrade_required');

        await h.db.execute(
          "UPDATE businesses SET plan = 'crew', plan_status = 'active'",
        );
        await h.accounts.addMember(owner.account, {'email': 'c@example.com'});
      });

      test('removing a member ends their sessions', () async {
        final owner = await h.owner('dana@example.com');
        await h.accounts.addMember(owner.account, {'email': 'lee@example.com'});
        final lee = await h.signIn('lee@example.com');
        expect(
          (await apiError(
            () => h.accounts.removeMember(owner.account, owner.account.userId),
          )).code,
          'cannot_remove_self',
        );
        final team = await h.accounts.removeMember(
          owner.account,
          lee.account.userId,
        );
        expect(team, hasLength(1));
        expect(await h.accounts.authenticate(lee.token), isNull);
        expect(
          (await apiError(
            () => h.accounts.removeMember(owner.account, lee.account.userId),
          )).status,
          404,
        );
      });

      test("owners can't touch another business's people", () async {
        final dana = await h.owner('dana@example.com');
        final other = await h.owner('sam@example.com', business: 'Other Co');
        final e = await apiError(
          () => h.accounts.removeMember(dana.account, other.account.userId),
        );
        expect(e.status, 404);
      });
    });

    group('your data', () {
      test('export includes the business and its people', () async {
        final owner = await h.owner('dana@example.com');
        final data = await h.accounts.export(owner.account);
        expect((data['business']! as Map)['id'], owner.account.businessId);
        expect(data['users'], hasLength(1));
        expect(data['quotes'], isEmpty);
      });

      test('deleting needs confirmation and removes everything', () async {
        final owner = await h.owner('dana@example.com');
        await h.accounts.addMember(owner.account, {'email': 'lee@example.com'});
        final lee = await h.signIn('lee@example.com');
        await h.db.execute(
          'INSERT INTO photos (business_id, id, object_key, content_type, '
          "bytes) VALUES (@b, 'p1', 'photos/x/p1.jpg', 'image/jpeg', 10)",
          {'b': owner.account.businessId},
        );
        await h.db.execute(
          "UPDATE businesses SET stripe_subscription_id = 'sub_123'",
        );

        expect(
          (await apiError(
            () => h.accounts.deleteAccount(owner.account, confirm: 'yes'),
          )).code,
          'confirmation_required',
        );
        await h.accounts.deleteAccount(owner.account, confirm: 'DELETE');
        expect(await h.db.query('SELECT * FROM businesses'), isEmpty);
        expect(await h.db.query('SELECT * FROM users'), isEmpty);
        expect(await h.accounts.authenticate(owner.token), isNull);
        expect(await h.accounts.authenticate(lee.token), isNull);
        final jobs = await h.db.query(
          'SELECT kind, payload FROM jobs '
          "WHERE kind <> 'email.send' ORDER BY id",
        );
        expect(
          [for (final j in jobs) j['kind']],
          ['storage.delete', 'stripe.cancel_subscription'],
        );
        expect((jobs.first['payload'] as Map)['keys'], ['photos/x/p1.jpg']);
      });

      test('a member deleting their account leaves the business', () async {
        final owner = await h.owner('dana@example.com');
        await h.accounts.addMember(owner.account, {'email': 'lee@example.com'});
        final lee = await h.signIn('lee@example.com');
        await h.accounts.deleteAccount(lee.account, confirm: 'DELETE');
        expect(await h.accounts.team(owner.account), hasLength(1));
        expect(await h.accounts.authenticate(owner.token), isNotNull);
      });
    });

    test('plan rules', () {
      const rules = PlanRules(trialDrafts: 2);
      BusinessPlan plan(String id, String status, int used) => BusinessPlan(
        plan: id,
        status: status,
        trialDraftsUsed: used,
        rules: rules,
      );
      expect(plan('trial', 'trialing', 1).canDraft, isTrue);
      expect(plan('trial', 'trialing', 2).canDraft, isFalse);
      expect(plan('pro', 'active', 99).canDraft, isTrue);
      expect(plan('pro', 'past_due', 99).paid, isTrue);
      expect(plan('pro', 'canceled', 99).canDraft, isFalse);
      expect(plan('crew', 'canceled', 0).maxUsers, 3);
      expect(plan('crew', 'active', 0).maxUsers, 15);
    });
  });
}
