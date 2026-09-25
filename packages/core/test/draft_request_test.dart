import 'dart:convert';
import 'dart:typed_data';

import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:test/test.dart';

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 0x10, 0x4A]);
final png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, //
]);
final webp = Uint8List.fromList([
  ...'RIFF'.codeUnits,
  0,
  0,
  0,
  0,
  ...'WEBP'.codeUnits,
]);

Map<String, Object?> body({Object? photos, Object? note = 'two coats'}) => {
  'profile': const BusinessProfile(
    name: 'Brightline Painting',
    trades: [Trade.painting],
  ).toJson(),
  'rates': Rates.forTrade(Trade.painting).toJson(),
  'note': note,
  'photos':
      photos ??
      [
        {'media_type': 'image/jpeg', 'data': base64Encode(jpeg)},
      ],
};

void main() {
  test('round trip', () {
    final r = DraftRequest.fromJson(body());
    expect(r.profile.name, 'Brightline Painting');
    expect(r.profile.primaryTrade, Trade.painting);
    expect(r.rates.laborRateCents, Trade.painting.defaultLaborRateCents);
    expect(r.photos.single.mediaType, 'image/jpeg');
    expect(r.note, 'two coats');
    final again = DraftRequest.fromJson(jsonDecode(jsonEncode(r.toJson())));
    expect(again.photos.single.bytes, jpeg);
  });

  test('sniffs the real image type', () {
    expect(sniffImageType(jpeg), 'image/jpeg');
    expect(sniffImageType(png), 'image/png');
    expect(sniffImageType(webp), 'image/webp');
    expect(sniffImageType([1, 2, 3]), isNull);
    final r = DraftRequest.fromJson(
      body(
        photos: [
          // Declared type is ignored.
          {'media_type': 'image/jpeg', 'data': base64Encode(png)},
        ],
      ),
    );
    expect(r.photos.single.mediaType, 'image/png');
  });

  test('trims the note and names anonymous businesses', () {
    final long = 'x' * (DraftRequest.maxNoteLength + 50);
    final r = DraftRequest.fromJson({
      ...body(note: '  $long  '),
      'profile': {'name': ''},
    });
    expect(r.note, hasLength(DraftRequest.maxNoteLength));
    expect(r.profile.name, 'Contractor');
  });

  group('rejects', () {
    void rejects(Object? json, String pattern) => expect(
      () => DraftRequest.fromJson(json),
      throwsA(
        isA<InvalidDraftRequest>().having(
          (e) => e.message,
          'message',
          contains(pattern),
        ),
      ),
    );

    test('non-objects', () => rejects([1, 2], 'JSON object'));

    test('no photos', () {
      rejects(body(photos: <Object?>[]), 'At least one');
      rejects({...body()}..remove('photos'), 'At least one');
    });

    test('too many photos', () {
      rejects(
        body(
          photos: [
            for (var i = 0; i < DraftRequest.maxPhotos + 1; i++)
              {'data': base64Encode(jpeg)},
          ],
        ),
        'At most',
      );
    });

    test('bad photo data', () {
      rejects(body(photos: [<String, Object?>{}]), 'no data');
      rejects(
        body(
          photos: [
            {'data': '%%%'},
          ],
        ),
        'base64',
      );
      rejects(
        body(
          photos: [
            {'data': base64Encode(utf8.encode('hello'))},
          ],
        ),
        'JPEG, PNG, or WebP',
      );
      rejects(
        body(
          photos: [
            {'data': 'A' * (DraftRequest.maxPhotoBytes * 2)},
          ],
        ),
        'too large',
      );
    });
  });

  test('rates and profile are clamped', () {
    final rates = Rates.fromJson({
      'labor_rate_cents': 1e12,
      'material_markup_pct': -5,
      'deposit_pct': 250,
      'valid_days': 0,
      'price_list': [
        {'id': 'p1', 'name': 'Walls', 'unit': 'sq_ft', 'unit_price_cents': 210},
        {'id': '', 'name': 'No id'},
        'junk',
      ],
    });
    expect(rates.laborRateCents, 100000);
    expect(rates.materialMarkupPct, 0);
    expect(rates.depositPct, 100);
    expect(rates.validDays, 1);
    expect(rates.priceList.single.name, 'Walls');

    final profile = BusinessProfile.fromJson({
      'name': 'A' * 500,
      'trades': ['painting', 'fencing', 'nonsense'],
      'payment_link': 'ftp://example.com',
    });
    expect(profile.name, hasLength(80));
    expect(profile.trades, [Trade.painting, Trade.fencing, Trade.other]);
    expect(profile.paymentLink, isEmpty);
    expect(profile.terms, BusinessProfile.defaultTerms);
  });
}
