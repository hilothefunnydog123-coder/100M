import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

import 'fakes.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('jobwalk'));
  tearDown(() async => dir.delete(recursive: true));

  QuoteRecord record(String id) => QuoteRecord(
    id: id,
    ownerTokenHash: hashToken('secret'),
    createdAt: now,
    updatedAt: now,
    quote: publicQuote(),
  );

  test('file store round trip', () async {
    final store = FileQuoteStore(Directory('${dir.path}/quotes'));
    expect(await store.get('abc'), isNull);
    await store.put(record('abc'));
    final back = (await store.get('abc'))!;
    expect(back.toJson(), record('abc').toJson());
    expect(back.ownedBy('secret'), isTrue);
    expect(back.ownedBy('Secret'), isFalse);
  });

  test('file store refuses unsafe ids', () async {
    final store = FileQuoteStore(dir);
    expect(await store.get('../x'), isNull);
    expect(() => store.put(record('../x')), throwsArgumentError);
  });

  test('waitlist appends JSON lines', () async {
    final file = File('${dir.path}/sub/waitlist.jsonl');
    final store = FileWaitlistStore(file);
    await Future.wait([
      for (var i = 0; i < 5; i++)
        store.add(WaitlistEntry(email: 'a$i@b.co', at: now, trade: 'painting')),
    ]);
    final lines = await file.readAsLines();
    expect(lines, hasLength(5));
    expect((jsonDecode(lines.first) as Map)['trade'], 'painting');
  });

  test('keyed lock runs tasks for one key in order', () async {
    final lock = KeyedLock();
    final events = <String>[];
    final gate = Completer<void>();
    final a = lock.run('k', () async {
      events.add('a start');
      await gate.future;
      events.add('a end');
    });
    final b = lock.run('k', () async => events.add('b'));
    final other = lock.run('other', () async => events.add('other'));
    await other;
    expect(events, ['a start', 'other']);
    gate.complete();
    await Future.wait([a, b]);
    expect(events, ['a start', 'other', 'a end', 'b']);
  });

  test('a failed task does not block the next', () async {
    final lock = KeyedLock();
    await expectLater(
      lock.run<void>('k', () async => throw StateError('boom')),
      throwsStateError,
    );
    expect(await lock.run('k', () async => 42), 42);
  });
}
