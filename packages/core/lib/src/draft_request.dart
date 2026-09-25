import 'dart:convert';
import 'dart:typed_data';

import 'json.dart';
import 'profile.dart';
import 'rates.dart';

class JobPhoto {
  const JobPhoto({required this.bytes, required this.mediaType});

  final Uint8List bytes;
  final String mediaType;

  Map<String, Object?> toJson() => {
    'media_type': mediaType,
    'data': base64Encode(bytes),
  };
}

class InvalidDraftRequest implements Exception {
  const InvalidDraftRequest(this.message);

  final String message;

  @override
  String toString() => 'InvalidDraftRequest: $message';
}

/// What the app sends to get an AI draft: the job photos, the owner's note,
/// and how this business prices work.
class DraftRequest {
  const DraftRequest({
    required this.profile,
    required this.rates,
    required this.photos,
    this.note = '',
  });

  static const maxPhotos = 8;
  static const maxNoteLength = 1000;

  /// Per-photo size limit after base64 decoding. The app downsizes photos
  /// well below this; the limit exists to reject abuse early.
  static const maxPhotoBytes = 3500000;

  final BusinessProfile profile;
  final Rates rates;
  final List<JobPhoto> photos;
  final String note;

  Map<String, Object?> toJson() => {
    'profile': profile.toJson(),
    'rates': rates.toJson(),
    'note': note,
    'photos': [for (final p in photos) p.toJson()],
  };

  /// Validates untrusted input. Throws [InvalidDraftRequest].
  factory DraftRequest.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const InvalidDraftRequest('Body must be a JSON object.');
    }
    final rawPhotos = json['photos'];
    if (rawPhotos is! List || rawPhotos.isEmpty) {
      throw const InvalidDraftRequest('At least one photo is required.');
    }
    if (rawPhotos.length > maxPhotos) {
      throw const InvalidDraftRequest('At most $maxPhotos photos are allowed.');
    }
    final photos = <JobPhoto>[];
    for (final (i, raw) in rawPhotos.indexed) {
      final data = readMap(raw)['data'];
      if (data is! String || data.isEmpty) {
        throw InvalidDraftRequest('Photo ${i + 1} has no data.');
      }
      // base64 inflates by 4/3; reject oversized payloads before decoding.
      if (data.length > (maxPhotoBytes * 4 / 3) + 4) {
        throw InvalidDraftRequest('Photo ${i + 1} is too large.');
      }
      final Uint8List bytes;
      try {
        bytes = base64Decode(data);
      } on FormatException {
        throw InvalidDraftRequest('Photo ${i + 1} is not valid base64.');
      }
      final type = sniffImageType(bytes);
      if (type == null) {
        throw InvalidDraftRequest(
          'Photo ${i + 1} must be a JPEG, PNG, or WebP image.',
        );
      }
      photos.add(JobPhoto(bytes: bytes, mediaType: type));
    }
    final profile = BusinessProfile.fromJson(json['profile']);
    return DraftRequest(
      profile: profile.name.isEmpty
          ? profile.copyWith(name: 'Contractor')
          : profile,
      rates: Rates.fromJson(json['rates']),
      photos: photos,
      note: readString(json['note'], max: maxNoteLength),
    );
  }
}

/// Detects the image type from magic bytes rather than trusting a declared
/// content type.
String? sniffImageType(List<int> b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  const png = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (b.length >= 8 && Iterable<int>.generate(8).every((i) => b[i] == png[i])) {
    return 'image/png';
  }
  if (b.length >= 12 &&
      String.fromCharCodes(b.sublist(0, 4)) == 'RIFF' &&
      String.fromCharCodes(b.sublist(8, 12)) == 'WEBP') {
    return 'image/webp';
  }
  return null;
}
