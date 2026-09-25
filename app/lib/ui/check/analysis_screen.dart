import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

import '../../data/models.dart';
import '../../services/analysis_service.dart';
import '../../services/launcher.dart';
import '../../services/photos.dart';
import '../../state/check_flow.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../result/result_view.dart';
import '../widgets/common.dart';

enum AnalysisOutcome { retake, done }

/// Runs the analysis with a progress animation, then shows the result.
class AnalysisScreen extends ConsumerStatefulWidget {
  const AnalysisScreen({super.key});

  @override
  ConsumerState<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends ConsumerState<AnalysisScreen> {
  late final CheckDraft _draft = ref.read(checkFlowProvider);
  CheckResult? _result;
  CheckRecord? _record;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    setState(() {
      _error = null;
      _result = null;
    });
    try {
      final result = await ref
          .read(analysisServiceProvider)
          .analyze(_draft.toRequest());
      CheckRecord? record;
      if (result.status == CheckStatus.complete) {
        record = await _save(result);
      }
      if (mounted) {
        setState(() {
          _result = result;
          _record = record;
        });
      }
    } on AnalysisError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    }
  }

  Future<CheckRecord> _save(CheckResult result) async {
    final history = ref.read(historyProvider.notifier);
    final previous = _draft.followUpOf == null
        ? null
        : history.byId(_draft.followUpOf!);
    final record = CheckRecord(
      id: result.id,
      createdAt: result.createdAt,
      site: _draft.site!,
      answers: _draft.answers,
      note: _draft.note.trim(),
      result: result,
      photoKeys: [
        for (var i = 0; i < _draft.photos.length; i++) '${result.id}_$i',
      ],
      followUpOf: previous?.id,
      // Keep tracking a spot the person was already tracking.
      recheckDue: previous?.tracking == true
          ? DateTime.now().add(const Duration(days: 14))
          : null,
    );
    await history.add(record, [
      for (final p in _draft.photos) await historyCopy(p.jpeg),
    ]);
    if (previous != null && previous.tracking) {
      await history.replace(previous.copyWith(recheckDue: () => null));
    }
    await ref.read(settingsProvider.notifier).recordCheckUsed();
    return record;
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final closeUp = _draft.photoOfKind(PhotoKind.closeUp);

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: PageBody(
          children: [
            const SizedBox(height: 40),
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: SpotColors.of(context).inkFaint,
            ),
            const SizedBox(height: 16),
            Text(
              "We couldn't finish the analysis",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        bottomNavigationBar: BottomActions(
          children: [
            FilledButton(onPressed: _run, child: const Text('Try again')),
          ],
        ),
      );
    }

    if (result == null) {
      return PopScope(
        canPop: false,
        child: Scaffold(body: _Analyzing(photo: closeUp)),
      );
    }

    final record = _record;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(AnalysisOutcome.done);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Your result'),
          actions: [
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(AnalysisOutcome.done),
            ),
          ],
        ),
        body: ResultView(
          result: result,
          site: _draft.site!,
          photo: closeUp == null ? null : PhotoThumb(bytes: closeUp.jpeg),
          extra: [
            if (record != null) ...[
              const SizedBox(height: 20),
              _ResultActions(record: record),
            ],
          ],
        ),
        bottomNavigationBar: BottomActions(
          children: [
            if (result.status == CheckStatus.retake)
              FilledButton.icon(
                onPressed: () =>
                    Navigator.of(context).pop(AnalysisOutcome.retake),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Retake photos'),
              )
            else
              FilledButton(
                onPressed: () =>
                    Navigator.of(context).pop(AnalysisOutcome.done),
                child: const Text('Done'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Share, track, and find care, for a saved result.
class _ResultActions extends ConsumerWidget {
  const _ResultActions({required this.record});

  final CheckRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(
      historyProvider.select(
        (list) => list.where((r) => r.id == record.id).firstOrNull,
      ),
    );
    return ResultActions(record: live ?? record);
  }
}

class ResultActions extends ConsumerWidget {
  const ResultActions({super.key, required this.record});

  final CheckRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        OutlinedButton.icon(
          onPressed: () => shareText(
            formatDoctorSummary(
              site: record.site,
              answers: record.answers,
              result: record.result,
              note: record.note,
            ),
            subject: 'SpotCheck summary',
          ),
          icon: const Icon(Icons.ios_share),
          label: const Text('Share summary with a doctor'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final tracking = !record.tracking;
            await ref
                .read(historyProvider.notifier)
                .replace(
                  record.copyWith(
                    recheckDue: () => tracking
                        ? DateTime.now().add(const Duration(days: 14))
                        : null,
                  ),
                );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    tracking
                        ? "We'll remind you to recheck in 2 weeks."
                        : 'Stopped tracking this spot.',
                  ),
                ),
              );
            }
          },
          icon: Icon(
            record.tracking ? Icons.event_busy_outlined : Icons.event_repeat,
          ),
          label: Text(
            record.tracking ? 'Stop tracking this spot' : 'Track this spot',
          ),
        ),
      ],
    );
  }
}

class _Analyzing extends StatefulWidget {
  const _Analyzing({required this.photo});

  final DraftPhoto? photo;

  @override
  State<_Analyzing> createState() => _AnalyzingState();
}

class _AnalyzingState extends State<_Analyzing>
    with SingleTickerProviderStateMixin {
  static const _steps = [
    'Checking photo quality',
    "Describing what's visible",
    'Comparing possibilities',
    'Weighing urgency with safety rules',
    'Writing your summary',
  ];

  late final _scan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);
  Timer? _timer;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (_step < _steps.length - 1) setState(() => _step++);
    });
  }

  @override
  void dispose() {
    _scan.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    final text = Theme.of(context).textTheme;
    const size = 200.0;
    return SafeArea(
      child: PageBody(
        padding: const EdgeInsets.fromLTRB(28, 48, 28, 32),
        children: [
          Center(
            child: SizedBox.square(
              dimension: size,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (widget.photo != null)
                      Image.memory(widget.photo!.jpeg, fit: BoxFit.cover)
                    else
                      ColoredBox(color: c.surfaceMuted),
                    AnimatedBuilder(
                      animation: _scan,
                      builder: (_, _) => Align(
                        alignment: Alignment(0, _scan.value * 2 - 1),
                        child: Container(
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                c.brand.withValues(alpha: 0),
                                c.brand.withValues(alpha: 0.45),
                                c.brand.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: c.brand, width: 3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Analyzing your photo',
            textAlign: TextAlign.center,
            style: text.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'This usually takes under a minute.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: 28),
          for (final (i, label) in _steps.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: 22,
                    child: i < _step
                        ? Icon(Icons.check_circle, color: c.brand, size: 22)
                        : i == _step
                        ? const Padding(
                            padding: EdgeInsets.all(2),
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : Icon(
                            Icons.radio_button_unchecked,
                            color: c.line,
                            size: 22,
                          ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    label,
                    style: text.bodyMedium?.copyWith(
                      color: i <= _step ? c.ink : c.inkFaint,
                      fontWeight: i == _step ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
