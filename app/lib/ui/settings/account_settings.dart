part of 'settings_screen.dart';

/// Account, plan, card deposits, and team. Shown when signed in.
class _AccountSettings extends ConsumerWidget {
  const _AccountSettings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final account = session.account;
    final owner = session.isOwner;
    final plan = account?.business.plan ?? const Plan();
    final profile = ref.watch(settingsProvider.select((s) => s.profile));
    final payments = ref.watch(paymentsProvider);
    final team = ref.watch(teamProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Account'),
        _Group(
          children: [
            _Row(
              title: account?.user.email ?? 'Signed in',
              subtitle: [
                owner ? 'Owner' : 'Team member',
                if (profile.name.isNotEmpty) profile.name,
              ].join(' · '),
            ),
            _Row(title: 'Sign out', onTap: () => _signOut(context, ref)),
          ],
        ),
        const SectionLabel('Plan'),
        _Group(
          children: [
            _Row(title: plan.label, subtitle: _planDetail(plan)),
            if (owner && !plan.paid)
              _Row(
                title: 'Choose a plan',
                subtitle: 'Unlimited AI drafts, more people, card deposits.',
                onTap: () => showPlans(context),
              ),
            if (owner && plan.id != 'trial')
              _Row(
                title: 'Manage billing',
                subtitle: 'Change plan, update your card, or cancel.',
                onTap: () => _open(
                  context,
                  () => ref.read(serverProvider)!.billingPortal(),
                ),
              ),
          ],
        ),
        ...switch (payments) {
          AsyncData(:final value) when value.enabled => [
            const SectionLabel('Card deposits'),
            _Group(children: [_paymentsRow(context, ref, value, owner)]),
          ],
          _ => const <Widget>[],
        },
        SectionLabel(
          'Team',
          trailing: owner
              ? TextButton.icon(
                  onPressed: () => _addMember(context, ref),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                )
              : null,
        ),
        switch (team) {
          AsyncData(:final value) => _Group(
            children: [
              for (final m in value)
                _Row(
                  title: m.name.isEmpty ? m.email : m.name,
                  subtitle: [
                    if (m.name.isNotEmpty) m.email,
                    m.role == 'owner' ? 'Owner' : 'Member',
                    if (m.you) 'You',
                  ].join(' · '),
                  onTap: owner && !m.you
                      ? () => _removeMember(context, ref, m)
                      : null,
                ),
            ],
          ),
          AsyncError() => Panel(
            child: Text(
              "Couldn't load your team. Pull to refresh on the home screen "
              'and try again.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          _ => const Panel(child: LinearProgressIndicator()),
        },
      ],
    );
  }

  static String _planDetail(Plan plan) {
    if (plan.paid) {
      return switch (plan.status) {
        'past_due' => 'Payment failed. Update your card in Manage billing.',
        'trialing' => 'Trial of the paid plan',
        _ => 'Active · up to ${plan.maxUsers} people',
      };
    }
    if (plan.id != 'trial') {
      return 'Plan ended (${plan.status}). Choose a plan to keep drafting.';
    }
    final left = plan.trialDraftsLeft ?? 0;
    return '$left of ${plan.trialDraftsIncluded} free AI drafts left. Quotes '
        'you build by hand are always free.';
  }

  Widget _paymentsRow(
    BuildContext context,
    WidgetRef ref,
    Payments payments,
    bool owner,
  ) {
    final server = ref.read(serverProvider)!;
    Future<void> connect() async {
      await _open(context, server.connectPayments);
      ref.invalidate(paymentsProvider);
    }

    if (payments.ready) {
      return _Row(
        title: 'Card deposits are on',
        subtitle:
            'Customers can pay the deposit when they approve. '
            '${payments.feeDescription}.',
        onTap: owner ? () => _open(context, server.paymentsDashboard) : null,
      );
    }
    if (payments.connected) {
      return _Row(
        title: 'Finish payment setup',
        subtitle: 'Stripe needs a few more details before customers can pay.',
        onTap: owner ? connect : null,
      );
    }
    return _Row(
      title: 'Take deposits by card',
      subtitle:
          'Customers pay the deposit when they approve, and it goes to your '
          'bank. ${payments.feeDescription}.',
      onTap: owner ? connect : null,
    );
  }

