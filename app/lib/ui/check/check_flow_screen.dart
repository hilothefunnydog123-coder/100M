import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

import '../../data/models.dart';
import '../../services/photos.dart';
import '../../state/check_flow.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../widgets/common.dart';
import '../widgets/options.dart';
import 'analysis_screen.dart';
import 'emergency_screen.dart';

enum _Step { site, person, photos, questions, note }

IconData siteIcon(BodySite site) => switch (site) {
  BodySite.face => Icons.face_outlined,
  BodySite.scalp => Icons.face_4_outlined,
  BodySite.eye => Icons.remove_red_eye_outlined,
  BodySite.mouth => Icons.sentiment_satisfied_outlined,
  BodySite.neck => Icons.person_outline,
  BodySite.torso => Icons.accessibility_new,
  BodySite.back => Icons.man_outlined,
  BodySite.arm => Icons.fitness_center,
  BodySite.hand => Icons.back_hand_outlined,
  BodySite.leg => Icons.directions_walk,
  BodySite.foot => Icons.directions_run,
  BodySite.nail => Icons.pan_tool_alt_outlined,
};

/// The guided flow: where → who → photos → questions → note → analysis.
///
/// Callers reset the draft with `checkFlowProvider.notifier.start()` before
/// pushing this screen (see `startCheck`).
class CheckFlowScreen extends ConsumerStatefulWidget {
  const CheckFlowScreen({super.key, this.recheckOf});

  final CheckRecord? recheckOf;

  @override
  ConsumerState<CheckFlowScreen> createState() => _CheckFlowScreenState();
}

class _CheckFlowScreenState extends ConsumerState<CheckFlowScreen> {
  late _Step _step;
  int _questionIndex = 0;
  Timer? _advance;

  @override
  void initState() {
    super.initState();
    _step = widget.recheckOf == null ? _Step.site : _Step.photos;
  }

  @override
  void dispose() {
    _advance?.cancel();
    super.dispose();
  }

  CheckFlowNotifier get _flow => ref.read(checkFlowProvider.notifier);

  void _goTo(_Step step, {int question = 0}) => setState(() {
    _step = step;
    _questionIndex = question;
  });

  void _next() {
    final draft = ref.read(checkFlowProvider);
    switch (_step) {
      case _Step.site:
        _goTo(_Step.person);
      case _Step.person:
        _goTo(_Step.photos);
      case _Step.photos:
        _goTo(draft.questions.isEmpty ? _Step.note : _Step.questions);
      case _Step.questions:
        if (_questionIndex + 1 < draft.questions.length) {
          setState(() => _questionIndex++);
        } else {
          _goTo(_Step.note);
        }
      case _Step.note:
        unawaited(_analyze());
    }
  }

  bool _back() {
    final draft = ref.read(checkFlowProvider);
    switch (_step) {
      case _Step.site:
        return true;
      case _Step.person:
        _goTo(_Step.site);
      case _Step.photos:
        if (widget.recheckOf != null) return true;
        _goTo(_Step.person);
      case _Step.questions:
        if (_questionIndex > 0) {
          setState(() => _questionIndex--);
        } else {
          _goTo(_Step.photos);
        }
      case _Step.note:
        final n = draft.questions.length;
        n == 0 ? _goTo(_Step.photos) : _goTo(_Step.questions, question: n - 1);
    }
    return false;
  }

