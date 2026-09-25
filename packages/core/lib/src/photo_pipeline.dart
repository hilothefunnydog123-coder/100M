import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A problem worth retaking the photo for.
enum PhotoProblem {
  tooDark('Too dark', 'Turn on the lights or open the blinds and retake.'),
  lowResolution(
    'Low resolution',
    'Use the camera directly instead of a screenshot or a cropped image.',
  );

  const PhotoProblem(this.label, this.tip);

  final String label;
  final String tip;
}

class PreparedPhoto {
  const PreparedPhoto({
    required this.jpeg,
    required this.width,
    required this.height,
    required this.brightness,
  });

  static const darkBelow = 0.12;
  static const minShortSide = 480;

  final Uint8List jpeg;
  final int width;
  final int height;

  /// Mean luminance, 0 (black) to 1 (white).
  final double brightness;

  List<PhotoProblem> get problems => [
    if (brightness < darkBelow) PhotoProblem.tooDark,
    if (math.min(width, height) < minShortSide) PhotoProblem.lowResolution,
  ];
}

/// Decodes any common image, applies EXIF rotation, downsizes it so the long
/// edge is at most [maxDimension], and re-encodes it as JPEG.
///
/// The app and the accuracy harness both use this, so accuracy is measured
/// on exactly what production sends. Pure Dart: run it in an isolate.
PreparedPhoto preparePhoto(
  Uint8List input, {
  int maxDimension = 2048,
  int jpegQuality = 85,
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
  if (math.max(image.width, image.height) > maxDimension) {
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
  return PreparedPhoto(
    jpeg: img.encodeJpg(image, quality: jpegQuality),
    width: image.width,
    height: image.height,
    brightness: meanBrightness(image),
  );
}

/// Mean luminance on a small copy.
double meanBrightness(img.Image image) {
  final small = math.max(image.width, image.height) > 256
      ? img.copyResize(
          image,
          width: image.width >= image.height ? 256 : null,
          height: image.width >= image.height ? null : 256,
          interpolation: img.Interpolation.average,
        )
      : image;
  var sum = 0.0;
  var count = 0;
  for (final pixel in small) {
    sum += pixel.luminanceNormalized;
    count++;
  }
  return count == 0 ? 0 : sum / count;
}
