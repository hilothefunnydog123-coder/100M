import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/options.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  static const _pages = 5;
  final _controller = PageController();
  int _page = 0;
  bool _understands = false;
  bool _eligible = false;
  IntakeAnswers _profile = IntakeAnswers.empty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int page) {
    setState(() => _page = page);
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish({required bool saveProfile}) async {
    final notifier = ref.read(settingsProvider.notifier);
    if (saveProfile && _profile.answeredQuestionIds.isNotEmpty) {
      await notifier.setProfile(_profile);
    }
    await notifier.completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    final consentPage = _page == 3;
    final profilePage = _page == _pages - 1;
    final canContinue = !consentPage || (_understands && _eligible);

    return Scaffold(
      appBar: AppBar(
        leading: _page == 0
            ? null
            : IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _go(_page - 1),
              ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < _pages; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 22 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i <= _page ? c.brand : c.line,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
        centerTitle: true,
        actions: [
          if (profilePage)
            TextButton(
              onPressed: () => _finish(saveProfile: false),
              child: const Text('Skip'),
            ),
        ],
      ),
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          const _WelcomePage(),
          const _HowItWorksPage(),
          const _PrivacyPage(),
          _ConsentPage(
            understands: _understands,
            eligible: _eligible,
            onUnderstands: (v) => setState(() => _understands = v),
            onEligible: (v) => setState(() => _eligible = v),
            emergencyNumber: ref.watch(
              settingsProvider.select((s) => s.emergencyNumber),
            ),
          ),
          _ProfilePage(
            answers: _profile,
            onChanged: (a) => setState(() => _profile = a),
          ),
        ],
      ),
      bottomNavigationBar: BottomActions(
        children: [
          FilledButton(
            onPressed: !canContinue
                ? null
                : profilePage
                ? () => _finish(saveProfile: true)
                : () => _go(_page + 1),
            child: Text(switch (_page) {
              0 => 'Get started',
              3 => 'I understand',
              4 => 'Continue',
              _ => 'Next',
            }),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: c.brand.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Icon(icon, size: 34, color: c.brand),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = SpotColors.of(context);
    return PageBody(
      children: [
        const SizedBox(height: 24),
        const Align(alignment: Alignment.centerLeft, child: SpotLogo(size: 76)),
        const SizedBox(height: 28),
        Text("Know what you're looking at.", style: text.displaySmall),
        const SizedBox(height: 14),
        Text(
          'Photograph a skin, eye, mouth, or nail concern. SpotCheck explains '
          'what it might be, how soon to get it checked, and what to do next.',
          style: text.bodyLarge?.copyWith(color: c.inkMuted),
        ),
        const SizedBox(height: 28),
        const IconList(
          icon: Icons.check_circle_outline,
          items: [
            'Results in about a minute',
            'Clear urgency: home care, a doctor visit, or urgent care',
            'Safety rules that flag emergencies instantly',
          ],
        ),
      ],
    );
  }
}

class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = SpotColors.of(context);
    Widget step(int n, IconData icon, String title, String body) => Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
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
                Text('$n. $title', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(body, style: text.bodyMedium?.copyWith(color: c.inkMuted)),
              ],
            ),
          ),
        ],
      ),
    );
    return PageBody(
      children: [
        const SizedBox(height: 24),
        Text('How it works', style: text.headlineMedium),
        const SizedBox(height: 28),
        step(
          1,
          Icons.photo_camera_outlined,
          'Take a clear photo',
          'Good light and a steady hand matter most. We check the photo '
              'before analyzing it.',
        ),
        step(
          2,
          Icons.checklist_rounded,
          'Answer a few questions',
          'How long, what changed, how it feels. Doctors rely on this as much '
              'as on the photo.',
        ),
        step(
          3,
          Icons.insights_outlined,
          'See possibilities and urgency',
          'What it might be, what to watch for, and whether to see a doctor, '
              'and how soon.',
        ),
      ],
    );
  }
}

