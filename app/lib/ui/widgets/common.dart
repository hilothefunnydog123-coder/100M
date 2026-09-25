import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../theme/theme.dart';

/// Money in the condensed display face with tabular figures.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.cents, {
    super.key,
    this.size = 17,
    this.weight = FontWeight.w700,
    this.color,
    this.prefix = '',
  });

  final int cents;
  final double size;
  final FontWeight weight;
  final Color? color;
  final String prefix;

  @override
  Widget build(BuildContext context) => Text(
    '$prefix${Money.format(cents)}',
    maxLines: 1,
    style: TextStyle(
      fontFamily: numberFont,
      fontSize: size,
      fontWeight: weight,
      height: 1.1,
      color: color ?? JobColors.of(context).ink,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.quote, {super.key});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final tone = JobColors.of(context).forStatus(quote.status);
    final views = quote.response.views;
    final label = quote.status == QuoteStatus.viewed && views > 1
        ? 'Viewed $views×'
        : quote.status.label;
    return Pill(label, tone: tone);
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, required this.tone, this.icon});

  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: tone.bg,
      borderRadius: BorderRadius.circular(7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: tone.fg),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tone.fg,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    ),
  );
}

/// Small uppercase heading for a group of content.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding});

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding ?? const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: JobColors.of(context).inkFaint,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// The orange mark: a square with a diamond, like a site marker.
class LogoMark extends StatelessWidget {
  const LogoMark({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Transform.rotate(
        angle: 0.785398,
        child: Container(
          width: size * 0.36,
          height: size * 0.36,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: size * 0.09),
            borderRadius: BorderRadius.circular(size * 0.07),
          ),
        ),
      ),
    );
  }
}

/// A job photo from local storage, cropped to fill.
class PhotoThumb extends ConsumerWidget {
  const PhotoThumb(
    this.photoKey, {
    super.key,
    this.size = 56,
    this.radius = 12,
    this.width,
    this.height,
  });

  final String photoKey;
  final double size;
  final double radius;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(storedPhotoProvider(photoKey)).value;
    final c = JobColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: width ?? size,
        height: height ?? size,
        color: c.surfaceMuted,
        child: bytes == null
            ? null
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                cacheWidth: ((width ?? size) * 3).round(),
              ),
      ),
    );
  }
}

/// A placeholder square when a quote has no photos.
class JobIcon extends StatelessWidget {
  const JobIcon({super.key, this.size = 56});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.description_outlined, color: c.inkMuted),
    );
  }
}

/// A rounded white card with the app's border.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    return Material(
      color: color ?? c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor ?? c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Digits and one decimal point, for quantities, hours, and money.
final decimalInput = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,$]'))];

double? parseNumber(String text) {
  final cleaned = text.replaceAll(RegExp(r'[,$\s]'), '');
  if (cleaned.isEmpty) return null;
  final v = double.tryParse(cleaned);
  return v == null || v.isNaN || v.isInfinite || v < 0 ? null : v;
}

/// "$4,850" style for editing: no symbol, cents only when present.
String moneyInputText(int cents) =>
    Money.format(cents).replaceFirst(r'$', '').replaceAll(',', '');

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Standard sheet with a title and scrollable content above the keyboard.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: builder(context),
  ),
);

/// Title row used at the top of sheets.
class SheetHeader extends StatelessWidget {
  const SheetHeader(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.headlineSmall),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: text.bodySmall),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
