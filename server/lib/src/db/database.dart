import 'package:postgres/postgres.dart';

typedef Row = Map<String, dynamic>;

/// A thin layer over the Postgres pool: named parameters in, maps out, and
/// transactions that nest by reusing the outer one.
///
/// Parameters use `@name` placeholders; annotate the type where Postgres
/// can't infer it, e.g. `@data:jsonb`, `@at:timestamptz`, `@n:int4`.
class Db {
  Db._(this._session, this._executor, this._pool);

  /// Opens a pool from a `postgres://user:pass@host:port/db?sslmode=...`
  /// URL, as Heroku, Fly, Railway, Render, Neon, and Supabase provide.
  factory Db.open(String url, {int maxConnections = 10}) {
    final uri = Uri.parse(url);
    final params = {...uri.queryParameters};
    params.putIfAbsent('max_connection_count', () => '$maxConnections');
    params.putIfAbsent('sslmode', () => defaultSslMode(uri.host));
    final pool = Pool.withUrl(uri.replace(queryParameters: params).toString());
    return Db._(pool, pool, pool);
  }

  /// TLS unless the host is local or on a private network (a Compose
  /// service name, Fly's `.internal` and `.flycast`), where Postgres
  /// usually has none. An `sslmode` in the URL always wins.
  static String defaultSslMode(String host) {
    final h = host.toLowerCase();
    final private =
        const {'localhost', '127.0.0.1', '::1'}.contains(h) ||
        !h.contains('.') ||
        h.endsWith('.internal') ||
        h.endsWith('.flycast') ||
        h.endsWith('.local');
    return private ? 'disable' : 'require';
  }

  final Session _session;

  /// Null inside a transaction: nested calls join the outer one.
  final SessionExecutor? _executor;
  final Pool<Object?>? _pool;

  bool get inTransaction => _executor == null;

  Future<List<Row>> query(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async {
    final result = await _session.execute(
      Sql.named(sql),
      parameters: _used(sql, params),
    );
    return [for (final row in result) row.toColumnMap()];
  }

  Future<Row?> one(String sql, [Map<String, Object?> params = const {}]) async {
    final rows = await query(sql, params);
    return rows.isEmpty ? null : rows.first;
  }

  /// Runs a statement and returns the number of rows it touched.
  Future<int> execute(
    String sql, [
    Map<String, Object?> params = const {},
  ]) async {
    final result = await _session.execute(
      Sql.named(sql),
      parameters: _used(sql, params),
    );
    return result.affectedRows;
  }

  /// Runs several statements at once (migrations). No parameters.
  Future<void> script(String sql) async {
    await _session.execute(sql, queryMode: QueryMode.simple);
  }

  /// Runs [fn] in a transaction; rolls back if it throws.
  Future<T> tx<T>(Future<T> Function(Db tx) fn) {
    final executor = _executor;
    if (executor == null) return fn(this);
    return executor.runTx((session) => fn(Db._(session, null, null)));
  }

  /// Runs [fn] on one dedicated connection, e.g. to hold an advisory lock.
  Future<T> withConnection<T>(Future<T> Function(Db connection) fn) {
    final pool = _pool;
    if (pool == null) return fn(this);
    return pool.withConnection(
      (connection) => fn(Db._(connection, connection, null)),
    );
  }

  Future<bool> ping() async {
    try {
      await _session.execute('SELECT 1', timeout: const Duration(seconds: 3));
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> close() async => _pool?.close();
}

final _placeholder = RegExp(r'@([A-Za-z_][A-Za-z0-9_]*)');
final _namesBySql = <String, Set<String>>{};

/// Drops parameters the statement doesn't use, so one map can serve
/// statements that differ by branch. (The driver rejects extras.)
Map<String, Object?> _used(String sql, Map<String, Object?> params) {
  if (params.isEmpty) return params;
  if (_namesBySql.length > 2000) _namesBySql.clear();
  final names = _namesBySql.putIfAbsent(
    sql,
    () => {for (final m in _placeholder.allMatches(sql)) m.group(1)!},
  );
  if (params.keys.every(names.contains)) return params;
  return {
    for (final e in params.entries)
      if (names.contains(e.key)) e.key: e.value,
  };
}

/// Postgres unique-constraint violation.
bool isUniqueViolation(Object e) => e is UniqueViolationException;
