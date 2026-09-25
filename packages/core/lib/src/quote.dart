import 'json.dart';
import 'line_item.dart';
import 'pricing.dart';
import 'rates.dart';
import 'units.dart';

enum QuoteStatus {
  draft('draft', 'Draft'),
  sent('sent', 'Sent'),
  viewed('viewed', 'Viewed'),
  approved('approved', 'Approved'),
  declined('declined', 'Declined');

  const QuoteStatus(this.id, this.label);

  final String id;
  final String label;

  static QuoteStatus fromId(Object? id) =>
      values.firstWhere((s) => s.id == id, orElse: () => QuoteStatus.draft);

  /// Sent and waiting on the customer.
  bool get isOpen => this == sent || this == viewed;
}

enum Impact {
  high('high'),
  medium('medium'),
  low('low');

  const Impact(this.id);

  final String id;

  static Impact fromId(Object? id) =>
      values.firstWhere((i) => i.id == id, orElse: () => Impact.medium);
}

/// One option the customer can choose, e.g. "Walls + trim".
class Tier {
  const Tier({
    required this.id,
    required this.name,
    this.summary = '',
    this.recommended = false,
  });

  final String id;
  final String name;
  final String summary;
  final bool recommended;

  Tier copyWith({String? name, String? summary, bool? recommended}) => Tier(
    id: id,
    name: name ?? this.name,
    summary: summary ?? this.summary,
    recommended: recommended ?? this.recommended,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'summary': summary,
    'recommended': recommended,
  };

  static Tier? fromJson(Object? json) {
    final m = readMap(json);
    final id = readString(
      m['id'],
      max: 20,
    ).toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    final name = readString(m['name'], max: 40);
    if (id.isEmpty || name.isEmpty) return null;
    return Tier(
      id: id,
      name: name,
      summary: readString(m['summary'], max: 200),
      recommended: readBool(m['recommended']),
    );
  }
}

class Customer {
  const Customer({
    this.name = '',
    this.phone = '',
    this.email = '',
    this.address = '',
  });

  final String name;
  final String phone;
  final String email;
  final String address;

  bool get isEmpty =>
      name.isEmpty && phone.isEmpty && email.isEmpty && address.isEmpty;

  /// "Dana" from "Dana Ortiz", for greetings.
  String get firstName => name.split(RegExp(r'\s+')).first;

  Customer copyWith({
    String? name,
    String? phone,
    String? email,
    String? address,
  }) => Customer(
    name: name ?? this.name,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    address: address ?? this.address,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'phone': phone,
    'email': email,
    'address': address,
  };

  factory Customer.fromJson(Object? json) {
    final m = readMap(json);
    return Customer(
      name: readString(m['name'], max: 80),
      phone: readString(m['phone'], max: 40),
      email: readString(m['email'], max: 120),
      address: readString(m['address'], max: 200),
    );
  }
}

/// Something the AI assumed that changes the price, for the contractor to
/// confirm before sending.
class Assumption {
  const Assumption({
    required this.text,
    this.impact = Impact.medium,
    this.confirmed = false,
  });

  final String text;
  final Impact impact;
  final bool confirmed;

  Assumption withConfirmed(bool value) =>
      Assumption(text: text, impact: impact, confirmed: value);

  Map<String, Object?> toJson() => {
    'text': text,
    'impact': impact.id,
    'confirmed': confirmed,
  };

  static Assumption? fromJson(Object? json) {
    final m = readMap(json);
    final text = readString(m['text'], max: 240);
    if (text.isEmpty) return null;
    return Assumption(
      text: text,
      impact: Impact.fromId(m['impact']),
      confirmed: readBool(m['confirmed']),
    );
  }
}

/// A measurement the AI took from the photos.
class Measurement {
  const Measurement({
    required this.name,
    required this.quantity,
    required this.unit,
    this.how = '',
    this.confidence = Impact.medium,
  });

  final String name;
  final double quantity;
  final Unit unit;

  /// How it was measured: "Door (80 in) for scale, 4 walls visible".
  final String how;

  /// Reuses [Impact]'s high/medium/low scale.
  final Impact confidence;

  Map<String, Object?> toJson() => {
    'name': name,
    'quantity': quantity,
    'unit': unit.id,
    'how': how,
    'confidence': confidence.id,
  };

