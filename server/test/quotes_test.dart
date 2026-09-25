import 'dart:typed_data';

import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

import 'support/harness.dart';
import 'support/test_db.dart';

void main() {
  withDb((testDb) {
    late Harness h;
    late SignIn dana;
    setUp(() async {
      h = Harness(testDb());
      dana = await h.owner('dana@example.com');
    });

    Map<String, Object?> quoteOf(Map<String, Object?> item) =>
        item['quote']! as Map<String, Object?>;

    group('sync', () {
      test('put creates, then updates with the right base version', () async {
        final q = h.sampleQuote();
        final created = await h.quotes.put(dana.account, q.id, {
          'quote': q.toJson(),
          'base_version': 0,
        });
        expect(created['version'], 1);
        expect(quoteOf(created)['id'], q.id);
        expect(quoteOf(created)['share'], isNull);

        final edited = q.copyWith(title: 'Living room, walls and trim');
        final updated = await h.quotes.put(dana.account, q.id, {
          'quote': edited.toJson(),
          'base_version': 1,
        });
        expect(updated['version'], 2);
        expect(quoteOf(updated)['title'], 'Living room, walls and trim');
      });

      test(
        'a stale base version conflicts and returns the server copy',
        () async {
          final q = h.sampleQuote();
          await h.quotes.put(dana.account, q.id, {'quote': q.toJson()});
          await h.quotes.put(dana.account, q.id, {
            'quote': q.copyWith(title: 'From the tablet').toJson(),
            'base_version': 1,
          });
          final e = await apiError(
            () => h.quotes.put(dana.account, q.id, {
              'quote': q.copyWith(title: 'From the phone').toJson(),
              'base_version': 1,
            }),
          );
          expect(e.status, 409);
          expect(e.code, 'conflict');
          final current = e.details['current']! as Map<String, Object?>;
          expect(current['version'], 2);
          expect(quoteOf(current)['title'], 'From the tablet');
        },
      );

      test('retrying a write that landed is not a conflict', () async {
        final q = h.sampleQuote();
        await h.quotes.put(dana.account, q.id, {'quote': q.toJson()});
        final edit = {
          'quote': q.copyWith(title: 'New').toJson(),
          'base_version': 1,
        };
        await h.quotes.put(dana.account, q.id, edit);
        final retry = await h.quotes.put(dana.account, q.id, edit);
        expect(retry['version'], 2);
      });

      test('changes page through by cursor, oldest change first', () async {
        final ids = <String>[];
        for (var i = 0; i < 5; i++) {
          final q = h.sampleQuote(number: 1000 + i);
          ids.add(q.id);
          await h.quotes.put(dana.account, q.id, {'quote': q.toJson()});
        }
        final first = await h.quotes.changes(dana.account, limit: 3);
        expect(first['more'], isTrue);
        expect([
          for (final i in first['items']! as List) (i as Map)['id'],
        ], ids.sublist(0, 3));
        final second = await h.quotes.changes(
          dana.account,
          since: first['cursor']! as int,
          limit: 3,
        );
        expect(second['more'], isFalse);
        expect((second['items']! as List).length, 2);

        // An edit moves the quote to the end.
        final cursor = second['cursor']! as int;
        final edited = await h.quotes.get(dana.account, ids.first);
        await h.quotes.put(dana.account, ids.first, {
          'quote': {...quoteOf(edited), 'title': 'Edited'},
          'base_version': 1,
        });
        final third = await h.quotes.changes(dana.account, since: cursor);
        expect(
          [for (final i in third['items']! as List) (i as Map)['id']],
          [ids.first],
        );
        final idle = await h.quotes.changes(
          dana.account,
          since: third['cursor']! as int,
        );
        expect(idle['items'], isEmpty);
        expect(idle['cursor'], third['cursor']);
      });

      test('deletes leave a tombstone that syncs', () async {
        final q = h.sampleQuote();
        await h.quotes.put(dana.account, q.id, {'quote': q.toJson()});
        final cursor = (await h.quotes.changes(dana.account))['cursor']! as int;
        final deleted = await h.quotes.delete(dana.account, q.id);
        expect(deleted, {'id': q.id, 'version': 2, 'deleted': true});
        final changes = await h.quotes.changes(dana.account, since: cursor);
        expect(changes['items'], [
          {'id': q.id, 'version': 2, 'deleted': true},
        ]);
        expect(
          (await apiError(() => h.quotes.get(dana.account, q.id))).status,
          404,
        );
        final e = await apiError(
          () => h.quotes.put(dana.account, q.id, {
            'quote': q.toJson(),
            'base_version': 1,
          }),
        );
        expect(e.code, 'deleted');
        // Deleting again is fine.
        await h.quotes.delete(dana.account, q.id);
      });

      test('deleting removes its photos and the customer link', () async {
        final q = h.sampleQuote();
        final withPhotos = q.copyWith(photoKeys: ['${q.id}_0', '${q.id}_1']);
        for (final key in withPhotos.photoKeys) {
          await h.app.photos.put(dana.account, key, jpeg());
        }
        final publicId = await h.sendQuote(dana.account, withPhotos);
        await h.quotes.delete(dana.account, q.id);
        expect(await h.quotes.open(publicId, countView: false), isNull);
        expect(await h.db.query('SELECT * FROM photos'), isEmpty);
        await h.runJobs();
        expect(h.store.objects, isEmpty);
      });

      test('quotes are private to their business', () async {
        final sam = await h.owner('sam@example.com', business: 'Other Co');
        final q = h.sampleQuote();
        await h.quotes.put(dana.account, q.id, {'quote': q.toJson()});
        expect(
          (await apiError(() => h.quotes.get(sam.account, q.id))).status,
          404,
        );
        expect((await h.quotes.changes(sam.account))['items'], isEmpty);
        expect(
          (await apiError(() => h.quotes.publish(sam.account, q.id))).status,
          404,
        );
        // The same id in another business is a different quote.
        final theirs = await h.quotes.put(sam.account, q.id, {
          'quote': q.copyWith(title: 'Theirs').toJson(),
        });
        expect(theirs['version'], 1);
        expect(
          quoteOf(await h.quotes.get(dana.account, q.id))['title'],
          isNot('Theirs'),
        );
      });

      test('rejects malformed quotes and ids', () async {
        final q = h.sampleQuote();
        expect(
          (await apiError(
            () => h.quotes.put(dana.account, 'other_id', {'quote': q.toJson()}),
          )).code,
          'invalid_quote',
        );
        expect(
          (await apiError(
            () => h.quotes.put(dana.account, q.id, {'quote': 'nope'}),
          )).code,
          'invalid_quote',
        );
        expect(
          (await apiError(
            () => h.quotes.put(dana.account, 'bad id!', {'quote': q.toJson()}),
          )).status,
          404,
        );
      });

      test('members share the business quotes', () async {
        await h.accounts.addMember(dana.account, {'email': 'lee@example.com'});
        final lee = await h.signIn('lee@example.com');
        final q = h.sampleQuote();
        await h.quotes.put(lee.account, q.id, {'quote': q.toJson()});
        expect(quoteOf(await h.quotes.get(dana.account, q.id))['id'], q.id);
      });
    });

    group('publishing', () {
      test('builds the customer page from the synced quote', () async {
        final q = h.sampleQuote();
        await h.quotes.put(dana.account, q.id, {'quote': q.toJson()});
        final published = await h.quotes.publish(dana.account, q.id);
        expect(published['changed'], isTrue);
        final quote = quoteOf(published);
        expect(quote['status'], 'sent');
        final share = quote['share']! as Map;
        expect(share['public_id'], matches(RegExp(r'^[a-z0-9]{16}$')));
        expect(share['url'], 'https://jobwalk.test/q/${share['public_id']}');
        expect(share['revision'], 1);
        expect(share['owner_token'], '');
        expect(published['version'], 1, reason: 'publishing is not an edit');

        final view = await h.quotes.open(
          share['public_id']! as String,
          countView: false,
        );
        expect(view!.quote.business.name, 'Brightline Painting');
        expect(view.quote.number, 1042);
        expect(view.quote.options.map((o) => o.totalCents), [
          72500,
          124500,
          141000,
        ]);
        final events = await h.db.query('SELECT kind FROM quote_events');
        expect(events.single['kind'], 'sent');
      });

      test('needs a business name and a valid quote', () async {
        final nobody = await h.signIn('new@example.com');
        final q = h.sampleQuote();
        await h.quotes.put(nobody.account, q.id, {'quote': q.toJson()});
        expect(
          (await apiError(() => h.quotes.publish(nobody.account, q.id))).code,
          'profile_incomplete',
        );
        final empty = h.sampleQuote().copyWith(items: const []);
        await h.quotes.put(dana.account, empty.id, {'quote': empty.toJson()});
        expect(
          (await apiError(() => h.quotes.publish(dana.account, empty.id))).code,
          'invalid_quote',
        );
      });

      test('republishing an unchanged quote keeps the revision', () async {
        final q = h.sampleQuote();
        final publicId = await h.sendQuote(dana.account, q);
        h.advance(const Duration(days: 1));
        final again = await h.quotes.publish(dana.account, q.id);
        expect(again['changed'], isFalse);
        expect((quoteOf(again)['share']! as Map)['public_id'], publicId);
        expect((quoteOf(again)['share']! as Map)['revision'], 1);
      });

      test('edits make a new revision that clears a decline', () async {
        final q = h.sampleQuote();
        final publicId = await h.sendQuote(dana.account, q);
        await h.quotes.open(publicId, countView: true);
        await h.quotes.decline(
          publicId,
          reason: 'Too pricey',
          ip: '1.1.1.1',
          userAgent: browser,
        );
        var current = await h.quotes.get(dana.account, q.id);
        expect(quoteOf(current)['status'], 'declined');

        await h.quotes.put(dana.account, q.id, {
          'quote': q.copyWith(discountCents: 10000).toJson(),
          'base_version': current['version'],
        });
        final republished = await h.quotes.publish(dana.account, q.id);
        final share = quoteOf(republished)['share']! as Map;
        expect(share['public_id'], publicId, reason: 'same link');
        expect(share['revision'], 2);
        expect(quoteOf(republished)['status'], 'viewed');
        final view = await h.quotes.open(publicId, countView: false);
        expect(view!.response.declinedAt, isNull);
        expect(view.response.views, 1, reason: 'views survive revisions');
        expect(view.quote.defaultOption.discountCents, 10000);
        current = await h.quotes.get(dana.account, q.id);
        expect(quoteOf(current)['status'], 'viewed');
      });

      test('an expired unchanged quote is re-issued with new dates', () async {
        final q = h.sampleQuote();
        final publicId = await h.sendQuote(dana.account, q);
        h.advance(const Duration(days: 31));
        final again = await h.quotes.publish(dana.account, q.id);
        expect(again['changed'], isTrue);
        final view = await h.quotes.open(publicId, countView: false);
        expect(view!.revision, 2);
        expect(view.quote.validUntil.isAfter(h.now), isTrue);
      });

      test('approved quotes are final', () async {
        final q = h.sampleQuote();
        final publicId = await h.sendQuote(dana.account, q);
        await approve(h, publicId, option: 'walls_trim');
        await h.quotes.put(dana.account, q.id, {
          'quote': q.copyWith(title: 'Changed').toJson(),
          'base_version': 1,
        });
        final e = await apiError(() => h.quotes.publish(dana.account, q.id));
        expect(e.code, 'already_approved');
      });
    });

    group('the customer', () {
      late Quote q;
      late String publicId;
      setUp(() async {
        q = h.sampleQuote();
        publicId = await h.sendQuote(dana.account, q);
        h.emails.sent.clear();
      });

      test('the first view marks it viewed and tells the contractor', () async {
        final view = await h.quotes.open(publicId, countView: true);
        expect(view!.response.views, 1);
        await h.quotes.open(publicId, countView: true);
        final current = await h.quotes.get(dana.account, q.id);
        expect(quoteOf(current)['status'], 'viewed');
        expect((quoteOf(current)['response']! as Map)['views'], 2);
        await h.runJobs();
        expect(h.emails.sent.map((m) => m.subject), [
          'Dana Ortiz opened Quote #1042',
        ]);
      });

      test('previews are not views', () async {
        await h.quotes.open(publicId, countView: false);
        final current = await h.quotes.get(dana.account, q.id);
        expect(quoteOf(current)['status'], 'sent');
      });

      test('approval records an audit trail and notifies', () async {
        final outcome = await h.quotes.approve(
          publicId,
          optionId: 'walls_trim',
          name: ' Dana Ortiz ',
          agreed: true,
          ip: '198.51.100.9',
          userAgent: browser,
        );
        expect(outcome, ApproveOutcome.approved);
        final current = quoteOf(await h.quotes.get(dana.account, q.id));
        expect(current['status'], 'approved');
        expect(current['chosen_tier_id'], 'walls_trim');
        final response = current['response']! as Map;
        expect(response['signature'], 'Dana Ortiz');
        expect(response['approved_option'], 'walls_trim');

        final event =
            (await h.db.one(
                  "SELECT data FROM quote_events WHERE kind = 'approved'",
                ))!['data']
                as Map;
        expect(event['option_id'], 'walls_trim');
        expect(event['total_cents'], 124500);
        expect(event['signature'], 'Dana Ortiz');
        expect(event['ip'], '198.51.100.9');
        expect(event['user_agent'], browser);
        expect(event['revision'], 1);
        expect(event['content_hash'], hasLength(64));

        await h.runJobs();
        final mail = h.emails.sent.single;
        expect(mail.to, 'dana@example.com');
        expect(mail.subject, 'Dana Ortiz approved Quote #1042');
        expect(mail.text, contains('Walls + trim, \$1,245'));
        expect(mail.text, contains('https://jobwalk.test/q/$publicId'));

        // The activity feed hides the IP and browser.
        final activity = await h.quotes.activity(dana.account);
        final approved = (activity['events']! as List).first as Map;
        expect(approved['kind'], 'approved');
        expect(approved['quote_number'], 1042);
        expect(approved['customer'], 'Dana Ortiz');
        expect((approved['data']! as Map).containsKey('ip'), isFalse);
      });

      test('approval explains what is missing', () async {
        Future<ApproveOutcome> attempt({
          String option = 'walls_trim',
          String name = 'Dana',
          bool agreed = true,
        }) => h.quotes.approve(
          publicId,
          optionId: option,
          name: name,
          agreed: agreed,
          ip: '1.1.1.1',
          userAgent: browser,
        );
        expect(await attempt(option: 'nope'), ApproveOutcome.option);
        expect(await attempt(name: '  '), ApproveOutcome.name);
        expect(await attempt(agreed: false), ApproveOutcome.agree);
        expect(
          await h.quotes.approve(
            'zzzzzzzzzzzzzzzz',
            optionId: '',
            name: 'x',
            agreed: true,
            ip: '',
            userAgent: '',
          ),
          ApproveOutcome.missing,
        );
        expect(await attempt(), ApproveOutcome.approved);
        expect(
          await attempt(option: 'full_room'),
          ApproveOutcome.alreadyApproved,
        );
        final view = await h.quotes.open(publicId, countView: false);
        expect(view!.response.approvedTierId, 'walls_trim');
      });

      test('expired quotes cannot be approved', () async {
        h.advance(const Duration(days: 31));
        expect(
          await h.quotes.approve(
            publicId,
            optionId: 'walls_trim',
            name: 'Dana',
            agreed: true,
            ip: '',
            userAgent: '',
          ),
          ApproveOutcome.expired,
        );
      });

      test('decline records the reason; approval still possible', () async {
        expect(
          await h.quotes.decline(
            publicId,
            reason: 'Went with someone else',
            ip: '1.1.1.1',
            userAgent: browser,
          ),
          isTrue,
        );
        expect(
          quoteOf(await h.quotes.get(dana.account, q.id))['status'],
          'declined',
        );
        await h.runJobs();
        expect(h.emails.sent.single.text, contains('Went with someone else'));
        await approve(h, publicId, option: 'walls');
        expect(
          quoteOf(await h.quotes.get(dana.account, q.id))['status'],
          'approved',
        );
      });

      test('a decline cannot undo an approval', () async {
        await approve(h, publicId, option: 'walls');
        await h.quotes.decline(publicId, reason: 'Oops', ip: '', userAgent: '');
        final view = await h.quotes.open(publicId, countView: false);
        expect(view!.response.approvedAt, isNotNull);
        expect(view.response.declinedAt, isNull);
      });

      test(
        'a manual close after sending sticks; before sending does not',
        () async {
          final current = await h.quotes.get(dana.account, q.id);
          final lost = Quote.fromJson(quoteOf(current))!.copyWith(
            status: QuoteStatus.declined,
            closedAt: h.now.add(const Duration(hours: 1)),
          );
          await h.quotes.put(dana.account, q.id, {
            'quote': lost.toJson(),
            'base_version': current['version'],
          });
          await h.quotes.open(publicId, countView: true);
          expect(
            quoteOf(await h.quotes.get(dana.account, q.id))['status'],
            'declined',
          );
        },
      );
    });

    group('follow-ups', () {
      test('nudge the contractor when a sent quote gets no decision', () async {
        final q = h.sampleQuote();
        final publicId = await h.sendQuote(dana.account, q);
        await h.quotes.open(publicId, countView: true);
        await h.runJobs();
        h.emails.sent.clear();

        h.advance(const Duration(days: 3, minutes: 1));
        await h.runJobs();
        final mail = h.emails.sent.single;
        expect(mail.subject, 'No decision yet on Quote #1042');
        expect(mail.text, contains('opened it once'));
        final kinds = [
          for (final e in await h.db.query(
            'SELECT kind FROM quote_events ORDER BY id',
          ))
            e['kind'],
        ];
        expect(kinds.last, 'follow_up_sent');
      });

      test('skip quotes that were decided, closed, or revised', () async {
        final decided = h.sampleQuote(number: 1);
        final decidedId = await h.sendQuote(dana.account, decided);
        await approve(h, decidedId, option: 'walls');

        final revised = h.sampleQuote(number: 2);
        await h.sendQuote(dana.account, revised);
        h.advance(const Duration(days: 1));
        await h.quotes.put(dana.account, revised.id, {
          'quote': revised.copyWith(discountCents: 5000).toJson(),
          'base_version': 1,
        });
        await h.quotes.publish(dana.account, revised.id);

        await h.runJobs();
        h.emails.sent.clear();
        h.advance(const Duration(days: 2, minutes: 1));
        await h.runJobs();
        expect(h.emails.sent, isEmpty, reason: 'revision 1 nudge skipped');
        h.advance(const Duration(days: 1));
        await h.runJobs();
        expect(h.emails.sent.single.subject, contains('Quote #2'));
      });

      test('notifications respect preferences and reach the sender', () async {
        await h.accounts.addMember(dana.account, {'email': 'lee@example.com'});
        await h.accounts.addMember(dana.account, {'email': 'kim@example.com'});
        final lee = await h.signIn('lee@example.com');
        await h.signIn('kim@example.com');
        await h.accounts.updateUser(dana.account, {
          'email_notifications': false,
        });
        final q = h.sampleQuote();
        final publicId = await h.sendQuote(lee.account, q);
        await h.runJobs();
        h.emails.sent.clear();
        await approve(h, publicId, option: 'walls');
        await h.runJobs();
        expect(h.emails.sent.map((m) => m.to), ['lee@example.com']);
      });
    });

    test('activity pages newest first', () async {
      for (var i = 0; i < 3; i++) {
        await h.sendQuote(dana.account, h.sampleQuote(number: 2000 + i));
      }
      final page = await h.quotes.activity(dana.account, limit: 2);
      final events = page['events']! as List;
      expect(events.map((e) => (e as Map)['quote_number']), [2002, 2001]);
      final rest = await h.quotes.activity(
        dana.account,
        before: page['next']! as int,
      );
      expect(
        (rest['events']! as List).single,
        containsPair('quote_number', 2000),
      );
      expect(rest['next'], isNull);
    });

    test('concurrent writes keep the sync order gap-free', () async {
      final quotes = [for (var i = 0; i < 12; i++) h.sampleQuote(number: i)];
      await Future.wait([
        for (final q in quotes)
          h.quotes.put(dana.account, q.id, {'quote': q.toJson()}),
      ]);
      var cursor = 0;
      final seen = <String>{};
      while (true) {
        final page = await h.quotes.changes(
          dana.account,
          since: cursor,
          limit: 5,
        );
        for (final item in page['items']! as List) {
          seen.add((item as Map)['id']! as String);
        }
        cursor = page['cursor']! as int;
        if (page['more'] != true) break;
      }
      expect(seen, hasLength(12));
    });
  });
}

Future<void> approve(
  Harness h,
  String publicId, {
  required String option,
}) async {
  final outcome = await h.quotes.approve(
    publicId,
    optionId: option,
    name: 'Dana Ortiz',
    agreed: true,
    ip: '198.51.100.9',
    userAgent: browser,
  );
  if (outcome != ApproveOutcome.approved) throw StateError('$outcome');
}

Uint8List jpeg() => Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);
