import 'dart:async';

import 'package:jobwalk_server/jobwalk_server.dart';
import 'package:test/test.dart';

void main() {
  group('RateLimiter', () {
    test('allows a burst, then refills over time', () {
      var now = DateTime.utc(2026);
      final limiter = RateLimiter(
        capacity: 2,
        refillEvery: const Duration(minutes: 10),
        clock: () => now,
      );
      expect(limiter.tryAcquire('a'), isNull);
      expect(limiter.tryAcquire('a'), isNull);
      final wait = limiter.tryAcquire('a');
      expect(wait, isNotNull);
      expect(wait!.inMinutes, inInclusiveRange(9, 10));

      // Other keys are independent.
      expect(limiter.tryAcquire('b'), isNull);

      now = now.add(const Duration(minutes: 10));
      expect(limiter.tryAcquire('a'), isNull);
      expect(limiter.tryAcquire('a'), isNotNull);
    });

    test('never refills beyond capacity', () {
      var now = DateTime.utc(2026);
      final limiter = RateLimiter(
        capacity: 1,
        refillEvery: const Duration(seconds: 1),
        clock: () => now,
      );
      expect(limiter.tryAcquire('a'), isNull);
      now = now.add(const Duration(hours: 1));
      expect(limiter.tryAcquire('a'), isNull);
      expect(limiter.tryAcquire('a'), isNotNull);
    });

    test('evicts idle keys instead of growing without bound', () {
      var now = DateTime.utc(2026);
      final limiter = RateLimiter(
        capacity: 1,
        refillEvery: const Duration(seconds: 1),
        clock: () => now,
        maxKeys: 10,
      );
      for (var i = 0; i < 100; i++) {
        now = now.add(const Duration(seconds: 2));
        expect(limiter.tryAcquire('key$i'), isNull);
      }
    });
  });

  group('ConcurrencyLimiter', () {
    test('caps concurrency and queues the rest', () async {
      final limiter = ConcurrencyLimiter(maxConcurrent: 2, maxQueued: 1);
      final gates = List.generate(3, (_) => Completer<void>());
      var running = 0;
      var peak = 0;
      Future<int> task(int i) => limiter.run(() async {
        running++;
        peak = running > peak ? running : peak;
        await gates[i].future;
        running--;
        return i;
      });

      final futures = [task(0), task(1), task(2)];
      await Future<void>.delayed(Duration.zero);
      expect(limiter.active, 2);
      expect(limiter.queued, 1);

      // The queue is full: a fourth request is rejected immediately.
      await expectLater(limiter.run(() async => 0), throwsA(isA<Overloaded>()));

      for (final g in gates) {
        g.complete();
      }
      expect(await Future.wait(futures), [0, 1, 2]);
      expect(peak, 2);
      expect(limiter.active, 0);
      expect(limiter.queued, 0);
    });

    test('releases the slot when a task throws', () async {
      final limiter = ConcurrencyLimiter(maxConcurrent: 1, maxQueued: 0);
      await expectLater(
        limiter.run<void>(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(await limiter.run(() async => 'ok'), 'ok');
    });
  });
}
