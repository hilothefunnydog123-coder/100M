import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

import '../../services/launcher.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../widgets/common.dart';

/// Shown before analysis when the answers alone point to an emergency.
/// Returns true if the person still wants the photo analyzed.
class EmergencyScreen extends ConsumerWidget {
  const EmergencyScreen({super.key, required this.safety});

  final SafetyEvaluation safety;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final number = ref.watch(settingsProvider.select((s) => s.emergencyNumber));
    final p = SpotColors.of(context).forUrgency(Urgency.emergency);
    final text = Theme.of(context).textTheme;
    final reasons = [
      for (final r in safety.triggered)
        if (r.floor == Urgency.emergency) r.reason,
    ];
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(backgroundColor: p.bg),
      body: PageBody(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: p.solid,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.emergency_outlined,
                color: Colors.white,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'This could be an emergency',
            style: text.headlineMedium?.copyWith(color: p.fg),
          ),
          const SizedBox(height: 12),
          Text(
            "Based on what you told us, please get emergency care now. Don't "
            'wait for a photo analysis.',
            style: text.bodyLarge,
          ),
          const SizedBox(height: 20),
          IconList(items: reasons, icon: Icons.error_outline, iconColor: p.fg),
          if (safety.actions.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Do this now', style: text.titleMedium),
            const SizedBox(height: 10),
            IconList(
              items: safety.actions,
              icon: Icons.priority_high_rounded,
              iconColor: p.fg,
            ),
          ],
        ],
      ),
      bottomNavigationBar: BottomActions(
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: p.solid),
            onPressed: () => callNumber(number),
            icon: const Icon(Icons.call),
            label: Text('Call $number'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: p.fg),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue to photo analysis'),
          ),
        ],
      ),
    );
  }
}
