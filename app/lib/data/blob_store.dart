import 'dart:typed_data';

import 'blob_store_prefs.dart'
    if (dart.library.io) 'blob_store_file.dart'
    as platform;

/// Minimal key-value storage for text and bytes. Everything the app keeps
/// (settings, history, photos) lives on the device behind this interface.
abstract interface class BlobStore {
  Future<String?> readText(String key);
  Future<void> writeText(String key, String value);
  Future<Uint8List?> readBytes(String key);
  Future<void> writeBytes(String key, Uint8List bytes);
  Future<void> delete(String key);
  Future<void> deleteAll();
}

/// Files on iOS and Android; browser storage on the web.
Future<BlobStore> openBlobStore() => platform.openPlatformBlobStore();

/// For tests.
class MemoryBlobStore implements BlobStore {
  final _text = <String, String>{};
  final _bytes = <String, Uint8List>{};

  @override
  Future<String?> readText(String key) async => _text[key];

  @override
  Future<void> writeText(String key, String value) async => _text[key] = value;

  @override
  Future<Uint8List?> readBytes(String key) async => _bytes[key];

  @override
  Future<void> writeBytes(String key, Uint8List bytes) async =>
      _bytes[key] = bytes;

  @override
  Future<void> delete(String key) async {
    _text.remove(key);
    _bytes.remove(key);
  }

  @override
  Future<void> deleteAll() async {
    _text.clear();
    _bytes.clear();
  }
}
