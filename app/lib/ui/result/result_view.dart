import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

import '../../services/launcher.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../widgets/common.dart';
import '../widgets/triage.dart';

/// Renders a [CheckResult]: urgency first, then what it might be, what was
/// seen, what to do, and what to watch for.
class ResultView extends ConsumerWidget {
  const ResultView({
    super.key,
    required this.result,
    required this.site,
    this.photo,
    this.extra = const [],
  });

  final CheckResult result;
  final BodySite site;
  final Widget? photo;

  /// Extra content placed before the disclaimer (actions, notes).
  final List<Widget> extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emergencyNumber = ref.watch(
      settingsProvider.select((s) => s.emergencyNumber),
    );
    final a = result.assessment;
    final text = Theme.of(context).textTheme;
    final c = SpotColors.of(context);
    // When the safety rules raised the urgency, the model's own headline and
    // reasoning argued for less urgent advice. Lead with the rules instead
    // so the page never contradicts itself.
    final escalated = result.escalatedBySafetyRules;
    final headline = escalated && result.urgency != null
        ? escalatedHeadline(result.urgency!)
        : a?.headline ?? '';

    return PageBody(
      children: [
        if (result.demo) ...[const DemoBanner(), const SizedBox(height: 14)],
        Row(
          children: [
            if (photo != null) ...[photo!, const SizedBox(width: 14)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(site.label, style: text.titleMedium),
                  Text(formatDate(result.createdAt), style: text.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (result.status == CheckStatus.retake)
          _StatusCard(
            icon: Icons.camera_enhance_outlined,
            title: "Let's retake that photo",
            body: result.message,
            chips: [
              for (final i in a?.imageQuality.issues ?? const <PhotoIssue>[])
                i.label,
            ],
          )
        else if (result.status == CheckStatus.declined)
          _StatusCard(
            icon: Icons.help_outline,
            title: "We couldn't analyze this one",
            body: result.message,
          )
        else if (headline.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(headline, style: text.headlineSmall),
          ),
        if (result.urgency case final urgency?) ...[
          if (result.status != CheckStatus.complete) const SizedBox(height: 14),
          UrgencyCard(
            urgency: urgency,
            careSetting: result.careSetting,
            reason: result.status == CheckStatus.complete && !escalated
                ? a?.urgencyReason
                : null,
            emergencyNumber: emergencyNumber,
            onCall: () => callNumber(emergencyNumber),
            onFindCare: () => findCareNearby(
              result.careSetting ?? CareSetting.defaultFor(urgency),
            ),
          ),
        ],
        if (result.safetyNotes.isNotEmpty) _SafetyNotes(result: result),
        if (a != null && result.status == CheckStatus.complete) ...[
          if (a.possibilities.isNotEmpty) ...[
            const SectionTitle('What it might be', icon: Icons.search),
            for (final p in a.possibilities)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PossibilityCard(possibility: p),
              ),
          ],
          if (a.observationSummary.isNotEmpty ||
              a.observedFeatures.isNotEmpty) ...[
            const SectionTitle(
              'What we noticed',
              icon: Icons.center_focus_strong_outlined,
            ),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (a.observationSummary.isNotEmpty)
                    Text(a.observationSummary, style: text.bodyMedium),
                  if (a.observedFeatures.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final f in a.observedFeatures) Pill(label: f),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (a.redFlags.isNotEmpty) ...[
            const SectionTitle('Worth pointing out', icon: Icons.flag_outlined),
            SurfaceCard(
              color: c.forUrgency(Urgency.soon).bg,
              borderColor: c.forUrgency(Urgency.soon).border,
              child: IconList(
                items: a.redFlags,
                icon: Icons.flag_outlined,
                iconColor: c.forUrgency(Urgency.soon).fg,
              ),
            ),
          ],
          if (a.selfCare.isNotEmpty && result.urgency != Urgency.emergency) ...[
            const SectionTitle(
              'What you can do now',
              icon: Icons.volunteer_activism_outlined,
            ),
            SurfaceCard(
              child: IconList(
                items: a.selfCare,
                icon: Icons.check_circle_outline,
              ),
            ),
          ],
          if (a.watchFor.isNotEmpty) ...[
            const SectionTitle(
              'Get care sooner if',
              icon: Icons.visibility_outlined,
            ),
            SurfaceCard(
              child: IconList(
                items: a.watchFor,
                icon: Icons.arrow_upward_rounded,
                iconColor: c.forUrgency(Urgency.urgent).solid,
              ),
            ),
          ],
          if (a.doctorQuestions.isNotEmpty) ...[
            const SectionTitle(
              'Questions for your doctor',
              icon: Icons.forum_outlined,
            ),
            SurfaceCard(
              child: IconList(
                items: a.doctorQuestions,
                icon: Icons.chat_bubble_outline,
              ),
            ),
          ],
          const SectionTitle('How sure is this?', icon: Icons.tune),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Confidence: ${a.confidence.label}',
                  style: text.titleSmall,
                ),
                if (a.confidenceNote.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    a.confidenceNote,
                    style: text.bodyMedium?.copyWith(color: c.inkMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
        ...extra,
        const DisclaimerText(),
      ],
    );
  }
}

/// Headline used when safety rules raised the urgency above the model's.
String escalatedHeadline(Urgency urgency) => switch (urgency) {
  Urgency.emergency => 'Your answers point to an emergency.',
  Urgency.urgent => 'Based on your answers, get this seen today.',
  Urgency.soon => 'Based on your answers, see a doctor in the next few days.',
  Urgency.routine => 'Based on your answers, have a doctor look at this.',
  Urgency.selfCare => 'Home care is a reasonable start.',
};

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.icon,
    required this.title,
    required this.body,
    this.chips = const [],
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> chips;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 32, color: c.brand),
          const SizedBox(height: 12),
          Text(title, style: text.titleLarge),
          const SizedBox(height: 8),
          Text(body, style: text.bodyMedium?.copyWith(color: c.inkMuted)),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final label in chips) Pill(label: label)],
            ),
          ],
        ],
      ),
    );
  }
}