  static Measurement? fromJson(Object? json) {
    final m = readMap(json);
    final name = readString(m['name'], max: 80);
    if (name.isEmpty) return null;
    return Measurement(
      name: name,
      quantity: readDouble(m['quantity'], max: LineItem.maxQuantity),
      unit: Unit.fromId(m['unit']),
      how: readString(m['how'], max: 300),
      confidence: Impact.fromId(m['confidence']),
    );
  }
}

/// What the AI produced, kept for the contractor: its reasoning, and the
/// draft totals so we can show how much they changed.
class AiInfo {
  const AiInfo({
    this.model = '',
    this.demo = false,
    this.confidence = Impact.medium,
    this.confidenceNote = '',
    this.observations = const [],
    this.measurements = const [],
    this.crewPeople = 0,
    this.crewDays = 0,
    this.draftTotals = const {},
  });

  final String model;

  /// A canned sample, not an analysis of real photos.
  final bool demo;
  final Impact confidence;
  final String confidenceNote;
  final List<String> observations;
  final List<Measurement> measurements;
  final int crewPeople;
  final double crewDays;

  /// Total per option key (see `Quote.tierKey`) when the draft was made.
  final Map<String, int> draftTotals;

  Map<String, Object?> toJson() => {
    'model': model,
    'demo': demo,
    'confidence': confidence.id,
    'confidence_note': confidenceNote,
    'observations': observations,
    'measurements': [for (final m in measurements) m.toJson()],
    'crew_people': crewPeople,
    'crew_days': crewDays,
    'draft_totals': draftTotals,
  };

  factory AiInfo.fromJson(Object? json) {
    final m = readMap(json);
    final totals = readMap(m['draft_totals']);
    return AiInfo(
      model: readString(m['model'], max: 80),
      demo: readBool(m['demo']),
      confidence: Impact.fromId(m['confidence']),
      confidenceNote: readString(m['confidence_note'], max: 400),
      observations: readStrings(m['observations'], maxItems: 12),
      measurements: [
        for (final x in readList(m['measurements'], max: 20))
          ?Measurement.fromJson(x),
      ],
      crewPeople: readInt(m['crew_people'], max: 50),
      crewDays: readDouble(m['crew_days'], max: 365),
      draftTotals: {
        for (final e in totals.entries)
          if (e.value is num) e.key: readInt(e.value),
      },
    );
  }
}

/// Where a sent quote lives.
class ShareInfo {
  const ShareInfo({
    required this.publicId,
    required this.url,
    required this.ownerToken,
    required this.sentAt,
    this.revision = 1,
  });

  final String publicId;
  final String url;

  /// Secret that lets this device update the quote and read its status.
  final String ownerToken;
  final DateTime sentAt;
  final int revision;

  ShareInfo copyWith({DateTime? sentAt, int? revision}) => ShareInfo(
    publicId: publicId,
    url: url,
    ownerToken: ownerToken,
    sentAt: sentAt ?? this.sentAt,
    revision: revision ?? this.revision,
  );

  Map<String, Object?> toJson() => {
    'public_id': publicId,
    'url': url,
    'owner_token': ownerToken,
    'sent_at': writeDate(sentAt),
    'revision': revision,
  };

  static ShareInfo? fromJson(Object? json) {
    final m = readMap(json);
    final id = readString(m['public_id'], max: 64);
    final sentAt = readDate(m['sent_at']);
    if (id.isEmpty || sentAt == null) return null;
    return ShareInfo(
      publicId: id,
      url: readString(m['url'], max: 300),
      ownerToken: readString(m['owner_token'], max: 128),
      sentAt: sentAt,
      revision: readInt(m['revision'], min: 1, max: 1000, fallback: 1),
    );
  }
}

/// What the customer did with a sent quote. The server's status endpoint
/// returns exactly this.
class CustomerResponse {
  const CustomerResponse({
    this.views = 0,
    this.firstViewedAt,
    this.lastViewedAt,
    this.approvedAt,
    this.approvedTierId,
    this.signature = '',
    this.declinedAt,
    this.declineReason = '',
  });

  final int views;
  final DateTime? firstViewedAt;
  final DateTime? lastViewedAt;
  final DateTime? approvedAt;
  final String? approvedTierId;

  /// The name the customer typed to approve.
  final String signature;
  final DateTime? declinedAt;
  final String declineReason;

  Map<String, Object?> toJson() => {
    'views': views,
    'first_viewed_at': writeDate(firstViewedAt),
    'last_viewed_at': writeDate(lastViewedAt),
    'approved_at': writeDate(approvedAt),
    'approved_option': approvedTierId,
    'signature': signature,
    'declined_at': writeDate(declinedAt),
    'decline_reason': declineReason,
  };

