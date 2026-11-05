import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;

import '../driver.dart';

/// PostgreSQL driver built on `package:postgres`.
///
/// Holds two connections: one for user queries and one for metadata, so
/// browsing the schema tree isn't blocked behind a long-running query.
/// Cancellation opens a short-lived third connection and calls
/// `pg_cancel_backend` on the query connection's backend.
class PostgresDriver implements DatabaseDriver {
  PostgresDriver(this.config);

  @override
  final ConnectionConfig config;

  pg.Connection? _query;
  pg.Connection? _meta;
  int? _queryBackendPid;
  String? _password;
  final _typeNames = <int, String>{};

  pg.Endpoint get _endpoint => pg.Endpoint(
    host: config.host,
    port: config.port,
    database: config.database,
    username: config.username,
    password: _password,
  );

  pg.ConnectionSettings get _settings => pg.ConnectionSettings(
    applicationName: 'DB Client',
    connectTimeout: const Duration(seconds: 10),
    queryTimeout: const Duration(hours: 1),
    sslMode: switch (config.tlsMode) {
      TlsMode.disable => pg.SslMode.disable,
      TlsMode.require => pg.SslMode.require,
      TlsMode.verifyFull => pg.SslMode.verifyFull,
    },
  );

  pg.Connection get _queryConn => _query ?? (throw _notConnected());
  pg.Connection get _metaConn => _meta ?? (throw _notConnected());

  @override
  Future<void> connect(String? password) async {
    _password = password;
    await _guard(() async {
      _meta = await pg.Connection.open(_endpoint, settings: _settings);
      _query = await pg.Connection.open(_endpoint, settings: _settings);
      final pidResult = await _query!.execute('SELECT pg_backend_pid()');
      _queryBackendPid = pidResult.first.first as int;
    });
  }

  @override
  Future<void> close() async {
    final connections = [_query, _meta];
    _query = null;
    _meta = null;
    _queryBackendPid = null;
    for (final c in connections) {
      try {
        await c?.close(force: true);
      } catch (_) {
        // Already broken; nothing left to clean up.
      }
    }
  }

  @override
  Future<Duration> ping() async {
    final watch = Stopwatch()..start();
    await _guard(() => _metaConn.execute('SELECT 1'));
    return watch.elapsed;
  }

  @override
  Future<List<String>> listSchemas() async {
    final result = await _guard(
      () => _metaConn.execute('''
        SELECT nspname FROM pg_namespace
        WHERE nspname NOT LIKE 'pg\\_%' AND nspname <> 'information_schema'
        ORDER BY nspname = 'public' DESC, nspname
      '''),
    );
    return [for (final row in result) row[0] as String];
  }

  @override
  Future<List<DbObject>> listObjects(String schema) async {
    final result = await _guard(
      () => _metaConn.execute(
        pg.Sql.named('''
          SELECT c.relname, c.relkind::text
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = @schema:text
            AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
            AND NOT c.relispartition
          ORDER BY c.relname
        '''),
        parameters: {'schema': schema},
      ),
    );
    return [
      for (final row in result)
        DbObject(
          schema: schema,
          name: row[0] as String,
          kind: switch (row[1] as String) {
            'p' => DbObjectKind.partitionedTable,
            'v' => DbObjectKind.view,
            'm' => DbObjectKind.materializedView,
            'f' => DbObjectKind.foreignTable,
            _ => DbObjectKind.table,
          },
        ),
    ];
  }

