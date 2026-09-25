import '../limits.dart';
import 'database.dart';

/// Token buckets in Postgres, so every instance shares the same limits.
/// One statement per check: refill by elapsed time, then take a token.
class PgLimiter implements Limiter {
  PgLimiter(
    this._db, {
    required this.capacity,
    required this.refillEvery,
    DateTime Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().toUtc());

  final Db _db;
  final int capacity;
  final Duration refillEvery;
  final DateTime Function() _clock;

  @override
  Future<Duration?> acquire(String key) async {
    final refill = refillEvery.inMicroseconds / 1e6;
    final row = await _db.one(
      '''
      INSERT INTO rate_limits (key, tokens, updated_at)
      VALUES (@key, @cap::float8 - 1, @now:timestamptz)
      ON CONFLICT (key) DO UPDATE SET
        tokens = GREATEST(-1, LEAST(@cap::float8,
          rate_limits.tokens +
          GREATEST(0, EXTRACT(EPOCH FROM @now:timestamptz - rate_limits.updated_at))
            / @refill::float8) - 1),
        updated_at = @now:timestamptz
      RETURNING tokens''',
      {
        'key': key,
        'cap': capacity.toDouble(),
        'now': _clock(),
        'refill': refill,
      },
    );
    final tokens = (row!['tokens'] as num).toDouble();
    if (tokens >= 0) return null;
    return Duration(
      microseconds: (-tokens * refillEvery.inMicroseconds).ceil(),
    );
  }
}
