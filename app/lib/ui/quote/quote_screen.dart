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
import 'customer_preview_screen.dart';
import 'edit_sheets.dart';
import 'line_editor.dart';
import 'send_sheet.dart';

/// The quote as a document: review what the AI drafted, fix anything, send.
class QuoteScreen extends ConsumerStatefulWidget {
  const QuoteScreen({super.key, required this.quoteId});

  final String quoteId;

  @override
  ConsumerState<QuoteScreen> createState() => _QuoteScreenState();
}

class _QuoteScreenState extends ConsumerState<QuoteScreen> {
  String? _tierId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final q = ref.read(quoteProvider(widget.quoteId));
      if (q?.share == null) return;
      try {
        await ref.read(quoteActionsProvider).refresh(q!);
      } on ApiError {
        // Stale status is fine; pull to refresh on the home screen.
      }
    });
  }

  Future<void> _save(Quote q) => ref.read(quotesProvider.notifier).save(q);

  Future<void> _editLine(Quote q, LineItem? item) async {
    final result = await showLineEditor(
      context,
      quote: q,
      item: item,
      tierId: _tierId ?? q.defaultTierId,
    );
    if (result == null) return;
    final current = ref.read(quoteProvider(q.id));
    if (current == null) return;
    if (result.deleted) {
      await _save(current.removeItem(result.item.id));
    } else if (item == null) {
      await _save(current.copyWith(items: [...current.items, result.item]));
    } else {
      await _save(current.replaceItem(result.item));
    }
  }

  Future<void> _menu(Quote q, String action) async {
    final actions = ref.read(quoteActionsProvider);
    switch (action) {
      case 'won':
        await actions.close(q, QuoteStatus.approved, tierId: _tierId);
        if (mounted) showSnack(context, 'Marked as won.');
      case 'lost':
        await actions.close(q, QuoteStatus.declined);
        if (mounted) showSnack(context, 'Marked as lost.');
      case 'duplicate':
        final copy = await actions.duplicate(q);
        if (!mounted) return;
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => QuoteScreen(quoteId: copy.id),
          ),
        );
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete ${q.label}?'),
            content: const Text(
              'This removes it from this phone. A link you already sent '
              'keeps working.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (ok != true || !mounted) return;
        Navigator.of(context).pop();
        await ref.read(quotesProvider.notifier).delete(q.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = ref.watch(quoteProvider(widget.quoteId));
    if (quote == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This quote was deleted.')),
      );
    }
    final c = JobColors.of(context);
    final tierId = quote.tier(_tierId)?.id ?? quote.defaultTierId;
    final locked = quote.status == QuoteStatus.approved;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(quote.label),
            const SizedBox(width: 10),
            StatusPill(quote),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Preview as customer',
            icon: const Icon(Icons.visibility_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CustomerPreviewScreen(quoteId: quote.id),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (a) => _menu(quote, a),
            itemBuilder: (_) => [
              if (!locked)
                const PopupMenuItem(value: 'won', child: Text('Mark as won')),
              if (quote.status != QuoteStatus.declined && !locked)
                const PopupMenuItem(value: 'lost', child: Text('Mark as lost')),
              const PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
        children: [
          if (quote.ai?.demo ?? false)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                'Demo mode: this draft is one of the sample jobs, not an '
                'analysis of your photos.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          if (quote.share != null) ...[
            _StatusCard(quote: quote),
            const SizedBox(height: 10),
          ],
          if (quote.assumptions.isNotEmpty && !locked) ...[
            _AssumptionsCard(quote: quote, onChanged: _save),
            const SizedBox(height: 10),
          ],
          _Document(
            quote: quote,
            tierId: tierId,
            locked: locked,
            onTier: (id) => setState(() => _tierId = id),
            onLine: (item) => _editLine(quote, item),
            onChanged: _save,
          ),
          const SizedBox(height: 10),
          _InsightsCard(quote: quote, tierId: tierId),
          if (quote.photoKeys.isNotEmpty) ...[
            const SectionLabel('Job photos'),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                itemCount: quote.photoKeys.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => _viewPhoto(quote.photoKeys[i]),
                  child: PhotoThumb(quote.photoKeys[i], width: 122, height: 92),
                ),
              ),
            ),
          ],
          const SizedBox(height: 90),
        ],
      ),
      bottomNavigationBar: _BottomBar(quote: quote, locked: locked, c: c),
    );
  }

  void _viewPhoto(String key) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Consumer(
              builder: (context, ref, _) {
                final bytes = ref.watch(storedPhotoProvider(key)).value;
                return bytes == null
                    ? const SizedBox()
                    : Image.memory(bytes, fit: BoxFit.contain);
              },
            ),
          ),
        ),
      ),
    ),
  );
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({
    required this.quote,
    required this.locked,
    required this.c,
  });

  final Quote quote;
  final bool locked;
  final JobColors c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final share = quote.share;
    final stale = share != null && quote.updatedAt.isAfter(share.sentAt);
    final label = locked
        ? null
        : share == null
        ? 'Send to customer'
        : stale
        ? 'Send the update'
        : 'Send again';
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      locked
                          ? 'Approved'
                          : quote.hasTiers
                          ? '${quote.tiers.length} options'
                          : 'Total',
                      style: text.bodySmall,
                    ),
                    MoneyText(
                      quote.headlineTotalCents,
                      size: 24,
                      weight: FontWeight.w800,
                      prefix: !locked && quote.hasTiers ? 'up to ' : '',
                    ),
                  ],
                ),
              ),
              if (label != null)
                FilledButton.icon(
                  onPressed: () => showSendSheet(context, quote.id),
                  icon: const Icon(Icons.send_rounded, size: 20),
                  label: Text(label),
                )
              else
                Text('Duplicate to make changes', style: text.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sent, viewed, and what the customer did.
class _StatusCard extends ConsumerWidget {
  const _StatusCard({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final share = quote.share!;
    final r = quote.response;
    final profile = ref.watch(settingsProvider.select((s) => s.profile));
    final steps = <(IconData, String, Tone)>[
      (
        Icons.send_rounded,
        'Sent ${formatShortDay(share.sentAt)}, ${formatTime(share.sentAt)}'
            '${share.revision > 1 ? ' (revision ${share.revision})' : ''}',
        c.info,
      ),
      if (r.views > 0)
        (
          Icons.visibility_rounded,
          'Viewed ${r.views == 1 ? 'once' : '${r.views} times'}, last '
              '${formatShortDay(r.lastViewedAt!)}, ${formatTime(r.lastViewedAt!)}',
          c.warn,
        ),
      if (quote.status == QuoteStatus.approved)
        (
          Icons.check_circle_rounded,
          'Approved${quote.tier(quote.chosenTierId) == null ? '' : ': ${quote.tier(quote.chosenTierId)!.name}'}'
              '${r.signature.isEmpty ? '' : ', signed by ${r.signature}'}',
          c.ok,
        ),
      if (quote.status == QuoteStatus.declined)
        (
          Icons.cancel_rounded,
          'Declined${r.declineReason.isEmpty ? '' : ': "${r.declineReason}"'}',
          c.danger,
        ),
    ];
    final firstName = quote.customer.name.isEmpty
        ? ''
        : ' ${quote.customer.firstName}';
    final nudge =
        'Hi$firstName, just checking in on the quote from ${profile.name}. '
        'Here it is again: ${share.url}';
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (icon, label, tone) in steps)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: tone.fg),
                  const SizedBox(width: 10),
                  Expanded(child: Text(label, style: text.bodyMedium)),
                ],
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (quote.status.isOpen)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                  onPressed: () => quote.customer.phone.isEmpty
                      ? shareText(nudge)
                      : composeText(quote.customer.phone, nudge),
                  icon: const Icon(
                    Icons.notifications_active_outlined,
                    size: 18,
                  ),
                  label: const Text('Nudge'),
                ),
              if (quote.customer.phone.isNotEmpty)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 40),
                  ),
                  onPressed: () => callNumber(quote.customer.phone),
                  icon: const Icon(Icons.call_outlined, size: 18),
                  label: const Text('Call'),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                onPressed: () async {
                  await copyText(share.url);
                  if (context.mounted) showSnack(context, 'Link copied.');
                },
                icon: const Icon(Icons.link_rounded, size: 18),
                label: const Text('Copy link'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What the AI assumed, for the contractor to confirm before sending.
class _AssumptionsCard extends StatelessWidget {
  const _AssumptionsCard({required this.quote, required this.onChanged});

  final Quote quote;
  final Future<void> Function(Quote) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final open = quote.openAssumptions;
    final tone = open == 0 ? c.ok : c.warn;
    return Panel(
      color: tone.bg,
      borderColor: tone.bg,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                open == 0 ? Icons.task_alt_rounded : Icons.fact_check_outlined,
                color: tone.fg,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  open == 0
                      ? 'Assumptions checked'
                      : 'Check before sending: $open',
                  style: text.titleSmall?.copyWith(color: tone.fg),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final (i, a) in quote.assumptions.indexed)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                final list = [...quote.assumptions];
                list[i] = a.withConfirmed(!a.confirmed);
                unawaited(onChanged(quote.copyWith(assumptions: list)));
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 24,
                      child: Checkbox(
                        value: a.confirmed,
                        onChanged: (v) {
                          final list = [...quote.assumptions];
                          list[i] = a.withConfirmed(v ?? false);
                          unawaited(
                            onChanged(quote.copyWith(assumptions: list)),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: a.text),
                              if (a.impact == Impact.high && !a.confirmed)
                                TextSpan(
                                  text: '  Big price impact',
                                  style: text.labelSmall?.copyWith(
                                    color: c.warn.fg,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                            ],
                          ),
                          style: text.bodyMedium?.copyWith(
                            color: a.confirmed ? c.inkMuted : c.ink,
                            decoration: a.confirmed
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The quote as the customer will read it, editable by tapping.
class _Document extends ConsumerWidget {
  const _Document({
    required this.quote,
    required this.tierId,
    required this.locked,
    required this.onTier,
    required this.onLine,
    required this.onChanged,
  });

  final Quote quote;
  final String? tierId;
  final bool locked;
  final ValueChanged<String> onTier;
  final void Function(LineItem?) onLine;
  final Future<void> Function(Quote) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final profile = ref.watch(settingsProvider.select((s) => s.profile));
    final totals = quote.totals(tierId);
    final lines = groupBySection(
      quote.items.where((i) => i.inTier(tierId)),
      (i) => i.section,
    );
    final customer = quote.customer;

    Future<void> editHeader() async {
      final updated = await showHeaderEditor(context, quote);
      if (updated != null) await onChanged(updated);
    }

    return Panel(
      color: c.paper,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: locked ? null : editHeader,
            borderRadius: BorderRadius.circular(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        profile.name,
                        style: text.labelSmall?.copyWith(color: c.inkFaint),
                      ),
                    ),
                    Text(
                      formatDay(quote.share?.sentAt ?? quote.createdAt),
                      style: text.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  quote.title.isEmpty ? 'Untitled job' : quote.title,
                  style: text.headlineMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  customer.name.isEmpty
                      ? 'Add customer'
                      : [
                          customer.name,
                          if (customer.address.isNotEmpty) customer.address,
                        ].join(' · '),
                  style: text.bodyMedium?.copyWith(
                    color: customer.name.isEmpty ? c.accentInk : c.inkMuted,
                    fontWeight: customer.name.isEmpty ? FontWeight.w700 : null,
                  ),
                ),
                if (quote.summary.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(quote.summary, style: text.bodyMedium),
                ],
              ],
            ),
          ),
          if (quote.hasTiers) ...[
            const SizedBox(height: 16),
            _TierPicker(
              quote: quote,
              selected: tierId,
              onSelect: onTier,
              onEdit: locked
                  ? null
                  : (tier) async {
                      final updated = await showTierEditor(
                        context,
                        quote,
                        tier,
                      );
                      if (updated != null) await onChanged(updated);
                    },
            ),
          ],
          const SizedBox(height: 8),
          for (final (i, item) in lines.indexed) ...[
            if (item.section.isNotEmpty &&
                (i == 0 || lines[i - 1].section != item.section))
              Padding(
                padding: const EdgeInsets.only(top: 14, bottom: 2),
                child: Text(
                  item.section.toUpperCase(),
                  style: text.labelSmall?.copyWith(color: c.inkFaint),
                ),
              ),
            _LineRow(
              item: item,
              rates: quote.rates,
              onTap: locked ? null : () => onLine(item),
            ),
          ],
          if (!locked)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => onLine(null),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add line'),
              ),
            ),
          const SizedBox(height: 6),
          Container(height: 2, color: c.ink),
          const SizedBox(height: 10),
          _Totals(
            quote: quote,
            totals: totals,
            locked: locked,
            onChanged: onChanged,
          ),
          if (quote.exclusions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'NOT INCLUDED',
              style: text.labelSmall?.copyWith(color: c.inkFaint),
            ),
            const SizedBox(height: 6),
            for (final e in quote.exclusions)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '•  $e',
                  style: text.bodyMedium?.copyWith(color: c.inkMuted),
                ),
              ),
          ],
          const SizedBox(height: 18),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: locked
                ? null
                : () async {
                    final updated = await showMessageEditor(context, quote);
                    if (updated != null) await onChanged(updated);
                  },
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.canvas,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NOTE TO CUSTOMER',
                    style: text.labelSmall?.copyWith(color: c.inkFaint),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    quote.message.isEmpty ? 'Add a short note' : quote.message,
                    style: text.bodyMedium?.copyWith(
                      color: quote.message.isEmpty ? c.inkFaint : c.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TierPicker extends StatelessWidget {
  const _TierPicker({
    required this.quote,
    required this.selected,
    required this.onSelect,
    this.onEdit,
  });

  final Quote quote;
  final String? selected;
  final ValueChanged<String> onSelect;
  final void Function(Tier)? onEdit;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'OPTIONS THE CUSTOMER CAN PICK',
          style: text.labelSmall?.copyWith(color: c.inkFaint),
        ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, t) in quote.tiers.indexed) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: t.id == selected ? c.ink : c.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: t.id == selected ? c.ink : c.line,
                        width: 1.5,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () =>
                          t.id == selected ? onEdit?.call(t) : onSelect(t.id),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: text.labelMedium?.copyWith(
                                color: t.id == selected ? c.canvas : c.ink,
                                height: 1.2,
                              ),
                            ),
                            const Spacer(),
                            const SizedBox(height: 6),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: MoneyText(
                                quote.totals(t.id).totalCents,
                                size: 20,
                                weight: FontWeight.w800,
                                color: t.id == selected ? c.canvas : c.ink,
                              ),
                            ),
                            if (t.recommended) ...[
                              const SizedBox(height: 4),
                              Text(
                                'RECOMMENDED',
                                style: text.labelSmall?.copyWith(
                                  fontSize: 10,
                                  color: t.id == selected
                                      ? c.accent
                                      : c.accentInk,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.item, required this.rates, this.onTap});

  final LineItem item;
  final Rates rates;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final quantity = describeQuantity(item.quantity, item.unit);
    final sub = [
      if (item.detail.isNotEmpty) item.detail,
      if (quantity.isNotEmpty) quantity,
    ].join(' · ');
    final tag = item.priceListId != null
        ? 'Your price'
        : item.mode == PricingMode.fixed ||
              (item.mode == PricingMode.unitRate && item.fromAi)
        ? 'Edited'
        : null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
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
                  Text(item.description, style: text.titleSmall),
                  if (sub.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(sub, style: text.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(Pricing.line(item, rates), size: 17),
                if (tag != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    tag,
                    style: text.labelSmall?.copyWith(
                      color: tag == 'Your price' ? c.ok.fg : c.inkFaint,
                      fontSize: 11,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({
    required this.quote,
    required this.totals,
    required this.locked,
    required this.onChanged,
  });

  final Quote quote;
  final QuoteTotals totals;
  final bool locked;
  final Future<void> Function(Quote) onChanged;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget row(
      String label,
      int cents, {
      String prefix = '',
      VoidCallback? onTap,
    }) => InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
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
              prefix: prefix,
            ),
          ],
        ),
      ),
    );
    final adjusted =
        totals.minimumAdjustmentCents > 0 ||
        totals.discountCents > 0 ||
        totals.taxCents > 0;
    Future<void> editDiscount() async {
      final updated = await showDiscountEditor(context, quote);
      if (updated != null) await onChanged(updated);
    }

    return Column(
      children: [
        if (adjusted) row('Subtotal', totals.subtotalCents),
        if (totals.minimumAdjustmentCents > 0)
          row('Minimum job charge', totals.minimumAdjustmentCents),
        if (totals.discountCents > 0)
          row(
            'Discount',
            totals.discountCents,
            prefix: '-',
            onTap: locked ? null : editDiscount,
          ),
        if (totals.taxCents > 0)
          row(
            'Tax (${trimNumber(quote.rates.taxRatePct, decimals: 3)}%)',
            totals.taxCents,
          ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(child: Text('Total', style: text.headlineSmall)),
            MoneyText(totals.totalCents, size: 30, weight: FontWeight.w800),
          ],
        ),
        if (totals.depositCents > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Deposit at approval (${trimNumber(quote.rates.depositPct)}%)',
                    style: text.bodyMedium,
                  ),
                ),
                MoneyText(totals.depositCents, size: 16),
              ],
            ),
          ),
        if (!locked && totals.discountCents == 0)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: editDiscount,
              child: const Text('Add discount'),
            ),
          ),
      ],
    );
  }
}

