import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:jobwalk_core/jobwalk_core.dart';

/// A published quote: what the customer sees and what they did with it.
class QuoteRecord {
  const QuoteRecord({
    required this.id,
    required this.ownerTokenHash,
    required this.createdAt,
    required this.updatedAt,
    required this.quote,
    this.revision = 1,
    this.response = const CustomerResponse(),
  });

  final String id;

  /// SHA-256 of the owner token; the token itself is never stored.
  final String ownerTokenHash;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final PublicQuote quote;
  final CustomerResponse response;

  bool ownedBy(String token) =>
      _constantTimeEquals(hashToken(token), ownerTokenHash);

  QuoteRecord copyWith({
    DateTime? updatedAt,
    int? revision,
    PublicQuote? quote,
    CustomerResponse? response,
  }) => QuoteRecord(
    id: id,
    ownerTokenHash: ownerTokenHash,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    revision: revision ?? this.revision,
    quote: quote ?? this.quote,
    response: response ?? this.response,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'owner_token_hash': ownerTokenHash,
    'created_at': createdAt.toUtc().toIso8601String(),
    'updated_at': updatedAt.toUtc().toIso8601String(),
    'revision': revision,
    'quote': quote.toJson(),
    'response': response.toJson(),
  };

  factory QuoteRecord.fromJson(Map<String, Object?> json) => QuoteRecord(
    id: json['id']! as String,
    ownerTokenHash: json['owner_token_hash']! as String,
    createdAt: DateTime.parse(json['created_at']! as String),
    updatedAt: DateTime.parse(json['updated_at']! as String),
    revision: (json['revision'] as num?)?.toInt() ?? 1,
    quote: PublicQuote.fromJson(json['quote']),
    response: CustomerResponse.fromJson(json['response']),
  );
}

String hashToken(String token) => sha256.convert(utf8.encode(token)).toString();

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

abstract interface class QuoteStore {
  Future<QuoteRecord?> get(String id);
  Future<void> put(QuoteRecord record);
}

/// Runs read-modify-write updates for the same key one at a time, so a
/// view and an approval landing together can't overwrite each other.
class KeyedLock {
  final _tails = <String, Future<void>>{};

  Future<T> run<T>(String key, Future<T> Function() task) {
    final previous = _tails[key] ?? Future<void>.value();
    final result = previous.then((_) => task());
    final tail = result.then<void>((_) {}, onError: (_) {});
    _tails[key] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_tails[key], tail)) _tails.remove(key);
      }),
    );
    return result;
  }
}

class MemoryQuoteStore implements QuoteStore {
  final records = <String, QuoteRecord>{};

  @override
  Future<QuoteRecord?> get(String id) async => records[id];

  @override
  Future<void> put(QuoteRecord record) async => records[record.id] = record;
}

/// One JSON file per quote. Fine for a single instance with a persistent
/// disk (a VM, or Fly.io with a volume). For several instances, implement
/// [QuoteStore] on Postgres or Firestore.
class FileQuoteStore implements QuoteStore {
  FileQuoteStore(this.dir);

  final Directory dir;
  static final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  File _file(String id) => File('${dir.path}/$id.json');

  @override
  Future<QuoteRecord?> get(String id) async {
    if (!_safeId.hasMatch(id)) return null;
    final f = _file(id);
    if (!await f.exists()) return null;
    final decoded = jsonDecode(await f.readAsString());
    return QuoteRecord.fromJson(decoded as Map<String, Object?>);
  }

  @override
  Future<void> put(QuoteRecord record) async {
    if (!_safeId.hasMatch(record.id)) {
      throw ArgumentError.value(record.id, 'id', 'Unsafe id.');
    }
    await dir.create(recursive: true);
    final f = _file(record.id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(record.toJson()), flush: true);
    await tmp.rename(f.path);
  }
}

class WaitlistEntry {
  const WaitlistEntry({
    required this.email,
    required this.at,
    this.trade = '',
    this.crew = '',
  });

  final String email;
  final DateTime at;
  final String trade;
  final String crew;

  Map<String, Object?> toJson() => {
    'email': email,
    'trade': trade,
    'crew': crew,
    'at': at.toUtc().toIso8601String(),
  };
}

abstract interface class WaitlistStore {
  Future<void> add(WaitlistEntry entry);
}

class MemoryWaitlistStore implements WaitlistStore {
  final entries = <WaitlistEntry>[];

  @override
  Future<void> add(WaitlistEntry entry) async => entries.add(entry);
}

/// Appends one JSON line per signup.
class FileWaitlistStore implements WaitlistStore {
  FileWaitlistStore(this.file);

  final File file;
  final _lock = KeyedLock();

  @override
  Future<void> add(WaitlistEntry entry) => _lock.run('waitlist', () async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      '${jsonEncode(entry.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
  });
}
