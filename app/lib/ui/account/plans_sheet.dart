import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/api.dart';
import '../../services/launcher.dart';
import '../../state/session.dart';
import '../../theme/colors.dart';
import '../widgets/common.dart';

/// Pro and Crew, bought on Stripe's checkout page (not in-app purchase).
Future<void> showPlans(BuildContext context, {String? reason}) =>
    showAppSheet<void>(context, builder: (_) => _PlansSheet(reason: reason));

class _PlansSheet extends ConsumerStatefulWidget {
  const _PlansSheet({this.reason});

  final String? reason;

  @override
  ConsumerState<_PlansSheet> createState() => _PlansSheetState();
}

class _PlansSheetState extends ConsumerState<_PlansSheet> {
  String? _busy;
  String? _error;

  Future<void> _choose(String plan) async {
    setState(() {
      _busy = plan;
      _error = null;
    });
    try {
      final url = await ref.read(serverProvider)!.checkout(plan);
      await openLink(url.toString());
      if (mounted) Navigator.of(context).pop();
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final owner = ref.watch(sessionProvider.select((s) => s.isOwner));
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader('Choose a plan', subtitle: widget.reason),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                if (!owner)
                  Text(
                    'Ask the account owner to choose a plan.',
                    style: text.bodyMedium?.copyWith(color: c.inkMuted),
                  )
                else ...[
                  _PlanCard(
                    name: 'Pro',
                    price: r'$79 / month',
                    points: const [
                      'Unlimited AI drafts',
                      'Up to 3 people',
                      'Card deposits',
                    ],
                    busy: _busy == 'pro',
                    onChoose: _busy == null ? () => _choose('pro') : null,
                  ),
                  const SizedBox(height: 12),
                  _PlanCard(
                    name: 'Crew',
                    price: r'$149 / month',
                    points: const ['Everything in Pro', 'Up to 15 people'],
                    busy: _busy == 'crew',
                    onChoose: _busy == null ? () => _choose('crew') : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "You pay on Stripe's secure page and can cancel any time "
                    'from Settings.',
                    style: text.bodySmall,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: text.bodyMedium?.copyWith(color: c.danger.fg),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.price,
    required this.points,
    required this.busy,
    required this.onChoose,
  });

  final String name;
  final String price;
  final List<String> points;
  final bool busy;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: text.titleLarge)),
              Text(price, style: text.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $p', style: text.bodyMedium),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: onChoose,
            child: Text(busy ? 'Opening…' : 'Choose $name'),
          ),
        ],
      ),
    );
  }
}
