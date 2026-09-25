import 'package:flutter/material.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import '../widgets/common.dart';

/// Job title, scope summary, and customer.
Future<Quote?> showHeaderEditor(BuildContext context, Quote quote) =>
    showAppSheet<Quote>(context, builder: (_) => _HeaderEditor(quote));

class _HeaderEditor extends StatefulWidget {
  const _HeaderEditor(this.quote);

  final Quote quote;

  @override
  State<_HeaderEditor> createState() => _HeaderEditorState();
}

class _HeaderEditorState extends State<_HeaderEditor> {
  late final _title = TextEditingController(text: widget.quote.title);
  late final _summary = TextEditingController(text: widget.quote.summary);
  late final _name = TextEditingController(text: widget.quote.customer.name);
  late final _phone = TextEditingController(text: widget.quote.customer.phone);
  late final _email = TextEditingController(text: widget.quote.customer.email);
  late final _address = TextEditingController(
    text: widget.quote.customer.address,
  );

  @override
  void dispose() {
    for (final c in [_title, _summary, _name, _phone, _email, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SheetForm(
    title: 'Job and customer',
    onSave: () => Navigator.of(context).pop(
      widget.quote.copyWith(
        title: _title.text.trim(),
        summary: _summary.text.trim(),
        customer: Customer(
          name: _name.text.trim(),
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          address: _address.text.trim(),
        ),
      ),
    ),
    children: [
      _field(_title, 'Job title', words: true),
      _field(_summary, 'Scope (what the customer reads first)', lines: 4),
      const SizedBox(height: 8),
      _field(_name, 'Customer name', words: true),
      _field(_phone, 'Mobile', keyboard: TextInputType.phone),
      _field(_email, 'Email', keyboard: TextInputType.emailAddress),
      _field(_address, 'Job address', words: true),
    ],
  );
}

/// An option's name and blurb, and whether it's the recommended one.
Future<Quote?> showTierEditor(BuildContext context, Quote quote, Tier tier) =>
    showAppSheet<Quote>(context, builder: (_) => _TierEditor(quote, tier));

class _TierEditor extends StatefulWidget {
  const _TierEditor(this.quote, this.tier);

  final Quote quote;
  final Tier tier;

  @override
  State<_TierEditor> createState() => _TierEditorState();
}

class _TierEditorState extends State<_TierEditor> {
  late final _name = TextEditingController(text: widget.tier.name);
  late final _summary = TextEditingController(text: widget.tier.summary);
  late var _recommended = widget.tier.recommended;

  @override
  void dispose() {
    _name.dispose();
    _summary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SheetForm(
    title: 'Edit option',
    onSave: () {
      final name = _name.text.trim();
      Navigator.of(context).pop(
        widget.quote.copyWith(
          tiers: [
            for (final t in widget.quote.tiers)
              t.id == widget.tier.id
                  ? t.copyWith(
                      name: name.isEmpty ? t.name : name,
                      summary: _summary.text.trim(),
                      recommended: _recommended,
                    )
                  : t.copyWith(recommended: _recommended ? false : null),
          ],
        ),
      );
    },
    children: [
      _field(_name, 'Name', words: false),
      _field(_summary, 'One line for the customer', lines: 2),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Recommend this option'),
        value: _recommended,
        onChanged: (v) => setState(() => _recommended = v),
      ),
    ],
  );
}

/// The note to the customer and what's not included.
Future<Quote?> showMessageEditor(BuildContext context, Quote quote) =>
    showAppSheet<Quote>(context, builder: (_) => _MessageEditor(quote));

class _MessageEditor extends StatefulWidget {
  const _MessageEditor(this.quote);

  final Quote quote;

  @override
  State<_MessageEditor> createState() => _MessageEditorState();
}

class _MessageEditorState extends State<_MessageEditor> {
  late final _message = TextEditingController(text: widget.quote.message);
  late final _exclusions = TextEditingController(
    text: widget.quote.exclusions.join('\n'),
  );

  @override
  void dispose() {
    _message.dispose();
    _exclusions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SheetForm(
    title: 'Note and exclusions',
    onSave: () => Navigator.of(context).pop(
      widget.quote.copyWith(
        message: _message.text.trim(),
        exclusions: [
          for (final line in _exclusions.text.split('\n'))
            if (line.trim().isNotEmpty) line.trim(),
        ],
      ),
    ),
    children: [
      _field(_message, 'Note to the customer', lines: 4),
      _field(_exclusions, 'Not included (one per line)', lines: 4),
    ],
  );
}

/// A discount off the job, before tax.
Future<Quote?> showDiscountEditor(BuildContext context, Quote quote) =>
    showAppSheet<Quote>(context, builder: (_) => _DiscountEditor(quote));

class _DiscountEditor extends StatefulWidget {
  const _DiscountEditor(this.quote);

  final Quote quote;

  @override
  State<_DiscountEditor> createState() => _DiscountEditorState();
}

class _DiscountEditorState extends State<_DiscountEditor> {
  late final _amount = TextEditingController(
    text: widget.quote.discountCents == 0
        ? ''
        : moneyInputText(widget.quote.discountCents),
  );

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _SheetForm(
    title: 'Discount',
    subtitle: 'Taken off every option, before tax.',
    onSave: () => Navigator.of(
      context,
    ).pop(widget.quote.copyWith(discountCents: Money.parse(_amount.text) ?? 0)),
    children: [
      TextField(
        controller: _amount,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: decimalInput,
        decoration: const InputDecoration(
          labelText: 'Amount',
          prefixText: r'$ ',
          helperText: 'Leave empty for no discount.',
        ),
      ),
    ],
  );
}

Widget _field(
  TextEditingController controller,
  String label, {
  int lines = 1,
  bool words = false,
  TextInputType? keyboard,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: TextField(
    controller: controller,
    minLines: lines,
    maxLines: lines == 1 ? 1 : lines + 2,
    keyboardType: keyboard,
    textCapitalization: words
        ? TextCapitalization.words
        : TextCapitalization.sentences,
    decoration: InputDecoration(labelText: label, alignLabelWithHint: true),
  ),
);

class _SheetForm extends StatelessWidget {
  const _SheetForm({
    required this.title,
    required this.children,
    required this.onSave,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title, subtitle: subtitle),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              ...children,
              const SizedBox(height: 8),
              FilledButton(onPressed: onSave, child: const Text('Save')),
            ],
          ),
        ),
      ],
    ),
  );
}
