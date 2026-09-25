import 'package:flutter/material.dart';

import '../../theme/colors.dart';

/// The SpotCheck mark: a viewfinder framing a spot.
class SpotLogo extends StatelessWidget {
  const SpotLogo({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _LogoPainter(c.brand, c.brandInk)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.top, this.bottom);

  final Color top;
  final Color bottom;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rect = Offset.zero & size;
    final bg = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [top, bottom],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(s * 0.28)),
      bg,
    );

    // Viewfinder corners.
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.075
      ..strokeCap = StrokeCap.round;
    final inset = s * 0.24, len = s * 0.15;
    for (final (x, y, dx, dy) in [
      (inset, inset, 1.0, 1.0),
      (s - inset, inset, -1.0, 1.0),
      (inset, s - inset, 1.0, -1.0),
      (s - inset, s - inset, -1.0, -1.0),
    ]) {
      canvas
        ..drawLine(Offset(x, y), Offset(x + dx * len, y), stroke)
        ..drawLine(Offset(x, y), Offset(x, y + dy * len), stroke);
    }

    // The spot.
    final center = Offset(s / 2, s / 2);
    canvas
      ..drawCircle(center, s * 0.12, Paint()..color = const Color(0xFFFF8A65))
      ..drawCircle(
        center.translate(-s * 0.035, -s * 0.035),
        s * 0.035,
        Paint()..color = Colors.white.withValues(alpha: 0.7),
      );
  }

  @override
  bool shouldRepaint(_LogoPainter old) =>
      old.top != top || old.bottom != bottom;
}

class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SpotLogo(size: size),
        SizedBox(width: size * 0.3),
        Text(
          'SpotCheck',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: size * 0.62,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}
