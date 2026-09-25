import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jobwalk/config.dart';
import 'package:jobwalk/data/blob_store.dart';
import 'package:jobwalk/data/session.dart';
import 'package:jobwalk/data/settings.dart';
import 'package:jobwalk/data/sync_state.dart';
import 'package:jobwalk/state/providers.dart';
import 'package:jobwalk/state/quote_actions.dart';
import 'package:jobwalk/state/session.dart';
import 'package:jobwalk/state/sync.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import 'fake_backend.dart';
import 'helpers.dart';

/// The app's state, signed in (or not) to [backend].
class Phone {
  Phone(
    this.backend, {
    bool signedIn = true,
    List<Quote> quotes = const [],
    AppSettings? settings,
    SyncState? sync,
  }) {
    tokens.token = signedIn ? FakeBackend.token : null;
    container = ProviderContainer(
      overrides: [
        configProvider.overrideWithValue(
          AppConfig(
            apiBaseUrl: Uri.parse('https://api.jobwalk.test'),
            demoMode: false,
          ),
        ),
        blobStoreProvider.overrideWithValue(store),
        initialSettingsProvider.overrideWithValue(settings ?? testSettings()),
        initialQuotesProvider.overrideWithValue(quotes),
        tokenStoreProvider.overrideWithValue(tokens),
        initialTokenProvider.overrideWithValue(tokens.token),
        initialSyncStateProvider.overrideWithValue(
          sync ??
              (signedIn
                  ? const SyncState(businessId: 'b_1')
                  : const SyncState()),
        ),
        httpClientProvider.overrideWithValue(backend.client),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
  }

  final FakeBackend backend;
  final store = MemoryBlobStore();
  final tokens = MemoryTokenStore();
  late final ProviderContainer container;
  DateTime now = testNow;

  SyncController get sync => container.read(syncProvider.notifier);
  QuotesNotifier get quotes => container.read(quotesProvider.notifier);
  List<Quote> get all => container.read(quotesProvider);
  Quote? quote(String id) => quotes.byId(id);
  SyncStatus get status => container.read(syncProvider);
  Session get session => container.read(sessionProvider);
}

Quote sample(String id, {int number = 1042, DateTime? at}) =>
    QuoteBuilder.fromDraft(
      SampleJob.livingRoom.draft,
      id: id,
      number: number,
      rates: Rates.forTrade(Trade.painting),
      now: at ?? testNow,
      customer: const Customer(name: 'Dana Ortiz'),
    );

void main() {
  late FakeBackend backend;
  setUp(() => backend = FakeBackend());

  test('signing in sets up the business and uploads existing quotes', () async {
    final phone = Phone(
      backend,
      signedIn: false,
      quotes: [sample('q_before_1')],
    );
    final session = phone.container.read(sessionProvider.notifier);
    await session.requestCode(' dana@example.com ');
    expect(backend.codeSentTo, 'dana@example.com');
    await session.signIn('dana@example.com', FakeBackend.code);
    await phone.sync.sync();

    expect(phone.session.signedIn, isTrue);
    expect(phone.tokens.token, FakeBackend.token);
    // This phone's setup became the business's.
    expect(backend.profile['name'], 'Brightline Painting');
    expect(backend.quotes.keys, ['q_before_1']);
    expect(phone.sync.data.versions['q_before_1'], 1);
    expect(phone.status.pending, 0);
    expect(phone.status.phase, SyncPhase.idle);
  });

  test('a new phone takes the business from the server', () async {
    backend.profile = {
      'name': 'Oak & Iron Fence Co.',
      'trades': ['fencing'],
    };
    backend.quotes.clear();
    final other = Phone(backend);
    await other.quotes.add(sample('q_other'));
    await other.sync.sync();

    final phone = Phone(
      backend,
      signedIn: false,
      settings: testSettings(setupDone: false),
    );
    await phone.container
        .read(sessionProvider.notifier)
        .signIn('dana@example.com', FakeBackend.code);
    await phone.sync.sync();
    final settings = phone.container.read(settingsProvider);
    expect(settings.setupDone, isTrue);
    expect(settings.profile.name, 'Oak & Iron Fence Co.');
    expect(phone.all.map((q) => q.id), ['q_other']);
  });

  test('edits go up with their base version; changes come down', () async {
    final phone = Phone(backend);
    await phone.quotes.add(sample('q_1'));
    await phone.sync.sync();
    expect(backend.quotes['q_1']!.version, 1);

    final q = phone.quote('q_1')!;
    await phone.quotes.save(q.copyWith(title: 'Walls and trim'));
    expect(phone.status.pending, 1);
    await phone.sync.sync();
    expect(backend.quote('q_1')!.title, 'Walls and trim');
    expect(
      backend.bodies['PUT /v1/quotes/q_1'],
      containsPair('base_version', 1),
    );

    backend.editElsewhere('q_1', (q) => q.copyWith(message: 'See you Monday'));
    await phone.sync.sync();
    expect(phone.quote('q_1')!.message, 'See you Monday');
    expect(phone.sync.data.versions['q_1'], 3);
  });

  test('when two phones edit a quote, the later edit wins', () async {
    final phone = Phone(backend);
    await phone.quotes.add(sample('q_1'));
    await phone.sync.sync();

    // Edited elsewhere first, then here: this phone's edit is newer.
    backend.editElsewhere(
      'q_1',
      (q) => q.copyWith(
        title: 'From the tablet',
        updatedAt: testNow.add(const Duration(minutes: 1)),
      ),
    );
    phone.now = testNow.add(const Duration(minutes: 2));
    await phone.quotes.save(phone.quote('q_1')!.copyWith(title: 'From here'));
    await phone.sync.sync();
    expect(backend.quote('q_1')!.title, 'From here');

    // Edited here, then later elsewhere: the other edit wins.
    phone.now = testNow.add(const Duration(minutes: 3));
    await phone.quotes.save(phone.quote('q_1')!.copyWith(title: 'Older'));
    backend.editElsewhere(
      'q_1',
      (q) => q.copyWith(
        title: 'Newer elsewhere',
        updatedAt: testNow.add(const Duration(minutes: 9)),
      ),
    );
    await phone.sync.sync();
    expect(phone.quote('q_1')!.title, 'Newer elsewhere');
    expect(backend.quote('q_1')!.title, 'Newer elsewhere');
    expect(phone.status.pending, 0);
  });

  test('a quote saved elsewhere mid-sync is retried, not an error', () async {
    final phone = Phone(backend);
    await phone.quotes.add(sample('q_1'));
    await phone.sync.sync();
    backend.editElsewhere(
      'q_1',
      (q) => q.copyWith(updatedAt: testNow.add(const Duration(minutes: 1))),
    );
    // The retry after the first conflict meets a second one.
    backend.afterConflict = () => backend.editElsewhere(
      'q_1',
      (q) => q.copyWith(updatedAt: testNow.add(const Duration(minutes: 2))),
    );
    phone.now = testNow.add(const Duration(minutes: 5));
    await phone.quotes.save(phone.quote('q_1')!.copyWith(title: 'Mine'));
    await phone.sync.sync();
    expect(phone.status.phase, SyncPhase.idle);
    expect(phone.status.pending, 1, reason: 'still to send');
    await phone.sync.sync();
    expect(backend.quote('q_1')!.title, 'Mine');
    expect(phone.status.pending, 0);
  });

  test('deletes travel both ways', () async {
    final phone = Phone(backend);
    await phone.quotes.add(sample('q_1'));
    await phone.quotes.add(sample('q_2', number: 1043));
    await phone.sync.sync();

    await phone.quotes.delete('q_1');
    await phone.sync.sync();
    expect(backend.quotes['q_1']!.deleted, isTrue);

    backend.deleteElsewhere('q_2');
    await phone.sync.sync();
    expect(phone.all, isEmpty);

    // A quote deleted elsewhere while edited here stays deleted.
    await phone.quotes.add(sample('q_3', number: 1044));
    await phone.sync.sync();
    backend.deleteElsewhere('q_3');
    await phone.quotes.save(phone.quote('q_3')!.copyWith(title: 'x'));
    await phone.sync.sync();
    expect(phone.quote('q_3'), isNull);
  });

  test('sending publishes the latest version; approvals come back', () async {
    final phone = Phone(backend);
    await phone.quotes.add(sample('q_1'));
    final sent = await phone.container
        .read(quoteActionsProvider)
        .publish(phone.quote('q_1')!);
    expect(sent.status, QuoteStatus.sent);
    expect(sent.share!.url, startsWith('https://jobwalk.test/q/'));
    expect(
      backend.calls,
      containsAllInOrder(['PUT /v1/quotes/q_1', 'POST /v1/quotes/q_1/publish']),
    );
    expect(phone.status.pending, 0);

    backend.customerApproves('q_1', option: 'walls_trim');
    backend.depositPaid('q_1', 31100);
    await phone.quotes.refresh();
    final won = phone.quote('q_1')!;
    expect(won.status, QuoteStatus.approved);
    expect(won.chosenTierId, 'walls_trim');
    expect(won.response.signature, 'Dana');
    expect(phone.container.read(depositPaidProvider('q_1')), 31100);
  });

  test('photos upload once, and phones without them fetch them', () async {
    final phone = Phone(backend);
    final q = sample('q_1').copyWith(photoKeys: ['q_1_0']);
    await phone.quotes.add(q, photos: [Uint8List.fromList(tinyJpeg)]);
    await phone.sync.sync();
    await phone.sync.sync();
    expect(backend.photos.keys, ['q_1_0']);
    expect(
      backend.calls.where((c) => c == 'PUT /v1/photos/q_1_0'),
      hasLength(1),
    );

    final tablet = Phone(backend);
    await tablet.sync.sync();
    final photo = await tablet.container.read(
      storedPhotoProvider('q_1_0').future,
    );
    expect(photo, tinyJpeg);
  });

  test('offline changes wait, then sync', () async {
    final phone = Phone(backend);
    backend.offline = true;
    await phone.quotes.add(sample('q_1'));
    await phone.sync.sync();
    expect(phone.status.phase, SyncPhase.offline);
    expect(phone.status.pending, 1);

    backend.offline = false;
    await phone.sync.sync();
    expect(phone.status.phase, SyncPhase.idle);
    expect(backend.quotes.keys, ['q_1']);
  });

  test('quote numbers come from a block reserved on the server', () async {
    backend.nextNumber = 2001;
    final phone = Phone(backend);
    final settings = phone.container.read(settingsProvider.notifier);
    expect(await settings.takeNumber(), 2001);
    expect(await settings.takeNumber(), 2002);
    expect(
      backend.calls.where((c) => c == 'POST /v1/business/numbers'),
      hasLength(1),
    );
    backend.offline = true;
    final other = Phone(backend);
    expect(
      await other.container.read(settingsProvider.notifier).takeNumber(),
      1001,
      reason: 'offline falls back to the local counter',
    );
  });

  test('an expired session asks to sign in but keeps the data', () async {
    final phone = Phone(backend);
    await phone.quotes.add(sample('q_1'));
    backend.signedOut = true;
    await phone.sync.sync();
    await Future<void>.delayed(Duration.zero);
    expect(phone.session.signedIn, isFalse);
    expect(phone.tokens.token, isNull);
    expect(phone.all, hasLength(1));
  });

  test('signing out removes the business from the phone', () async {
    final phone = Phone(backend);
    await phone.quotes.add(sample('q_1'));
    await phone.sync.sync();
    await phone.container.read(sessionProvider.notifier).signOut();
    expect(phone.session.signedIn, isFalse);
    expect(phone.all, isEmpty);
    expect(phone.container.read(settingsProvider).setupDone, isFalse);
    expect(backend.signedOut, isTrue);
  });

  test("another business's quotes are cleared on sign-in", () async {
    final phone = Phone(
      backend,
      signedIn: false,
      quotes: [sample('q_theirs')],
      sync: const SyncState(businessId: 'b_other'),
    );
    await phone.container
        .read(sessionProvider.notifier)
        .signIn('dana@example.com', FakeBackend.code);
    await phone.sync.sync();
    expect(phone.all.map((q) => q.id), isNot(contains('q_theirs')));
    expect(backend.quotes.keys, isNot(contains('q_theirs')));
  });
}
