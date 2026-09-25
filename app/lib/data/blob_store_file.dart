import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'blob_store.dart';

Future<BlobStore> openPlatformBlobStore() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory('${support.path}/spotcheck');
  await dir.create(recursive: true);
  return FileBlobStore(dir);
}

/// Stores each key as a file in the app's private support directory.
///
/// Health photos stay on the device. Before launch, consider excluding this
/// directory from iCloud backups and encrypting it at rest.
class FileBlobStore implements BlobStore {
  FileBlobStore(this.dir);

  final Directory dir;

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
      _atomicWrite(_file(key), utf8.encode(value));

  @override
  Future<Uint8List?> readBytes(String key) async {
    final f = _file(key);
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> writeBytes(String key, Uint8List bytes) =>
      _atomicWrite(_file(key), bytes);

  @override
  Future<void> delete(String key) async {
    final f = _file(key);
    if (await f.exists()) await f.delete();
  }

  @override
  Future<void> deleteAll() async {
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
  }
}
