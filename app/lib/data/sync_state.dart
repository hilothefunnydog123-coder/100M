import 'dart:convert';

import '../services/models.dart';
import 'blob_store.dart';

/// What this phone knows about the server's copy of its data.
class SyncState {
  const SyncState({
    this.businessId = '',
    this.account,
    this.cursor = 0,
    this.versions = const {},
    this.dirty = const {},
    this.deleted = const {},
    this.uploaded = const {},
    this.deposits = const {},
    this.numbers = const [],
    this.businessDirty = false,
  });

  /// Whose quotes are on this phone. Signing in to another business
  /// clears them first.
  final String businessId;

  /// The last account seen, so the app knows its plan while offline.
  final Account? account;

  /// Where the next pull starts.
  final int cursor;

  /// The server's version of each quote this phone has synced.
  final Map<String, int> versions;

  /// Quotes changed here and not yet sent.
  final Set<String> dirty;

  /// Quotes deleted here and not yet deleted on the server.
  final Set<String> deleted;

  /// Photos known to be on the server.
  final Set<String> uploaded;

  /// Card deposits paid, by quote id.
  final Map<String, int> deposits;

  /// Quote numbers reserved for this phone, next first.
  final List<int> numbers;

  /// The profile or rates changed here and haven't reached the server.
  final bool businessDirty;

  int get pending => dirty.length + deleted.length + (businessDirty ? 1 : 0);

  static const _keep = Object();

  SyncState copyWith({
    String? businessId,
    Object? account = _keep,
    int? cursor,
    Map<String, int>? versions,
    Set<String>? dirty,
    Set<String>? deleted,
    Set<String>? uploaded,
    Map<String, int>? deposits,
    List<int>? numbers,
    bool? businessDirty,
  }) => SyncState(
    businessId: businessId ?? this.businessId,
    account: identical(account, _keep) ? this.account : account as Account?,
    cursor: cursor ?? this.cursor,
    versions: versions ?? this.versions,
    dirty: dirty ?? this.dirty,
    deleted: deleted ?? this.deleted,
    uploaded: uploaded ?? this.uploaded,
    deposits: deposits ?? this.deposits,
    numbers: numbers ?? this.numbers,
    businessDirty: businessDirty ?? this.businessDirty,
  );

  Map<String, Object?> toJson() => {
    'business_id': businessId,
    'account': account?.toJson(),
    'cursor': cursor,
    'versions': versions,
    'dirty': dirty.toList(),
    'deleted': deleted.toList(),
    'uploaded': uploaded.toList(),
    'deposits': deposits,
    'numbers': numbers,
    'business_dirty': businessDirty,
  };

  factory SyncState.fromJson(Map<String, Object?> json) {
    Set<String> strings(Object? v) => {
      if (v is List)
        for (final s in v)
          if (s is String) s,
    };
    Map<String, int> ints(Object? v) => {
      if (v is Map)
        for (final e in v.entries)
          if (e.key is String && e.value is num)
            e.key as String: (e.value as num).toInt(),
    };
    final account = json['account'];
    final cursor = json['cursor'];
    return SyncState(
      businessId: json['business_id'] is String
          ? json['business_id']! as String
          : '',
      account: account is Map ? Account.fromJson(account) : null,
      cursor: cursor is num ? cursor.toInt() : 0,
      versions: ints(json['versions']),
      dirty: strings(json['dirty']),
      deleted: strings(json['deleted']),
      uploaded: strings(json['uploaded']),
      deposits: ints(json['deposits']),
      numbers: [
        if (json['numbers'] is List)
          for (final n in json['numbers']! as List)
            if (n is num) n.toInt(),
      ],
      businessDirty: json['business_dirty'] == true,
    );
  }
}

class SyncStateRepository {
  SyncStateRepository(this._store);

  static const _key = 'sync.json';
  final BlobStore _store;

  Future<SyncState> load() async {
    final raw = await _store.readText(_key);
    if (raw == null) return const SyncState();
    try {
      return SyncState.fromJson(jsonDecode(raw) as Map<String, Object?>);
    } on Object {
      // Unreadable: a full pull rebuilds it.
      return const SyncState();
    }
  }

  Future<void> save(SyncState state) =>
      _store.writeText(_key, jsonEncode(state.toJson()));
}
