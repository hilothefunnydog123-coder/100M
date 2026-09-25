// Generates the synthetic sample photos used by demo mode:
//   dart run tool/generate_samples.dart
//
// They are procedurally drawn (no real patient images) so the app can be
// demoed on the web or in a simulator without a camera.
import 'dart:io';
import 'dart:math';

import 'package:image/image.dart' as img;

const size = 1200;

void main() {
  File(
    'assets/samples/mole.jpg',
  ).writeAsBytesSync(img.encodeJpg(mole(), quality: 90));
  File(
    'assets/samples/rash.jpg',
  ).writeAsBytesSync(img.encodeJpg(rash(), quality: 90));
  stdout.writeln('Wrote assets/samples/{mole,rash}.jpg');
}

/// Smooth random field in [-1, 1] from bilinear-interpolated lattice noise.
double Function(double, double) smoothNoise(Random r, int cells) {
  final grid = List.generate(
    cells + 2,
    (_) => List.generate(cells + 2, (_) => r.nextDouble() * 2 - 1),
  );
  return (x, y) {
    final gx = x * cells, gy = y * cells;
    final x0 = gx.floor(), y0 = gy.floor();
    final fx = gx - x0, fy = gy - y0;
    double s(double t) => t * t * (3 - 2 * t);
    final a = grid[y0][x0], b = grid[y0][x0 + 1];
    final c = grid[y0 + 1][x0], d = grid[y0 + 1][x0 + 1];
    final top = a + (b - a) * s(fx), bottom = c + (d - c) * s(fx);
    return top + (bottom - top) * s(fy);
  };
}

img.Image skin(Random r, {List<int> base = const [226, 176, 146]}) {
  final image = img.Image(width: size, height: size);
  final blotch = smoothNoise(r, 6);
  final fine = smoothNoise(r, 60);
  for (final p in image) {
    final u = p.x / size, v = p.y / size;
    // Soft light from the top left.
    final light = 1.06 - 0.14 * sqrt(pow(u - 0.2, 2) + pow(v - 0.15, 2));
    final tone = 1 + 0.035 * blotch(u, v) + 0.02 * fine(u, v);
    final grain = (r.nextDouble() - 0.5) * 7;
    p
      ..r = (base[0] * light * tone + grain).clamp(0, 255)
      ..g = (base[1] * light * tone + grain).clamp(0, 255)
      ..b = (base[2] * light * tone + grain).clamp(0, 255);
  }
  // Pores and fine hairs.
  for (var i = 0; i < 1400; i++) {
    final x = r.nextInt(size), y = r.nextInt(size);
    final px = image.getPixel(x, y);
    img.fillCircle(
      image,
      x: x,
      y: y,
      radius: r.nextInt(2) + 1,
      color: img.ColorRgb8(
        (px.r * 0.9).toInt(),
        (px.g * 0.86).toInt(),
        (px.b * 0.84).toInt(),
      ),
    );
  }
  return image;
}

img.Image mole() {
  final r = Random(11);
  final image = skin(r);
  const cx = size * 0.52, cy = size * 0.5, r0 = size * 0.1;
  final texture = smoothNoise(r, 14);
  for (final p in image) {
    final dx = p.x - cx, dy = p.y - cy;
    final theta = atan2(dy, dx);
    // Irregular, slightly asymmetric border.
    final radius =
        r0 *
        (1 +
            0.09 * sin(3 * theta + 1) +
            0.05 * sin(5 * theta + 2) +
            0.03 * sin(9 * theta));
    final dist = sqrt(dx * dx + dy * dy);
    final edge = ((radius - dist) / 5).clamp(0.0, 1.0);
    if (edge <= 0) continue;
    // Two shades of brown: darker on the left side.
    final side = ((dx / r0) + 1) / 2;
    final t = texture(p.x / size, p.y / size) * 10;
    final mr = 88 + 55 * side + t,
        mg = 56 + 38 * side + t,
        mb = 40 + 24 * side + t;
    p
      ..r = p.r * (1 - edge) + mr * edge
      ..g = p.g * (1 - edge) + mg * edge
      ..b = p.b * (1 - edge) + mb * edge;
  }
  return img.gaussianBlur(image, radius: 1);
}

img.Image rash() {
  final r = Random(23);
  final image = skin(r, base: const [220, 168, 138]);
  final field = smoothNoise(r, 7);
  final spots = smoothNoise(r, 40);
  for (final p in image) {
    final u = p.x / size, v = p.y / size;
    final centerFalloff = 1 - sqrt(pow(u - 0.5, 2) + pow(v - 0.52, 2)) * 2.1;
    final intensity = (centerFalloff + 0.55 * field(u, v) + 0.25 * spots(u, v))
        .clamp(0.0, 1.0);
    if (intensity <= 0.05) continue;
    final a = 0.62 * intensity;
    p
      ..r = p.r * (1 - a) + 206 * a
      ..g = p.g * (1 - a) + 96 * a
      ..b = p.b * (1 - a) + 92 * a;
    // Fine dry scale on the most inflamed areas.
    if (intensity > 0.5 && r.nextDouble() < 0.012) {
      img.fillCircle(
        image,
        x: p.x,
        y: p.y,
        radius: 1 + r.nextInt(2),
        color: img.ColorRgb8(236, 214, 204),
      );
    }
  }
  return img.gaussianBlur(image, radius: 1);
}
