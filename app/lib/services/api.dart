import 'dart:convert';
import 'dart:math';

import 'package:jobwalk_core/jobwalk_core.dart';

import '../data/blob_store.dart';

class DraftResult {
  const DraftResult({required this.draft, this.model = '', this.demo = false});

  final AiDraft draft;
  final String model;
  final bool demo;
}

class ShareResult {
  const ShareResult({
    required this.id,
    required this.url,
    required this.ownerToken,
    this.revision = 1,
  });

  final String id;
  final String url;
  final String ownerToken;
  final int revision;
}

/// A failure the UI can explain to the contractor.
class ApiError implements Exception {
  const ApiError(
    this.message, {
    this.retryable = true,
    this.code = '',
    this.status = 0,
    this.offline = false,
    this.details = const {},
  });

  final String message;
  final bool retryable;

  /// The server's stable error code, e.g. `upgrade_required`.
  final String code;

  /// HTTP status, or 0 when the request never got an answer.
  final int status;

  /// No connection: the change will sync later.
  final bool offline;

  /// Extra fields from the error body, e.g. `current` on a conflict.
  final Map<String, Object?> details;

  @override
  String toString() => message;
}

/// Drafting quotes: the server (see `server.dart`), or samples in demo mode.
abstract interface class JobwalkClient {
  /// Sample drafts and on-device links instead of the real server.
  bool get isDemo;

  /// Drafts a quote from photos. In demo mode, [sample] picks the canned
  /// draft; the real server always looks at the photos. Retries with the
  /// same [idempotencyKey] never draft (or charge) twice.
  Future<DraftResult> draft(
    DraftRequest request, {
    SampleJob? sample,
    String? idempotencyKey,
  });
}

/// Demo mode: sample drafts, and quote links that live on this device so
/// the whole loop (send, customer approves, won) can be tried offline.
class DemoJobwalkClient implements JobwalkClient {
  DemoJobwalkClient({
    required BlobStore store,
    this.draftDelay = const Duration(seconds: 4),
    DateTime Function()? clock,
  }) : _store = store,
       _clock = clock ?? (() => DateTime.now().toUtc());

  static const _key = 'demo_links.json';
  final BlobStore _store;
  final Duration draftDelay;
  final DateTime Function() _clock;
  final _random = Random();
  Map<String, CustomerResponse>? _responses;

  @override
  bool get isDemo => true;

  @override
  Future<DraftResult> draft(
    DraftRequest request, {
    SampleJob? sample,
    String? idempotencyKey,
  }) async {
    await Future<void>.delayed(draftDelay);
    final job = sample ?? SampleJob.forTrade(request.profile.primaryTrade);
    return DraftResult(draft: job.draft, model: 'demo', demo: true);
  }

  Future<ShareResult> publish(PublicQuote quote) async {
    final id = List.generate(
      16,
      (_) => 'abcdefghijkmnpqrstuvwxyz23456789'[_random.nextInt(32)],
    ).join();
    final responses = await _load();
    responses[id] = const CustomerResponse();
    await _save();
    return ShareResult(
      id: id,
      url: 'https://jobwalk.app/q/$id',
      ownerToken: 'demo',
    );
  }

  Future<int> update(String id, String ownerToken, PublicQuote quote) async {
    final responses = await _load();
    final r = responses[id] ?? const CustomerResponse();
    if (r.approvedAt != null) {
      throw const ApiError(
        'The customer already approved this quote. Duplicate it to make '
        'changes.',
        retryable: false,
        code: 'already_approved',
      );
    }
    responses[id] = CustomerResponse(
      views: r.views,
      firstViewedAt: r.firstViewedAt,
      lastViewedAt: r.lastViewedAt,
    );
    await _save();
    return 2;
  }

  Future<CustomerResponse> status(String id, String ownerToken) async =>
      (await _load())[id] ?? const CustomerResponse();

  /// Plays the customer opening the link.
  Future<void> recordView(String id) => _change(id, (r, now) {
    return CustomerResponse(
      views: r.views + 1,
      firstViewedAt: r.firstViewedAt ?? now,
      lastViewedAt: now,
      approvedAt: r.approvedAt,
      approvedTierId: r.approvedTierId,
      signature: r.signature,
      declinedAt: r.declinedAt,
      declineReason: r.declineReason,
    );
  });

  /// Plays the customer approving an option.
  Future<void> approve(String id, {String? optionId, required String name}) =>
      _change(
        id,
        (r, now) => CustomerResponse(
          views: r.views,
          firstViewedAt: r.firstViewedAt,
          lastViewedAt: r.lastViewedAt,
          approvedAt: now,
          approvedTierId: optionId,
          signature: name,
        ),
      );

  Future<void> _change(
    String id,
    CustomerResponse Function(CustomerResponse, DateTime) change,
  ) async {
    final responses = await _load();
    responses[id] = change(responses[id] ?? const CustomerResponse(), _clock());
    await _save();
  }

  Future<Map<String, CustomerResponse>> _load() async {
    if (_responses != null) return _responses!;
    final map = <String, CustomerResponse>{};
    final raw = await _store.readText(_key);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, Object?>;
        for (final e in json.entries) {
          map[e.key] = CustomerResponse.fromJson(e.value);
        }
      } on Object {
        // Start over if the demo state is unreadable.
      }
    }
    return _responses = map;
  }

  Future<void> _save() => _store.writeText(
    _key,
    jsonEncode({for (final e in _responses!.entries) e.key: e.value.toJson()}),
  );
}
