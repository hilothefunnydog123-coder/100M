import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import '../../services/launcher.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final config = ref.watch(configProvider);
    final p = settings.profile;
    final r = settings.rates;
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final notifier = ref.read(settingsProvider.notifier);
    final learned = r.priceList.where((e) => e.learned).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          const SectionLabel('Business'),
          _Group(
            children: [
              _Row(
                title: p.name,
                subtitle: [
                  p.trades.map((t) => t.label).join(', '),
                  if (p.phone.isNotEmpty) p.phone,
                  if (p.email.isNotEmpty) p.email,
                  if (p.license.isNotEmpty) 'License ${p.license}',
                ].where((s) => s.isNotEmpty).join(' · '),
                onTap: () async {
                  final updated = await showAppSheet<BusinessProfile>(
                    context,
                    builder: (_) => _BusinessForm(p),
                  );
                  if (updated != null) await notifier.setProfile(updated);
                },
              ),
            ],
          ),
          const SectionLabel('How you price'),
          _Group(
            children: [
              _Row(
                title:
                    'Labor ${Money.format(r.laborRateCents, cents: r.laborRateCents % 100 != 0)}/hr'
                    ' · materials +${trimNumber(r.materialMarkupPct)}%',
                subtitle: [
                  if (r.minimumJobCents > 0)
                    'Minimum job ${Money.format(r.minimumJobCents)}',
                  'Deposit ${trimNumber(r.depositPct)}%',
                  if (r.taxRatePct > 0)
                    'Tax ${trimNumber(r.taxRatePct, decimals: 3)}%',
                  'Valid ${r.validDays} days',
                ].join(' · '),
                onTap: () async {
                  final updated = await showAppSheet<Rates>(
                    context,
                    builder: (_) => _RatesForm(r),
                  );
                  if (updated != null) await notifier.setRates(updated);
                },
              ),
            ],
          ),
          SectionLabel(
            'Your prices',
            trailing: TextButton.icon(
              onPressed: () async {
                final entry = await showAppSheet<PriceEntry>(
                  context,
                  builder: (_) => const _PriceForm(null),
                );
                if (entry != null) {
                  await notifier.setRates(
                    r.copyWith(priceList: [...r.priceList, entry]),
                  );
                }
              },
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              'When a line matches one of these, Jobwalk uses your price '
              'instead of estimating. Prices you type over a draft are '
              'learned here automatically${learned > 0 ? ' ($learned so far)' : ''}.',
              style: text.bodySmall,
            ),
          ),
          if (r.priceList.isEmpty)
            Panel(
              child: Text(
                'No prices yet. Add the ones you quote the most, like '
                '"Interior walls, 2 coats" per sq ft.',
                style: text.bodyMedium?.copyWith(color: c.inkMuted),
              ),
            )
          else
            _Group(
              children: [
                for (final e in r.priceList)
                  _Row(
                    title: e.name,
                    subtitle: e.learned ? 'Learned from your quotes' : null,
                    trailing: Text(
                      '${Money.format(e.unitPriceCents, cents: e.unitPriceCents % 100 != 0)}'
                      ' / ${e.unit.isLumpSum ? 'job' : e.unit.singular}',
                      style: text.titleSmall,
                    ),
                    onTap: () async {
                      final updated = await showAppSheet<PriceEntry>(
                        context,
                        builder: (_) => _PriceForm(e),
                      );
                      if (updated == null) return;
                      await notifier.setRates(
                        r.copyWith(
                          priceList: [
                            for (final x in r.priceList)
                              if (x.id != e.id)
                                x
                              else if (updated.name.isNotEmpty)
                                updated,
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          const SectionLabel('Getting paid'),
          _Group(
            children: [
              _Row(
                title: p.paymentLink.isEmpty
                    ? 'Add a deposit link'
                    : 'Deposit link',
                subtitle: p.paymentLink.isEmpty
                    ? 'A Stripe, Square, or PayPal payment link. Customers '
                          'see a Pay deposit button after approving.'
                    : p.paymentLink,
                onTap: () async {
                  final link = await showAppSheet<String>(
                    context,
                    builder: (_) => _TextForm(
                      title: 'Deposit link',
                      label: 'https://',
                      initial: p.paymentLink,
                      keyboard: TextInputType.url,
                      validate: (v) => v.isEmpty || safeLink(v).isNotEmpty
                          ? null
                          : 'Use a full https:// link.',
                    ),
                  );
                  if (link != null) {
                    await notifier.setProfile(p.copyWith(paymentLink: link));
                  }
                },
              ),
              _Row(
                title: 'Terms on every quote',
                subtitle: p.terms,
                onTap: () async {
                  final terms = await showAppSheet<String>(
                    context,
                    builder: (_) => _TextForm(
                      title: 'Terms',
                      label: 'Terms',
                      initial: p.terms,
                      lines: 5,
                    ),
                  );
                  if (terms != null) {
                    await notifier.setProfile(p.copyWith(terms: terms));
                  }
                },
              ),
            ],
          ),
          const SectionLabel('About'),
          _Group(
            children: [
              _Row(
                title: config.demoMode ? 'Demo mode' : 'Connected',
                subtitle: config.demoMode
                    ? 'Drafts come from sample jobs and links stay on this '
                          'phone. Build with API_BASE_URL to quote real jobs.'
                    : config.apiBaseUrl.toString(),
              ),
              _Row(
                title: 'Privacy policy',
                onTap: () => openLink(config.privacyPolicyUrl),
              ),
              _Row(
                title: 'Erase all data',
                titleColor: c.danger.fg,
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Erase everything?'),
                      content: const Text(
                        'This deletes every quote, photo, and setting on '
                        'this phone. Links you sent keep working.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Erase'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true || !context.mounted) return;
                  Navigator.of(context).popUntil((r) => r.isFirst);
                  await ref.read(quotesProvider.notifier).clearAll();
                  await notifier.reset();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Panel(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const Divider(indent: 16),
          child,
        ],
      ],
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text.titleSmall?.copyWith(color: titleColor),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            if (onTap != null && trailing == null)
              Icon(
                Icons.chevron_right_rounded,
                color: JobColors.of(context).inkFaint,
              ),
          ],
        ),
      ),
    );
  }
}

class _BusinessForm extends StatefulWidget {
  const _BusinessForm(this.profile);

  final BusinessProfile profile;

  @override
  State<_BusinessForm> createState() => _BusinessFormState();
}

class _BusinessFormState extends State<_BusinessForm> {
  late final _name = TextEditingController(text: widget.profile.name);
  late final _phone = TextEditingController(text: widget.profile.phone);
  late final _email = TextEditingController(text: widget.profile.email);
  late final _zip = TextEditingController(text: widget.profile.zip);
  late final _license = TextEditingController(text: widget.profile.license);
  late final _trades = [...widget.profile.trades];

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _zip, _license]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    return _Form(
      title: 'Business',
      canSave: _name.text.trim().isNotEmpty && _trades.isNotEmpty,
      onSave: () => Navigator.of(context).pop(
        widget.profile.copyWith(
          name: _name.text.trim(),
          trades: _trades,
          phone: _phone.text.trim(),
          email: _email.text.trim(),
          zip: _zip.text.trim(),
          license: _license.text.trim(),
        ),
      ),
      children: [
        _input(_name, 'Business name', onChanged: () => setState(() {})),
        _input(_phone, 'Phone', keyboard: TextInputType.phone),
        _input(_email, 'Email', keyboard: TextInputType.emailAddress),
        Row(
          children: [
            Expanded(
              child: _input(
                _zip,
                'ZIP (for material prices)',
                keyboard: TextInputType.number,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _input(_license, 'License #')),
          ],
        ),
        Text('Trades', style: text.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in Trade.values)
              FilterChip(
                label: Text(t.label),
                selected: _trades.contains(t),
                labelStyle: text.labelMedium?.copyWith(
                  color: _trades.contains(t) ? c.canvas : c.ink,
                ),
                onSelected: (on) =>
                    setState(() => on ? _trades.add(t) : _trades.remove(t)),
              ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _RatesForm extends StatefulWidget {
  const _RatesForm(this.rates);

  final Rates rates;

  @override
  State<_RatesForm> createState() => _RatesFormState();
}

class _RatesFormState extends State<_RatesForm> {
  late final _labor = TextEditingController(
    text: moneyInputText(widget.rates.laborRateCents),
  );
  late final _markup = TextEditingController(
    text: trimNumber(widget.rates.materialMarkupPct),
  );
  late final _minimum = TextEditingController(
    text: moneyInputText(widget.rates.minimumJobCents),
  );
  late final _tax = TextEditingController(
    text: trimNumber(widget.rates.taxRatePct, decimals: 3),
  );
  late final _deposit = TextEditingController(
    text: trimNumber(widget.rates.depositPct),
  );
  late final _valid = TextEditingController(text: '${widget.rates.validDays}');
  late var _round = widget.rates.roundPrices;

  @override
  void dispose() {
    for (final c in [_labor, _markup, _minimum, _tax, _deposit, _valid]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Form(
    title: 'How you price',
    subtitle:
        'Applies to new quotes. Quotes you already made keep their '
        'prices.',
    onSave: () {
      final r = widget.rates;
      Navigator.of(context).pop(
        r.copyWith(
          laborRateCents: Money.parse(_labor.text) ?? r.laborRateCents,
          materialMarkupPct: (parseNumber(_markup.text) ?? r.materialMarkupPct)
              .clamp(0, 300)
              .toDouble(),
          minimumJobCents: Money.parse(_minimum.text) ?? 0,
          taxRatePct: (parseNumber(_tax.text) ?? 0).clamp(0, 25).toDouble(),
          depositPct: (parseNumber(_deposit.text) ?? r.depositPct)
              .clamp(0, 100)
              .toDouble(),
          validDays: (parseNumber(_valid.text)?.round() ?? r.validDays).clamp(
            1,
            365,
          ),
          roundPrices: _round,
        ),
      );
    },
    children: [
      Row(
        children: [
          Expanded(
            child: _input(
              _labor,
              'Labor per hour',
              prefix: r'$ ',
              number: true,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _input(
              _markup,
              'Material markup',
              suffix: '%',
              number: true,
            ),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: _input(_minimum, 'Minimum job', prefix: r'$ ', number: true),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _input(_deposit, 'Deposit', suffix: '%', number: true),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(child: _input(_tax, 'Sales tax', suffix: '%', number: true)),
          const SizedBox(width: 10),
          Expanded(
            child: _input(_valid, 'Valid for', suffix: 'days', number: true),
          ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Round prices'),
        subtitle: const Text(r'$2,480 instead of $2,477.63'),
        value: _round,
        onChanged: (v) => setState(() => _round = v),
      ),
    ],
  );
}

class _PriceForm extends StatefulWidget {
  const _PriceForm(this.entry);

  final PriceEntry? entry;

  @override
  State<_PriceForm> createState() => _PriceFormState();
}

class _PriceFormState extends State<_PriceForm> {
  late final _name = TextEditingController(text: widget.entry?.name ?? '');
  late final _price = TextEditingController(
    text: widget.entry == null
        ? ''
        : moneyInputText(widget.entry!.unitPriceCents),
  );
  late var _unit = widget.entry?.unit ?? Unit.sqFt;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Form(
    title: widget.entry == null ? 'Add a price' : 'Edit price',
    canSave: _name.text.trim().isNotEmpty && Money.parse(_price.text) != null,
    onSave: () => Navigator.of(context).pop(
      PriceEntry(
        id: widget.entry?.id ?? newId('p', length: 8),
        name: _name.text.trim(),
        unit: _unit,
        unitPriceCents: Money.parse(_price.text)!,
        updatedAt: DateTime.now().toUtc(),
      ),
    ),
    extraAction: widget.entry == null
        ? null
        : TextButton(
            onPressed: () =>
                Navigator.of(context).pop(widget.entry!.copyWith(name: '')),
            child: const Text('Delete'),
          ),
    children: [
      _input(
        _name,
        'What',
        hint: 'Interior walls, 2 coats',
        onChanged: () => setState(() {}),
      ),
      Row(
        children: [
          Expanded(
            child: _input(
              _price,
              'Price',
              prefix: r'$ ',
              number: true,
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DropdownButtonFormField<Unit>(
                initialValue: _unit,
                decoration: const InputDecoration(labelText: 'Per'),
                items: [
                  for (final u in Unit.values)
                    DropdownMenuItem(
                      value: u,
                      child: Text(u.isLumpSum ? 'job' : u.singular),
                    ),
                ],
                onChanged: (u) => setState(() => _unit = u ?? _unit),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _TextForm extends StatefulWidget {
  const _TextForm({
    required this.title,
    required this.label,
    required this.initial,
    this.lines = 1,
    this.keyboard,
    this.validate,
  });

  final String title;
  final String label;
  final String initial;
  final int lines;
  final TextInputType? keyboard;
  final String? Function(String)? validate;

  @override
  State<_TextForm> createState() => _TextFormState();
}

class _TextFormState extends State<_TextForm> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Form(
    title: widget.title,
    onSave: () {
      final value = _controller.text.trim();
      final error = widget.validate?.call(value);
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      Navigator.of(context).pop(value);
    },
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: widget.lines,
          maxLines: widget.lines == 1 ? 1 : widget.lines + 3,
          keyboardType: widget.keyboard,
          decoration: InputDecoration(
            labelText: widget.label,
            errorText: _error,
            alignLabelWithHint: true,
          ),
        ),
      ),
    ],
  );
}

Widget _input(
  TextEditingController controller,
  String label, {
  String? prefix,
  String? suffix,
  String? hint,
  bool number = false,
  TextInputType? keyboard,
  VoidCallback? onChanged,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 10),
  child: TextField(
    controller: controller,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : keyboard,
    inputFormatters: number ? decimalInput : null,
    textCapitalization: number || keyboard != null
        ? TextCapitalization.none
        : TextCapitalization.words,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      prefixText: prefix,
      suffixText: suffix,
    ),
    onChanged: onChanged == null ? null : (_) => onChanged(),
  ),
);

class _Form extends StatelessWidget {
  const _Form({
    required this.title,
    required this.children,
    required this.onSave,
    this.subtitle,
    this.canSave = true,
    this.extraAction,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final VoidCallback onSave;
  final bool canSave;
  final Widget? extraAction;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SheetHeader(title, subtitle: subtitle, trailing: extraAction),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              ...children,
              const SizedBox(height: 8),
              FilledButton(
                onPressed: canSave ? onSave : null,
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
