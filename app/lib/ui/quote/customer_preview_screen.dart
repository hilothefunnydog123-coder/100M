import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import '../../services/api.dart';
import '../../services/launcher.dart';
import '../../state/providers.dart';
import '../../state/quote_actions.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../widgets/common.dart';

/// The quote the way the customer's page shows it. In demo mode, the
/// contractor can play the customer and approve it.
class CustomerPreviewScreen extends ConsumerStatefulWidget {
  const CustomerPreviewScreen({super.key, required this.quoteId});

  final String quoteId;

  @override
  ConsumerState<CustomerPreviewScreen> createState() =>
      _CustomerPreviewScreenState();
}

class _CustomerPreviewScreenState extends ConsumerState<CustomerPreviewScreen> {
  String? _option;
  late final _name = TextEditingController(
    text: ref.read(quoteProvider(widget.quoteId))?.customer.name ?? '',
  );
  var _agree = false;
  var _busy = false;

  @override
  void initState() {
    super.initState();
    final client = ref.read(clientProvider);
    final share = ref.read(quoteProvider(widget.quoteId))?.share;
    // Demo: opening the customer's view counts as the customer opening it.
    if (client is DemoJobwalkClient && share != null) {
      unawaited(client.recordView(share.publicId));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _approve(Quote quote, PublicOption option) async {
    final client = ref.read(clientProvider);
    if (client is! DemoJobwalkClient || quote.share == null) return;
    setState(() => _busy = true);
    await client.approve(
      quote.share!.publicId,
      optionId: quote.hasTiers ? option.id : null,
      name: _name.text.trim(),
    );
    await ref.read(quoteActionsProvider).refresh(quote);
    if (!mounted) return;
    Navigator.of(context).pop();
    showSnack(
      context,
      'Approved: ${option.name}, ${Money.format(option.totalCents)}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final quote = ref.watch(quoteProvider(widget.quoteId));
    if (quote == null) return const Scaffold();
    final profile = ref.watch(settingsProvider.select((s) => s.profile));
    final client = ref.watch(clientProvider);
    final now = ref.watch(clockProvider)();
    final public = PublicQuote.fromQuote(
      quote,
      profile,
      issuedAt: quote.share?.sentAt ?? now,
    );
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final approved = quote.status == QuoteStatus.approved;
    final chosen = approved
        ? (public.option(quote.chosenTierId) ?? public.defaultOption)
        : (public.option(_option) ?? public.defaultOption);
    final options = approved ? [chosen] : public.options;
    final biz = public.business;
    final who = [
      if (public.customerName.isNotEmpty) public.customerName,
      if (public.customerAddress.isNotEmpty) public.customerAddress,
    ].join(', ');
    final canPlayCustomer =
        client is DemoJobwalkClient && quote.share != null && !approved;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          quote.customer.name.isEmpty
              ? 'Customer view'
              : 'What ${quote.customer.firstName} sees',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 40),
        children: [
          Panel(
            color: c.paper,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(biz.name, style: text.headlineMedium),
                if (biz.phone.isNotEmpty || biz.email.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      [
                        biz.phone,
                        biz.email,
                        if (biz.license.isNotEmpty) 'License ${biz.license}',
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: text.bodySmall,
                    ),
                  ),
                const SizedBox(height: 16),
                Container(height: 1, color: c.line),
                const SizedBox(height: 12),
                _Meta(
                  left: ('Quote', '#${public.number}'),
                  right: ('Date', formatDay(public.issuedAt)),
                ),
                const SizedBox(height: 8),
                _Meta(
                  left: ('For', who.isEmpty ? ' ' : who),
                  right: ('Valid until', formatDay(public.validUntil)),
                ),
                const SizedBox(height: 12),
                Container(height: 1, color: c.line),
                if (approved) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.ok.bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Approved${quote.response.signature.isEmpty ? '' : ' by ${quote.response.signature}'}: '
                      '${chosen.name}, ${Money.format(chosen.totalCents)}.',
                      style: text.titleSmall?.copyWith(color: c.ok.fg),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (public.title.isNotEmpty)
                  Text(public.title, style: text.headlineSmall),
                if (public.summary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    public.summary,
                    style: text.bodyMedium?.copyWith(color: c.inkMuted),
                  ),
                ],
                if (options.length > 1) ...[
                  const SizedBox(height: 18),
                  Text(
                    'CHOOSE AN OPTION',
                    style: text.labelSmall?.copyWith(color: c.inkFaint),
                  ),
                  const SizedBox(height: 8),
                  for (final o in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _OptionCard(
                        option: o,
                        selected: o.id == chosen.id,
                        onTap: () => setState(() => _option = o.id),
                      ),
                    ),
                ],
                const SizedBox(height: 8),
                for (final (i, line) in chosen.lines.indexed) ...[
                  if (line.section.isNotEmpty &&
                      (i == 0 || chosen.lines[i - 1].section != line.section))
                    Padding(
                      padding: const EdgeInsets.only(top: 14, bottom: 2),
                      child: Text(
                        line.section.toUpperCase(),
                        style: text.labelSmall?.copyWith(color: c.inkFaint),
                      ),
                    ),
                  _PublicLineRow(line: line),
                ],
                const SizedBox(height: 12),
                _PublicTotals(option: chosen, depositPct: public.depositPct),
                if (public.exclusions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'NOT INCLUDED',
                    style: text.labelSmall?.copyWith(color: c.inkFaint),
                  ),
                  const SizedBox(height: 6),
                  for (final e in public.exclusions)
                    Text(
                      '•  $e',
                      style: text.bodyMedium?.copyWith(color: c.inkMuted),
                    ),
                ],
                if (public.message.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'FROM ${biz.name.toUpperCase()}',
                    style: text.labelSmall?.copyWith(color: c.inkFaint),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.canvas,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(public.message, style: text.bodyMedium),
                  ),
                ],
                if (public.terms.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'TERMS',
                    style: text.labelSmall?.copyWith(color: c.inkFaint),
                  ),
                  const SizedBox(height: 6),
                  Text(public.terms, style: text.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (canPlayCustomer)
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Try it as the customer', style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Demo mode: approve it the way your customer would from '
                    'the link.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Your name'),
                    onChanged: (_) => setState(() {}),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _agree,
                    onChanged: (v) => setState(() => _agree = v ?? false),
                    title: Text(
                      'I approve this quote and its terms.',
                      style: text.bodyMedium,
                    ),
                  ),
                  FilledButton(
                    onPressed: _busy || !_agree || _name.text.trim().isEmpty
                        ? null
                        : () => _approve(quote, chosen),
                    child: Text(
                      'Approve${options.length > 1 ? ' ${chosen.name}' : ''}: '
                      '${Money.format(chosen.totalCents)}',
                    ),
                  ),
                ],
              ),
            )
          else if (quote.share != null && !client.isDemo)
            OutlinedButton.icon(
              onPressed: () => openLink('${quote.share!.url}?preview=1'),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open the live page'),
            )
          else if (quote.share == null)
            Text(
              'Send the quote to get a link your customer can approve.',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.left, required this.right});

  final (String, String) left;
  final (String, String) right;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget cell((String, String) v, CrossAxisAlignment align) => Column(
      crossAxisAlignment: align,
      children: [
        Text(
          v.$1.toUpperCase(),
          style: text.labelSmall?.copyWith(color: c.inkFaint, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(v.$2, style: text.bodyMedium),
      ],
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: cell(left, CrossAxisAlignment.start)),
        const SizedBox(width: 12),
        cell(right, CrossAxisAlignment.end),
      ],
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final PublicOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: c.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected ? c.ink : c.line,
          width: selected ? 2 : 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? c.ink : c.inkFaint,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(option.name, style: text.titleSmall),
                        if (option.recommended)
                          Pill(
                            'Recommended',
                            tone: Tone(c.accentInk, c.accentSoft),
                          ),
                      ],
                    ),
                    if (option.summary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(option.summary, style: text.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              MoneyText(option.totalCents, size: 18, weight: FontWeight.w800),
            ],
          ),
        ),
      ),
    );
  }
}

