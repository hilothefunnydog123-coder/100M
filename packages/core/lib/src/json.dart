/// Lenient readers for JSON from the model, the network, or local storage.
/// A wrong type becomes a default instead of an exception; limits keep one
/// bad value from blowing up a layout or a total.
library;

String readString(Object? v, {int max = 2000}) {
  if (v is! String) return '';
  final t = v.trim();
  return t.length <= max ? t : t.substring(0, max).trimRight();
}

double readDouble(
  Object? v, {
  double min = 0,
  double max = 1e9,
  double fallback = 0,
}) {
  if (v is! num) return fallback;
  final d = v.toDouble();
  if (d.isNaN || d.isInfinite) return fallback;
  return d.clamp(min, max).toDouble();
}

int readInt(Object? v, {int min = 0, int max = 1 << 50, int fallback = 0}) {
  if (v is! num) return fallback;
  final d = v.toDouble();
  if (d.isNaN || d.isInfinite) return fallback;
  return d.round().clamp(min, max).toInt();
}

bool readBool(Object? v, {bool fallback = false}) => v is bool ? v : fallback;

List<Object?> readList(Object? v, {int max = 200}) =>
    v is List ? v.take(max).toList() : const [];

Map<String, Object?> readMap(Object? v) =>
    v is Map<String, Object?> ? v : const {};

List<String> readStrings(Object? v, {int maxItems = 20, int maxLength = 300}) =>
    [
      for (final s in readList(v, max: maxItems))
        if (readString(s, max: maxLength) case final t when t.isNotEmpty) t,
    ];

DateTime? readDate(Object? v) =>
    v is String ? DateTime.tryParse(v)?.toUtc() : null;

String? writeDate(DateTime? d) => d?.toUtc().toIso8601String();

/// Converts dollars from the model (e.g. 52.5) to cents.
int dollarsToCents(Object? v, {double max = 1e7}) =>
    (readDouble(v, max: max) * 100).round();
