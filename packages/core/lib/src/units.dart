import 'money.dart';

/// Units a line item is measured in. [lot] is a lump sum: no quantity is
/// shown to the customer.
enum Unit {
  lot('lot', 'lot', 'lot'),
  each('each', 'ea', 'ea'),
  hour('hr', 'hr', 'hrs'),
  day('day', 'day', 'days'),
  sqFt('sq_ft', 'sq ft', 'sq ft'),
  lnFt('ln_ft', 'ln ft', 'ln ft'),
  square('square', 'square', 'squares'),
  gallon('gal', 'gal', 'gal'),
  cuYd('cu_yd', 'cu yd', 'cu yd'),
  ton('ton', 'ton', 'tons'),
  load('load', 'load', 'loads');

  const Unit(this.id, this.singular, this.plural);

  final String id;
  final String singular;
  final String plural;

  static Unit fromId(Object? id) =>
      values.firstWhere((u) => u.id == id, orElse: () => Unit.each);

  String labelFor(double quantity) => quantity == 1 ? singular : plural;

  bool get isLumpSum => this == lot;
}

/// `1,240`, `2.5`, or `0.75`.
String formatQuantity(double q) {
  final rounded = (q * 100).round() / 100;
  if (rounded == rounded.roundToDouble()) {
    return groupThousands(rounded.round());
  }
  final whole = rounded.truncate();
  final fraction = (rounded - whole).abs().toStringAsFixed(2).substring(1);
  return '${groupThousands(whole)}${fraction.replaceFirst(RegExp(r'0$'), '')}';
}

/// `1,240 sq ft` or `3 ea`; empty for a lump sum or a single item, where a
/// quantity says nothing.
String describeQuantity(double quantity, Unit unit) =>
    unit.isLumpSum || (unit == Unit.each && quantity == 1)
    ? ''
    : '${formatQuantity(quantity)} ${unit.labelFor(quantity)}';
