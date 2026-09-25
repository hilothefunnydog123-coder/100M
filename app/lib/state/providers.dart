import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

import '../config.dart';
import '../data/blob_store.dart';
import '../data/models.dart';
import '../data/repositories.dart';
import '../services/analysis_service.dart';
import '../services/photos.dart';
import '../services/purchases.dart';

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
final initialHistoryProvider = Provider<List<CheckRecord>>(
  (ref) => throw UnimplementedError('initialHistoryProvider'),
);

final settingsRepositoryProvider = Provider(
  (ref) => SettingsRepository(ref.watch(blobStoreProvider)),
);
final historyRepositoryProvider = Provider(
  (ref) => HistoryRepository(ref.watch(blobStoreProvider)),
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  Future<void> _update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await ref.read(settingsRepositoryProvider).save(state);
  }

  Future<void> completeOnboarding() =>
      _update((s) => s.copyWith(onboarded: true));

  Future<void> setProfile(IntakeAnswers answers) =>
      _update((s) => s.copyWith(profile: answers));

  Future<void> recordCheckUsed() =>
      _update((s) => s.copyWith(checksUsed: s.checksUsed + 1));

  Future<void> setPro(bool pro) => _update((s) => s.copyWith(pro: pro));

  Future<void> setEmergencyNumber(String number) =>
      _update((s) => s.copyWith(emergencyNumber: number));

  /// Keeps the install id so rate limits can't be reset by clearing data.
  Future<void> reset() async {
    state = AppSettings(installId: state.installId);
    await ref.read(settingsRepositoryProvider).save(state);
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

/// Free checks left, or null for Pro members.
final checksRemainingProvider = Provider<int?>((ref) {
  final settings = ref.watch(settingsProvider);
  if (settings.pro) return null;
  final free = ref.watch(configProvider).freeChecks;
  return math.max(0, free - settings.checksUsed);
});

class HistoryNotifier extends Notifier<List<CheckRecord>> {
  @override
  List<CheckRecord> build() => ref.watch(initialHistoryProvider);

  HistoryRepository get _repo => ref.read(historyRepositoryProvider);

  CheckRecord? byId(String id) {
    for (final r in state) {
      if (r.id == id) return r;
    }
    return null;
  }

  Future<void> add(CheckRecord record, List<Uint8List> photos) async {
    for (final (i, key) in record.photoKeys.indexed) {
      if (i < photos.length) await _repo.savePhoto(key, photos[i]);
    }
    state = [record, ...state];
    await _repo.save(state);
  }

  Future<void> replace(CheckRecord record) async {
    state = [for (final r in state) r.id == record.id ? record : r];
    await _repo.save(state);
  }

  Future<void> delete(String id) async {
    final record = byId(id);
    if (record == null) return;
    state = [
      for (final r in state)
        if (r.id != id) r,
    ];
    await _repo.save(state);
    await _repo.deletePhotos(record.photoKeys);
  }

  Future<void> clearAll() async {
    await ref.read(blobStoreProvider).deleteAll();
    state = const [];
  }
}

final historyProvider = NotifierProvider<HistoryNotifier, List<CheckRecord>>(
  HistoryNotifier.new,
);

/// Checks whose recheck reminder is due.
final dueRechecksProvider = Provider<List<CheckRecord>>((ref) {
  final now = DateTime.now();
  return [
    for (final r in ref.watch(historyProvider))
      if (r.recheckDue != null && !r.recheckDue!.isAfter(now)) r,
  ];
});

final storedPhotoProvider = FutureProvider.family<Uint8List?, String>(
  (ref, key) => ref.watch(historyRepositoryProvider).loadPhoto(key),
);

final analysisServiceProvider = Provider<AnalysisService>((ref) {
  final config = ref.watch(configProvider);
  if (config.demoMode) return DemoAnalysisService();
  return HttpAnalysisService(
    baseUrl: config.apiBaseUrl!,
    installId: ref.watch(settingsProvider.select((s) => s.installId)),
  );
});

final photoSourceProvider = Provider<PhotoSource>(
  (ref) => ImagePickerPhotoSource(),
);

final purchasesProvider = Provider<PurchasesService>(
  (ref) => SimulatedPurchasesService(
    onUnlock: () => ref.read(settingsProvider.notifier).setPro(true),
  ),
);
