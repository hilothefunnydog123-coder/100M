import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import '../../services/api.dart';
import '../../services/launcher.dart';
import '../../state/providers.dart';
import '../../state/quote_actions.dart';
import '../../theme/colors.dart';
import '../widgets/common.dart';

Future<void> showSendSheet(BuildContext context, String quoteId) =>
    showAppSheet<void>(context, builder: (_) => SendSheet(quoteId: quoteId));

enum _Channel { text, email, copy, share }

/// Publishes the quote and hands the link to the contractor's own messages
/// or email, so it comes from their number.
class SendSheet extends ConsumerStatefulWidget {
  const SendSheet({super.key, required this.quoteId});

  final String quoteId;

  @override
  ConsumerState<SendSheet> createState() => _SendSheetState();
}

class _SendSheetState extends ConsumerState<SendSheet> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  _Channel? _busy;
  String? _error;

  @override
  void initState() {
    super.initState();
    final customer = ref.read(quoteProvider(widget.quoteId))?.customer;
    _name.text = customer?.name ?? '';
    _phone.text = customer?.phone ?? '';
    _email.text = customer?.email ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  String _message(Quote q, String url) {
    final business = ref.read(settingsProvider).profile.name;
    final first = _name.text.trim().split(RegExp(r'\s+')).first;
    final job = q.title.isEmpty ? '' : ' for the ${q.title.toLowerCase()}';
    return 'Hi${first.isEmpty ? '' : ' $first'}, here is your quote from '
        '$business$job: $url\n\nYou can pick an option and approve it right '
        'on that page. Any questions, just reply here.';
  }

  Future<void> _send(_Channel channel) async {
    setState(() {
      _busy = channel;
      _error = null;
    });
    try {
      final quotes = ref.read(quotesProvider.notifier);
      var quote = ref.read(quoteProvider(widget.quoteId))!;
      final customer = quote.customer.copyWith(
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
      );
      if (customer.name != quote.customer.name ||
          customer.phone != quote.customer.phone ||
          customer.email != quote.customer.email) {
        quote = await quotes.save(quote.copyWith(customer: customer));
      }
      final sent = await ref.read(quoteActionsProvider).publish(quote);
      final url = sent.share!.url;
      final message = _message(sent, url);
      final business = ref.read(settingsProvider).profile.name;
      // The quote is live at this point; if the messages app, email, or
      // clipboard isn't available, show the link instead of failing.
      var handedOff = true;
      try {
        switch (channel) {
          case _Channel.text:
            handedOff = await composeText(customer.phone, message);
          case _Channel.email:
            handedOff = await composeEmail(
              customer.email,
              'Your quote from $business',
              message,
            );
          case _Channel.copy:
            await copyText(url);
          case _Channel.share:
            await shareText(message, subject: 'Your quote from $business');
        }
      } on Object {
        handedOff = false;
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showSnack(
        context,
        !handedOff
            ? 'Quote is live at $url'
            : channel == _Channel.copy
            ? 'Link copied. Paste it anywhere.'
            : 'Quote is live. You will see when it is opened.',
      );
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = ref.watch(quoteProvider(widget.quoteId));
    if (quote == null) return const SizedBox.shrink();
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final demo = ref.watch(clientProvider).isDemo;
    final totals = [
      for (final id in quote.tierIdsOrNull) quote.totals(id).totalCents,
    ]..sort();
    final range = quote.hasTiers
        ? '${quote.tiers.length} options, ${Money.format(totals.first)} to '
              '${Money.format(totals.last)}'
        : Money.format(totals.single);
    Widget busyOr(_Channel ch, Widget icon) => _busy == ch
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : icon;

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetHeader('Send ${quote.label}', subtitle: range),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                if (quote.openAssumptions > 0)
                  Container(
                    margin: const EdgeInsets.only(bottom: 14),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.warn.bg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${quote.openAssumptions} assumption'
                      '${quote.openAssumptions == 1 ? ' is' : 's are'} not '
                      'checked yet. You can still send.',
                      style: text.bodyMedium?.copyWith(color: c.warn.fg),
                    ),
                  ),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Customer name'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Mobile'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.canvas,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _message(quote, 'jobwalk.app/q/...'),
                    style: text.bodyMedium?.copyWith(color: c.inkMuted),
                  ),
                ),
                if (demo) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Demo mode: the link only works inside this app. Open '
                    'the quote and tap the eye icon to approve it as the '
                    'customer.',
                    style: text.bodySmall,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: text.bodyMedium?.copyWith(color: c.danger.fg),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy != null
                      ? null
                      : () => _send(
                          _phone.text.trim().isEmpty
                              ? _Channel.share
                              : _Channel.text,
                        ),
                  icon: busyOr(
                    _Channel.text,
                    busyOr(_Channel.share, const Icon(Icons.sms_outlined)),
                  ),
                  label: Text(
                    _phone.text.trim().isEmpty ? 'Send link' : 'Text it',
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy != null || _email.text.trim().isEmpty
                            ? null
                            : () => _send(_Channel.email),
                        icon: busyOr(
                          _Channel.email,
                          const Icon(Icons.mail_outline_rounded),
                        ),
                        label: const Text('Email'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy != null
                            ? null
                            : () => _send(_Channel.copy),
                        icon: busyOr(
                          _Channel.copy,
                          const Icon(Icons.link_rounded),
                        ),
                        label: const Text('Copy link'),
                      ),
                    ),
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
