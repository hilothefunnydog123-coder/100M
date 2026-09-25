import 'dart:convert';
import 'dart:typed_data';

import 'package:jobwalk_core/jobwalk_core.dart';
import 'package:jobwalk_server/jobwalk_server.dart';

final jpegBytes = Uint8List.fromList([
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, //
]);

/// Records requests and replies with queued responses (or errors).
class FakeMessagesApi implements MessagesApi {
  FakeMessagesApi(this.responses);

  /// Each entry is a [ClaudeMessage] to return or an exception to throw.
  final List<Object> responses;
  final requests = <Map<String, Object?>>[];
  final betaHeaders = <List<String>>[];

  @override
  Future<ClaudeMessage> createMessage(
    Map<String, Object?> body, {
    List<String> betas = const [],
  }) async {
    requests.add(body);
    betaHeaders.add(betas);
    if (responses.isEmpty) throw StateError('No fake response queued.');
    final next = responses.removeAt(0);
    if (next is ClaudeMessage) return next;
    throw next;
  }
}

ClaudeMessage message({
  Object? draft,
  String? rawText,
  String stopReason = 'end_turn',
  String model = 'claude-opus-5-5',
}) => ClaudeMessage({
  'id': 'msg_test',
  'type': 'message',
  'role': 'assistant',
  'model': model,
  'stop_reason': stopReason,
  'content': [
    {'type': 'thinking', 'thinking': '', 'signature': 'sig'},
    if (rawText != null || draft != null)
      {'type': 'text', 'text': rawText ?? jsonEncode(draft)},
  ],
  'usage': {
    'input_tokens': 9000,
    'output_tokens': 6000,
    'cache_read_input_tokens': 3000,
    'cache_creation_input_tokens': 0,
  },
});

ClaudeMessage refusal() => ClaudeMessage({
  'id': 'msg_refused',
  'model': 'claude-opus-5-5',
  'stop_reason': 'refusal',
  'content': <Object?>[],
  'usage': {'input_tokens': 0, 'output_tokens': 0},
});

/// A realistic model response: the fence sample in wire format.
Map<String, Object?> draftJson() => SampleJob.fence.draft.toJson();

DraftRequest draftRequest({
  String note = 'Customer wants cedar',
  int photos = 2,
  List<PriceEntry> priceList = const [],
}) => DraftRequest(
  profile: const BusinessProfile(
    name: 'Oak & Iron Fence Co.',
    trades: [Trade.fencing],
    zip: '78704',
  ),
  rates: Rates.forTrade(Trade.fencing).copyWith(priceList: priceList),
  note: note,
  photos: [
    for (var i = 0; i < photos; i++)
      JobPhoto(bytes: jpegBytes, mediaType: 'image/jpeg'),
  ],
);

final now = DateTime.utc(2026, 9, 25, 15);

/// A valid customer-facing quote, as the app publishes it.
PublicQuote publicQuote({
  String business = 'Brightline Painting',
  String paymentLink = '',
  DateTime? issuedAt,
}) {
  final quote = QuoteBuilder.fromDraft(
    SampleJob.livingRoom.draft,
    id: 'q_local',
    number: 1042,
    rates: Rates.forTrade(Trade.painting),
    now: now,
    customer: const Customer(name: 'Dana Ortiz', address: '12 Elm St'),
  );
  return PublicQuote.fromQuote(
    quote,
    BusinessProfile(
      name: business,
      phone: '(512) 555-0142',
      paymentLink: paymentLink,
    ),
    issuedAt: issuedAt ?? now,
  );
}
