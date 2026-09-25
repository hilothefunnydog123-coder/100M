import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../check/analysis_screen.dart';
import '../home/home_screen.dart';
import '../result/result_view.dart';
import '../widgets/common.dart';
import '../widgets/triage.dart';

class CheckDetailScreen extends ConsumerWidget {
  const CheckDetailScreen({super.key, required this.recordId});

  final String recordId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this check?'),
        content: const Text(
          'The photos and result will be removed from this phone.',
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
    if (ok != true || !context.mounted) return;
    Navigator.of(context).pop();
    await ref.read(historyProvider.notifier).delete(recordId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final record = history.where((r) => r.id == recordId).firstOrNull;
    if (record == null) return Scaffold(appBar: AppBar());
    final previous = record.followUpOf == null
        ? null
        : history.where((r) => r.id == record.followUpOf).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(record.site.label),
        actions: [
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ResultView(
        result: record.result,
        site: record.site,
        photo: StoredPhoto(photoKey: record.photoKeys.firstOrNull),
        extra: [
          if (record.photoKeys.length > 1) ...[
            const SectionTitle('Photos', icon: Icons.photo_library_outlined),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final key in record.photoKeys)
                  StoredPhoto(photoKey: key, size: 100),
              ],
            ),
          ],
          if (previous != null) ...[
            const SectionTitle('Compared with earlier', icon: Icons.compare),
            _Comparison(before: previous, after: record),
          ],
          const SectionTitle(
            'What did a doctor say?',
            icon: Icons.medical_information_outlined,
          ),
          _VerdictField(record: record),
          const SizedBox(height: 20),
          ResultActions(record: record),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => startCheck(context, ref, recheckOf: record),
            icon: const Icon(Icons.event_repeat),
            label: const Text('Recheck this spot'),
          ),
        ],
      ),
    );
  }
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.before, required this.after});

  final CheckRecord before;
  final CheckRecord after;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget column(String label, CheckRecord r) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelMedium),
          Text(formatDate(r.createdAt), style: text.bodySmall),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (_, constraints) => StoredPhoto(
              photoKey: r.photoKeys.firstOrNull,
              size: constraints.maxWidth,
            ),
          ),
          const SizedBox(height: 8),
          if (r.result.urgency case final u?) UrgencyBadge(u),
        ],
      ),
    );
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              column('Before', before),
              const SizedBox(width: 12),
              column('Now', after),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Look for changes in size, shape, color, or height. Any change '
            'in a mole is worth showing to a dermatologist.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _VerdictField extends ConsumerStatefulWidget {
  const _VerdictField({required this.record});

  final CheckRecord record;

  @override
  ConsumerState<_VerdictField> createState() => _VerdictFieldState();
}

class _VerdictFieldState extends ConsumerState<_VerdictField> {
  late final _controller = TextEditingController(
    text: widget.record.doctorVerdict,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref
        .read(historyProvider.notifier)
        .replace(
          widget.record.copyWith(doctorVerdict: _controller.text.trim()),
        );
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          maxLines: 3,
          minLines: 2,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'e.g. "Dermatologist said it\'s a harmless mole."',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                'Keeping track of what doctors conclude helps you, and it '
                'is how SpotCheck gets more accurate.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: SpotColors.of(context).inkFaint,
                ),
              ),
            ),
            TextButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ],
    );
  }
}
