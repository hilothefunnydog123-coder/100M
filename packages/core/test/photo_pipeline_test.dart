import 'dart:math';

import 'package:image/image.dart' as img;
import 'package:spotcheck_core/photo_pipeline.dart';
import 'package:test/test.dart';

img.Image solid(int w, int h, int value) => img.fill(
  img.Image(width: w, height: h),
  color: img.ColorRgb8(value, value, value),
);

/// Skin-like texture: a warm base with random fine detail.
img.Image textured(int w, int h, {int seed = 1}) {
  final random = Random(seed);
  final image = img.Image(width: w, height: h);
  for (final p in image) {
    final n = random.nextInt(60);
    p
      ..r = 150 + n
      ..g = 110 + n
      ..b = 90 + n;
  }
  return image;
}

void main() {
  test('a well-lit, detailed photo passes', () {
    final q = measureQuality(textured(600, 600));
    expect(q.problems, isEmpty);
    expect(q.isGood, isTrue);
  });

  test('flags a dark photo', () {
    final q = measureQuality(solid(600, 600, 20));
    expect(q.problems, contains(PhotoProblem.tooDark));
  });

  test('flags an overexposed photo', () {
    final q = measureQuality(solid(600, 600, 252));
    expect(q.problems, contains(PhotoProblem.tooBright));
  });

  test('flags glare on an otherwise normal photo', () {
    final image = textured(600, 600);
    img.fillRect(
      image,
      x1: 0,
      y1: 0,
      x2: 599,
      y2: 150,
      color: img.ColorRgb8(255, 255, 255),
    );
    final q = measureQuality(image);
    expect(q.problems, contains(PhotoProblem.glare));
    expect(q.problems, isNot(contains(PhotoProblem.tooBright)));
  });

  test('blurring lowers sharpness below the threshold', () {
    final sharp = textured(600, 600);
    final blurred = img.gaussianBlur(textured(600, 600), radius: 8);
    final a = measureQuality(sharp);
    final b = measureQuality(blurred);
    expect(b.sharpness, lessThan(a.sharpness / 10));
    expect(b.problems, contains(PhotoProblem.blurry));
  });

  test('flags tiny images', () {
    final q = measureQuality(textured(300, 200));
    expect(q.problems, contains(PhotoProblem.lowResolution));
  });

  test('preparePhoto downsizes, keeps aspect, and outputs JPEG', () {
    final png = img.encodePng(textured(3000, 1500));
    final prepared = preparePhoto(png, maxDimension: 1024);
    expect(prepared.width, 1024);
    expect(prepared.height, 512);
    expect(prepared.jpeg.sublist(0, 3), [0xFF, 0xD8, 0xFF]);
    expect(prepared.quality.width, 1024);
  });

  test('preparePhoto keeps small images at their size', () {
    final jpg = img.encodeJpg(textured(800, 600));
    final prepared = preparePhoto(jpg);
    expect(prepared.width, 800);
    expect(prepared.height, 600);
  });

  test('preparePhoto handles portrait images', () {
    final prepared = preparePhoto(
      img.encodePng(textured(1000, 3000)),
      maxDimension: 900,
    );
    expect(prepared.height, 900);
    expect(prepared.width, 300);
  });

  test('preparePhoto rejects non-images', () {
    expect(
      () => preparePhoto(img.encodePng(textured(10, 10)).sublist(0, 20)),
      throwsFormatException,
    );
  });
}
