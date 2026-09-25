import 'package:flutter/material.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

/// A foreground and a tinted background for a status or a callout.
@immutable
class Tone {
  const Tone(this.fg, this.bg);

  final Color fg;
  final Color bg;

  static Tone lerp(Tone a, Tone b, double t) =>
      Tone(Color.lerp(a.fg, b.fg, t)!, Color.lerp(a.bg, b.bg, t)!);
}

/// Jobwalk's colors, available via `JobColors.of(context)`.
@immutable
class JobColors extends ThemeExtension<JobColors> {
  const JobColors({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.paper,
    required this.ink,
    required this.inkMuted,
    required this.inkFaint,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.accentInk,
    required this.ok,
    required this.warn,
    required this.info,
    required this.danger,
    required this.neutral,
  });

  /// App background.
  final Color canvas;
  final Color surface;
  final Color surfaceMuted;

  /// The quote document.
  final Color paper;
  final Color ink;
  final Color inkMuted;
  final Color inkFaint;
  final Color line;

  /// Safety orange: primary actions only.
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color accentInk;
  final Tone ok;
  final Tone warn;
  final Tone info;
  final Tone danger;
  final Tone neutral;

  static JobColors of(BuildContext context) =>
      Theme.of(context).extension<JobColors>()!;

  Tone forStatus(QuoteStatus s) => switch (s) {
    QuoteStatus.draft => neutral,
    QuoteStatus.sent => info,
    QuoteStatus.viewed => warn,
    QuoteStatus.approved => ok,
    QuoteStatus.declined => danger,
  };

  static const light = JobColors(
    canvas: Color(0xFFF3F1EC),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEAE7E0),
    paper: Color(0xFFFFFFFF),
    ink: Color(0xFF16181C),
    inkMuted: Color(0xFF5B616B),
    inkFaint: Color(0xFF8A9099),
    line: Color(0xFFE2DED5),
    accent: Color(0xFFF2541B),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFFFEDE4),
    accentInk: Color(0xFFB23A0B),
    ok: Tone(Color(0xFF15704A), Color(0xFFE6F4EC)),
    warn: Tone(Color(0xFF8A4B00), Color(0xFFFFF1DC)),
    info: Tone(Color(0xFF2252B0), Color(0xFFE8EFFC)),
    danger: Tone(Color(0xFFB42318), Color(0xFFFDEEEC)),
    neutral: Tone(Color(0xFF5B616B), Color(0xFFEAE7E0)),
  );

  static const dark = JobColors(
    canvas: Color(0xFF0F1114),
    surface: Color(0xFF181B20),
    surfaceMuted: Color(0xFF22262D),
    paper: Color(0xFF1C1F25),
    ink: Color(0xFFF3F1EC),
    inkMuted: Color(0xFFABB0B8),
    inkFaint: Color(0xFF7D838D),
    line: Color(0xFF2C3139),
    accent: Color(0xFFFF6431),
    onAccent: Color(0xFF1A0A03),
    accentSoft: Color(0xFF3A1E12),
    accentInk: Color(0xFFFF9C75),
    ok: Tone(Color(0xFF5FD39C), Color(0xFF112C1F)),
    warn: Tone(Color(0xFFF7B964), Color(0xFF33230D)),
    info: Tone(Color(0xFF8CB0FF), Color(0xFF15213A)),
    danger: Tone(Color(0xFFFF8E84), Color(0xFF3A1614)),
    neutral: Tone(Color(0xFFABB0B8), Color(0xFF22262D)),
  );

  @override
  JobColors copyWith() => this;

  @override
  JobColors lerp(covariant JobColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return JobColors(
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      paper: c(paper, other.paper),
      ink: c(ink, other.ink),
      inkMuted: c(inkMuted, other.inkMuted),
      inkFaint: c(inkFaint, other.inkFaint),
      line: c(line, other.line),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      accentSoft: c(accentSoft, other.accentSoft),
      accentInk: c(accentInk, other.accentInk),
      ok: Tone.lerp(ok, other.ok, t),
      warn: Tone.lerp(warn, other.warn, t),
      info: Tone.lerp(info, other.info, t),
      danger: Tone.lerp(danger, other.danger, t),
      neutral: Tone.lerp(neutral, other.neutral, t),
    );
  }
}