  Future<void> _analyze() async {
    final draft = ref.read(checkFlowProvider);
    final safety = SafetyRules.evaluate(draft.site!, draft.answers);
    if (safety.isEmergency) {
      final proceed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => EmergencyScreen(safety: safety)),
      );
      if (proceed != true || !mounted) return;
    }
    final outcome = await Navigator.of(context).push<AnalysisOutcome>(
      MaterialPageRoute(builder: (_) => const AnalysisScreen()),
    );
    if (!mounted) return;
    switch (outcome) {
      case AnalysisOutcome.retake:
        _goTo(_Step.photos);
      case AnalysisOutcome.done:
        Navigator.of(context).pop();
      case null:
        break;
    }
  }

  double _progress(CheckDraft draft) {
    final q = draft.questions.length;
    final total = 4 + q;
    final done = switch (_step) {
      _Step.site => 0,
      _Step.person => 1,
      _Step.photos => 2,
      _Step.questions => 3 + _questionIndex,
      _Step.note => 3 + q,
    };
    return (done + 1) / (total + 1);
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(checkFlowProvider);
    final questions = draft.questions;
    // Follow-up questions can disappear when an earlier answer changes.
    if (_step == _Step.questions && _questionIndex >= questions.length) {
      _questionIndex = questions.isEmpty ? 0 : questions.length - 1;
    }

    final Widget body;
    final Widget? actions;
    switch (_step) {
      case _Step.site:
        body = _SiteStep(
          selected: draft.site,
          onSelect: (site) {
            _flow.selectSite(site);
            _next();
          },
        );
        actions = null;
      case _Step.person:
        body = _PersonStep(
          forSelf: draft.forSelf,
          onSelect: (forSelf) {
            _flow.setForSelf(
              forSelf,
              ref.read(settingsProvider).profileAnswers,
            );
            _next();
          },
        );
        actions = null;
      case _Step.photos:
        body = _PhotosStep(draft: draft);
        actions = BottomActions(
          children: [
            FilledButton(
              onPressed: draft.photoOfKind(PhotoKind.closeUp) == null
                  ? null
                  : _next,
              child: const Text('Continue'),
            ),
          ],
        );
      case _Step.questions:
        final q = questions.isEmpty ? null : questions[_questionIndex];
        body = q == null
            ? const SizedBox.shrink()
            : _QuestionStep(
                key: ValueKey(q.id),
                question: q,
                index: _questionIndex,
                count: questions.length,
                answers: draft.answers,
                onToggle: (option) {
                  _flow.toggle(q, option);
                  if (q.kind == QuestionKind.single) {
                    _advance?.cancel();
                    _advance = Timer(const Duration(milliseconds: 260), () {
                      if (mounted && _step == _Step.questions) _next();
                    });
                  }
                },
              );
        final answered = q != null && draft.answers.isAnswered(q.id);
        actions = BottomActions(
          children: [
            FilledButton(
              onPressed: answered ? _next : null,
              child: const Text('Next'),
            ),
            if (q != null && q.optional && !answered)
              TextButton(onPressed: _next, child: const Text('Skip')),
          ],
        );
      case _Step.note:
        body = _NoteStep(draft: draft);
        final remaining = ref.watch(checksRemainingProvider);
        actions = BottomActions(
          children: [
            FilledButton.icon(
              onPressed: _next,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Analyze'),
            ),
            if (remaining != null)
              Center(
                child: Text(
                  remaining == 1
                      ? 'This uses your last free check'
                      : 'This uses 1 of your $remaining free checks',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        );
    }

    return PopScope(
      canPop:
          _step == _Step.site ||
          (_step == _Step.photos && widget.recheckOf != null),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_back()) Navigator.of(context).pop();
            },
          ),
          title: Text(draft.site?.label ?? 'New check'),
          actions: [
            IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 4),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _progress(draft)),
              duration: const Duration(milliseconds: 300),
              builder: (_, value, _) =>
                  LinearProgressIndicator(value: value, minHeight: 4),
            ),
          ),
        ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: KeyedSubtree(
            key: ValueKey('$_step-$_questionIndex'),
            child: body,
          ),
        ),
        bottomNavigationBar: actions,
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader(this.title, [this.subtitle]);

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: text.headlineSmall),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: text.bodyMedium?.copyWith(
                color: SpotColors.of(context).inkMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SiteStep extends StatelessWidget {
  const _SiteStep({required this.selected, required this.onSelect});

  final BodySite? selected;
  final ValueChanged<BodySite> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    final text = Theme.of(context).textTheme;
    return PageBody(
      children: [
        const _StepHeader('Where is it?'),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.98,
          children: [
            for (final site in BodySite.values)
              Material(
                color: selected == site ? c.brandSoft : c.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(
                    color: selected == site ? c.brand : c.line,
                    width: selected == site ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onSelect(site),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: c.brandSoft,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(siteIcon(site), color: c.brandInk),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          site.label,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          style: text.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text('Private or genital area?'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (_) => const _PrivateAreaSheet(),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrivateAreaSheet extends StatelessWidget {
  const _PrivateAreaSheet();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Intimate areas', style: text.titleLarge),
            const SizedBox(height: 10),
            Text(
              "For privacy and safety, SpotCheck doesn't analyze photos of "
              'genital or intimate areas. A doctor, urgent care, or sexual '
              'health clinic can help, and many offer confidential '
              'appointments or telehealth.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonStep extends ConsumerWidget {
  const _PersonStep({required this.forSelf, required this.onSelect});

  final bool? forSelf;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final profile = settings.profileAnswers;
    final age = IntakeCatalog.byId(
      Q.ageBand,
    )!.option(profile.single(Q.ageBand) ?? '')?.label;
    return PageBody(
      children: [
        const _StepHeader(
          'Who is this check for?',
          'Age and health details change what a spot is likely to be.',
        ),
        _ChoiceCard(
          icon: Icons.person_outline,
          title: 'Me',
          subtitle: age == null
              ? "We'll ask a couple of quick questions about you."
              : 'Using your profile ($age). Change it in Settings.',
          selected: forSelf == true,
          onTap: () => onSelect(true),
        ),
        const SizedBox(height: 12),
        _ChoiceCard(
          icon: Icons.family_restroom_outlined,
          title: 'Someone else',
          subtitle: 'A child, partner, or family member.',
          selected: forSelf == false,
          onTap: () => onSelect(false),
        ),
      ],
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      onTap: onTap,
      color: selected ? c.brandSoft : null,
      borderColor: selected ? c.brand : null,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: c.brandSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: c.brandInk),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                const SizedBox(height: 2),
                Text(subtitle, style: text.bodySmall),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: c.inkFaint),
        ],
      ),
    );
  }
}

class _PhotosStep extends ConsumerWidget {
  const _PhotosStep({required this.draft});

  final CheckDraft draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SpotColors.of(context);
    final isEye = draft.site?.domain == Domain.eye;
    final isMouth = draft.site?.domain == Domain.mouth;
    return PageBody(
      children: [
        const _StepHeader(
          'Take a clear photo',
          'Photo quality is the biggest factor in a useful result.',
        ),
        SurfaceCard(
          color: c.surfaceMuted,
          borderColor: Colors.transparent,
          child: IconList(
            icon: Icons.tips_and_updates_outlined,
            items: [
              'Use bright, even light. Daylight from a window is best.',
              'Hold steady about 10 cm (4 in) away and tap to focus.',
              if (isEye)
                'Look straight ahead with the eye wide open.'
              else if (isMouth)
                'Use the flashlight of another phone to light the inside.'
              else
                'Include some normal skin around the spot.',
              'No filters, zoom, or beauty mode.',
            ],
          ),
        ),
        const SizedBox(height: 16),
        _PhotoSlot(
          kind: PhotoKind.closeUp,
          title: 'Close-up',
          hint: 'Required. Fill most of the frame with the area.',
          photo: draft.photoOfKind(PhotoKind.closeUp),
        ),
        const SizedBox(height: 12),
        _PhotoSlot(
          kind: PhotoKind.context,
          title: 'Wider view',
          hint: 'Recommended. Shows where it is and the surrounding area.',
          photo: draft.photoOfKind(PhotoKind.context),
        ),
      ],
    );
  }
}

class _PhotoSlot extends ConsumerStatefulWidget {
  const _PhotoSlot({
    required this.kind,
    required this.title,
    required this.hint,
    required this.photo,
  });

  final PhotoKind kind;
  final String title;
  final String hint;
  final DraftPhoto? photo;

  @override
  ConsumerState<_PhotoSlot> createState() => _PhotoSlotState();
}

class _PhotoSlotState extends ConsumerState<_PhotoSlot> {
  bool _busy = false;

  Future<void> _choose() async {
    final demo = ref.read(configProvider).demoMode;
    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(context, PhotoOrigin.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(context, PhotoOrigin.library),
            ),
            if (demo)
              for (final sample in SamplePhoto.values)
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: Text(sample.label),
                  subtitle: const Text('Synthetic demo image'),
                  onTap: () => Navigator.pop(context, sample),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final bytes = switch (choice) {
        final SamplePhoto s => await s.load(),
        final PhotoOrigin o => await ref.read(photoSourceProvider).pick(o),
        _ => null,
      };
      if (bytes == null) return;
      final prepared = await processPhoto(bytes);
      ref
          .read(checkFlowProvider.notifier)
          .setPhoto(
            DraftPhoto(
              jpeg: prepared.jpeg,
              kind: widget.kind,
              quality: prepared.quality,
              sample: choice is SamplePhoto,
            ),
          );
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("That image couldn't be read. Try another photo."),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    final text = Theme.of(context).textTheme;
    final photo = widget.photo;

    if (_busy) {
      return SurfaceCard(
        child: SizedBox(
          height: 120,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text('Checking photo quality…', style: text.bodySmall),
              ],
            ),
          ),
        ),
      );
    }

    if (photo == null) {
      return SurfaceCard(
        onTap: _choose,
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.brandSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(Icons.add_a_photo_outlined, color: c.brandInk),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add ${widget.title.toLowerCase()}',
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(widget.hint, style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final problems = photo.quality.problems;
    final good = c.forUrgency(Urgency.selfCare);
    final warn = c.forUrgency(Urgency.soon);
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PhotoThumb(bytes: photo.jpeg, size: 84),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: text.titleSmall),
                    const SizedBox(height: 6),
                    if (problems.isEmpty)
                      Pill(
                        label: 'Looks good',
                        icon: Icons.check_circle,
                        fg: good.fg,
                        bg: good.bg,
                      )
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final p in problems)
                            Pill(
                              label: p.label,
                              icon: Icons.warning_amber_rounded,
                              fg: warn.fg,
                              bg: warn.bg,
                            ),
                        ],
                      ),
                    if (photo.sample) ...[
                      const SizedBox(height: 6),
                      Text('Synthetic sample', style: text.bodySmall),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Retake',
                icon: const Icon(Icons.refresh),
                onPressed: _choose,
              ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => ref
                    .read(checkFlowProvider.notifier)
                    .removePhoto(widget.kind),
              ),
            ],
          ),
          if (problems.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              problems.map((p) => p.tip).join(' '),
              style: text.bodySmall?.copyWith(color: warn.fg),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuestionStep extends StatelessWidget {
  const _QuestionStep({
    super.key,
    required this.question,
    required this.index,
    required this.count,
    required this.answers,
    required this.onToggle,
  });

  final IntakeQuestion question;
  final int index;
  final int count;
  final IntakeAnswers answers;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = SpotColors.of(context);
    return PageBody(
      children: [
        const SizedBox(height: 12),
        Text(
          'QUESTION ${index + 1} OF $count',
          style: text.labelSmall?.copyWith(color: c.brandInk),
        ),
        const SizedBox(height: 8),
        Text(question.prompt, style: text.headlineSmall),
        if (question.help != null) ...[
          const SizedBox(height: 8),
          Text(
            question.help!,
            style: text.bodyMedium?.copyWith(color: c.inkMuted),
          ),
        ],
        if (question.kind == QuestionKind.multi) ...[
          const SizedBox(height: 6),
          Text('Select all that apply.', style: text.bodySmall),
        ],
        const SizedBox(height: 20),
        QuestionOptions(
          question: question,
          answers: answers,
          onToggle: onToggle,
        ),
      ],
    );
  }
}

class _NoteStep extends ConsumerStatefulWidget {
  const _NoteStep({required this.draft});

  final CheckDraft draft;

  @override
  ConsumerState<_NoteStep> createState() => _NoteStepState();
}

class _NoteStepState extends ConsumerState<_NoteStep> {
  late final _controller = TextEditingController(text: widget.draft.note);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageBody(
      children: [
        const _StepHeader(
          'Anything else we should know?',
          'Optional. For example: what you have tried, what makes it better '
              'or worse, or anything unusual.',
        ),
        TextField(
          controller: _controller,
          maxLines: 5,
          minLines: 4,
          maxLength: CheckRequest.maxNoteLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'It started after I switched laundry detergent…',
          ),
          onChanged: ref.read(checkFlowProvider.notifier).setNote,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: 16,
              color: SpotColors.of(context).inkFaint,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Don't include names or other personal details.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