class _PrivacyPage extends StatelessWidget {
  const _PrivacyPage();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = SpotColors.of(context);
    return PageBody(
      children: [
        const SizedBox(height: 24),
        const Align(
          alignment: Alignment.centerLeft,
          child: _Hero(icon: Icons.lock_outline),
        ),
        const SizedBox(height: 24),
        Text('Private by design', style: text.headlineMedium),
        const SizedBox(height: 12),
        Text(
          'Health photos are personal. Here is exactly what happens to yours.',
          style: text.bodyLarge?.copyWith(color: c.inkMuted),
        ),
        const SizedBox(height: 24),
        const IconList(
          icon: Icons.verified_user_outlined,
          items: [
            "Photos are analyzed and then discarded. They aren't stored on "
                'our servers.',
            'Your history stays on this phone. Delete it any time.',
            'No ads, and we never sell health data.',
          ],
        ),
      ],
    );
  }
}

class _ConsentPage extends StatelessWidget {
  const _ConsentPage({
    required this.understands,
    required this.eligible,
    required this.onUnderstands,
    required this.onEligible,
    required this.emergencyNumber,
  });

  final bool understands;
  final bool eligible;
  final ValueChanged<bool> onUnderstands;
  final ValueChanged<bool> onEligible;
  final String emergencyNumber;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = SpotColors.of(context);
    final red = c.forUrgency(Urgency.emergency);
    return PageBody(
      children: [
        const SizedBox(height: 24),
        const Align(
          alignment: Alignment.centerLeft,
          child: _Hero(icon: Icons.health_and_safety_outlined),
        ),
        const SizedBox(height: 24),
        Text('SpotCheck is not a doctor', style: text.headlineMedium),
        const SizedBox(height: 12),
        Text(
          'It gives information to help you decide what to do next. It can be '
          "wrong, and it can't examine you, order tests, or diagnose.",
          style: text.bodyLarge?.copyWith(color: c.inkMuted),
        ),
        const SizedBox(height: 24),
        OptionTile(
          multi: true,
          selected: understands,
          onTap: () => onUnderstands(!understands),
          label:
              'I understand SpotCheck gives information, not a diagnosis, '
              "and doesn't replace a medical professional.",
        ),
        const SizedBox(height: 10),
        OptionTile(
          multi: true,
          selected: eligible,
          onTap: () => onEligible(!eligible),
          label:
              "I'm 18 or older, or a parent or guardian checking for my child.",
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: red.bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.emergency_outlined, color: red.fg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'In an emergency, call $emergencyNumber now. Don\'t wait '
                  'for an app.',
                  style: text.bodyMedium?.copyWith(color: red.fg),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfilePage extends StatelessWidget {
  const _ProfilePage({required this.answers, required this.onChanged});

  final IntakeAnswers answers;
  final ValueChanged<IntakeAnswers> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = SpotColors.of(context);
    return PageBody(
      children: [
        const SizedBox(height: 24),
        Text('A little about you', style: text.headlineMedium),
        const SizedBox(height: 12),
        Text(
          "Optional. It's used when you check yourself, so you won't be "
          'asked every time. It stays on this phone.',
          style: text.bodyLarge?.copyWith(color: c.inkMuted),
        ),
        ProfileForm(answers: answers, onChanged: onChanged),
      ],
    );
  }
}

/// Edits the "about the person" answers. Shared with Settings.
class ProfileForm extends StatelessWidget {
  const ProfileForm({
    super.key,
    required this.answers,
    required this.onChanged,
  });

  static const questionIds = [Q.ageBand, Q.skinTone, Q.sex];

  /// The catalog asks about "the person"; here it's about you.
  static const _titles = {
    Q.ageBand: 'Your age',
    Q.skinTone: 'Your natural skin',
    Q.sex: 'Sex assigned at birth',
  };

  final IntakeAnswers answers;
  final ValueChanged<IntakeAnswers> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in questionIds) ...[
          SectionTitle(_titles[id]!),
          QuestionOptions(
            question: IntakeCatalog.byId(id)!,
            answers: answers,
            onToggle: (option) =>
                onChanged(answers.toggle(IntakeCatalog.byId(id)!, option)),
          ),
        ],
      ],
    );
  }
}
