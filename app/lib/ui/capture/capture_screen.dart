import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import '../../services/photos.dart';
import '../../state/providers.dart';
import '../../theme/colors.dart';
import '../widgets/common.dart';
import 'building_screen.dart';

/// What the walkthrough produced: photos, a note, maybe a customer.
class CaptureResult {
  const CaptureResult({
    required this.photos,
    this.note = '',
    this.customer = const Customer(),
    this.sample,
  });

  final List<JobPhotoFile> photos;
  final String note;
  final Customer customer;

  /// Set when the photos are one of the bundled sample jobs.
  final SampleJob? sample;
}

class _Shot {
  _Shot(this.preview);

  final Uint8List preview;
  JobPhotoFile? file;
}

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key, this.sample});

  /// Starts with a sample job loaded.
  final SampleJob? sample;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> {
  static const maxPhotos = DraftRequest.maxPhotos;

  final _shots = <_Shot>[];
  final _note = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  var _showCustomer = false;
  var _busy = 0;
  SampleJob? _sample;

  @override
  void initState() {
    super.initState();
    final sample = widget.sample;
    if (sample != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSample(sample));
    }
  }

  @override
  void dispose() {
    for (final c in [_note, _name, _phone, _email, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addBytes(List<Uint8List> picked) async {
    final process = ref.read(photoProcessorProvider);
    final room = maxPhotos - _shots.length;
    for (final bytes in picked.take(room)) {
      final shot = _Shot(bytes);
      setState(() {
        _shots.add(shot);
        _busy++;
      });
      try {
        shot.file = await process(bytes);
      } on FormatException {
        if (mounted) showSnack(context, "That file isn't a photo we can read.");
        _shots.remove(shot);
      } finally {
        if (mounted) setState(() => _busy--);
      }
    }
  }

  Future<void> _pick(PhotoOrigin origin) async {
    final picked = await ref
        .read(photoSourceProvider)
        .pick(origin, max: maxPhotos - _shots.length);
    if (picked.isEmpty || !mounted) return;
    setState(() => _sample = null);
    await _addBytes(picked);
  }

  Future<void> _loadSample(SampleJob job) async {
    final photos = await loadSamplePhotos(job);
    if (!mounted) return;
    final context = sampleContext(job);
    setState(() {
      _shots.clear();
      _sample = job;
      _note.text = context.note;
      if (_name.text.isEmpty) _name.text = context.customer;
      _showCustomer = true;
    });
    await _addBytes(photos);
    if (mounted) setState(() => _sample = job);
  }

  void _build() {
    final files = [for (final s in _shots) ?s.file];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BuildingScreen(
          capture: CaptureResult(
            photos: files,
            note: _note.text.trim(),
            sample: _sample,
            customer: Customer(
              name: _name.text.trim(),
              phone: _phone.text.trim(),
              email: _email.text.trim(),
              address: _address.text.trim(),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final ready = _shots.isNotEmpty && _busy == 0;
    final dark = [
      for (final s in _shots)
        if (s.file?.problems.isNotEmpty ?? false) s.file!.problems.first,
    ];

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('New quote'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Row(
            children: [
              Expanded(child: Text('Photos', style: text.titleLarge)),
              Text('${_shots.length} of $maxPhotos', style: text.bodySmall),
            ],
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final shot in _shots)
                _ShotTile(
                  shot: shot,
                  onRemove: () => setState(() {
                    _shots.remove(shot);
                    if (_shots.isEmpty) _sample = null;
                  }),
                ),
              if (_shots.length < maxPhotos) ...[
                _AddTile(
                  icon: Icons.photo_camera_rounded,
                  label: 'Take photo',
                  primary: true,
                  onTap: () => _pick(PhotoOrigin.camera),
                ),
                if (_shots.length < maxPhotos - 1)
                  _AddTile(
                    icon: Icons.photo_library_outlined,
                    label: 'From library',
                    onTap: () => _pick(PhotoOrigin.library),
                  ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          if (dark.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${dark.first.label}: ${dark.first.tip}',
                style: text.bodySmall?.copyWith(color: c.warn.fg),
              ),
            ),
          Text(
            'Get the whole area first, then the details. Something of known '
            'size in the shot (a door, a car, a tape measure) sharpens the '
            'measurements.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 24),
          Text('Notes', style: text.titleLarge),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            minLines: 3,
            maxLines: 6,
            maxLength: DraftRequest.maxNoteLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText:
                  'What should the quote cover? "Two coats, trim too, '
                  'customer supplies paint."',
              helperText: 'Tip: tap the mic on your keyboard to talk.',
              counterText: '',
            ),
          ),
          const SizedBox(height: 16),
          if (!_showCustomer)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _showCustomer = true),
                icon: const Icon(Icons.person_add_alt_rounded),
                label: const Text('Add customer (optional)'),
              ),
            )
          else ...[
            Text('Customer', style: text.titleLarge),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: 'Mobile'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _address,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Job address'),
            ),
          ],
          const SizedBox(height: 28),
          Text(
            'No job handy? Try a sample:',
            style: text.bodySmall?.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in SampleJob.values)
                ChoiceChip(
                  label: Text(s.title),
                  selected: _sample == s,
                  onSelected: (_) => _loadSample(s),
                  labelStyle: text.labelMedium?.copyWith(
                    color: _sample == s ? c.canvas : c.ink,
                  ),
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: ready ? _build : null,
            icon: const Icon(Icons.bolt_rounded),
            label: Text(
              _busy > 0
                  ? 'Preparing photos...'
                  : _shots.isEmpty
                  ? 'Add a photo to start'
                  : 'Build quote',
            ),
          ),
        ),
      ),
    );
  }
}

class _ShotTile extends StatelessWidget {
  const _ShotTile({required this.shot, required this.onRemove});

  final _Shot shot;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            shot.file?.preview ?? shot.preview,
            fit: BoxFit.cover,
            cacheWidth: 360,
            gaplessPlayback: true,
          ),
        ),
        if (shot.file == null)
          Container(
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: c.ink.withValues(alpha: 0.7),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: primary ? c.accentSoft : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: primary ? c.accent.withValues(alpha: 0.35) : c.line,
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: primary ? c.accentInk : c.ink, size: 28),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: text.labelMedium?.copyWith(
                color: primary ? c.accentInk : c.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
