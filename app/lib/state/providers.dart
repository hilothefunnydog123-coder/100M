import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:jobwalk_core/jobwalk_core.dart';

import '../config.dart';
import '../data/blob_store.dart';
import '../data/repositories.dart';
import '../data/settings.dart';
import '../data/sync_state.dart';
import '../services/api.dart';
import '../services/photos.dart';
import 'session.dart';
import 'sync.dart';

final configProvider = Provider<AppConfig>(
  (ref) => AppConfig.fromEnvironment(),
);

/// Overridden in `main()` once storage is open.
final blobStoreProvider = Provider<BlobStore>(
  (ref) => throw UnimplementedError('blobStoreProvider must be overridden'),
);

/// Loaded before the first frame and overridden in `main()`.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) => throw UnimplementedError('initialSettingsProvider'),
);
final initialQuotesProvider = Provider<List<Quote>>(
  (ref) => throw UnimplementedError('initialQuotesProvider'),
);

final clockProvider = Provider<DateTime Function()>(
  (ref) =>
      () => DateTime.now().toUtc(),
);

final settingsRepositoryProvider = Provider(
  (ref) => SettingsRepository(ref.watch(blobStoreProvider)),
);
final quoteRepositoryProvider = Provider(
  (ref) => QuoteRepository(ref.watch(blobStoreProvider)),
);
final syncStateRepositoryProvider = Provider(
  (ref) => SyncStateRepository(ref.watch(blobStoreProvider)),
);

