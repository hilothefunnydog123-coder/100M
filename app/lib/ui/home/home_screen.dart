import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

import '../../data/models.dart';
import '../../services/launcher.dart';
import '../../state/check_flow.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../check/check_flow_screen.dart';
import '../history/check_detail_screen.dart';
import '../paywall/paywall_screen.dart';
import '../settings/settings_screen.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';
import '../widgets/triage.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final due = ref.watch(dueRechecksProvider);
    final remaining = ref.watch(checksRemainingProvider);
    final emergency = ref.watch(
      settingsProvider.select((s) => s.emergencyNumber),
    );
    final c = SpotColors.of(context);
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: const Wordmark(size: 30),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageBody(
        children: [
          _StartCard(remaining: remaining),
          if (due.isNotEmpty) ...[
            const SectionTitle('Time to recheck', icon: Icons.event_repeat),
            for (final r in due)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RecheckTile(record: r),
              ),
          ],
          SectionTitle(
            'Your checks',
            icon: Icons.history,
            trailing: history.isEmpty
                ? null
                : Text('${history.length}', style: text.labelMedium),
          ),
          if (history.isEmpty)
            const _EmptyHistory()
          else
            for (final r in history)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _HistoryTile(record: r),
              ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: () => callNumber(emergency),
              style: TextButton.styleFrom(
                foregroundColor: c.forUrgency(Urgency.emergency).fg,
              ),
              icon: const Icon(Icons.call_outlined, size: 18),
              label: Text('Emergency? Call $emergency'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Starts a check, or shows the paywall when free checks are used up.
Future<void> startCheck(
  BuildContext context,
  WidgetRef ref, {
  CheckRecord? recheckOf,
}) async {
  final remaining = ref.read(checksRemainingProvider);
  if (remaining == 0) {
    final unlocked = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const PaywallScreen(),
      ),
    );
    if (unlocked != true || !context.mounted) return;
  }
  ref.read(checkFlowProvider.notifier).start(recheckOf: recheckOf);
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => CheckFlowScreen(recheckOf: recheckOf),
    ),
  );
}

class _StartCard extends ConsumerWidget {
  const _StartCard({required this.remaining});

  final int? remaining;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SpotColors.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.brand, c.brandInk],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What should we look at?',
            style: text.headlineSmall?.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Skin, moles, rashes, eyes, mouth, nails, or scalp.',
            style: text.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => startCheck(context, ref),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: c.brandInk,
            ),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Start a check'),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              remaining == null
                  ? 'SpotCheck Pro: unlimited checks'
                  : remaining == 1
                  ? '1 free check left'
                  : '$remaining free checks left',
              style: text.labelMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    final text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      child: Column(
        children: [
          Icon(Icons.photo_library_outlined, size: 36, color: c.inkFaint),
          const SizedBox(height: 12),
          Text('No checks yet', style: text.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Your results will be saved here on this phone, so you can '
            'track changes and share them with a doctor.',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: c.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record});

  final CheckRecord record;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = SpotColors.of(context);
    final headline = record.result.assessment?.headline ?? '';
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CheckDetailScreen(recordId: record.id),
        ),
      ),
      child: Row(
        children: [
          StoredPhoto(photoKey: record.photoKeys.firstOrNull, size: 64),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.site.label,
                        style: text.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(formatDate(record.createdAt), style: text.bodySmall),
                  ],
                ),
                if (headline.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyMedium?.copyWith(color: c.inkMuted),
                  ),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (record.result.urgency case final u?) UrgencyBadge(u),
                    if (record.tracking)
                      Icon(Icons.event_repeat, size: 16, color: c.inkFaint),
                    if (record.result.demo) Pill(label: 'Demo', fg: c.pro),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecheckTile extends ConsumerWidget {
  const _RecheckTile({required this.record});

  final CheckRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final c = SpotColors.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.all(12),
      borderColor: c.brand,
      child: Row(
        children: [
          StoredPhoto(photoKey: record.photoKeys.firstOrNull, size: 52),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(record.site.label, style: text.titleSmall),
                Text(
                  'Checked ${formatDate(record.createdAt)}. See if it changed.',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 42),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: () => startCheck(context, ref, recheckOf: record),
            child: const Text('Recheck'),
          ),
        ],
      ),
    );
  }
}
