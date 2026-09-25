import 'package:flutter/material.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import '../../theme/colors.dart';
import '../../util/format.dart';
import '../widgets/common.dart';

class LineEditResult {
  const LineEditResult(this.item, {this.deleted = false});

  final LineItem item;
  final bool deleted;
}

/// Edits one line, or adds one when [item] is null.
Future<LineEditResult?> showLineEditor(
  BuildContext context, {
  required Quote quote,
  LineItem? item,
  String? tierId,
}) => showAppSheet<LineEditResult>(
  context,
  builder: (_) => _LineEditor(quote: quote, item: item, tierId: tierId),
);

class _LineEditor extends StatefulWidget {
  const _LineEditor({required this.quote, this.item, this.tierId});

  final Quote quote;
  final LineItem? item;
  final String? tierId;

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  late final LineItem _base =
      widget.item ??
      LineItem(id: newId('li'), description: '', quantity: 1, unit: Unit.lot);
  late final _description = TextEditingController(text: _base.description);
  late final _detail = TextEditingController(text: _base.detail);
  late final _section = TextEditingController(text: _base.section);
  late final _quantity = TextEditingController(
    text: formatQuantity(_base.quantity).replaceAll(',', ''),
  );
  late final _price = TextEditingController();
  late final _hours = TextEditingController(
    text: trimNumber(_base.laborHours, decimals: 2),
  );
  late final _materials = TextEditingController(
    text: moneyInputText(_base.materialCostCents),
  );
  late final _other = TextEditingController(
    text: moneyInputText(_base.otherCostCents),
  );
  late Unit _unit = _base.unit;
  late Set<String> _tiers = _base.tierIds.isEmpty
      ? {for (final t in widget.quote.tiers) t.id}
      : {..._base.tierIds};
  var _priceTyped = false;
  var _costsTyped = false;
  var _dropOverride = false;

  Rates get _rates => widget.quote.rates;

  @override
  void dispose() {
    for (final c in [
      _description,
      _detail,
      _section,
      _quantity,
      _price,
      _hours,
      _materials,
      _other,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// The line as it would be saved right now.
  LineItem _resolve() {
    var item = _base.copyWith(
      description: _description.text.trim(),
      detail: _detail.text.trim(),
      section: _section.text.trim(),
      unit: _unit,
      tierIds: _tiers.length == widget.quote.tiers.length ? const {} : _tiers,
    );
    if (_dropOverride) item = item.withoutOverride();
    final q = parseNumber(_quantity.text);
    if (q != null && q > 0 && q != _base.quantity) item = item.withQuantity(q);
    if (_costsTyped) {
      item = item.withCosts(
        laborHours: parseNumber(_hours.text) ?? 0,
        materialCostCents: Money.parse(_materials.text) ?? 0,
        otherCostCents: Money.parse(_other.text) ?? 0,
      );
    }
    final typed = Money.parse(_price.text);
    if (_priceTyped && typed != null) item = item.withTotal(typed);
    return item;
  }

  String _explain(LineItem item) {
    switch (item.mode) {
      case PricingMode.fixed:
        return 'You set this price.';
      case PricingMode.unitRate:
        final entry = _rates.priceEntry(item.priceListId);
        return '${describeQuantity(item.quantity, item.unit)} at '
            '${Money.format(item.unitPriceCents!, cents: true)} per '
            '${item.unit.singular}'
            '${entry == null ? '' : ', from your price list'}.';
      case PricingMode.cost:
        final parts = [
          if (item.laborHours > 0)
            '${trimNumber(item.laborHours, decimals: 2)} hrs at '
                '${Money.format(_rates.laborRateCents)}',
          if (item.materialCostCents > 0)
            '${Money.format(item.materialCostCents)} materials + '
                '${trimNumber(_rates.materialMarkupPct)}%',
          if (item.otherCostCents > 0)
            '${Money.format(item.otherCostCents)} other',
        ];
        return parts.isEmpty
            ? 'Add hours or materials below, or set a price.'
            : '${parts.join(' + ')}${_rates.roundPrices ? ', rounded' : ''}.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final item = _resolve();
    final total = Pricing.line(item, _rates);
    final sections = {
      for (final i in widget.quote.items)
        if (i.section.isNotEmpty) i.section,
    };
    final isNew = widget.item == null;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader(
            isNew ? 'Add line' : 'Edit line',
            trailing: isNew
                ? null
                : IconButton(
                    tooltip: 'Delete line',
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: c.danger.fg,
                    ),
                    onPressed: () => Navigator.of(
                      context,
                    ).pop(LineEditResult(_base, deleted: true)),
                  ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                TextField(
                  controller: _description,
                  autofocus: isNew,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'What'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _detail,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Details (optional)',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _quantity,
                        enabled: !_unit.isLumpSum,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: decimalInput,
                        decoration: const InputDecoration(
                          labelText: 'Quantity',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<Unit>(
                        initialValue: _unit,
                        decoration: const InputDecoration(labelText: 'Unit'),
                        items: [
                          for (final u in Unit.values)
                            DropdownMenuItem(
                              value: u,
                              child: Text(u.isLumpSum ? 'lump sum' : u.plural),
                            ),
                        ],
                        onChanged: (u) => setState(() => _unit = u ?? _unit),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _section,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Section'),
                  onChanged: (_) => setState(() {}),
                ),
                if (sections.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in sections)
                        ActionChip(
                          label: Text(s),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _section.text = s),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.canvas,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('Line total', style: text.titleMedium),
                          ),
                          MoneyText(total, size: 28, weight: FontWeight.w800),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(_explain(item), style: text.bodySmall),
                      if (item.mode == PricingMode.fixed && !_priceTyped)
                        TextButton(
                          onPressed: () => setState(() => _dropOverride = true),
                          child: const Text('Use the calculated price'),
                        ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _price,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: decimalInput,
                        decoration: const InputDecoration(
                          labelText: 'Set your own price',
                          prefixText: r'$ ',
                        ),
                        onChanged: (v) =>
                            setState(() => _priceTyped = v.trim().isNotEmpty),
                      ),
                    ],
                  ),
                ),
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text('Hours and materials', style: text.titleSmall),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    children: [
                      for (final (controller, label, prefix) in [
                        (_hours, 'Labor hours, all workers', ''),
                        (_materials, 'Materials, your cost', r'$ '),
                        (_other, 'Other costs (dump fees, rentals)', r'$ '),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: TextField(
                            controller: controller,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: decimalInput,
                            decoration: InputDecoration(
                              labelText: label,
                              prefixText: prefix,
                            ),
                            onChanged: (_) => setState(() {
                              _costsTyped = true;
                              _priceTyped = false;
                              _price.clear();
                            }),
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.quote.hasTiers) ...[
                  Text('Included in', style: text.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in widget.quote.tiers)
                        FilterChip(
                          label: Text(t.name),
                          selected: _tiers.contains(t.id),
                          labelStyle: text.labelMedium?.copyWith(
                            color: _tiers.contains(t.id) ? c.canvas : c.ink,
                          ),
                          onSelected: (on) => setState(() {
                            final next = {..._tiers};
                            on ? next.add(t.id) : next.remove(t.id);
                            if (next.isNotEmpty) _tiers = next;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (_base.basis.isNotEmpty) ...[
                  Text('How Jobwalk estimated this', style: text.titleSmall),
                  const SizedBox(height: 4),
                  Text(_base.basis, style: text.bodySmall),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  onPressed: item.description.isEmpty
                      ? null
                      : () => Navigator.of(context).pop(LineEditResult(item)),
                  child: Text(isNew ? 'Add line' : 'Save'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
