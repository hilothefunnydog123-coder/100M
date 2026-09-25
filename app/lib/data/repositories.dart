import 'dart:convert';
import 'dart:typed_data';

import 'package:spotcheck_core/spotcheck_core.dart';

import 'blob_store.dart';
import 'models.dart';

class SettingsRepository {
  SettingsRepository(this._store);

  static const _key = 'settings.json';
  final BlobStore _store;

  Future<AppSettings> load() async {
    final raw = await _store.readText(_key);
    if (raw != null) {
      try {
        return AppSettings.fromJson(jsonDecode(raw) as Map<String, Object?>);
      } on Object {
        // Fall through to fresh settings.
      }
    }
    final fresh = AppSettings(installId: newId('inst'));
    await save(fresh);
    return fresh;
  }

  Future<void> save(AppSettings settings) =>
      _store.writeText(_key, jsonEncode(settings.toJson()));
}

class HistoryRepository {
  HistoryRepository(this._store);

  static const _key = 'history.json';
  final BlobStore _store;

  Future<List<CheckRecord>> load() async {
    final raw = await _store.readText(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return [for (final item in list) ?CheckRecord.tryParse(item)]
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } on Object {
      return [];
    }
  }

  Future<void> save(List<CheckRecord> records) =>
      _store.writeText(_key, jsonEncode([for (final r in records) r.toJson()]));

  Future<void> savePhoto(String key, Uint8List bytes) =>
      _store.writeBytes('photo_$key', bytes);

  Future<Uint8List?> loadPhoto(String key) => _store.readBytes('photo_$key');

  Future<void> deletePhotos(Iterable<String> keys) async {
    for (final k in keys) {
      await _store.delete('photo_$k');
    }
  }
}
