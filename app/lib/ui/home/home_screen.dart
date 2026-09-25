import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import '../../state/providers.dart';
import '../../state/session.dart';
import '../../state/sync.dart';
import '../../theme/colors.dart';
import '../../util/format.dart';
import '../capture/capture_screen.dart';
import '../quote/quote_screen.dart';
import '../settings/settings_screen.dart';
import '../widgets/common.dart';

enum _Filter {
  all('All'),
  drafts('Drafts'),
  waiting('Waiting'),
  won('Won');

  const _Filter(this.label);

  final String label;

  bool matches(Quote q) => switch (this) {
    _Filter.all => true,
    _Filter.drafts => q.status == QuoteStatus.draft,
    _Filter.waiting => q.status.isOpen,
    _Filter.won => q.status == QuoteStatus.approved,
  };
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  var _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    // Catch up on views and approvals since the app was last open.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(ref.read(quotesProvider.notifier).refresh()),
    );
  }

  void _newQuote({SampleJob? sample}) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => CaptureScreen(sample: sample)),
  );

  @override
  Widget build(BuildContext context) {
    final quotes = ref.watch(quotesProvider);
    final profile = ref.watch(settingsProvider.select((s) => s.profile));
    final demo = ref.watch(configProvider).demoMode;
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final visible = quotes.where(_filter.matches).toList();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const LogoMark(size: 26),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                profile.name,
                overflow: TextOverflow.ellipsis,
                style: text.titleMedium,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: c.accent,
        onRefresh: () async {
          final session = ref.read(sessionProvider.notifier);
          await Future.wait([
            ref.read(quotesProvider.notifier).refresh(),
            session.refresh().catchError((Object _) {}),
          ]);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverToBoxAdapter(child: _SyncBanner()),
            if (demo)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    'Demo mode: drafts come from sample jobs and links stay '
                    'on this phone.',
                    style: text.bodySmall,
                  ),
                ),
              ),
            if (quotes.isNotEmpty) ...[
              const SliverToBoxAdapter(child: _StatsRow()),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    children: [
                      for (final f in _Filter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f.label),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                            labelStyle: text.labelMedium?.copyWith(
                              color: _filter == f ? c.canvas : c.ink,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (quotes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(onSample: (s) => _newQuote(sample: s)),
              )
            else if (visible.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Nothing here yet.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: c.inkMuted),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                sliver: SliverList.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => _QuoteTile(visible[i]),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: SizedBox(
        height: 60,
        child: FloatingActionButton.extended(
          onPressed: _newQuote,
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          icon: const Icon(Icons.photo_camera_rounded),
          label: Text(
            'New quote',
            style: text.labelLarge?.copyWith(color: c.onAccent),
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends ConsumerWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(statsProvider);
    final month = formatDay(ref.watch(clockProvider)()).split(' ').first;
    final winRate = s.winRate;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _Stat(
              label: 'Waiting on',
              cents: s.openCents,
              detail: '${s.openCount} quote${s.openCount == 1 ? '' : 's'}',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Stat(
              label: 'Won in $month',
              cents: s.wonCents,
              detail: '${s.wonCount} job${s.wonCount == 1 ? '' : 's'}',
              highlight: s.wonCents > 0,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _Stat(
              label: 'Win rate',
              value: winRate == null ? '–' : '${(winRate * 100).round()}%',
              detail: '${s.sentCount} sent',
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.detail,
    this.cents,
    this.value,
    this.highlight = false,
  });

  final String label;
  final String detail;
  final int? cents;
  final String? value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    return Panel(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall,
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: cents != null
                ? MoneyText(
                    cents!,
                    size: 24,
                    weight: FontWeight.w800,
                    color: highlight ? c.ok.fg : c.ink,
                  )
                : Text(value!, style: text.headlineSmall),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: c.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _QuoteTile extends ConsumerWidget {
  const _QuoteTile(this.quote);

  final Quote quote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    final now = ref.watch(clockProvider)();
    final when = switch (quote.status) {
      QuoteStatus.draft => 'Drafted ${timeAgo(quote.createdAt, now: now)}',
      QuoteStatus.sent => 'Sent ${timeAgo(quote.share!.sentAt, now: now)}',
      QuoteStatus.viewed =>
        'Viewed ${timeAgo(quote.response.lastViewedAt ?? now, now: now)}',
      QuoteStatus.approved ||
      QuoteStatus.declined => timeAgo(quote.closedAt ?? now, now: now),
    };
    final subtitle = [
      if (quote.customer.name.isNotEmpty && quote.title.isNotEmpty) quote.title,
      '#${quote.number}',
      when,
    ].join(' · ');
    return Panel(
      padding: const EdgeInsets.all(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => QuoteScreen(quoteId: quote.id)),
      ),
      child: Row(
        children: [
          quote.photoKeys.isEmpty
              ? const JobIcon()
              : PhotoThumb(quote.photoKeys.first),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quote.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MoneyText(
                quote.headlineTotalCents,
                size: 19,
                color: quote.status == QuoteStatus.declined
                    ? c.inkFaint
                    : c.ink,
              ),
              const SizedBox(height: 6),
              StatusPill(quote),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSample});

  final void Function(SampleJob) onSample;

  @override
  Widget build(BuildContext context) {
    final c = JobColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: c.accentSoft,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(
              Icons.photo_camera_outlined,
              size: 40,
              color: c.accentInk,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Your first quote is a few photos away.',
            textAlign: TextAlign.center,
            style: text.headlineSmall,
          ),
          const SizedBox(height: 10),
          Text(
            'On your next walkthrough, tap New quote and snap the job. No '
            'job handy? Try one of these:',
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in SampleJob.values)
                ActionChip(
                  avatar: Icon(
                    Icons.play_arrow_rounded,
                    size: 18,
                    color: c.ink,
                  ),
                  label: Text(s.title),
                  onPressed: () => onSample(s),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Says so when changes are waiting for a connection.
class _SyncBanner extends ConsumerWidget {
  const _SyncBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncProvider);
    final text = Theme.of(context).textTheme;
    final c = JobColors.of(context);
    final String? message = switch (status.phase) {
      SyncPhase.offline =>
        status.pending == 0
            ? "Offline. Customer updates will show when you're back online."
            : "Offline. ${status.pending == 1 ? 'One change' : '${status.pending} changes'} "
                  "will sync when you're back online.",
      SyncPhase.failed => "Couldn't sync: ${status.error ?? 'try again.'}",
      _ => null,
    };
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: c.inkMuted),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: text.bodySmall)),
        ],
      ),
    );
  }
}
