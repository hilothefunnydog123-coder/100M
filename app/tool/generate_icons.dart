// Renders the SpotCheck mark into every platform icon slot:
//   dart run tool/generate_icons.dart
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

const top = (11, 122, 117); // brand #0B7A75
const bottom = (7, 90, 86); // brandInk #075A56

void main() {
  // iOS masks icons itself and rejects transparency: full-bleed, opaque.
  final ios = Directory('ios/Runner/Assets.xcassets/AppIcon.appiconset');
  final pattern = RegExp(r'Icon-App-([\d.]+)x[\d.]+@(\d)x\.png');
  for (final f in ios.listSync().whereType<File>()) {
    final m = pattern.firstMatch(f.uri.pathSegments.last);
    if (m == null) continue;
    final px = (double.parse(m.group(1)!) * int.parse(m.group(2)!)).round();
    _write(f.path, render(px, rounded: false, opaque: true));
  }

  // Android legacy launcher icons.
  const android = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final e in android.entries) {
    _write(
      'android/app/src/main/res/mipmap-${e.key}/ic_launcher.png',
      render(e.value, rounded: true),
    );
  }

  // Web: regular and maskable (full-bleed, content inside the safe zone).
  _write('web/icons/Icon-192.png', render(192, rounded: true));
  _write('web/icons/Icon-512.png', render(512, rounded: true));
  _write('web/icons/Icon-maskable-192.png', render(192, rounded: false));
  _write('web/icons/Icon-maskable-512.png', render(512, rounded: false));
  _write('web/favicon.png', render(64, rounded: true));
  stdout.writeln('Icons written.');
}

void _write(String path, img.Image image) =>
    File(path).writeAsBytesSync(img.encodePng(image));

/// Draws at 4x and downsamples for smooth edges.
img.Image render(int size, {required bool rounded, bool opaque = false}) {
  const ss = 4;
  final s = size * ss;
  final image = img.Image(width: s, height: s, numChannels: 4);
  final radius = rounded ? s * 0.26 : 0.0;

  bool inside(int x, int y) {
    if (radius == 0) return true;
    final cx = x < radius
        ? radius
        : (x > s - radius ? s - radius : x.toDouble());
    final cy = y < radius
        ? radius
        : (y > s - radius ? s - radius : y.toDouble());
    return pow(x - cx, 2) + pow(y - cy, 2) <= radius * radius;
  }

  for (final p in image) {
    if (!inside(p.x, p.y)) {
      p.a = opaque ? 255 : 0;
      continue;
    }
    final t = (p.x + p.y) / (2 * s);
    p
      ..r = top.$1 + (bottom.$1 - top.$1) * t
      ..g = top.$2 + (bottom.$2 - top.$2) * t
      ..b = top.$3 + (bottom.$3 - top.$3) * t
      ..a = 255;
  }

  // Viewfinder corners with round caps.
  final white = img.ColorRgba8(255, 255, 255, 255);
  final stroke = s * 0.075;
  final inset = s * 0.24, len = s * 0.15;
  void line(double x0, double y0, double x1, double y1) {
    final steps = (sqrt(pow(x1 - x0, 2) + pow(y1 - y0, 2)) * 2).ceil();
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      img.fillCircle(
        image,
        x: (x0 + (x1 - x0) * t).round(),
        y: (y0 + (y1 - y0) * t).round(),
        radius: (stroke / 2).round(),
        color: white,
      );
    }
  }

  for (final (x, y, dx, dy) in [
    (inset, inset, 1, 1),
    (s - inset, inset, -1, 1),
    (inset, s - inset, 1, -1),
    (s - inset, s - inset, -1, -1),
  ]) {
    line(x, y, x + dx * len, y);
    line(x, y, x, y + dy * len);
  }

  // The spot, with a soft highlight.
  img.fillCircle(
    image,
    x: s ~/ 2,
    y: s ~/ 2,
    radius: (s * 0.12).round(),
    color: img.ColorRgba8(255, 138, 101, 255),
  );
  img.fillCircle(
    image,
    x: (s * 0.465).round(),
    y: (s * 0.465).round(),
    radius: (s * 0.035).round(),
    color: img.ColorRgba8(255, 255, 255, 180),
  );

  final out = img.copyResize(
    image,
    width: size,
    height: size,
    interpolation: img.Interpolation.average,
  );
  if (!opaque) return out;
  // Drop the alpha channel entirely for App Store icons.
  return out.convert(numChannels: 3);
}