class _PublicLineRow extends StatelessWidget {
  const _PublicLineRow({required this.line});

  final PublicLine line;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final quantity = describeQuantity(line.quantity, line.unit);
    final sub = [
      if (line.detail.isNotEmpty) line.detail,
      if (quantity.isNotEmpty) quantity,
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.description, style: text.titleSmall),
                if (sub.isNotEmpty) Text(sub, style: text.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 12),
          MoneyText(line.totalCents, size: 17),
        ],
      ),
    );
  }
}

class _PublicTotals extends StatelessWidget {
  const _PublicTotals({required this.option, required this.depositPct});

  final PublicOption option;
  final double depositPct;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget row(String label, int cents, {bool minus = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(color: c.inkMuted),
            ),
          ),
          MoneyText(
            cents,
            size: 16,
            weight: FontWeight.w600,
            color: c.inkMuted,
            prefix: minus ? '-' : '',
          ),
        ],
      ),
    );
    final adjusted =
        option.minimumAdjustmentCents > 0 ||
        option.discountCents > 0 ||
        option.taxCents > 0;
    return Column(
      children: [
        if (adjusted) row('Subtotal', option.subtotalCents),
        if (option.minimumAdjustmentCents > 0)
          row('Minimum job charge', option.minimumAdjustmentCents),
        if (option.discountCents > 0)
          row('Discount', option.discountCents, minus: true),
        if (option.taxCents > 0)
          row(
            'Tax (${trimNumber(option.taxRatePct, decimals: 3)}%)',
            option.taxCents,
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: Text('Total', style: text.headlineSmall)),
            MoneyText(option.totalCents, size: 28, weight: FontWeight.w800),
          ],
        ),
        if (option.depositCents > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Deposit due at approval (${trimNumber(depositPct)}%)',
                    style: text.bodyMedium,
                  ),
                ),
                MoneyText(option.depositCents, size: 16),
              ],
            ),
          ),
      ],
    );
  }
}
