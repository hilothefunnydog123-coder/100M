import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import '../../services/api.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../account/plans_sheet.dart';
import '../quote/quote_screen.dart';
import 'capture_screen.dart';

enum _Phase { working, unusable, failed }

/// Waits for the draft, then opens the new quote.
class BuildingScreen extends ConsumerStatefulWidget {
  const BuildingScreen({super.key, required this.capture});

  final CaptureResult capture;

  @override
  ConsumerState<BuildingScreen> createState() => _BuildingScreenState();
}

class _BuildingScreenState extends ConsumerState<BuildingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();
  final _watch = Stopwatch();
  Timer? _ticker;
  var _phase = _Phase.working;
  var _message = '';
  var _retryable = true;
  var _upgrade = false;
  var _attempt = 0;

  /// One key for this set of photos: if the phone gives up waiting and
  /// retries, the server returns the draft it already made.
  final _idempotencyKey = newId('draft', length: 24);

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  @override
  void dispose() {
    _attempt = -1;
    _ticker?.cancel();
    _scan.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final attempt = ++_attempt;
    setState(() => _phase = _Phase.working);
    if (!_scan.isAnimating) unawaited(_scan.repeat());
    _watch
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => mounted ? setState(() {}) : null,
    );
    final capture = widget.capture;
    final settings = ref.read(settingsProvider);
    try {
      final result = await ref
          .read(clientProvider)
          .draft(
            DraftRequest(
              profile: settings.profile,
              rates: settings.rates,
              note: capture.note,
              photos: [
                for (final p in capture.photos)
                  JobPhoto(bytes: p.jpeg, mediaType: 'image/jpeg'),
              ],
            ),
            sample: capture.sample,
            idempotencyKey: _idempotencyKey,
          );
      if (attempt != _attempt || !mounted) return;
      if (!result.draft.isUsable) {
        _finish(
          _Phase.unusable,
          result.draft.retakeAdvice.isEmpty
              ? "Jobwalk couldn't see enough of the job to quote it. Take "
                    'wider photos in good light.'
              : result.draft.retakeAdvice,
        );
        return;
      }
      final now = ref.read(clockProvider)();
      final id = newId('q');
      final number = await ref.read(settingsProvider.notifier).takeNumber();
      final quote = QuoteBuilder.fromDraft(
        result.draft,
        id: id,
        number: number,
        rates: ref.read(settingsProvider).rates,
        now: now,
        customer: capture.customer,
        photoKeys: [for (var i = 0; i < capture.photos.length; i++) '${id}_$i'],
        model: result.model,
        demo: result.demo,
      );
      await ref
          .read(quotesProvider.notifier)
          .add(quote, photos: [for (final p in capture.photos) p.preview]);
      if (attempt != _attempt || !mounted) return;
      _ticker?.cancel();
      await Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => QuoteScreen(quoteId: id)),
        (route) => route.isFirst,
      );
    } on ApiError catch (e) {
      if (attempt != _attempt || !mounted) return;
      _retryable = e.retryable;
      _upgrade = e.code == 'upgrade_required';
      _finish(_Phase.failed, e.message);
    }
  }

  void _finish(_Phase phase, String message) {
    _ticker?.cancel();
    _watch.stop();
    _scan.stop();
    setState(() {
      _phase = phase;
      _message = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final photos = widget.capture.photos;
    const onDark = Color(0xFFF3F1EC);
    const onDarkMuted = Color(0xFFA9AEB6);

    return Scaffold(
      backgroundColor: const Color(0xFF121418),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121418),
        foregroundColor: onDark,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.memory(photos.first.preview, fit: BoxFit.cover),
                    if (_phase == _Phase.working)
                      AnimatedBuilder(
                        animation: _scan,
                        builder: (context, _) => CustomPaint(
                          painter: _ScanPainter(_scan.value, c.accent),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (photos.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 54,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: photos.length - 1,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      photos[i + 1].preview,
                      width: 72,
                      height: 54,
                      fit: BoxFit.cover,
                      cacheWidth: 216,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 28),
            ...switch (_phase) {
              _Phase.working => [
                Text(
                  'Measuring and pricing',
                  style: text.headlineMedium?.copyWith(color: onDark),
                ),
                const SizedBox(height: 10),
                Text(
                  'Jobwalk measures the job from your photos, estimates '
                  'hours and materials, then prices it with your rates. '
                  'Usually under a minute.',
                  style: text.bodyLarge?.copyWith(color: onDarkMuted),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: c.accent,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      formatElapsed(_watch.elapsed),
                      style: text.titleMedium?.copyWith(color: onDark),
                    ),
                  ],
                ),
              ],
              _Phase.unusable => [
                Text(
                  "These photos won't work",
                  style: text.headlineMedium?.copyWith(color: onDark),
                ),
                const SizedBox(height: 10),
                Text(
                  _message,
                  style: text.bodyLarge?.copyWith(color: onDarkMuted),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Retake photos'),
                ),
              ],
              _Phase.failed => [
                Text(
                  "Couldn't build the quote",
                  style: text.headlineMedium?.copyWith(color: onDark),
                ),
                const SizedBox(height: 10),
                Text(
                  _message,
                  style: text.bodyLarge?.copyWith(color: onDarkMuted),
                ),
                const SizedBox(height: 24),
                if (_upgrade)
                  FilledButton(
                    onPressed: () async {
                      await showPlans(context);
                      // Paid on Stripe and came back: pick up the plan.
                      try {
                        await ref.read(sessionProvider.notifier).refresh();
                      } on ApiError {
                        return;
                      }
                      final plan = ref
                          .read(sessionProvider)
                          .account
                          ?.business
                          .plan;
                      if (plan != null && plan.paid && mounted) {
                        unawaited(_run());
                      }
                    },
                    child: const Text('See plans'),
                  )
                else if (_retryable)
                  FilledButton(onPressed: _run, child: const Text('Try again')),
                const SizedBox(height: 10),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: onDark,
                    side: const BorderSide(
                      color: Color(0xFF3A3F47),
                      width: 1.5,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back to photos'),
                ),
              ],
            },
          ],
        ),
      ),
    );
  }
}

/// A bright line sweeping down the photo, like a scanner.
class _ScanPainter extends CustomPainter {
  _ScanPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * t;
    final glow = Rect.fromLTWH(0, y - 60, size.width, 60);
    canvas
      ..drawRect(
        glow,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0), color.withValues(alpha: 0.28)],
          ).createShader(glow),
      )
      ..drawRect(
        Rect.fromLTWH(0, y - 1.5, size.width, 3),
        Paint()..color = color,
      );
  }

  @override
  bool shouldRepaint(_ScanPainter old) => old.t != t;
}
