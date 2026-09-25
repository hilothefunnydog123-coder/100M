import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/blob_store.dart';
import 'data/repositories.dart';
import 'state/providers.dart';

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
  final settings = await SettingsRepository(store).load();
  final history = await HistoryRepository(store).load();
  runApp(
    ProviderScope(
      overrides: [
        blobStoreProvider.overrideWithValue(store),
        initialSettingsProvider.overrideWithValue(settings),
        initialHistoryProvider.overrideWithValue(history),
      ],
      child: const SpotCheckApp(),
    ),
  );
}
