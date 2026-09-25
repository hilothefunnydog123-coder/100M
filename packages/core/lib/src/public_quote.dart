import 'json.dart';
import 'line_item.dart';
import 'pricing.dart';
import 'profile.dart';
import 'quote.dart';
import 'units.dart';

/// A line as the customer sees it: no hours, costs, or AI reasoning.
class PublicLine {
  const PublicLine({
    required this.description,
    required this.totalCents,
    this.detail = '',
    this.section = '',
    this.quantity = 1,
    this.unit = Unit.lot,
  });

  final String description;
  final String detail;
  final String section;
  final double quantity;
  final Unit unit;
  final int totalCents;

  Map<String, Object?> toJson() => {
    'description': description,
    'detail': detail,
    'section': section,
    'quantity': quantity,
    'unit': unit.id,
    'total_cents': totalCents,
  };

  static PublicLine? fromJson(Object? json) {
    final m = readMap(json);
    final description = readString(m['description'], max: 120);
    if (description.isEmpty) return null;
    return PublicLine(
      description: description,
      detail: readString(m['detail'], max: 240),
      section: readString(m['section'], max: 40),
      quantity: readDouble(m['quantity'], max: 1000000, fallback: 1),
      unit: Unit.fromId(m['unit']),
      totalCents: readInt(m['total_cents'], min: -1 << 40),
    );
  }
}

/// One option with its lines and totals.
class PublicOption {
  const PublicOption({
    required this.id,
    required this.name,
    required this.lines,
    required this.subtotalCents,
    required this.totalCents,
    this.summary = '',
    this.recommended = false,
    this.minimumAdjustmentCents = 0,
    this.discountCents = 0,
    this.taxCents = 0,
    this.taxRatePct = 0,
    this.depositCents = 0,
  });

  final String id;
  final String name;
  final String summary;
  final bool recommended;
  final List<PublicLine> lines;
  final int subtotalCents;
  final int minimumAdjustmentCents;
  final int discountCents;
  final int taxCents;
  final double taxRatePct;
  final int totalCents;
  final int depositCents;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'summary': summary,
    'recommended': recommended,
    'lines': [for (final l in lines) l.toJson()],
    'subtotal_cents': subtotalCents,
    'minimum_adjustment_cents': minimumAdjustmentCents,
    'discount_cents': discountCents,
    'tax_cents': taxCents,
    'tax_rate_pct': taxRatePct,
    'total_cents': totalCents,
    'deposit_cents': depositCents,
  };

  static PublicOption? fromJson(Object? json) {
    final m = readMap(json);
    final id = readString(m['id'], max: 20);
    final name = readString(m['name'], max: 40);
    if (id.isEmpty || name.isEmpty) return null;
    int cents(String key) => readInt(m[key], min: -1 << 40);
    return PublicOption(
      id: id,
      name: name,
      summary: readString(m['summary'], max: 200),
      recommended: readBool(m['recommended']),
      lines: [
        for (final l in readList(m['lines'], max: PublicQuote.maxLines + 1))
          ?PublicLine.fromJson(l),
      ],
      subtotalCents: cents('subtotal_cents'),
      minimumAdjustmentCents: cents('minimum_adjustment_cents'),
      discountCents: cents('discount_cents'),
      taxCents: cents('tax_cents'),
      taxRatePct: readDouble(m['tax_rate_pct'], max: 25),
      totalCents: cents('total_cents'),
      depositCents: cents('deposit_cents'),
    );
  }
}

/// The contractor's contact details as printed on the quote.
class PublicBusiness {
  const PublicBusiness({
    required this.name,
    this.phone = '',
    this.email = '',
    this.license = '',
    this.paymentLink = '',
  });

  final String name;
  final String phone;
  final String email;
  final String license;
  final String paymentLink;

  Map<String, Object?> toJson() => {
    'name': name,
    'phone': phone,
    'email': email,
    'license': license,
    'payment_link': paymentLink,
  };

  factory PublicBusiness.fromJson(Object? json) {
    final m = readMap(json);
    return PublicBusiness(
      name: readString(m['name'], max: 80),
      phone: readString(m['phone'], max: 40),
      email: readString(m['email'], max: 120),
      license: readString(m['license'], max: 60),
      paymentLink: safeLink(readString(m['payment_link'], max: 500)),
    );
  }
}

/// Everything the customer's quote page shows, and nothing else. This is
/// the only quote data that leaves the contractor's phone.
class PublicQuote {
  const PublicQuote({
    required this.business,
    required this.number,
    required this.issuedAt,
    required this.validUntil,
    required this.options,
    this.customerName = '',
    this.customerAddress = '',
    this.title = '',
    this.summary = '',
    this.message = '',
    this.exclusions = const [],
    this.terms = '',
    this.depositPct = 0,
  });

  static const maxLines = 60;
  static const maxTotalCents = 1000000000;

  final PublicBusiness business;
  final int number;
  final DateTime issuedAt;
  final DateTime validUntil;
  final List<PublicOption> options;
  final String customerName;
  final String customerAddress;
  final String title;
  final String summary;
  final String message;
  final List<String> exclusions;
  final String terms;
  final double depositPct;

