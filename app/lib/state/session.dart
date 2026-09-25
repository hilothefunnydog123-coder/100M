import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/session.dart';
import '../data/sync_state.dart';
import '../services/api.dart';
import '../services/models.dart';
import '../services/server.dart';
import 'providers.dart';
import 'sync.dart';

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// Read before the first frame and overridden in `main()`.
final initialTokenProvider = Provider<String?>((ref) => null);
final initialSyncStateProvider = Provider<SyncState>(
  (ref) => const SyncState(),
);

/// Who is signed in, if anyone. Demo mode never signs in.
class Session {
  const Session({this.token, this.account});

  final String? token;

  /// Null until the server has answered once.
  final Account? account;

  bool get signedIn => token != null;

  /// Members can't change the business profile, rates, plan, or team.
  bool get isOwner => account?.user.isOwner ?? true;
}

class SessionNotifier extends Notifier<Session> {
  @override
  Session build() => Session(
    token: ref.watch(initialTokenProvider),
    account: ref.watch(initialSyncStateProvider).account,
  );

  ServerClient get _server =>
      ref.read(serverProvider) ??
      (throw const ApiError('Sign-in needs a server.', retryable: false));

  Future<void> requestCode(String email) => _server.requestCode(email.trim());

  /// Checks the emailed code, stores the session, and brings this phone's
  /// data in line with the account.
  Future<void> signIn(String email, String code) async {
    final (token, account) = await _server.verifyCode(
      email.trim(),
      code.trim(),
      device: _deviceName(),
    );
    await ref.read(tokenStoreProvider).write(token);
    await ref.read(syncProvider.notifier).adopt(account);
    state = Session(token: token, account: account);
    // The first sync runs while the home screen shows what's on the phone.
    unawaited(ref.read(syncProvider.notifier).sync());
  }

  /// Picks up plan and profile changes made elsewhere.
  Future<void> refresh() async {
    if (!state.signedIn) return;
    await setAccount(await _server.me());
  }

  Future<void> setAccount(Account account) async {
    if (!state.signedIn) return;
    state = Session(token: state.token, account: account);
    await ref.read(syncProvider.notifier).accountChanged(account);
  }

  /// Ends the session everywhere it matters and removes the business's
  /// data from this phone.
  Future<void> signOut() async {
    try {
      await _server.signOut();
    } on ApiError {
      // Already expired or offline: forgetting it here is what counts.
    }
    await _forget();
    await ref.read(syncProvider.notifier).wipe();
  }

  /// Deletes the account on the server (an owner deletes the business,
  /// a member leaves it), then everything on this phone.
  Future<void> deleteAccount() async {
    await _server.deleteAccount();
    await _forget();
    await ref.read(syncProvider.notifier).wipe();
  }

  /// The server no longer accepts the token (expired or revoked). The
  /// data stays; signing in again picks up where it left off.
  void expired() {
    if (!state.signedIn) return;
    unawaited(_forget());
  }

  Future<void> _forget() async {
    state = const Session();
    await ref.read(tokenStoreProvider).write(null);
  }

  static String _deviceName() {
    if (kIsWeb) return 'Web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'iPhone',
      TargetPlatform.android => 'Android',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => 'Device',
    };
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, Session>(
  SessionNotifier.new,
);

/// The API client when this build talks to a server; null in demo mode.
final serverProvider = Provider<ServerClient?>((ref) {
  final config = ref.watch(configProvider);
  if (config.demoMode) return null;
  return ServerClient(
    baseUrl: config.apiBaseUrl!,
    token: () => ref.read(sessionProvider).token,
    onUnauthorized: () => ref.read(sessionProvider.notifier).expired(),
    client: ref.watch(httpClientProvider),
  );
});
