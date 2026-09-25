import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import '../data/repositories.dart';
import '../data/sync_state.dart';
import '../services/api.dart';
import '../services/models.dart';
import '../services/server.dart';
import 'providers.dart';
import 'session.dart';

enum SyncPhase { idle, syncing, offline, failed }

class SyncStatus {
  const SyncStatus({
    this.phase = SyncPhase.idle,
    this.lastSynced,
    this.pending = 0,
    this.error,
  });

  final SyncPhase phase;
  final DateTime? lastSynced;

  /// Local changes the server hasn't seen yet.
  final int pending;
  final String? error;

  SyncStatus copyWith({SyncPhase? phase, int? pending}) => SyncStatus(
    phase: phase ?? this.phase,
    lastSynced: lastSynced,
    pending: pending ?? this.pending,
    error: error,
  );
}

/// Runs tasks one at a time, in order.
class _Serial {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

/// Keeps this phone's quotes and the server's in step.
///
/// The phone works offline: every save lands locally first and is marked
/// for sending. A sync sends deletes, then changed quotes (each with the
/// server version it was based on), then photos, then pulls everything
/// that changed elsewhere, customer activity included. When two phones
/// edited the same quote, the later edit wins; a delete beats an edit.
class SyncController extends Notifier<SyncStatus> {
  late SyncState _data;
  final _serial = _Serial();
  Future<void>? _queued;
  Timer? _debounce;

  @override
  SyncStatus build() {
    _data = ref.watch(initialSyncStateProvider);
    ref.onDispose(() => _debounce?.cancel());
    return SyncStatus(pending: _data.pending);
  }

  SyncState get data => _data;

  ServerClient? get _server => ref.read(serverProvider);

  /// Signed in to a server (not demo mode).
  bool get enabled => _server != null && ref.read(sessionProvider).signedIn;

  QuotesNotifier get _quotes => ref.read(quotesProvider.notifier);
  QuoteRepository get _repo => ref.read(quoteRepositoryProvider);

  Future<void> _update(SyncState next) async {
    _data = next;
    state = state.copyWith(pending: next.pending);
    await ref.read(syncStateRepositoryProvider).save(next);
  }

  // ---------------------------------------------------------------------------
  // Local changes
  // ---------------------------------------------------------------------------

  void quoteChanged(String id) {
    if (!enabled) return;
    unawaited(_update(_data.copyWith(dirty: {..._data.dirty, id})));
    _schedule();
  }

  void quoteDeleted(String id) {
    if (!enabled) return;
    final onServer = _data.versions.containsKey(id);
    unawaited(
      _update(
        _data.copyWith(
          dirty: {..._data.dirty}..remove(id),
          deleted: onServer ? {..._data.deleted, id} : _data.deleted,
        ),
      ),
    );
    if (onServer) _schedule();
  }

  /// The profile or rates changed here.
  void businessChanged() {
    if (!enabled || !ref.read(sessionProvider).isOwner) return;
    unawaited(_update(_data.copyWith(businessDirty: true)));
    _schedule();
  }