  factory CustomerResponse.fromJson(Object? json) {
    final m = readMap(json);
    final tier = readString(m['approved_option'], max: 20);
    return CustomerResponse(
      views: readInt(m['views'], max: 1000000),
      firstViewedAt: readDate(m['first_viewed_at']),
      lastViewedAt: readDate(m['last_viewed_at']),
      approvedAt: readDate(m['approved_at']),
      approvedTierId: tier.isEmpty ? null : tier,
      signature: readString(m['signature'], max: 80),
      declinedAt: readDate(m['declined_at']),
      declineReason: readString(m['decline_reason'], max: 500),
    );
  }
}

/// A quote as the contractor edits it.
class Quote {
  const Quote({
    required this.id,
    required this.number,
    required this.createdAt,
    required this.updatedAt,
    required this.rates,
    this.status = QuoteStatus.draft,
    this.customer = const Customer(),
    this.title = '',
    this.summary = '',
    this.tiers = const [],
    this.items = const [],
    this.assumptions = const [],
    this.exclusions = const [],
    this.message = '',
    this.discountCents = 0,
    this.photoKeys = const [],
    this.ai,
    this.share,
    this.response = const CustomerResponse(),
    this.chosenTierId,
    this.closedAt,
  });

  final String id;

  /// Human-friendly number, e.g. 1042.
  final int number;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The contractor's rates when the quote was made.
  final Rates rates;
  final QuoteStatus status;
  final Customer customer;
  final String title;
  final String summary;
  final List<Tier> tiers;
  final List<LineItem> items;
  final List<Assumption> assumptions;
  final List<String> exclusions;

  /// Note to the customer.
  final String message;
  final int discountCents;

  /// Keys of the job photos in local storage.
  final List<String> photoKeys;
  final AiInfo? ai;
  final ShareInfo? share;
  final CustomerResponse response;

  /// The option the customer approved.
  final String? chosenTierId;

  /// When it was approved or declined.
  final DateTime? closedAt;

  String get label => 'Quote #$number';

  String get displayName => customer.name.isNotEmpty
      ? customer.name
      : title.isNotEmpty
      ? title
      : label;

  bool get hasTiers => tiers.isNotEmpty;

  /// The option shown first: the recommended one, else the first.
  String? get defaultTierId {
    if (tiers.isEmpty) return null;
    for (final t in tiers) {
      if (t.recommended) return t.id;
    }
    return tiers.first.id;
  }

  /// Key for per-option maps: the tier id, or '' without options.
  static String tierKey(String? tierId) => tierId ?? '';

  List<String?> get tierIdsOrNull =>
      tiers.isEmpty ? const [null] : [for (final t in tiers) t.id];

  Tier? tier(String? id) {
    for (final t in tiers) {
      if (t.id == id) return t;
    }
    return null;
  }

  QuoteTotals totals([String? tierId]) => Pricing.totals(
    items: items,
    rates: rates,
    tierId: tiers.isEmpty ? null : (tierId ?? defaultTierId),
    discountCents: discountCents,
  );

  /// The amount that matters in lists: the approved option's total once
  /// won, else the default option's.
  int get headlineTotalCents =>
      totals(status == QuoteStatus.approved ? chosenTierId : null).totalCents;

  DateTime get validUntil =>
      (share?.sentAt ?? createdAt).add(Duration(days: rates.validDays));

  /// Percent change from the AI draft to now for [tierId], or null.
  double? changeFromDraft([String? tierId]) {
    final id = tiers.isEmpty ? null : (tierId ?? defaultTierId);
    final draft = ai?.draftTotals[tierKey(id)];
    if (draft == null || draft == 0) return null;
    return (totals(id).totalCents - draft) / draft * 100;
  }

  int get openAssumptions => assumptions.where((a) => !a.confirmed).length;

  LineItem? item(String id) {
    for (final i in items) {
      if (i.id == id) return i;
    }
    return null;
  }

  Quote replaceItem(LineItem updated) => copyWith(
    items: [for (final i in items) i.id == updated.id ? updated : i],
  );

  Quote removeItem(String id) =>
      copyWith(items: items.where((i) => i.id != id).toList());