  /// Opens a Stripe page the server made for us.
  static Future<void> _open(
    BuildContext context,
    Future<Uri> Function() link,
  ) async {
    try {
      await openLink((await link()).toString());
    } on ApiError catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final sync = ref.read(syncProvider.notifier);
    await sync.sync();
    final pending = sync.data.pending;
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          pending == 0
              ? 'Your quotes stay in your account. They leave this phone '
                    'until you sign in again.'
              : '${pending == 1 ? 'One change has' : '$pending changes have'}'
                    ' not reached Jobwalk yet (no connection). Signing out '
                    'now loses ${pending == 1 ? 'it' : 'them'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(sessionProvider.notifier).signOut();
  }

  Future<void> _addMember(BuildContext context, WidgetRef ref) async {
    final added = await showAppSheet<bool>(
      context,
      builder: (_) => const _MemberForm(),
    );
    if (added == true) ref.invalidate(teamProvider);
  }

  Future<void> _removeMember(
    BuildContext context,
    WidgetRef ref,
    TeamMember member,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Remove ${member.name.isEmpty ? member.email : member.name}?',
        ),
        content: const Text(
          'They lose access right away. Quotes they made stay with the '
          'business.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(serverProvider)!.removeMember(member.id);
      ref.invalidate(teamProvider);
    } on ApiError catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }

  static Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    bool owner,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteDialog(owner: owner),
    );
    if (ok != true) return;
    try {
      await ref.read(sessionProvider.notifier).deleteAccount();
    } on ApiError catch (e) {
      if (context.mounted) showSnack(context, e.message);
    }
  }
}

/// Deleting the account, at the bottom of settings.
class _YourData extends ConsumerWidget {
  const _YourData();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(sessionProvider.select((s) => s.isOwner));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Your data'),
        _Group(
          children: [
            _Row(
              title: owner ? 'Delete account' : 'Leave this business',
              titleColor: JobColors.of(context).danger.fg,
              subtitle: owner
                  ? 'Deletes the business, its quotes, customer links, and '
                        'photos, and cancels your plan.'
                  : 'Removes your access. Quotes stay with the business.',
              onTap: () => _AccountSettings._delete(context, ref, owner),
            ),
          ],
        ),
      ],
    );
  }
}

class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({required this.owner});

  final bool owner;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  final _confirm = TextEditingController();

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.owner ? 'Delete your account?' : 'Leave the business?'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.owner
              ? 'This permanently deletes every quote, customer link, and '
                    'photo, removes your team, and cancels your plan. It '
                    "can't be undone."
              : 'You will lose access to the business on every phone.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirm,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Type DELETE'),
          onChanged: (_) => setState(() {}),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: _confirm.text.trim() == 'DELETE'
            ? () => Navigator.pop(context, true)
            : null,
        child: Text(widget.owner ? 'Delete' : 'Leave'),
      ),
    ],
  );
}

class _MemberForm extends ConsumerStatefulWidget {
  const _MemberForm();

  @override
  ConsumerState<_MemberForm> createState() => _MemberFormState();
}

class _MemberFormState extends ConsumerState<_MemberForm> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(serverProvider)!
          .addMember(_email.text.trim(), name: _name.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } on ApiError catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      if (e.code == 'upgrade_required') {
        await showPlans(context, reason: e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _Form(
    title: 'Add someone',
    subtitle:
        'They sign in with this email and quote under your business name.',
    canSave: !_busy && _email.text.contains('@'),
    onSave: _save,
    children: [
      _input(
        _email,
        'Email',
        keyboard: TextInputType.emailAddress,
        onChanged: () => setState(() {}),
      ),
      _input(_name, 'Name (optional)'),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            _error!,
            style: TextStyle(color: JobColors.of(context).danger.fg),
          ),
        ),
    ],
  );
}