  @override
  Future<List<ColumnInfo>> listColumns(String schema, String object) async {
    final result = await _guard(
      () => _metaConn.execute(
        pg.Sql.named('''
          SELECT a.attname,
                 format_type(a.atttypid, a.atttypmod),
                 NOT a.attnotnull,
                 pg_get_expr(d.adbin, d.adrelid),
                 EXISTS (
                   SELECT 1 FROM pg_index i
                   WHERE i.indrelid = a.attrelid AND i.indisprimary
                     AND a.attnum = ANY (i.indkey)
                 )
          FROM pg_attribute a
          LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
          WHERE a.attrelid = (quote_ident(@schema:text) || '.' || quote_ident(@object:text))::regclass
            AND a.attnum > 0 AND NOT a.attisdropped
          ORDER BY a.attnum
        '''),
        parameters: {'schema': schema, 'object': object},
      ),
    );
    return [
      for (final row in result)
        ColumnInfo(
          name: row[0] as String,
          dataType: row[1] as String,
          nullable: row[2] as bool,
          defaultValue: row[3] as String?,
          isPrimaryKey: row[4] as bool,
        ),
    ];
  }

  @override
  Future<QueryResult> execute(String sql, {int maxRows = 10000}) async {
    final watch = Stopwatch()..start();
    final rows = <List<Object?>>[];
    var truncated = false;

    return _guard(() async {
      final statement = await _queryConn.prepare(sql);
      try {
        final subscription = statement.bind(null).listen((row) {
          if (rows.length < maxRows) {
            rows.add([for (final value in row) _convert(value)]);
          } else if (!truncated) {
            // Stop the server from sending the rest instead of downloading
            // rows we would throw away.
            truncated = true;
            unawaited(_cancelBackend().catchError((_) {}));
          }
        });
        try {
          await subscription.asFuture<void>();
        } on pg.ServerException catch (e) {
          if (!(truncated && e.code == '57014')) rethrow;
        }
        final schema = await subscription.schema;
        final affected = await subscription.affectedRows;
        final columns = await _resultColumns(schema);
        return QueryResult(
          columns: columns,
          rows: rows,
          affectedRows: affected,
          elapsed: watch.elapsed,
          truncated: truncated,
        );
      } finally {
        await statement.dispose().catchError((_) {});
      }
    });
  }

  @override
  Future<void> cancel() => _guard(_cancelBackend);

  Future<void> _cancelBackend() async {
    final pid = _queryBackendPid;
    if (pid == null) return;
    final side = await pg.Connection.open(_endpoint, settings: _settings);
    try {
      await side.execute('SELECT pg_cancel_backend($pid)');
    } finally {
      await side.close();
    }
  }

  Future<List<ResultColumn>> _resultColumns(pg.ResultSchema schema) async {
    final missing = {
      for (final c in schema.columns)
        if (!_typeNames.containsKey(c.typeOid)) c.typeOid,
    };
    if (missing.isNotEmpty) {
      final result = await _metaConn.execute(
        'SELECT oid::int4, format_type(oid, NULL) FROM pg_type '
        'WHERE oid IN (${missing.join(',')})',
      );
      for (final row in result) {
        _typeNames[row[0] as int] = row[1] as String;
      }
    }
    return [
      for (final (i, c) in schema.columns.indexed)
        ResultColumn(
          name: (c.columnName?.isNotEmpty ?? false)
              ? c.columnName!
              : '?column${i + 1}?',
          dataType: _typeNames[c.typeOid] ?? 'oid ${c.typeOid}',
        ),
    ];
  }

  Object? _convert(Object? value) {
    if (value is pg.UndecodedBytes) {
      return value.isBinary ? value.bytes : value.encoding.decode(value.bytes);
    }
    return value;
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on pg.ServerException catch (e) {
      throw DriverException(
        e.message,
        code: e.code,
        detail: e.detail,
        hint: e.hint,
        position: e.position,
      );
    } on pg.PgException catch (e) {
      throw DriverException(e.message);
    } on SocketException catch (e) {
      throw DriverException(
        'Cannot reach ${config.host}:${config.port} — ${e.osError?.message ?? e.message}',
      );
    } on TimeoutException {
      throw DriverException(
        'Timed out connecting to ${config.host}:${config.port}',
      );
    } on HandshakeException catch (e) {
      throw DriverException('TLS handshake failed: ${e.message}');
    }
  }

  DriverException _notConnected() =>
      const DriverException('Not connected. Connect first.');
}