  /// Folds in what the customer did. A customer's approval or decline is
  /// newer information than a manual mark, except that a manual approval
  /// isn't undone by a mere view.
  Quote applyResponse(CustomerResponse r) {
    var status = this.status;
    var chosen = chosenTierId;
    var closed = closedAt;
    if (r.approvedAt != null) {
      status = QuoteStatus.approved;
      chosen = r.approvedTierId ?? chosen;
      closed = r.approvedAt;
    } else if (r.declinedAt != null && status != QuoteStatus.approved) {
      status = QuoteStatus.declined;
      closed = r.declinedAt;
    } else if (r.views > 0 && status == QuoteStatus.sent) {
      status = QuoteStatus.viewed;
    }
    return copyWith(
      response: r,
      status: status,
      chosenTierId: chosen,
      closedAt: closed,
    );
  }

  static const _keep = Object();

  Quote copyWith({
    DateTime? updatedAt,
    Rates? rates,
    QuoteStatus? status,
    Customer? customer,
    String? title,
    String? summary,
    List<Tier>? tiers,
    List<LineItem>? items,
    List<Assumption>? assumptions,
    List<String>? exclusions,
    String? message,
    int? discountCents,
    List<String>? photoKeys,
    Object? ai = _keep,
    Object? share = _keep,
    CustomerResponse? response,
    Object? chosenTierId = _keep,
    Object? closedAt = _keep,
  }) => Quote(
    id: id,
    number: number,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    rates: rates ?? this.rates,
    status: status ?? this.status,
    customer: customer ?? this.customer,
    title: title ?? this.title,
    summary: summary ?? this.summary,
    tiers: tiers ?? this.tiers,
    items: items ?? this.items,
    assumptions: assumptions ?? this.assumptions,
    exclusions: exclusions ?? this.exclusions,
    message: message ?? this.message,
    discountCents: discountCents ?? this.discountCents,
    photoKeys: photoKeys ?? this.photoKeys,
    ai: identical(ai, _keep) ? this.ai : ai as AiInfo?,
    share: identical(share, _keep) ? this.share : share as ShareInfo?,
    response: response ?? this.response,
    chosenTierId: identical(chosenTierId, _keep)
        ? this.chosenTierId
        : chosenTierId as String?,
    closedAt: identical(closedAt, _keep)
        ? this.closedAt
        : closedAt as DateTime?,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'number': number,
    'created_at': writeDate(createdAt),
    'updated_at': writeDate(updatedAt),
    'rates': rates.toJson(),
    'status': status.id,
    'customer': customer.toJson(),
    'title': title,
    'summary': summary,
    'tiers': [for (final t in tiers) t.toJson()],
    'items': [for (final i in items) i.toJson()],
    'assumptions': [for (final a in assumptions) a.toJson()],
    'exclusions': exclusions,
    'message': message,
    'discount_cents': discountCents,
    'photo_keys': photoKeys,
    'ai': ai?.toJson(),
    'share': share?.toJson(),
    'response': response.toJson(),
    'chosen_tier_id': chosenTierId,
    'closed_at': writeDate(closedAt),
  };

  static Quote? fromJson(Object? json) {
    final m = readMap(json);
    final id = readString(m['id'], max: 64);
    final created = readDate(m['created_at']);
    if (id.isEmpty || created == null) return null;
    final chosen = readString(m['chosen_tier_id'], max: 20);
    return Quote(
      id: id,
      number: readInt(m['number'], max: 99999999),
      createdAt: created,
      updatedAt: readDate(m['updated_at']) ?? created,
      rates: Rates.fromJson(m['rates']),
      status: QuoteStatus.fromId(m['status']),
      customer: Customer.fromJson(m['customer']),
      title: readString(m['title'], max: 120),
      summary: readString(m['summary'], max: 1000),
      tiers: [for (final t in readList(m['tiers'], max: 3)) ?Tier.fromJson(t)],
      items: [
        for (final i in readList(m['items'], max: 100)) ?LineItem.fromJson(i),
      ],
      assumptions: [
        for (final a in readList(m['assumptions'], max: 20))
          ?Assumption.fromJson(a),
      ],
      exclusions: readStrings(m['exclusions'], maxLength: 240),
      message: readString(m['message'], max: 1000),
      discountCents: readInt(m['discount_cents'], max: 100000000),
      photoKeys: readStrings(m['photo_keys'], maxItems: 12, maxLength: 120),
      ai: m['ai'] == null ? null : AiInfo.fromJson(m['ai']),
      share: ShareInfo.fromJson(m['share']),
      response: CustomerResponse.fromJson(m['response']),
      chosenTierId: chosen.isEmpty ? null : chosen,
      closedAt: readDate(m['closed_at']),
    );
  }
}
