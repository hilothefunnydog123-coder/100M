import 'dart:convert';
import 'dart:typed_data';

import 'body_site.dart';
import 'intake.dart';

enum PhotoKind {
  closeUp('close_up', 'Close-up'),
  context('context', 'Wider view');

  const PhotoKind(this.id, this.label);

  final String id;
  final String label;

  static PhotoKind fromId(Object? id) =>
      values.firstWhere((v) => v.id == id, orElse: () => PhotoKind.closeUp);
}

class CheckPhoto {
  const CheckPhoto({
    required this.bytes,
    required this.mediaType,
    this.kind = PhotoKind.closeUp,
  });

  static const supportedMediaTypes = {'image/jpeg', 'image/png', 'image/webp'};

  final Uint8List bytes;
  final String mediaType;
  final PhotoKind kind;

  Map<String, Object?> toJson() => {
    'media_type': mediaType,
    'kind': kind.id,
    'data': base64Encode(bytes),
  };
}

class InvalidCheckRequest implements Exception {
  const InvalidCheckRequest(this.message);

  final String message;

  @override
  String toString() => 'InvalidCheckRequest: $message';
}

/// What the app sends for analysis: where, what the person answered, and
/// 1-3 photos.
class CheckRequest {
  const CheckRequest({
    required this.site,
    required this.answers,
    required this.photos,
    this.note = '',
  });

  static const maxPhotos = 3;
  static const maxNoteLength = 500;

  /// Per-photo size limit after base64 decoding. The app downsizes photos
  /// well below this; the limit exists to reject abuse early.
  static const maxPhotoBytes = 3500000;

  final BodySite site;
  final IntakeAnswers answers;
  final List<CheckPhoto> photos;
  final String note;

  Map<String, Object?> toJson() => {
    'site': site.id,
    'answers': answers.toJson(),
    'note': note,
    'photos': [for (final p in photos) p.toJson()],
  };

  /// Validates untrusted input. Throws [InvalidCheckRequest].
  factory CheckRequest.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const InvalidCheckRequest('Body must be a JSON object.');
    }
    final site = BodySite.fromId(json['site'] as String?);
    if (site == null) {
      throw const InvalidCheckRequest('Unknown or missing "site".');
    }
    final rawPhotos = json['photos'];
    if (rawPhotos is! List || rawPhotos.isEmpty) {
      throw const InvalidCheckRequest('At least one photo is required.');
    }
    if (rawPhotos.length > maxPhotos) {
      throw const InvalidCheckRequest('At most $maxPhotos photos are allowed.');
    }
    final photos = <CheckPhoto>[];
    for (final (i, raw) in rawPhotos.indexed) {
      if (raw is! Map<String, Object?>) {
        throw InvalidCheckRequest('Photo ${i + 1} is malformed.');
      }
      final data = raw['data'];
      if (data is! String || data.isEmpty) {
        throw InvalidCheckRequest('Photo ${i + 1} has no data.');
      }
      // base64 inflates by 4/3; reject oversized payloads before decoding.
      if (data.length > (maxPhotoBytes * 4 / 3) + 4) {
        throw InvalidCheckRequest('Photo ${i + 1} is too large.');
      }
      final Uint8List bytes;
      try {
        bytes = base64Decode(data);
      } on FormatException {
        throw InvalidCheckRequest('Photo ${i + 1} is not valid base64.');
      }
      final sniffed = sniffImageType(bytes);
      if (sniffed == null) {
        throw InvalidCheckRequest(
          'Photo ${i + 1} must be a JPEG, PNG, or WebP image.',
        );
      }
      photos.add(
        CheckPhoto(
          bytes: bytes,
          mediaType: sniffed,
          kind: PhotoKind.fromId(raw['kind']),
        ),
      );
    }
    final note = json['note'];
    final cleanNote = note is String ? note.trim() : '';
    return CheckRequest(
      site: site,
      answers: IntakeAnswers.fromJson(json['answers']).prunedFor(site.domain),
      photos: photos,
      note: cleanNote.length > maxNoteLength
          ? cleanNote.substring(0, maxNoteLength)
          : cleanNote,
    );
  }
}

/// Detects the image type from magic bytes rather than trusting a declared
/// content type.
String? sniffImageType(List<int> b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length >= 8 &&
      b[0] == 0x89 &&
      b[1] == 0x50 &&
      b[2] == 0x4E &&
      b[3] == 0x47 &&
      b[4] == 0x0D &&
      b[5] == 0x0A &&
      b[6] == 0x1A &&
      b[7] == 0x0A) {
    return 'image/png';
  }
  if (b.length >= 12 &&
      b[0] == 0x52 && // R
      b[1] == 0x49 && // I
      b[2] == 0x46 && // F
      b[3] == 0x46 && // F
      b[8] == 0x57 && // W
      b[9] == 0x45 && // E
      b[10] == 0x42 && // B
      b[11] == 0x50) {
    // P
    return 'image/webp';
  }
  return null;
}