/// Only the contractor sees this: effort, cost, and how it was measured.
class _InsightsCard extends StatelessWidget {
  const _InsightsCard({required this.quote, required this.tierId});

  final Quote quote;
  final String? tierId;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final ai = quote.ai;
    final totals = quote.totals(tierId);
    final change = quote.changeFromDraft(tierId);
    final draft = ai?.draftTotals[Quote.tierKey(tierId)];
    final crew = ai == null || ai.crewPeople == 0
        ? ''
        : ' · about ${ai.crewPeople} ${ai.crewPeople == 1 ? 'person' : 'people'}'
              ' for ${trimNumber(ai.crewDays)} ${ai.crewDays == 1 ? 'day' : 'days'}';
    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 16, color: c.inkFaint),
              const SizedBox(width: 6),
              Text(
                'ONLY YOU SEE THIS',
                style: text.labelSmall?.copyWith(color: c.inkFaint),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Labor: ${trimNumber(totals.laborHours)} hrs$crew',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            'Materials at cost: ${Money.format(totals.materialCostCents)}',
            style: text.bodyMedium,
          ),
          if (draft != null) ...[
            const SizedBox(height: 2),
            Text(
              change == null || change.abs() < 0.05
                  ? 'Same as the AI draft (${Money.format(draft)})'
                  : 'AI draft ${Money.format(draft)} · your changes '
                        '${change > 0 ? '+' : ''}${trimNumber(change)}%',
              style: text.bodyMedium,
            ),
          ],
          if (ai != null &&
              (ai.measurements.isNotEmpty || ai.observations.isNotEmpty))
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 10),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: Text(
                  'How Jobwalk got these numbers',
                  style: text.titleSmall,
                ),
                children: [
                  for (final m in ai.measurements)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  '${m.name}: ${describeQuantity(m.quantity, m.unit).isEmpty ? formatQuantity(m.quantity) : describeQuantity(m.quantity, m.unit)}',
                              style: text.titleSmall,
                            ),
                            TextSpan(
                              text: '  ${m.confidence.id} confidence\n',
                              style: text.bodySmall?.copyWith(
                                color: m.confidence == Impact.low
                                    ? c.warn.fg
                                    : c.inkFaint,
                              ),
                            ),
                            TextSpan(text: m.how, style: text.bodySmall),
                          ],
                        ),
                      ),
                    ),
                  for (final o in ai.observations)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('•  $o', style: text.bodySmall),
                    ),
                  if (ai.confidenceNote.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Confidence: ${ai.confidence.id}. ${ai.confidenceNote}',
                      style: text.bodySmall,
                    ),
                  ],
                ],
              ),
            )
          else
            const SizedBox(height: 10),
        ],
      ),
    );
  }
}
