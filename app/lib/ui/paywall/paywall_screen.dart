import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/launcher.dart';
import '../../services/purchases.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../widgets/brand.dart';
import '../widgets/common.dart';

/// Returns true when the person unlocked Pro.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  late final PurchasesService _purchases = ref.read(purchasesProvider);
  late Plan _selected = _purchases.plans.first;
  bool _busy = false;

  Future<void> _buy() async {
    setState(() => _busy = true);
    final ok = await _purchases.purchase(_selected);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop(true);
  }

  Future<void> _restore() async {
    final ok = await _purchases.restore();
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No previous purchase found.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SpotColors.of(context);
    final text = Theme.of(context).textTheme;
    final config = ref.watch(configProvider);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: PageBody(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: SpotLogo(size: 56),
          ),
          const SizedBox(height: 20),
          Text('Keep checking with SpotCheck Pro', style: text.headlineMedium),
          const SizedBox(height: 10),
          Text(
            "You've used your free checks. Pro covers you and your family.",
            style: text.bodyLarge?.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: 22),
          const IconList(
            icon: Icons.check_circle,
            items: [
              'Unlimited checks for skin, eyes, mouth, nails, and scalp',
              'Track moles and spots over time with recheck reminders',
              'Doctor-ready summaries to share at appointments',
              'Check for your kids and family members',
            ],
          ),
          const SizedBox(height: 24),
          for (final plan in _purchases.plans)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PlanCard(
                plan: plan,
                selected: plan.id == _selected.id,
                onTap: () => setState(() => _selected = plan),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            _selected.trialDays > 0
                ? '${_selected.trialDays} days free, then ${_selected.price} '
                      'per ${_selected.period}. Cancel anytime in your store '
                      'settings at least 24 hours before renewal.'
                : '${_selected.price} per ${_selected.period}. Renews '
                      'automatically. Cancel anytime in your store settings '
                      'at least 24 hours before renewal.',
            style: text.bodySmall,
          ),
          if (_purchases.simulated) ...[
            const SizedBox(height: 14),
            Pill(
              icon: Icons.science_outlined,
              label: 'Development build: purchases are simulated',
              fg: c.pro,
              bg: c.pro.withValues(alpha: 0.1),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(onPressed: _restore, child: const Text('Restore')),
              TextButton(
                onPressed: () => openLink(config.termsUrl),
                child: const Text('Terms'),
              ),
              TextButton(
                onPressed: () => openLink(config.privacyPolicyUrl),
                child: const Text('Privacy'),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: BottomActions(
        children: [
          FilledButton(
            onPressed: _busy ? null : _buy,
            child: _busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Text(
                    _selected.trialDays > 0
                        ? 'Start ${_selected.trialDays}-day free trial'
                        : 'Subscribe',
                  ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final Plan plan;
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
          Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? c.brand : c.inkFaint,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(plan.title, style: text.titleMedium),
                    if (plan.badge != null)
                      Pill(label: plan.badge!, fg: Colors.white, bg: c.pro),
                  ],
                ),
                Text('${plan.price} / ${plan.period}', style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(plan.perWeek, style: text.labelMedium),
        ],
      ),
    );
  }
}
