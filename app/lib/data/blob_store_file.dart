import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'blob_store.dart';

Future<BlobStore> openPlatformBlobStore() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/jobwalk');
  await dir.create(recursive: true);
  return FileBlobStore(dir);
}

/// Stores each key as a file in the app's private support directory.
class FileBlobStore implements BlobStore {
  FileBlobStore(this.dir);

  final Directory dir;

  /// The last write or delete per key. Operations on one key run in call
  /// order, so the newest value is always the one left on disk.
  final _pending = <String, Future<void>>{};

  Future<void> _serial(String key, Future<void> Function() op) {
    final result = (_pending[key] ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) => op());
    _pending[key] = result.catchError((Object _) {});
    return result;
  }

  File _file(String key) =>
      File('${dir.path}/${key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')}');

  Future<void> _atomicWrite(File file, List<int> bytes) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<String?> readText(String key) async {
    final f = _file(key);
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> writeText(String key, String value) =>
      _serial(key, () => _atomicWrite(_file(key), utf8.encode(value)));

  @override
  Future<Uint8List?> readBytes(String key) async {
    final f = _file(key);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> writeBytes(String key, Uint8List bytes) =>
      _serial(key, () => _atomicWrite(_file(key), bytes));

  @override
  Future<void> delete(String key) => _serial(key, () async {
    final f = _file(key);
    if (await f.exists()) await f.delete();
  });

  @override
  Future<void> deleteAll() async {
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
  }
}
