/// A failed request to an AI provider's API. Each client's exception
/// implements it, so drafts handle every provider's outages alike.
abstract interface class ModelApiException implements Exception {
  int get statusCode;
  String get type;
  String? get requestId;

  /// Overloaded, rate limited, or a transient server error: worth trying
  /// again in a minute.
  bool get isTransient;
}
