import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services/api.dart';
import 'state/providers.dart';
import 'state/session.dart';
import 'state/sync.dart';
import 'theme/theme.dart';
import 'ui/auth/sign_in_screen.dart';
import 'ui/home/home_screen.dart';
import 'ui/setup/setup_screen.dart';

class JobwalkApp extends ConsumerWidget {
  const JobwalkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connected = !ref.watch(configProvider).demoMode;
    final signedIn = ref.watch(sessionProvider.select((s) => s.signedIn));
    final setupDone = ref.watch(settingsProvider.select((s) => s.setupDone));
    final Widget home;
    if (connected && !signedIn) {
      home = const SignInScreen();
    } else if (!setupDone) {
      home = const SetupScreen();
    } else {
      home = const HomeScreen();
    }
    return MaterialApp(
      // Signing in or out starts navigation over, whatever was open.
      key: ValueKey(signedIn),
      title: 'Jobwalk',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: connected && signedIn
          ? (context, child) => SyncScope(child: child!)
          : null,
      home: home,
    );
  }
}

/// Syncs when the app opens, when it comes back to the foreground, and
/// every minute while it's open.
class SyncScope extends ConsumerStatefulWidget {
  const SyncScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<SyncScope> createState() => _SyncScopeState();
}

class _SyncScopeState extends ConsumerState<SyncScope>
    with WidgetsBindingObserver {
  Timer? _timer;
  var _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_foreground) unawaited(ref.read(syncProvider.notifier).sync());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _refresh();
  }

  void _refresh() {
    if (!mounted) return;
    unawaited(() async {
      try {
        await ref.read(sessionProvider.notifier).refresh();
      } on ApiError {
        // Offline: the plan shown is the last one seen.
      }
    }());
    unawaited(ref.read(syncProvider.notifier).sync());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