  /// Sends changes shortly after the last edit, not on every keystroke.
  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), () => unawaited(sync()));
  }

  // ---------------------------------------------------------------------------
  // Syncing
  // ---------------------------------------------------------------------------

  /// Sends local changes and fetches everyone else's. Never throws: the
  /// status says how it went. Calls during a sync queue one more pass.
  Future<void> sync() {
    if (!enabled) return Future.value();
    return _queued ??= _serial.run(() async {
      _queued = null;
      if (!enabled) return;
      state = state.copyWith(phase: SyncPhase.syncing);
      try {
        await _pass(_server!);
        state = SyncStatus(
          lastSynced: ref.read(clockProvider)(),
          pending: _data.pending,
        );
      } on ApiError catch (e) {
        state = SyncStatus(
          phase: e.offline ? SyncPhase.offline : SyncPhase.failed,
          lastSynced: state.lastSynced,
          pending: _data.pending,
          error: e.message,
        );
      }
    });
  }

  Future<void> _pass(ServerClient server) async {
    if (_data.businessDirty) await _pushBusiness(server);
    for (final id in [..._data.deleted]) {
      try {
        await server.deleteQuote(id);
      } on ApiError catch (e) {
        if (e.status != 404) rethrow;
      }
      await _update(
        _data.copyWith(
          deleted: {..._data.deleted}..remove(id),
          versions: {..._data.versions}..remove(id),
        ),
      );
    }
    for (final id in [..._data.dirty]) {
      final local = _quotes.byId(id);
      if (local == null) {
        await _update(_data.copyWith(dirty: {..._data.dirty}..remove(id)));
        continue;
      }
      await _push(server, local);
    }
    await _uploadPhotos(server);
    await _pull(server);
  }

  Future<void> _pushBusiness(ServerClient server) async {
    final settings = ref.read(settingsProvider);
    try {
      final account = await server.updateBusiness(
        profile: settings.profile.name.isEmpty ? null : settings.profile,
        rates: settings.rates,
      );
      await _update(_data.copyWith(businessDirty: false, account: account));
      await ref.read(sessionProvider.notifier).setAccount(account);
    } on ApiError catch (e) {
      // Members can't change the business; drop the local change.
      if (e.status != 403 && e.status != 400) rethrow;
      await _update(_data.copyWith(businessDirty: false));
    }
  }

  Future<void> _push(ServerClient server, Quote local) async {
    final id = local.id;
    SyncedQuote synced;
    try {
      synced = await server.putQuote(
        local,
        baseVersion: _data.versions[id] ?? 0,
      );
    } on QuoteConflict catch (conflict) {
      final current = conflict.current;
      final theirs = current.quote;
      if (current.deleted || theirs == null) {
        await _quotes.removeRemote(id);
        await _forgetQuote(id);
        return;
      }
      if (!local.updatedAt.isAfter(theirs.updatedAt)) {
        await _quotes.applyRemote(theirs);
        await _update(
          _data.copyWith(
            dirty: {..._data.dirty}..remove(id),
            versions: {..._data.versions, id: current.version},
          ),
        );
        return;
      }
      synced = await server.putQuote(local, baseVersion: current.version);
    }
    final versions = {..._data.versions, id: synced.version};
    if (identical(_quotes.byId(id), local)) {
      final server = synced.quote;
      if (server != null) await _quotes.applyRemote(server);
      await _update(
        _data.copyWith(dirty: {..._data.dirty}..remove(id), versions: versions),
      );
    } else {
      // Edited again while this was in flight: send that next time.
      await _update(_data.copyWith(versions: versions));
    }
  }

  Future<void> _uploadPhotos(ServerClient server) async {
    for (final q in [..._quotes.state]) {
      if (!_data.versions.containsKey(q.id)) continue;
      for (final key in q.photoKeys) {
        if (_data.uploaded.contains(key)) continue;
        final bytes = await _repo.loadPhoto(key);
        // Not on this phone means it came from the server.
        if (bytes != null) await server.putPhoto(key, bytes);
        await _update(_data.copyWith(uploaded: {..._data.uploaded, key}));
      }
    }
  }

  Future<void> _pull(ServerClient server) async {
    var more = true;
    while (more) {
      final page = await server.changes(_data.cursor);
      for (final item in page.items) {
        await _applyRemote(item);
      }
      await _update(_data.copyWith(cursor: page.cursor));
      more = page.more;
    }
  }

  Future<void> _applyRemote(SyncedQuote item) async {
    final id = item.id;
    if (item.deleted) {
      await _quotes.removeRemote(id);
      await _forgetQuote(id);
      return;
    }
    final quote = item.quote;
    if (quote == null) return;
    final paid = item.depositPaidCents;
    final deposits = paid == null
        ? ({..._data.deposits}..remove(id))
        : {..._data.deposits, id: paid};
    if (_data.dirty.contains(id)) {
      // Local edits go up first; the push settles any conflict.
      await _update(_data.copyWith(deposits: deposits));
      return;
    }
    await _quotes.applyRemote(quote);
    await _update(
      _data.copyWith(
        versions: {..._data.versions, id: item.version},
        deposits: deposits,
      ),
    );
  }

  Future<void> _forgetQuote(String id) => _update(
    _data.copyWith(
      dirty: {..._data.dirty}..remove(id),
      versions: {..._data.versions}..remove(id),
      deposits: {..._data.deposits}..remove(id),
    ),
  );

  // ---------------------------------------------------------------------------
  // Publishing and numbers
  // ---------------------------------------------------------------------------

  /// Sends [quote]'s latest version, then publishes it. Returns the quote
  /// with its link and status as the server has them.
  Future<Quote> publish(Quote quote) {
    final server = _server;
    if (server == null || !enabled) {
      throw const ApiError('Sign in to send quotes.', retryable: false);
    }
    return _serial.run(() async {
      final local = _quotes.byId(quote.id) ?? quote;
      if (_data.dirty.contains(local.id) ||
          !_data.versions.containsKey(local.id)) {
        await _push(server, local);
      }
      await _uploadPhotos(server);
      final synced = await server.publish(local.id);
      final published = synced.quote!;
      await _quotes.applyRemote(published);
      await _update(
        _data.copyWith(versions: {..._data.versions, local.id: synced.version}),
      );
      return _quotes.byId(local.id) ?? published;
    });
  }

  /// The next quote number: from the block the server reserved for this
  /// phone, or the local counter when offline.
  Future<int> takeNumber(int localNext) async {
    var pool = [..._data.numbers];
    if (pool.isEmpty && enabled) {
      try {
        final r = await _server!.reserveNumbers(10, atLeast: localNext);
        pool = [for (var i = 0; i < r.count; i++) r.first + i];
      } on ApiError {
        // Offline: numbers may repeat across phones until the next sync.
      }
    }
    if (pool.isEmpty) return localNext;
    final n = pool.removeAt(0);
    await _update(_data.copyWith(numbers: pool));
    return max(n, 1);
  }

  // ---------------------------------------------------------------------------
  // Accounts
  // ---------------------------------------------------------------------------

  /// Before a new session starts: clears another business's data from the
  /// phone, queues quotes made before signing in, and takes the business
  /// profile. The caller syncs once signed in.
  Future<void> adopt(Account account) async {
    final business = account.business.id;
    if (_data.businessId.isNotEmpty && _data.businessId != business) {
      await _wipeLocal();
    }
    final firstTime = _data.businessId != business;
    await _update(
      _data.copyWith(
        businessId: business,
        account: account,
        dirty: firstTime
            ? {..._data.dirty, for (final q in _quotes.state) q.id}
            : _data.dirty,
      ),
    );
    final settings = ref.read(settingsProvider);
    if (!account.business.setupComplete &&
        settings.setupDone &&
        account.user.isOwner) {
      // Set up on this phone before signing in: that becomes the
      // business's profile.
      await _update(_data.copyWith(businessDirty: true));
    } else {
      await _takeBusiness(account);
    }
  }

  Future<void> accountChanged(Account account) async {
    await _update(_data.copyWith(account: account));
    if (!_data.businessDirty) await _takeBusiness(account);
  }

  Future<void> _takeBusiness(Account account) async {
    if (!account.business.setupComplete) return;
    await ref
        .read(settingsProvider.notifier)
        .applyServer(account.business.profile, account.business.rates);
  }

  /// Removes everything the business has on this phone (sign-out).
  Future<void> wipe() async {
    _debounce?.cancel();
    await _wipeLocal();
    await ref.read(settingsProvider.notifier).reset();
  }

  Future<void> _wipeLocal() async {
    await _quotes.clearLocal();
    await _update(const SyncState());
  }
}

final syncProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);

/// The card deposit paid on a quote, if any.
final depositPaidProvider = Provider.family<int?, String>((ref, quoteId) {
  ref.watch(syncProvider);
  return ref.read(syncProvider.notifier).data.deposits[quoteId];
});