class _SafetyNotes extends StatelessWidget {
  const _SafetyNotes({required this.result});

  final CheckResult result;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    final text = Theme.of(context).textTheme;
    final actions = [
      for (final n in result.safetyNotes)
        if (n.action != null) n.action!,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 20, color: c.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.escalatedBySafetyRules
                        ? 'Raised by SpotCheck safety rules'
                        : 'Why this advice',
                    style: text.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            IconList(
              items: [for (final n in result.safetyNotes) n.reason],
              icon: Icons.fiber_manual_record,
              iconColor: c.inkFaint,
            ),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Do this now', style: text.titleSmall),
              const SizedBox(height: 8),
              IconList(
                items: actions,
                icon: Icons.priority_high_rounded,
                iconColor: c.forUrgency(Urgency.emergency).solid,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PossibilityCard extends StatefulWidget {
  const _PossibilityCard({required this.possibility});

  final Possibility possibility;

  @override
  State<_PossibilityCard> createState() => _PossibilityCardState();
}

class _PossibilityCardState extends State<_PossibilityCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.possibility;
    final c = SpotColors.of(context);
    final text = Theme.of(context).textTheme;
    final showTerm =
        p.medicalTerm.isNotEmpty &&
        p.medicalTerm.toLowerCase() != p.name.toLowerCase();
    return SurfaceCard(
      onTap: () => setState(() => _open = !_open),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: text.titleMedium),
                    if (showTerm) Text(p.medicalTerm, style: text.bodySmall),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: _open ? 0.5 : 0,
                duration: const Duration(milliseconds: 200),
                child: Icon(Icons.expand_more, color: c.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              LikelihoodMeter(p.likelihood),
              if (p.serious)
                Pill(
                  label: 'Needs medical care',
                  icon: Icons.medical_services_outlined,
                  fg: c.forUrgency(Urgency.urgent).fg,
                  bg: c.forUrgency(Urgency.urgent).bg,
                ),
            ],
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p.description.isNotEmpty)
                    Text(p.description, style: text.bodyMedium),
                  if (p.supportingFeatures.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Why', style: text.titleSmall),
                    const SizedBox(height: 4),
                    Text(
                      p.supportingFeatures,
                      style: text.bodyMedium?.copyWith(color: c.inkMuted),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
