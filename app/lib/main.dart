import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config.dart';
import 'data/blob_store.dart';
import 'data/repositories.dart';
import 'data/session.dart';
import 'data/sync_state.dart';
import 'state/providers.dart';
import 'state/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  BlobStore store;
  try {
    store = await openBlobStore();
  } on Object {
    // Storage can be unavailable (e.g. blocked browser storage). Run with
    // memory-only storage rather than failing to start.
    store = MemoryBlobStore();
  }
  final config = AppConfig.fromEnvironment();
  final settings = await SettingsRepository(store).load();
  final quotes = await QuoteRepository(store).load();
  final tokens = SecureTokenStore();
  final token = config.demoMode ? null : await tokens.read();
  final sync = config.demoMode
      ? const SyncState()
      : await SyncStateRepository(store).load();
  runApp(
    ProviderScope(
      overrides: [
        configProvider.overrideWithValue(config),
        blobStoreProvider.overrideWithValue(store),
        initialSettingsProvider.overrideWithValue(settings),
        initialQuotesProvider.overrideWithValue(quotes),
        tokenStoreProvider.overrideWithValue(tokens),
        initialTokenProvider.overrideWithValue(token),
        initialSyncStateProvider.overrideWithValue(sync),
      ],
      child: const JobwalkApp(),
    ),
  );
}
