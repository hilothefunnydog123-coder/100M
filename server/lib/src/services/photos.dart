import 'dart:typed_data';

import '../common.dart';
import '../db/database.dart';
import '../integrations/object_store.dart';
import 'accounts.dart';

/// Job photos, so every phone on the team sees them. Ids come from the
/// phone, which makes uploads idempotent.
class PhotoService {
  PhotoService({
    required Db db,
    required ObjectStore store,
    this.maxBytes = 10 * 1024 * 1024,
    this.maxPerBusiness = 50000,
    Clock clock = systemClock,
  }) : _db = db,
       _store = store,
       _clock = clock;

  final int maxBytes;
  final int maxPerBusiness;
  final Db _db;
  final ObjectStore _store;
  final Clock _clock;

  static final idPattern = RegExp(r'^[A-Za-z0-9_-]{4,100}$');

  Future<Map<String, Object?>> put(
    Account a,
    String id,
    Uint8List bytes,
  ) async {
    if (!idPattern.hasMatch(id)) {
      throw ApiError.badRequest(
        'invalid_id',
        'Photo ids are 4-100 letters, '
            'digits, dashes, or underscores.',
      );
    }
    if (bytes.length > maxBytes) {
      throw ApiError(
        413,
        'too_large',
        'Photos can be up to '
            '${maxBytes ~/ (1024 * 1024)} MB.',
      );
    }
    final type = imageType(bytes);
    if (type == null) {
      throw ApiError(415, 'unsupported_type', 'Upload a JPEG or PNG photo.');
    }
    final count =
        (await _db.one(
              'SELECT count(*)::int AS n FROM photos WHERE business_id = @b',
              {'b': a.businessId},
            ))!['n']
            as int;
    if (count >= maxPerBusiness) {
      throw ApiError(
        507,
        'storage_full',
        'Your account has reached its photo limit. Delete old quotes to '
            'make room.',
      );
    }
    final key = 'photos/${a.businessId}/$id';
    await _store.put(key, bytes, contentType: type);
    await _db.execute(
      '''
      INSERT INTO photos (business_id, id, object_key, content_type, bytes,
        created_at)
      VALUES (@b, @id, @k, @t, @n:int4, @now:timestamptz)
      ON CONFLICT (business_id, id) DO UPDATE SET object_key = EXCLUDED.object_key,
        content_type = EXCLUDED.content_type, bytes = EXCLUDED.bytes''',
      {
        'b': a.businessId,
        'id': id,
        'k': key,
        't': type,
        'n': bytes.length,
        'now': _clock(),
      },
    );
    return {'id': id, 'bytes': bytes.length, 'content_type': type};
  }

  /// The photo's bytes, or a short-lived link to them when the store can
  /// serve directly (S3).
  Future<({Uint8List? bytes, Uri? redirect, String contentType})> get(
    Account a,
    String id,
  ) async {
    if (!idPattern.hasMatch(id)) throw ApiError.notFound('No such photo.');
    final row = await _db.one(
      'SELECT object_key, content_type FROM photos '
      'WHERE business_id = @b AND id = @id',
      {'b': a.businessId, 'id': id},
    );
    if (row == null) throw ApiError.notFound('No such photo.');
    final key = row['object_key'] as String;
    final type = row['content_type'] as String;
    final signed = _store.signedUrl(key, expires: const Duration(minutes: 10));
    if (signed != null) {
      return (bytes: null, redirect: signed, contentType: type);
    }
    final bytes = await _store.get(key);
    if (bytes == null) throw ApiError.notFound('No such photo.');
    return (bytes: bytes, redirect: null, contentType: type);
  }

  /// JPEG or PNG by magic number; anything else is refused.
  static String? imageType(Uint8List b) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (b.length > 8 &&
        b[0] == 0x89 &&
        b[1] == 0x50 &&
        b[2] == 0x4E &&
        b[3] == 0x47) {
      return 'image/png';
    }
    return null;
  }
}
