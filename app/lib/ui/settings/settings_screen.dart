import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotcheck_core/spotcheck_core.dart';

import '../../services/launcher.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../onboarding/onboarding_screen.dart';
import '../paywall/paywall_screen.dart';
import '../widgets/common.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _editProfile(BuildContext context, WidgetRef ref) async {
    var answers = ref.read(settingsProvider).profileAnswers;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          builder: (context, scroll) => Column(
            children: [
              Expanded(
                child: PageBody(
                  controller: scroll,
                  children: [
                    Text(
                      'Your profile',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    ProfileForm(
                      answers: answers,
                      onChanged: (a) => setState(() => answers = a),
                    ),
                  ],
                ),
              ),
              BottomActions(
                children: [
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (saved == true) {
      await ref.read(settingsProvider.notifier).setProfile(answers);
    }
  }

  Future<void> _editEmergencyNumber(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: ref.read(settingsProvider).emergencyNumber,
    );
    final number = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Emergency number'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(hintText: '911, 112, 999, 000…'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (number != null && RegExp(r'^[0-9+]{2,6}$').hasMatch(number)) {
      await ref.read(settingsProvider.notifier).setEmergencyNumber(number);
    }
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text(
          'This removes every check, photo, and your profile from this '
          'phone. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete everything'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(historyProvider.notifier).clearAll();
    await ref.read(settingsProvider.notifier).reset();
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final config = ref.watch(configProvider);
    final c = SpotColors.of(context);
    final profile = settings.profileAnswers;
    final age = IntakeCatalog.byId(
      Q.ageBand,
    )!.option(profile.single(Q.ageBand) ?? '')?.label;

    Widget tile(
      IconData icon,
      String title, {
      String? subtitle,
      VoidCallback? onTap,
      Color? color,
    }) => ListTile(
      leading: Icon(icon, color: color ?? c.inkMuted),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: PageBody(
        children: [
          const SectionTitle('You'),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                tile(
                  Icons.person_outline,
                  'Profile',
                  subtitle: age ?? 'Not set',
                  onTap: () => _editProfile(context, ref),
                ),
                tile(
                  Icons.call_outlined,
                  'Emergency number',
                  subtitle: settings.emergencyNumber,
                  onTap: () => _editEmergencyNumber(context, ref),
                ),
              ],
            ),
          ),
          const SectionTitle('Subscription'),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: settings.pro
                ? tile(
                    Icons.workspace_premium_outlined,
                    'SpotCheck Pro',
                    subtitle: 'Active',
                    color: c.pro,
                  )
                : tile(
                    Icons.workspace_premium_outlined,
                    'Upgrade to Pro',
                    subtitle: switch (ref.watch(checksRemainingProvider)) {
                      1 => '1 free check left',
                      final n => '$n free checks left',
                    },
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<bool>(
                        fullscreenDialog: true,
                        builder: (_) => const PaywallScreen(),
                      ),
                    ),
                  ),
          ),
          const SectionTitle('Privacy'),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                tile(
                  Icons.phone_iphone,
                  'Stored on this phone',
                  subtitle:
                      'Your checks, photos, and profile. Photos sent for '
                      'analysis are not stored on our servers.',
                ),
                tile(
                  Icons.policy_outlined,
                  'Privacy policy',
                  onTap: () => openLink(config.privacyPolicyUrl),
                ),
                tile(
                  Icons.delete_forever_outlined,
                  'Delete all data',
                  color: c.forUrgency(Urgency.emergency).fg,
                  onTap: () => _deleteAll(context, ref),
                ),
              ],
            ),
          ),
          const SectionTitle('About'),
          SurfaceCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                tile(
                  Icons.health_and_safety_outlined,
                  'How SpotCheck works',
                  subtitle:
                      'An AI model describes the photo and suggests '
                      'possibilities; fixed safety rules based on your '
                      'answers can only make the advice more cautious.',
                ),
                tile(
                  Icons.gavel_outlined,
                  'Terms of use',
                  onTap: () => openLink(config.termsUrl),
                ),
                if (config.demoMode)
                  tile(
                    Icons.science_outlined,
                    'Demo mode',
                    subtitle:
                        'Results are canned examples. Build with '
                        '--dart-define=API_BASE_URL=… for real analysis.',
                    color: c.pro,
                  ),
              ],
            ),
          ),
          const DisclaimerText(),
        ],
      ),
    );
  }
}