  PublicOption? option(String? id) {
    for (final o in options) {
      if (o.id == id) return o;
    }
    return null;
  }

  PublicOption get defaultOption =>
      options.where((o) => o.recommended).firstOrNull ?? options.first;

  factory PublicQuote.fromQuote(
    Quote quote,
    BusinessProfile profile, {
    required DateTime issuedAt,
  }) {
    PublicOption optionFor(String? tierId) {
      final totals = quote.totals(tierId);
      final tier = quote.tier(tierId);
      return PublicOption(
        id: tier?.id ?? 'quote',
        name: tier?.name ?? 'Quote',
        summary: tier?.summary ?? '',
        recommended: tier?.recommended ?? false,
        lines: [
          for (final item in groupBySection(
            quote.items.where((i) => i.inTier(tierId)),
            (i) => i.section,
          ))
            PublicLine(
              description: item.description,
              detail: item.detail,
              section: item.section,
              quantity: item.quantity,
              unit: item.unit,
              totalCents: Pricing.line(item, quote.rates),
            ),
        ],
        subtotalCents: totals.subtotalCents,
        minimumAdjustmentCents: totals.minimumAdjustmentCents,
        discountCents: totals.discountCents,
        taxCents: totals.taxCents,
        taxRatePct: quote.rates.taxRatePct,
        totalCents: totals.totalCents,
        depositCents: totals.depositCents,
      );
    }

    return PublicQuote(
      business: PublicBusiness(
        name: profile.name,
        phone: profile.phone,
        email: profile.email,
        license: profile.license,
        paymentLink: profile.paymentLink,
      ),
      number: quote.number,
      issuedAt: issuedAt,
      validUntil: issuedAt.add(Duration(days: quote.rates.validDays)),
      options: [for (final id in quote.tierIdsOrNull) optionFor(id)],
      customerName: quote.customer.name,
      customerAddress: quote.customer.address,
      title: quote.title,
      summary: quote.summary,
      message: quote.message,
      exclusions: quote.exclusions,
      terms: profile.terms,
      depositPct: quote.rates.depositPct,
    );
  }

  /// Why this can't be shown to a customer, or null if it's fine. Totals
  /// must add up so the page never contradicts itself.
  String? validate() {
    if (business.name.isEmpty) return 'Add your business name.';
    if (options.isEmpty || options.length > 3) {
      return 'A quote needs one to three options.';
    }
    if (!validUntil.isAfter(issuedAt)) return 'The expiry date is invalid.';
    final ids = <String>{};
    for (final o in options) {
      if (!ids.add(o.id)) return 'Option ids must be unique.';
      if (o.lines.isEmpty) return '"${o.name}" has no lines.';
      if (o.lines.length > maxLines) return '"${o.name}" has too many lines.';
      final amounts = [
        for (final l in o.lines) l.totalCents,
        o.subtotalCents,
        o.minimumAdjustmentCents,
        o.discountCents,
        o.taxCents,
        o.totalCents,
        o.depositCents,
      ];
      if (amounts.any((a) => a < 0 || a > maxTotalCents)) {
        return '"${o.name}" has an invalid amount.';
      }
      final lines = o.lines.fold(0, (sum, l) => sum + l.totalCents);
      if (lines != o.subtotalCents) return '"${o.name}" lines don\'t add up.';
      final expected =
          o.subtotalCents +
          o.minimumAdjustmentCents -
          o.discountCents +
          o.taxCents;
      if (expected != o.totalCents || o.depositCents > o.totalCents) {
        return '"${o.name}" totals don\'t add up.';
      }
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'business': business.toJson(),
    'number': number,
    'issued_at': writeDate(issuedAt),
    'valid_until': writeDate(validUntil),
    'options': [for (final o in options) o.toJson()],
    'customer_name': customerName,
    'customer_address': customerAddress,
    'title': title,
    'summary': summary,
    'message': message,
    'exclusions': exclusions,
    'terms': terms,
    'deposit_pct': depositPct,
  };

  /// Lenient parse; call [validate] before trusting it.
  factory PublicQuote.fromJson(Object? json) {
    final m = readMap(json);
    final issued = readDate(m['issued_at']) ?? DateTime.utc(1970);
    return PublicQuote(
      business: PublicBusiness.fromJson(m['business']),
      number: readInt(m['number'], max: 99999999),
      issuedAt: issued,
      validUntil: readDate(m['valid_until']) ?? issued,
      options: [
        for (final o in readList(m['options'], max: 4))
          ?PublicOption.fromJson(o),
      ],
      customerName: readString(m['customer_name'], max: 80),
      customerAddress: readString(m['customer_address'], max: 200),
      title: readString(m['title'], max: 120),
      summary: readString(m['summary'], max: 1000),
      message: readString(m['message'], max: 1000),
      exclusions: readStrings(m['exclusions'], maxLength: 240),
      terms: readString(m['terms'], max: 600),
      depositPct: readDouble(m['deposit_pct'], max: 100),
    );
  }
}
