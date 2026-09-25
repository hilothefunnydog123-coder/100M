import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../theme/colors.dart';

/// Scrollable page content with comfortable padding, centered and width-
/// limited on tablets and the web.
class PageBody extends StatelessWidget {
  const PageBody({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 32),
    this.controller,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          controller: controller,
          padding: padding,
          children: children,
        ),
      ),
    );
  }
}

/// A bottom action area that stays above the keyboard and system insets.
class BottomActions extends StatelessWidget {
  const BottomActions({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.canvas,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 8,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.icon, this.trailing});

  final String text;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: c.inkMuted),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: c.inkMuted,
                letterSpacing: 0.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    return Material(
      color: color ?? c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
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

/// A list of short statements with a leading icon.
class IconList extends StatelessWidget {
  const IconList({
    super.key,
    required this.items,
    required this.icon,
    this.iconColor,
  });

  final List<String> items;
  final IconData icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        for (final item in items)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, size: 18, color: iconColor ?? c.brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// A small pill, e.g. for tags and statuses.
class Pill extends StatelessWidget {
  const Pill({super.key, required this.label, this.icon, this.fg, this.bg});

  final String label;
  final IconData? icon;
  final Color? fg;
  final Color? bg;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    final foreground = fg ?? c.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg ?? c.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded photo from bytes.
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({
    super.key,
    required this.bytes,
    this.size = 64,
    this.radius = 14,
  });

  final Uint8List? bytes;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: bytes == null
            ? ColoredBox(
                color: c.surfaceMuted,
                child: Icon(Icons.image_outlined, color: c.inkFaint),
              )
            : Image.memory(bytes!, fit: BoxFit.cover, gaplessPlayback: true),
      ),
    );
  }
}

/// A photo loaded from on-device history.
class StoredPhoto extends ConsumerWidget {
  const StoredPhoto({
    super.key,
    required this.photoKey,
    this.size = 64,
    this.radius = 14,
  });

  final String? photoKey;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = photoKey;
    final bytes = key == null
        ? null
        : ref.watch(storedPhotoProvider(key)).value;
    return PhotoThumb(bytes: bytes, size: size, radius: radius);
  }
}

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.pro.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 18, color: c.pro),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Demo result: a canned example, not an analysis of your photo.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: c.pro),
            ),
          ),
        ],
      ),
    );
  }
}

const medicalDisclaimer =
    'SpotCheck gives information, not a diagnosis, and it can be wrong. It '
    "doesn't replace a medical professional. If you're worried, or "
    'symptoms change or get worse, see a doctor.';

class DisclaimerText extends StatelessWidget {
  const DisclaimerText({super.key});

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: c.inkFaint),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              medicalDisclaimer,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: c.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}
