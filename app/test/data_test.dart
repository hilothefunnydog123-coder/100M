import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jobwalk/data/blob_store.dart';
import 'package:jobwalk/data/blob_store_file.dart';
import 'package:jobwalk/data/repositories.dart';
import 'package:jobwalk/data/settings.dart';
import 'package:jobwalk/services/api.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

final now = DateTime.utc(2026, 9, 25, 15);

Quote sampleQuote() => QuoteBuilder.fromDraft(
  SampleJob.livingRoom.draft,
  id: 'q_1',
  number: 1001,
  rates: Rates.forTrade(Trade.painting),
  now: now,
  customer: const Customer(name: 'Dana Ortiz'),
  photoKeys: const ['q_1_0'],
);

void main() {
  group('settings', () {
    test('fresh settings get an install id and are saved', () async {
      final store = MemoryBlobStore();
      final s = await SettingsRepository(store).load();
      expect(s.installId, startsWith('inst_'));
      expect(s.setupDone, isFalse);
      expect(s.nextNumber, 1001);
      final again = await SettingsRepository(store).load();
      expect(again.installId, s.installId);
    });

    test('round trip', () async {
      final store = MemoryBlobStore();
      final repo = SettingsRepository(store);
      final s = AppSettings(
        installId: 'inst_abc',
        profile: const BusinessProfile(
          name: 'Brightline Painting',
          trades: [Trade.painting],
          paymentLink: 'https://buy.stripe.com/x',
        ),
        rates: Rates.forTrade(Trade.painting).copyWith(taxRatePct: 8.25),
        nextNumber: 1042,
        setupDone: true,
      );
      await repo.save(s);
      final back = await repo.load();
      expect(back.toJson(), s.toJson());
    });

    test('unreadable settings start fresh', () async {
      final store = MemoryBlobStore();
      await store.writeText('settings.json', '{not json');
      final s = await SettingsRepository(store).load();
      expect(s.setupDone, isFalse);
    });
  });

  group('quotes', () {
    test('round trip keeps every field, newest first', () async {
      final repo = QuoteRepository(MemoryBlobStore());
      final older = sampleQuote();
      final newer = QuoteBuilder.fromDraft(
        SampleJob.fence.draft,
        id: 'q_2',
        number: 1002,
        rates: Rates.forTrade(Trade.fencing),
        now: now.add(const Duration(hours: 1)),
      );
      await repo.save([older, newer]);
      final back = await repo.load();
      expect(back.map((q) => q.id), ['q_2', 'q_1']);
      expect(back.last.toJson(), older.toJson());
    });

    test('photos are stored and deleted by key', () async {
      final repo = QuoteRepository(MemoryBlobStore());
      await repo.savePhoto('k', Uint8List.fromList([1, 2, 3]));
      expect(await repo.loadPhoto('k'), [1, 2, 3]);
      await repo.deletePhotos(['k']);
      expect(await repo.loadPhoto('k'), isNull);
    });
  });

  group('demo client', () {
    test('drafts the sample for the trade', () async {
      final client = DemoJobwalkClient(
        store: MemoryBlobStore(),
        draftDelay: Duration.zero,
      );
      final r = await client.draft(
        DraftRequest(
          profile: const BusinessProfile(
            name: 'Oak & Iron',
            trades: [Trade.fencing],
          ),
          rates: const Rates(),
          photos: const [],
        ),
      );
      expect(r.demo, isTrue);
      expect(r.draft.title, SampleJob.fence.draft.title);
    });

    test('the whole loop: publish, view, approve', () async {
      final store = MemoryBlobStore();
      final client = DemoJobwalkClient(
        store: store,
        draftDelay: Duration.zero,
        clock: () => now,
      );
      final quote = sampleQuote();
      final public = PublicQuote.fromQuote(
        quote,
        const BusinessProfile(name: 'Brightline Painting'),
        issuedAt: now,
      );
      final share = await client.publish(public);
      expect(share.url, 'https://jobwalk.app/q/${share.id}');

      await client.recordView(share.id);
      var r = await client.status(share.id, share.ownerToken);
      expect(r.views, 1);

      await client.approve(share.id, optionId: 'full_room', name: 'Dana');
      // State survives a new client, like an app restart.
      final restarted = DemoJobwalkClient(store: store);
      r = await restarted.status(share.id, share.ownerToken);
      expect(r.approvedTierId, 'full_room');
      expect(r.signature, 'Dana');

      final sent = quote.copyWith(status: QuoteStatus.sent).applyResponse(r);
      expect(sent.status, QuoteStatus.approved);
      expect(sent.headlineTotalCents, 141000);

      expect(
        () => restarted.update(share.id, share.ownerToken, public),
        throwsA(isA<ApiError>()),
      );
    });
  });

  test('file writes to one key land in order', () async {
    final dir = await Directory.systemTemp.createTemp('jobwalk_store');
    addTearDown(() => dir.delete(recursive: true));
    final store = FileBlobStore(dir);
    // Sync and an edit saving the quote list at the same moment.
    await Future.wait([
      for (var i = 0; i < 20; i++) store.writeText('quotes.json', 'v$i'),
      store.writeBytes('photo_a', Uint8List.fromList([1, 2, 3])),
    ]);
    expect(await store.readText('quotes.json'), 'v19');
    expect(await store.readBytes('photo_a'), [1, 2, 3]);
    await Future.wait([store.writeText('k', 'x'), store.delete('k')]);
    expect(await store.readText('k'), isNull);
    expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);
  });
}
