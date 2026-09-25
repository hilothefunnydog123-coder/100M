import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../widgets/common.dart';

/// First run: who you are, what you do, what you charge. One screen.
class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _name = TextEditingController();
  final _rate = TextEditingController();
  final _trades = <Trade>[];
  bool _rateTyped = false;

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    super.dispose();
  }

  void _toggle(Trade trade) {
    setState(() {
      if (_trades.contains(trade)) {
        _trades.remove(trade);
      } else {
        _trades.add(trade);
      }
      if (!_rateTyped && _trades.isNotEmpty) {
        _rate.text = moneyInputText(_trades.first.defaultLaborRateCents);
      }
    });
  }

  bool get _ready =>
      _name.text.trim().isNotEmpty &&
      _trades.isNotEmpty &&
      Money.parse(_rate.text) != null;

  Future<void> _start() async {
    final trade = _trades.first;
    final rate = Money.parse(_rate.text) ?? trade.defaultLaborRateCents;
    await ref
        .read(settingsProvider.notifier)
        .completeSetup(
          BusinessProfile(name: _name.text.trim(), trades: [..._trades]),
          Rates.forTrade(trade).copyWith(laborRateCents: rate),
        );
  }

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Row(
                  children: [
                    const LogoMark(),
                    const SizedBox(width: 10),
                    Text('Jobwalk', style: text.titleLarge),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  'Quote the job before you leave the driveway.',
                  style: text.displaySmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'Snap the job, get an itemized quote priced your way, and '
                  'text it to the customer. Three things to start:',
                  style: text.bodyLarge?.copyWith(color: c.inkMuted),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Business name',
                    hintText: 'Brightline Painting',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),
                Text('What do you do?', style: text.titleMedium),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in Trade.values)
                      ChoiceChip(
                        label: Text(t.label),
                        selected: _trades.contains(t),
                        onSelected: (_) => _toggle(t),
                        labelStyle: text.labelMedium?.copyWith(
                          color: _trades.contains(t) ? c.canvas : c.ink,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Your labor rate', style: text.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Per person, per hour. Jobwalk prices labor with it; '
                  'you can set markup and your own prices later.',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: 200,
                  child: TextField(
                    controller: _rate,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: decimalInput,
                    decoration: const InputDecoration(
                      labelText: 'Dollars per hour',
                      prefixText: r'$ ',
                      suffixText: '/ hr',
                    ),
                    onChanged: (_) => setState(() => _rateTyped = true),
                  ),
                ),
                const SizedBox(height: 28),
                _QuotePreview(
                  name: _name.text.trim(),
                  trade: _trades.firstOrNull,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _ready ? _start : null,
                  child: const Text('Start quoting'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// How the top of their quotes will look, updating as they type.
class _QuotePreview extends ConsumerWidget {
  const _QuotePreview({required this.name, required this.trade});

  final String name;
  final Trade? trade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final today = ref.watch(clockProvider)();
    return Panel(
      color: c.paper,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.isEmpty ? 'Your business' : name,
            style: text.headlineSmall?.copyWith(
              color: name.isEmpty ? c.inkFaint : c.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            [
              if (trade != null) trade!.label,
              'Quote #1001',
              formatDay(today),
            ].join(' · '),
            style: text.bodySmall,
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: c.line),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your customer picks an option and approves from their '
                  'phone.',
                  style: text.bodySmall,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Approve',
                  style: text.labelMedium?.copyWith(color: c.onAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
