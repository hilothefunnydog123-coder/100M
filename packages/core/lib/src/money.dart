/// Money is integer cents everywhere. Floating-point dollars never reach a
/// total.
abstract final class Money {
  /// `$4,850`, or `$4,850.25` when there are cents (or [cents] is forced).
  static String format(int amount, {bool cents = false}) {
    final negative = amount < 0;
    final abs = amount.abs();
    final whole = groupThousands(abs ~/ 100);
    final rest = abs % 100;
    final text = rest == 0 && !cents
        ? '\$$whole'
        : '\$$whole.${rest.toString().padLeft(2, '0')}';
    return negative ? '-$text' : text;
  }

  /// Parses `$1,234.50`, `1234`, or `1,234.5` into cents. Null when the
  /// input isn't a non-negative amount.
  static int? parse(String input) {
    final cleaned = input.replaceAll(RegExp(r'[\s,$]'), '');
    if (cleaned.isEmpty || !RegExp(r'^\d*\.?\d*$').hasMatch(cleaned)) {
      return null;
    }
    final value = double.tryParse(cleaned);
    if (value == null || value.isNaN || value.isInfinite) return null;
    return (value * 100).round();
  }

  /// Rounds a price the way contractors write them: whole dollars under
  /// $100, the nearest $5 under $1,000, and the nearest $10 above.
  static int roundNice(int amount) {
    if (amount <= 0) return 0;
    final step = amount < 10000
        ? 100
        : amount < 100000
        ? 500
        : 1000;
    final rounded = (amount + step ~/ 2) ~/ step * step;
    return rounded == 0 ? step : rounded;
  }

  /// Rounds to whole dollars.
  static int roundDollars(int amount) => (amount + 50) ~/ 100 * 100;
}

/// `1,240` for 1240.
String groupThousands(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}
