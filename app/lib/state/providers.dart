import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import '../config.dart';
import '../data/blob_store.dart';
import '../data/repositories.dart';
import '../data/settings.dart';
import '../services/api.dart';
import '../services/photos.dart';

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

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  Future<void> _update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await ref.read(settingsRepositoryProvider).save(state);
  }

  Future<void> completeSetup(BusinessProfile profile, Rates rates) => _update(
    (s) => s.copyWith(profile: profile, rates: rates, setupDone: true),
  );

  Future<void> setProfile(BusinessProfile profile) =>
      _update((s) => s.copyWith(profile: profile));

  Future<void> setRates(Rates rates) =>
      _update((s) => s.copyWith(rates: rates));

  /// Hands out the next quote number.
  Future<int> takeNumber() async {
    final n = state.nextNumber;
    await _update((s) => s.copyWith(nextNumber: n + 1));
    return n;
  }

  /// Remembers prices the contractor typed over AI lines.
  Future<void> learnFrom(Quote sent) => _update(
    (s) => s.copyWith(
      rates: PriceMemory.learn(s.rates, sent, now: ref.read(clockProvider)()),
    ),
  );

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
    state = [quote, ...state];
    await _repo.save(state);
  }

  /// Stores an edited quote. Edits bump `updatedAt` so a sent link knows it
  /// is out of date.
  Future<Quote> save(Quote quote, {bool touch = true}) async {
    final saved = touch
        ? quote.copyWith(updatedAt: ref.read(clockProvider)())
        : quote;
    state = [for (final q in state) q.id == saved.id ? saved : q];
    await _repo.save(state);
    return saved;
  }

  Future<void> delete(String id) async {
    final quote = byId(id);
    if (quote == null) return;
    state = [
      for (final q in state)
        if (q.id != id) q,
    ];
    await _repo.save(state);
    // Duplicates share photos; only delete ones nothing else uses.
    final inUse = {for (final q in state) ...q.photoKeys};
    await _repo.deletePhotos(quote.photoKeys.where((k) => !inUse.contains(k)));
  }

  /// Pulls what customers did with sent quotes. Quiet on failure: this runs
  /// in the background and the next refresh will catch up.
  Future<int> refreshStatuses() async {
    final client = ref.read(clientProvider);
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

final storedPhotoProvider = FutureProvider.family<Uint8List?, String>(
  (ref, key) => ref.watch(quoteRepositoryProvider).loadPhoto(key),
);

final clientProvider = Provider<JobwalkClient>((ref) {
  final config = ref.watch(configProvider);
  if (config.demoMode) {
    return DemoJobwalkClient(store: ref.watch(blobStoreProvider));
  }
  return HttpJobwalkClient(
    baseUrl: config.apiBaseUrl!,
    installId: ref.watch(settingsProvider.select((s) => s.installId)),
  );
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
