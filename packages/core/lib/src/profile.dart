import 'json.dart';
import 'trade.dart';

/// Who the quote is from.
class BusinessProfile {
  const BusinessProfile({
    required this.name,
    this.trades = const [],
    this.phone = '',
    this.email = '',
    this.zip = '',
    this.license = '',
    this.paymentLink = '',
    this.terms = defaultTerms,
  });

  static const defaultTerms =
      'Deposit due at approval to schedule the work; balance due on '
      'completion. Prices are valid until the date shown.';

  final String name;
  final List<Trade> trades;
  final String phone;
  final String email;

  /// Used for regional material prices.
  final String zip;
  final String license;

  /// Where customers pay the deposit (a Stripe, Square, or PayPal link).
  final String paymentLink;
  final String terms;

  Trade get primaryTrade => trades.isEmpty ? Trade.other : trades.first;

  BusinessProfile copyWith({
    String? name,
    List<Trade>? trades,
    String? phone,
    String? email,
    String? zip,
    String? license,
    String? paymentLink,
    String? terms,
  }) => BusinessProfile(
    name: name ?? this.name,
    trades: trades ?? this.trades,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    zip: zip ?? this.zip,
    license: license ?? this.license,
    paymentLink: paymentLink ?? this.paymentLink,
    terms: terms ?? this.terms,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'trades': [for (final t in trades) t.id],
    'phone': phone,
    'email': email,
    'zip': zip,
    'license': license,
    'payment_link': paymentLink,
    'terms': terms,
  };

  factory BusinessProfile.fromJson(Object? json) {
    final m = readMap(json);
    final trades = <Trade>{
      for (final t in readList(m['trades'], max: 5))
        if (t is String) Trade.fromId(t),
    };
    final terms = readString(m['terms'], max: 600);
    return BusinessProfile(
      name: readString(m['name'], max: 80),
      trades: trades.toList(),
      phone: readString(m['phone'], max: 40),
      email: readString(m['email'], max: 120),
      zip: readString(m['zip'], max: 10),
      license: readString(m['license'], max: 60),
      paymentLink: safeLink(readString(m['payment_link'], max: 500)),
      terms: m.containsKey('terms') ? terms : defaultTerms,
    );
  }
}

/// Only http(s) links are ever rendered as buttons.
String safeLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !(uri.isScheme('https') || uri.isScheme('http'))) {
    return '';
  }
  return uri.host.isEmpty ? '' : url;
}
