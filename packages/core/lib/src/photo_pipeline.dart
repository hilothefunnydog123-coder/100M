import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A problem the person can fix by retaking the photo.
enum PhotoProblem {
  tooDark('Too dark', 'Move to a window or turn on a bright light.'),
  tooBright('Too bright', 'Avoid direct sun or flash glare; try shade.'),
  glare('Glare', 'Tilt the phone a little to avoid shiny reflections.'),
  blurry(
    'Might be blurry',
    'Hold the phone steady about 10 cm away and tap the spot to focus.',
  ),
  lowResolution(
    'Low resolution',
    'Use the camera directly instead of a screenshot or a cropped image.',
  );

  const PhotoProblem(this.label, this.tip);

  final String label;
  final String tip;
}

/// Simple, fast image statistics used to coach the person before upload.
/// These are heuristics that warn; the model makes the final call.
class PhotoQuality {
  const PhotoQuality({
    required this.width,
    required this.height,
    required this.brightness,
    required this.sharpness,
    required this.glare,
  });

  // Thresholds are deliberately lenient: skin is low-texture, so a sharp
  // photo of smooth skin can still score low on sharpness.
  static const darkBelow = 0.16;
  static const brightAbove = 0.90;
  static const glareAbove = 0.10;
  static const blurryBelow = 12.0;
  static const minShortSide = 400;

  final int width;
  final int height;

  /// Mean luminance, 0 (black) to 1 (white).
  final double brightness;

  /// Variance of the Laplacian on a normalized grayscale copy. Higher is
  /// sharper.
  final double sharpness;

  /// Share of pixels that are blown-out white.
  final double glare;

  List<PhotoProblem> get problems => [
    if (brightness < darkBelow) PhotoProblem.tooDark,
    if (brightness > brightAbove) PhotoProblem.tooBright,
    if (glare > glareAbove && brightness <= brightAbove) PhotoProblem.glare,
    if (sharpness < blurryBelow) PhotoProblem.blurry,
    if (math.min(width, height) < minShortSide) PhotoProblem.lowResolution,
  ];

  bool get isGood => problems.isEmpty;

  Map<String, Object?> toJson() => {
    'width': width,
    'height': height,
    'brightness': double.parse(brightness.toStringAsFixed(3)),
    'sharpness': double.parse(sharpness.toStringAsFixed(1)),
    'glare': double.parse(glare.toStringAsFixed(3)),
  };
}

class PreparedPhoto {
  const PreparedPhoto({
    required this.jpeg,
    required this.width,
    required this.height,
    required this.quality,
  });

  final Uint8List jpeg;
  final int width;
  final int height;
  final PhotoQuality quality;
}

/// Decodes any common image, applies EXIF rotation, downsizes it so the long
/// edge is at most [maxDimension], and re-encodes it as JPEG.
///
/// The app and the evaluation harness both use this so accuracy is measured
/// on exactly what production sends. Pure Dart: run it in an isolate.
PreparedPhoto preparePhoto(
  Uint8List input, {
  int maxDimension = 2048,
  int jpegQuality = 88,
}) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(input);
  } on Object {
    // Truncated files make decoders throw RangeErrors and the like; callers
    // only need to know the image is unusable.
    decoded = null;
  }
  if (decoded == null) {
    throw const FormatException('Unsupported or corrupt image.');
  }
  var image = img.bakeOrientation(decoded);
  final longest = math.max(image.width, image.height);
  if (longest > maxDimension) {
    image = image.width >= image.height
        ? img.copyResize(
            image,
            width: maxDimension,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            image,
            height: maxDimension,
            interpolation: img.Interpolation.average,
          );
  }
  final jpeg = img.encodeJpg(image, quality: jpegQuality);
  return PreparedPhoto(
    jpeg: jpeg,
    width: image.width,
    height: image.height,
    quality: measureQuality(image),
  );
}

/// Measures brightness, glare, and sharpness on a small grayscale copy.
PhotoQuality measureQuality(img.Image image) {
  const analysisSize = 512;
  final small = math.max(image.width, image.height) > analysisSize
      ? (image.width >= image.height
            ? img.copyResize(
                image,
                width: analysisSize,
                interpolation: img.Interpolation.average,
              )
            : img.copyResize(
                image,
                height: analysisSize,
                interpolation: img.Interpolation.average,
              ))
      : image;

  final w = small.width;
  final h = small.height;
  final luma = Float64List(w * h);
  var sum = 0.0;
  var blown = 0;
  var i = 0;
  for (final pixel in small) {
    final l = pixel.luminanceNormalized.toDouble();
    luma[i++] = l;
    sum += l;
    if (l > 0.98) blown++;
  }
  final count = w * h;

  // Variance of a 4-neighbour Laplacian, on a 0-255 scale.
  var lapSum = 0.0;
  var lapSq = 0.0;
  var n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final c = y * w + x;
      final lap =
          255 *
          (luma[c - 1] + luma[c + 1] + luma[c - w] + luma[c + w] - 4 * luma[c]);
      lapSum += lap;
      lapSq += lap * lap;
      n++;
    }
  }
  final mean = n == 0 ? 0.0 : lapSum / n;
  final variance = n == 0 ? 0.0 : lapSq / n - mean * mean;

  return PhotoQuality(
    width: image.width,
    height: image.height,
    brightness: count == 0 ? 0 : sum / count,
    sharpness: variance,
    glare: count == 0 ? 0 : blown / count,
  );
}