/// Shared HTTP client; replaced in tests.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  Future<void> _update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await ref.read(settingsRepositoryProvider).save(state);
  }

  Future<void> completeSetup(BusinessProfile profile, Rates rates) async {
    await _update(
      (s) => s.copyWith(profile: profile, rates: rates, setupDone: true),
    );
    ref.read(syncProvider.notifier).businessChanged();
  }

  Future<void> setProfile(BusinessProfile profile) async {
    await _update((s) => s.copyWith(profile: profile));
    ref.read(syncProvider.notifier).businessChanged();
  }

  Future<void> setRates(Rates rates) async {
    await _update((s) => s.copyWith(rates: rates));
    ref.read(syncProvider.notifier).businessChanged();
  }

  /// The business as the server has it (edited on another phone, or by
  /// the owner). Not sent back.
  Future<void> applyServer(BusinessProfile profile, Rates rates) => _update(
    (s) => s.copyWith(profile: profile, rates: rates, setupDone: true),
  );

  /// Hands out the next quote number.
  Future<int> takeNumber() async {
    final sync = ref.read(syncProvider.notifier);
    final n = sync.enabled
        ? await sync.takeNumber(state.nextNumber)
        : state.nextNumber;
    await _update((s) => s.copyWith(nextNumber: max(s.nextNumber, n + 1)));
    return n;
  }

  /// Remembers prices the contractor typed over AI lines.
  Future<void> learnFrom(Quote sent) async {
    final learned = PriceMemory.learn(
      state.rates,
      sent,
      now: ref.read(clockProvider)(),
    );
    if (jsonEncode(learned.toJson()) == jsonEncode(state.rates.toJson())) {
      return;
    }
    await setRates(learned);
  }

  /// Keeps the install id so rate limits can't be reset by erasing data.
  Future<void> reset() async {
    state = AppSettings(installId: state.installId);
    await ref.read(settingsRepositoryProvider).save(state);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

class QuotesNotifier extends Notifier<List<Quote>> {
  @override
  List<Quote> build() => ref.watch(initialQuotesProvider);

  QuoteRepository get _repo => ref.read(quoteRepositoryProvider);

  Quote? byId(String id) {
    for (final q in state) {
      if (q.id == id) return q;
    }
    return null;
  }

  Future<void> add(Quote quote, {List<Uint8List> photos = const []}) async {
    for (final (i, key) in quote.photoKeys.indexed) {
      if (i < photos.length) await _repo.savePhoto(key, photos[i]);
    }
    state = _sorted([quote, ...state]);
    await _repo.save(state);
    ref.read(syncProvider.notifier).quoteChanged(quote.id);
  }

  /// Stores an edited quote. Edits bump `updatedAt` so a sent link knows it
  /// is out of date.
  Future<Quote> save(Quote quote, {bool touch = true}) async {
    final saved = touch
        ? quote.copyWith(updatedAt: ref.read(clockProvider)())
        : quote;
    state = [for (final q in state) q.id == saved.id ? saved : q];
    await _repo.save(state);
    ref.read(syncProvider.notifier).quoteChanged(saved.id);
    return saved;
  }

  Future<void> delete(String id) async {
    if (!await _remove(id)) return;
    ref.read(syncProvider.notifier).quoteDeleted(id);
  }

  /// A quote as the server has it. Not sent back.
  Future<void> applyRemote(Quote quote) async {
    final exists = state.any((q) => q.id == quote.id);
    state = exists
        ? [for (final q in state) q.id == quote.id ? quote : q]
        : _sorted([quote, ...state]);
    await _repo.save(state);
  }

  /// Deleted on another phone.
  Future<void> removeRemote(String id) => _remove(id);

  Future<bool> _remove(String id) async {
    final quote = byId(id);
    if (quote == null) return false;
    state = [
      for (final q in state)
        if (q.id != id) q,
    ];
    await _repo.save(state);
    // Duplicates share photos; only delete ones nothing else uses.
    final inUse = {for (final q in state) ...q.photoKeys};
    await _repo.deletePhotos(quote.photoKeys.where((k) => !inUse.contains(k)));
    return true;
  }

  /// Removes every quote and photo from this phone (signing out).
  Future<void> clearLocal() async {
    await _repo.deletePhotos({for (final q in state) ...q.photoKeys});
    state = const [];
    await _repo.save(state);
  }

  static List<Quote> _sorted(List<Quote> quotes) =>
      quotes..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Brings statuses up to date: a sync when signed in, else the demo
  /// links on this phone.
  Future<void> refresh() async {
    if (ref.read(syncProvider.notifier).enabled) {
      await ref.read(syncProvider.notifier).sync();
    } else {
      await refreshStatuses();
    }
  }

  /// Pulls what customers did with sent quotes. Quiet on failure: this runs
  /// in the background and the next refresh will catch up.
  Future<int> refreshStatuses() async {
    final client = ref.read(clientProvider);
    if (client is! DemoJobwalkClient) return 0;
    var changed = 0;
    for (final q in [...state]) {
      final share = q.share;
      if (share == null || q.status == QuoteStatus.draft) continue;
      try {
        final response = await client.status(share.publicId, share.ownerToken);
        final current = byId(q.id);
        if (current == null) continue;
        final updated = current.applyResponse(response);
        if (updated.status != current.status ||
            updated.response.views != current.response.views ||
            updated.response.approvedAt != current.response.approvedAt ||
            updated.response.declinedAt != current.response.declinedAt) {
          await save(updated, touch: false);
          changed++;
        }
      } on ApiError {
        continue;
      }
    }
    return changed;
  }

  Future<void> clearAll() async {
    await ref.read(blobStoreProvider).deleteAll();
    state = const [];
  }
}

final quotesProvider = NotifierProvider<QuotesNotifier, List<Quote>>(
  QuotesNotifier.new,
);

final quoteProvider = Provider.family<Quote?, String>((ref, id) {
  for (final q in ref.watch(quotesProvider)) {
    if (q.id == id) return q;
  }
  return null;
});

/// A job photo from this phone, or from the server when another phone
/// took it (then kept here).
final storedPhotoProvider = FutureProvider.family<Uint8List?, String>((
  ref,
  key,
) async {
  final repo = ref.watch(quoteRepositoryProvider);
  final local = await repo.loadPhoto(key);
  if (local != null) return local;
  final server = ref.read(serverProvider);
  if (server == null || !ref.read(sessionProvider).signedIn) return null;
  final remote = await server.getPhoto(key);
  if (remote != null) await repo.savePhoto(key, remote);
  return remote;
});

final clientProvider = Provider<JobwalkClient>((ref) {
  final server = ref.watch(serverProvider);
  if (server != null) return server;
  return DemoJobwalkClient(store: ref.watch(blobStoreProvider));
});

final photoSourceProvider = Provider<PhotoSource>(
  (ref) => ImagePickerPhotoSource(),
);

final photoProcessorProvider = Provider<PhotoProcessor>((ref) => processPhoto);

/// The numbers on the home screen.
class PipelineStats {
  const PipelineStats({
    required this.openCount,
    required this.openCents,
    required this.wonCount,
    required this.wonCents,
    required this.sentCount,
    required this.winRate,
  });

  /// Sent and waiting on the customer.
  final int openCount;
  final int openCents;

  /// Approved this calendar month.
  final int wonCount;
  final int wonCents;
  final int sentCount;

  /// Approved over decided, once there's enough to say anything.
  final double? winRate;
}

final statsProvider = Provider<PipelineStats>((ref) {
  final quotes = ref.watch(quotesProvider);
  final now = ref.watch(clockProvider)().toLocal();
  var openCount = 0, openCents = 0, wonCount = 0, wonCents = 0;
  var sent = 0, approved = 0, declined = 0;
  for (final q in quotes) {
    if (q.status != QuoteStatus.draft) sent++;
    if (q.status.isOpen) {
      openCount++;
      openCents += q.headlineTotalCents;
    }
    if (q.status == QuoteStatus.approved) {
      approved++;
      final at = (q.closedAt ?? q.updatedAt).toLocal();
      if (at.year == now.year && at.month == now.month) {
        wonCount++;
        wonCents += q.headlineTotalCents;
      }
    }
    if (q.status == QuoteStatus.declined) declined++;
  }
  final decided = approved + declined;
  return PipelineStats(
    openCount: openCount,
    openCents: openCents,
    wonCount: wonCount,
    wonCents: wonCents,
    sentCount: sent,
    winRate: decided >= 3 ? approved / decided : null,
  );
});
