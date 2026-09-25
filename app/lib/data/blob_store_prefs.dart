import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'blob_store.dart';

Future<BlobStore> openPlatformBlobStore() async =>
    PrefsBlobStore(await SharedPreferences.getInstance());

/// Browser storage for the web build. Browsers cap this at a few MB, so the
/// app stores only small photo previews on the web.
class PrefsBlobStore implements BlobStore {
  PrefsBlobStore(this.prefs);

  static const _prefix = 'blob:';
  final SharedPreferences prefs;

  @override
  Future<String?> readText(String key) async => prefs.getString(_prefix + key);

  @override
  Future<void> writeText(String key, String value) async {
    await prefs.setString(_prefix + key, value);
  }

  @override
  Future<Uint8List?> readBytes(String key) async {
    final s = prefs.getString(_prefix + key);
    return s == null ? null : base64Decode(s);
  }

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async {
    await prefs.setString(_prefix + key, base64Encode(bytes));
  }

  @override
  Future<void> delete(String key) async {
    await prefs.remove(_prefix + key);
  }

  @override
  Future<void> deleteAll() async {
    for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await prefs.remove(k);
    }
  }
}
