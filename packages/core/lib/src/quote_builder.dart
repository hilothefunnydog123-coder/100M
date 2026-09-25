import 'ai_draft.dart';
import 'line_item.dart';
import 'quote.dart';
import 'rates.dart';

/// Turns an AI draft into an editable quote priced with the contractor's
/// rates.
abstract final class QuoteBuilder {
  static Quote fromDraft(
    AiDraft draft, {
    required String id,
    required int number,
    required Rates rates,
    required DateTime now,
    Customer customer = const Customer(),
    List<String> photoKeys = const [],
    String model = '',
    bool demo = false,
  }) {
    final quote = Quote(
      id: id,
      number: number,
      createdAt: now,
      updatedAt: now,
      rates: rates,
      customer: customer,
      title: draft.title,
      summary: draft.summary,
      tiers: draft.tiers,
      items: [for (final item in draft.items) applyPriceList(item, rates)],
      assumptions: draft.assumptions,
      exclusions: draft.exclusions,
      message: draft.customerMessage,
      photoKeys: photoKeys,
    );
    return quote.copyWith(
      ai: AiInfo(
        model: model,
        demo: demo,
        confidence: draft.confidence,
        confidenceNote: draft.confidenceNote,
        observations: draft.observations,
        measurements: draft.measurements,
        crewPeople: draft.crewPeople,
        crewDays: draft.crewDays,
        draftTotals: {
          for (final tierId in quote.tierIdsOrNull)
            Quote.tierKey(tierId): quote.totals(tierId).totalCents,
        },
      ),
    );
  }

  /// Prices a line from the contractor's price list when the model matched
  /// an entry in the same unit. Otherwise the model's cost estimate stands.
  static LineItem applyPriceList(LineItem item, Rates rates) {
    final entry = rates.priceEntry(item.priceListId);
    if (entry == null || entry.unit != item.unit) {
      return item.priceListId == null ? item : item.withCosts();
    }
    return item.withUnitPrice(entry.unitPriceCents, priceListId: entry.id);
  }
}
