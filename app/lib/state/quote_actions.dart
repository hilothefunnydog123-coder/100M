import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

import '../services/api.dart';
import 'providers.dart';
import 'sync.dart';

/// Multi-step operations on a quote that talk to the server.
class QuoteActions {
  QuoteActions(this.ref);

  final Ref ref;

  QuotesNotifier get _quotes => ref.read(quotesProvider.notifier);

  /// Makes sure the customer's link shows the current version: publishes it
  /// the first time, and pushes a revision after edits. Returns the quote
  /// with its link.
  Future<Quote> publish(Quote quote) async {
    final settings = ref.read(settingsProvider);
    final now = ref.read(clockProvider)();
    final public = PublicQuote.fromQuote(
      quote,
      settings.profile,
      issuedAt: now,
    );
    final problem = public.validate();
    if (problem != null) throw ApiError(problem, retryable: false);

    final client = ref.read(clientProvider);
    if (client is! DemoJobwalkClient) {
      // The server builds the page from the synced quote and profile.
      final sent = await ref.read(syncProvider.notifier).publish(quote);
      await ref.read(settingsProvider.notifier).learnFrom(sent);
      return sent;
    }

    final share = quote.share;
    ShareInfo newShare;
    if (share == null) {
      final r = await client.publish(public);
      newShare = ShareInfo(
        publicId: r.id,
        url: r.url,
        ownerToken: r.ownerToken,
        sentAt: now,
        revision: r.revision,
      );
    } else if (quote.updatedAt.isAfter(share.sentAt)) {
      final revision = await client.update(
        share.publicId,
        share.ownerToken,
        public,
      );
      newShare = share.copyWith(sentAt: now, revision: revision);
    } else {
      return quote;
    }
    final sent = quote.copyWith(
      share: newShare,
      status:
          quote.status == QuoteStatus.draft ||
              quote.status == QuoteStatus.declined
          ? QuoteStatus.sent
          : quote.status,
      response: share == null ? const CustomerResponse() : quote.response,
    );
    final saved = await _quotes.save(sent, touch: false);
    await ref.read(settingsProvider.notifier).learnFrom(saved);
    return saved;
  }

  /// Marks a quote won or lost by hand, e.g. after a phone call.
  Future<void> close(Quote quote, QuoteStatus status, {String? tierId}) =>
      _quotes.save(
        quote.copyWith(
          status: status,
          closedAt: ref.read(clockProvider)(),
          chosenTierId: status == QuoteStatus.approved
              ? (tierId ?? quote.defaultTierId)
              : quote.chosenTierId,
        ),
        touch: false,
      );

  /// A fresh draft copy with no link, for changes after approval.
  Future<Quote> duplicate(Quote quote) async {
    final number = await ref.read(settingsProvider.notifier).takeNumber();
    final now = ref.read(clockProvider)();
    final copy = Quote(
      id: newId('q'),
      number: number,
      createdAt: now,
      updatedAt: now,
      rates: quote.rates,
      customer: quote.customer,
      title: quote.title,
      summary: quote.summary,
      tiers: quote.tiers,
      items: quote.items,
      assumptions: quote.assumptions,
      exclusions: quote.exclusions,
      message: quote.message,
      discountCents: quote.discountCents,
      photoKeys: quote.photoKeys,
      ai: quote.ai,
    );
    await _quotes.add(copy);
    return copy;
  }

  /// Refreshes one quote's status: a sync when signed in, else the demo
  /// link on this phone.
  Future<void> refresh(Quote quote) async {
    final client = ref.read(clientProvider);
    if (client is! DemoJobwalkClient) {
      await ref.read(syncProvider.notifier).sync();
      return;
    }
    final share = quote.share;
    if (share == null) return;
    final response = await client.status(share.publicId, share.ownerToken);
    final current = _quotes.byId(quote.id);
    if (current == null) return;
    await _quotes.save(current.applyResponse(response), touch: false);
  }
}

final quoteActionsProvider = Provider(QuoteActions.new);
