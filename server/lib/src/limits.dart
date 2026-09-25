import 'dart:async';
import 'dart:collection';

/// Token-bucket rate limiter keyed by an arbitrary string (install id, IP).
///
/// In-memory, so limits are per instance. For several instances behind a
/// load balancer, back this with Redis or use the platform's rate limiting.
class RateLimiter {
  RateLimiter({
    required this.capacity,
    required this.refillEvery,
    DateTime Function()? clock,
    this.maxKeys = 50000,
  }) : _clock = clock ?? DateTime.now;

  /// Maximum burst.
  final int capacity;

  /// Time to regain one token.
  final Duration refillEvery;

  final int maxKeys;
  final DateTime Function() _clock;
  final _buckets = <String, _Bucket>{};

  /// Takes a token for [key]. Returns null when allowed, or how long to wait.
  Duration? tryAcquire(String key) {
    final now = _clock();
    if (_buckets.length >= maxKeys) _evictFull(now);
    final bucket = _buckets.putIfAbsent(
      key,
      () => _Bucket(capacity.toDouble(), now),
    );
    bucket.refill(now, capacity, refillEvery);
    if (bucket.tokens >= 1) {
      bucket.tokens -= 1;
      return null;
    }
    final missing = 1 - bucket.tokens;
    return Duration(
      microseconds: (refillEvery.inMicroseconds * missing).ceil(),
    );
  }

  void _evictFull(DateTime now) {
    _buckets.removeWhere((_, b) {
      b.refill(now, capacity, refillEvery);
      return b.tokens >= capacity;
    });
    if (_buckets.length >= maxKeys) _buckets.clear();
  }
}

class _Bucket {
  _Bucket(this.tokens, this.updated);

  double tokens;
  DateTime updated;

  void refill(DateTime now, int capacity, Duration every) {
    final elapsed = now.difference(updated).inMicroseconds;
    if (elapsed <= 0) return;
    tokens = (tokens + elapsed / every.inMicroseconds).clamp(
      0,
      capacity.toDouble(),
    );
    updated = now;
  }
}

class Overloaded implements Exception {
  const Overloaded();
}

/// Caps concurrent upstream calls and the queue behind them, so a traffic
/// spike degrades into fast 503s instead of piling up slow requests.
class ConcurrencyLimiter {
  ConcurrencyLimiter({required this.maxConcurrent, required this.maxQueued});

  final int maxConcurrent;
  final int maxQueued;
  int _active = 0;
  final _waiting = Queue<Completer<void>>();

  int get active => _active;
  int get queued => _waiting.length;

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= maxConcurrent) {
      if (_waiting.length >= maxQueued) throw const Overloaded();
      final ticket = Completer<void>();
      _waiting.add(ticket);
      await ticket.future;
    } else {
      _active++;
    }
    try {
      return await task();
    } finally {
      if (_waiting.isNotEmpty) {
        // Hand the slot straight to the next waiter.
        _waiting.removeFirst().complete();
      } else {
        _active--;
      }
    }
  }
}
