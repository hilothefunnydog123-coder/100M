import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:jobwalk_core/photo_pipeline.dart';
import 'package:test/test.dart';

Uint8List photo(int w, int h, int gray) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(gray, gray, gray));
  return img.encodePng(image);
}

void main() {
  test('downsizes the long edge and re-encodes as JPEG', () {
    final p = preparePhoto(photo(4000, 3000, 180), maxDimension: 2048);
    expect(p.width, 2048);
    expect(p.height, 1536);
    expect(p.jpeg.sublist(0, 2), [0xFF, 0xD8]);
    expect(p.problems, isEmpty);
  });

  test('flags dark and tiny photos', () {
    expect(preparePhoto(photo(1200, 900, 10)).problems, [PhotoProblem.tooDark]);
    expect(preparePhoto(photo(300, 200, 150)).problems, [
      PhotoProblem.lowResolution,
    ]);
  });

  test('rejects data that is not an image', () {
    expect(
      () => preparePhoto(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    final truncated = photo(100, 100, 100).sublist(0, 40);
    expect(() => preparePhoto(truncated), throwsFormatException);
  });
}
