import 'package:flutter/material.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

import '../../theme/colors.dart';

IconData urgencyIcon(Urgency u) => switch (u) {
  Urgency.emergency => Icons.emergency_outlined,
  Urgency.urgent => Icons.local_hospital_outlined,
  Urgency.soon => Icons.event_available_outlined,
  Urgency.routine => Icons.calendar_month_outlined,
  Urgency.selfCare => Icons.spa_outlined,
};

/// Compact urgency label for lists.
class UrgencyBadge extends StatelessWidget {
  const UrgencyBadge(this.urgency, {super.key, this.short = false});

  final Urgency urgency;
  final bool short;

  @override
  Widget build(BuildContext context) {
    final p = SpotColors.of(context).forUrgency(urgency);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: p.solid, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              short ? urgency.timeframe : urgency.title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: p.fg, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// The headline answer to "how soon should I get this seen?".
class UrgencyCard extends StatelessWidget {
  const UrgencyCard({
    super.key,
    required this.urgency,
    this.careSetting,
    this.reason,
    this.onCall,
    this.emergencyNumber = '911',
    this.onFindCare,
  });

  final Urgency urgency;
  final CareSetting? careSetting;
  final String? reason;
  final VoidCallback? onCall;
  final String emergencyNumber;
  final VoidCallback? onFindCare;

  @override
  Widget build(BuildContext context) {
    final p = SpotColors.of(context).forUrgency(urgency);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.bg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: p.solid,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(urgencyIcon(urgency), color: Colors.white),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'HOW SOON',
                      style: text.labelSmall?.copyWith(color: p.fg),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      urgency.title,
                      style: text.titleLarge?.copyWith(color: p.fg),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(urgency.guidance, style: text.bodyMedium),
          if (reason != null && reason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(reason!, style: text.bodyMedium),
          ],
          if (careSetting != null && careSetting != CareSetting.selfCare) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.person_search_outlined, size: 18, color: p.fg),
                const SizedBox(width: 8),
                Text('Who to see: ', style: text.labelMedium),
                Flexible(
                  child: Text(
                    careSetting!.label,
                    style: text.labelMedium?.copyWith(color: p.fg),
                  ),
                ),
              ],
            ),
          ],
          if (urgency == Urgency.emergency && onCall != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCall,
              style: FilledButton.styleFrom(backgroundColor: p.solid),
              icon: const Icon(Icons.call),
              label: Text('Call $emergencyNumber'),
            ),
          ] else if (onFindCare != null && urgency != Urgency.selfCare) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onFindCare,
              style: OutlinedButton.styleFrom(
                foregroundColor: p.fg,
                side: BorderSide(color: p.border, width: 1.5),
                backgroundColor: Colors.white.withValues(alpha: 0.4),
              ),
              icon: const Icon(Icons.near_me_outlined),
              label: Text(
                'Find ${(careSetting ?? CareSetting.defaultFor(urgency)).label.toLowerCase()} nearby',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Three-segment likelihood bar.
class LikelihoodMeter extends StatelessWidget {
  const LikelihoodMeter(this.likelihood, {super.key});

  final Likelihood likelihood;

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    final filled = switch (likelihood) {
      Likelihood.high => 3,
      Likelihood.moderate => 2,
      Likelihood.low => 1,
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 14,
            height: 6,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: i < filled ? c.brand : c.line,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        const SizedBox(width: 6),
        Text(
          likelihood.label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: c.brandInk, fontSize: 12.5),
        ),
      ],
    );
  }
}
