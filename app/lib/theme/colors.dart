import 'package:flutter/material.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

/// Foreground, tinted background, and solid colors for one urgency level.
@immutable
class UrgencyPalette {
  const UrgencyPalette({
    required this.fg,
    required this.bg,
    required this.solid,
    required this.border,
  });

  final Color fg;
  final Color bg;
  final Color solid;
  final Color border;

  static UrgencyPalette lerp(UrgencyPalette a, UrgencyPalette b, double t) =>
      UrgencyPalette(
        fg: Color.lerp(a.fg, b.fg, t)!,
        bg: Color.lerp(a.bg, b.bg, t)!,
        solid: Color.lerp(a.solid, b.solid, t)!,
        border: Color.lerp(a.border, b.border, t)!,
      );
}

/// SpotCheck's semantic colors, available via `SpotColors.of(context)`.
@immutable
class SpotColors extends ThemeExtension<SpotColors> {
  const SpotColors({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.line,
    required this.brand,
    required this.brandInk,
    required this.brandSoft,
    required this.pro,
    required this.urgency,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color line;
  final Color brand;
  final Color brandInk;
  final Color brandSoft;
  final Color pro;
  final Map<Urgency, UrgencyPalette> urgency;

  static SpotColors of(BuildContext context) =>
      Theme.of(context).extension<SpotColors>()!;

  UrgencyPalette forUrgency(Urgency u) => urgency[u]!;

  static const light = SpotColors(
    canvas: Color(0xFFF4F6F8),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEEF1F4),
    ink: Color(0xFF0F1B2D),
    inkMuted: Color(0xFF55616F),
    inkFaint: Color(0xFF8A95A3),
    line: Color(0xFFE1E6EB),
    brand: Color(0xFF0B7A75),
    brandInk: Color(0xFF075A56),
    brandSoft: Color(0xFFE2F2F0),
    pro: Color(0xFF5B4BDB),
    urgency: {
      Urgency.emergency: UrgencyPalette(
        fg: Color(0xFFB42318),
        bg: Color(0xFFFEF3F2),
        solid: Color(0xFFD92D20),
        border: Color(0xFFFDA29B),
      ),
      Urgency.urgent: UrgencyPalette(
        fg: Color(0xFFB54708),
        bg: Color(0xFFFFF6ED),
        solid: Color(0xFFEC6A0C),
        border: Color(0xFFFEC49A),
      ),
      Urgency.soon: UrgencyPalette(
        fg: Color(0xFF8A5A04),
        bg: Color(0xFFFFFAEB),
        solid: Color(0xFFDB9A08),
        border: Color(0xFFFEDF89),
      ),
      Urgency.routine: UrgencyPalette(
        fg: Color(0xFF1D4ED8),
        bg: Color(0xFFEFF4FF),
        solid: Color(0xFF2E6BF0),
        border: Color(0xFFB2CCFF),
      ),
      Urgency.selfCare: UrgencyPalette(
        fg: Color(0xFF067647),
        bg: Color(0xFFECFDF3),
        solid: Color(0xFF12A15E),
        border: Color(0xFFA6F4C5),
      ),
    },
  );

  static const dark = SpotColors(
    canvas: Color(0xFF0C1117),
    surface: Color(0xFF151C24),
    surfaceMuted: Color(0xFF1D2630),
    ink: Color(0xFFE8EEF3),
    inkMuted: Color(0xFFA3AFBC),
    inkFaint: Color(0xFF6E7B89),
    line: Color(0xFF26313C),
    brand: Color(0xFF3CC4BC),
    brandInk: Color(0xFF7ADCD5),
    brandSoft: Color(0xFF12302F),
    pro: Color(0xFF9A8CFF),
    urgency: {
      Urgency.emergency: UrgencyPalette(
        fg: Color(0xFFFFA59E),
        bg: Color(0xFF3A1614),
        solid: Color(0xFFF04438),
        border: Color(0xFF7A271A),
      ),
      Urgency.urgent: UrgencyPalette(
        fg: Color(0xFFFDB57A),
        bg: Color(0xFF38200E),
        solid: Color(0xFFF38744),
        border: Color(0xFF7E3A0E),
      ),
      Urgency.soon: UrgencyPalette(
        fg: Color(0xFFFDD771),
        bg: Color(0xFF342808),
        solid: Color(0xFFF5B92B),
        border: Color(0xFF7A5A0B),
      ),
      Urgency.routine: UrgencyPalette(
        fg: Color(0xFF9CBDFF),
        bg: Color(0xFF14233F),
        solid: Color(0xFF5B8DEF),
        border: Color(0xFF26437A),
      ),
      Urgency.selfCare: UrgencyPalette(
        fg: Color(0xFF75E0A7),
        bg: Color(0xFF0E2A1D),
        solid: Color(0xFF32C47F),
        border: Color(0xFF155B3A),
      ),
    },
  );

  @override
  SpotColors copyWith() => this;

  @override
  SpotColors lerp(ThemeExtension<SpotColors>? other, double t) {
    if (other is! SpotColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return SpotColors(
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      inkFaint: c(inkFaint, other.inkFaint),
      line: c(line, other.line),
      brand: c(brand, other.brand),
      brandInk: c(brandInk, other.brandInk),
      brandSoft: c(brandSoft, other.brandSoft),
      pro: c(pro, other.pro),
      urgency: {
        for (final u in Urgency.values)
          u: UrgencyPalette.lerp(urgency[u]!, other.urgency[u]!, t),
      },
    );
  }
}

/// Representative swatches for the Fitzpatrick skin types in the intake.
const skinToneSwatches = {
  'fst1': Color(0xFFF6DDCC),
  'fst2': Color(0xFFEAC4A4),
  'fst3': Color(0xFFD29F79),
  'fst4': Color(0xFFAE7850),
  'fst5': Color(0xFF7B5034),
  'fst6': Color(0xFF4A2F22),
};
