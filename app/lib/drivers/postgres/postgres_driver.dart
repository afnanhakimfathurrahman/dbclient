import 'dart:async';
import 'dart:io';

import 'package:postgres/postgres.dart' as pg;

import '../driver.dart';
import '../sql_dialect.dart';
import 'postgres_sql.dart';

/// PostgreSQL driver built on `package:postgres`.
///
/// Holds two connections: one for user queries and one for metadata, so
/// browsing the schema tree isn't blocked behind a long-running query.
/// Cancellation opens a short-lived third connection and calls
/// `pg_cancel_backend` on the query connection's backend.
class PostgresDriver implements SqlDriver {
  PostgresDriver(this.config);

  @override
  final ConnectionConfig config;

  @override
  Set<SqlFeature> get features => SqlFeature.values.toSet();

  @override
  SqlDialect get dialect => postgresDialect;

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
            AND c.relkind IN ('r', 'p', 'v', 'm', 'f', 'S')
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
          kind: _kindOf(row[1] as String),
        ),
    ];
  }

  static DbObjectKind _kindOf(String relkind) => switch (relkind) {
    'p' => DbObjectKind.partitionedTable,
    'v' => DbObjectKind.view,
    'm' => DbObjectKind.materializedView,
    'f' => DbObjectKind.foreignTable,
    'S' => DbObjectKind.sequence,
    _ => DbObjectKind.table,
  };

  /// SQL expression resolving @schema/@object to the relation's oid.
  static const _relation =
      "(quote_ident(@schema:text) || '.' || quote_ident(@object:text))::regclass";

  Future<pg.Result> _metaQuery(String sql, String schema, String object) {
    return _guard(
      () => _metaConn.execute(
        pg.Sql.named(sql),
        parameters: {'schema': schema, 'object': object},
      ),
    );
  }

  @override
  Future<List<IndexInfo>> listIndexes(String schema, String object) async {
    final result = await _metaQuery(
      '''
      SELECT ic.relname, pg_get_indexdef(i.indexrelid), i.indisunique,
             i.indisprimary, pg_size_pretty(pg_relation_size(i.indexrelid))
      FROM pg_index i
      JOIN pg_class ic ON ic.oid = i.indexrelid
      WHERE i.indrelid = $_relation
      ORDER BY i.indisprimary DESC, ic.relname
      ''',
      schema,
      object,
    );
    return [
      for (final row in result)
        IndexInfo(
          name: row[0] as String,
          definition: row[1] as String,
          isUnique: row[2] as bool,
          isPrimary: row[3] as bool,
          size: row[4] as String?,
        ),
    ];
  }

  @override
  Future<List<ConstraintInfo>> listConstraints(
    String schema,
    String object,
  ) async {
    // Not-null constraints (contype 'n', Postgres 18+) are shown on columns.
    final result = await _metaQuery(
      '''
      SELECT con.conname, con.contype::text, pg_get_constraintdef(con.oid),
             CASE WHEN con.contype = 'f' THEN con.confrelid::regclass::text END
      FROM pg_constraint con
      WHERE con.conrelid = $_relation
        AND con.contype IN ('p', 'u', 'c', 'f', 'x')
      ORDER BY position(con.contype::text IN 'pufcx'), con.conname
      ''',
      schema,
      object,
    );
    return [
      for (final row in result)
        ConstraintInfo(
          name: row[0] as String,
          kind: switch (row[1] as String) {
            'p' => ConstraintKind.primaryKey,
            'u' => ConstraintKind.unique,
            'f' => ConstraintKind.foreignKey,
            'x' => ConstraintKind.exclusion,
            _ => ConstraintKind.check,
          },
          definition: row[2] as String,
          referencedTable: row[3] as String?,
        ),
    ];
  }

  @override
  Future<List<TriggerInfo>> listTriggers(String schema, String object) async {
    final result = await _metaQuery(
      '''
      SELECT t.tgname, pg_get_triggerdef(t.oid, true), t.tgenabled <> 'D'
      FROM pg_trigger t
      WHERE t.tgrelid = $_relation AND NOT t.tgisinternal
      ORDER BY t.tgname
      ''',
      schema,
      object,
    );
    return [
      for (final row in result)
        TriggerInfo(
          name: row[0] as String,
          definition: row[1] as String,
          enabled: row[2] as bool,
        ),
    ];
  }

  @override
  Future<List<PartitionInfo>> listPartitions(
    String schema,
    String object,
  ) async {
    final result = await _metaQuery(
      '''
      SELECT n.nspname, c.relname, c.relkind::text,
             coalesce(pg_get_expr(c.relpartbound, c.oid), '')
      FROM pg_inherits inh
      JOIN pg_class c ON c.oid = inh.inhrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE inh.inhparent = $_relation
      ORDER BY c.relname
      ''',
      schema,
      object,
    );
    return [
      for (final row in result)
        PartitionInfo(
          object: DbObject(
            schema: row[0] as String,
            name: row[1] as String,
            kind: _kindOf(row[2] as String),
          ),
          bound: row[3] as String,
        ),
    ];
  }

  @override
  Future<List<RoutineInfo>> listRoutines(String schema) async {
    // Hides functions that belong to extensions (e.g. pgcrypto), like
    // DBeaver does by default.
    final result = await _guard(
      () => _metaConn.execute(
        pg.Sql.named('''
          SELECT p.oid::int8, p.proname,
                 pg_get_function_identity_arguments(p.oid),
                 p.prokind::text,
                 CASE WHEN p.prokind = 'f' THEN pg_get_function_result(p.oid) END
          FROM pg_proc p
          JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = @schema:text
            AND p.prokind IN ('f', 'p')
            AND NOT EXISTS (
              SELECT 1 FROM pg_depend d
              WHERE d.classid = 'pg_proc'::regclass AND d.objid = p.oid
                AND d.deptype = 'e'
            )
          ORDER BY p.proname, 3
        '''),
        parameters: {'schema': schema},
      ),
    );
    return [
      for (final row in result)
        RoutineInfo(
          id: row[0] as int,
          name: row[1] as String,
          arguments: row[2] as String,
          kind: row[3] == 'p' ? RoutineKind.procedure : RoutineKind.function,
          returnType: row[4] as String?,
        ),
    ];
  }

  @override
  Future<String> routineDefinition(RoutineInfo routine) async {
    // The id comes from pg_proc, so inlining it is safe.
    final result = await _guard(
      () => _metaConn.execute('SELECT pg_get_functiondef(${routine.id}::oid)'),
    );
    return result.first.first as String;
  }

  @override
  Future<String> ddl(String schema, String object) async {
    final info = (await _metaQuery(
      '''
      SELECT c.oid::int8, c.relkind::text,
             obj_description(c.oid, 'pg_class'),
             CASE WHEN c.relkind = 'p' THEN pg_get_partkeydef(c.oid) END,
             CASE WHEN c.relispartition THEN (
               SELECT inhparent::regclass::text FROM pg_inherits
               WHERE inhrelid = c.oid
             ) END,
             CASE WHEN c.relispartition
                  THEN pg_get_expr(c.relpartbound, c.oid) END,
             CASE WHEN c.relkind IN ('v', 'm')
                  THEN pg_get_viewdef(c.oid, true) END,
             (SELECT s.srvname FROM pg_foreign_table ft
              JOIN pg_foreign_server s ON s.oid = ft.ftserver
              WHERE ft.ftrelid = c.oid)
      FROM pg_class c
      WHERE c.oid = $_relation
      ''',
      schema,
      object,
    )).first;
    final oid = info[0] as int;
    final kind = info[1] as String;
    final comment = info[2] as String?;

    if (kind == 'S') {
      // The oid comes from pg_class, so inlining it is safe.
      final seq = (await _guard(
        () => _metaConn.execute(
          'SELECT format_type(seqtypid, NULL), seqstart, seqincrement, '
          'seqmin, seqmax, seqcache, seqcycle '
          'FROM pg_sequence WHERE seqrelid = $oid',
        ),
      )).first;
      return buildPgSequenceDdl(
        schema: schema,
        name: object,
        type: seq[0] as String,
        start: seq[1] as int,
        increment: seq[2] as int,
        min: seq[3] as int,
        max: seq[4] as int,
        cache: seq[5] as int,
        cycle: seq[6] as bool,
      );
    }

    final indexes = await listIndexes(schema, object);
    if (kind == 'v' || kind == 'm') {
      return buildPgViewDdl(
        schema: schema,
        name: object,
        definition: info[6] as String,
        materialized: kind == 'm',
        indexes: indexes,
        comment: comment,
      );
    }

    final columns = await _metaQuery(
      '''
      SELECT a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull,
             pg_get_expr(d.adbin, d.adrelid), a.attidentity::text,
             a.attgenerated::text, col_description(a.attrelid, a.attnum)
      FROM pg_attribute a
      LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
      WHERE a.attrelid = $_relation AND a.attnum > 0 AND NOT a.attisdropped
      ORDER BY a.attnum
      ''',
      schema,
      object,
    );
    final constraints = await listConstraints(schema, object);
    final constraintNames = {for (final c in constraints) c.name};
    return buildPgTableDdl(
      schema: schema,
      name: object,
      columns: [
        for (final row in columns)
          PgColumnDdl(
            name: row[0] as String,
            type: row[1] as String,
            notNull: row[2] as bool,
            defaultExpr: row[3] as String?,
            identity: row[4] as String,
            generated: row[5] as String,
            comment: row[6] as String?,
          ),
      ],
      constraints: constraints,
      // Indexes backing a primary key/unique/exclusion constraint are
      // created by the constraint itself.
      indexes: [
        for (final i in indexes)
          if (!constraintNames.contains(i.name)) i,
      ],
      triggers: await listTriggers(schema, object),
      partitionKey: info[3] as String?,
      partitionOf: info[4] as String?,
      partitionBound: info[5] as String?,
      foreignServer: info[7] as String?,
      comment: comment,
    );
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
                 ),
                 col_description(a.attrelid, a.attnum)
          FROM pg_attribute a
          LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
          WHERE a.attrelid = $_relation
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
          comment: row[5] as String?,
        ),
    ];
  }

  @override
  Future<void> executeAll(List<String> statements) => _guard(
    () => _queryConn.runTx((tx) async {
      for (final sql in statements) {
        await tx.execute(sql);
      }
    }),
  );

  @override
  Future<QueryResult> execute(String sql, {int maxRows = 10000}) async {
    final watch = Stopwatch()..start();
    final rows = <List<Object?>>[];
    final budget = RowBudget(maxRows: maxRows);
    var truncated = false;
    Future<void>? cancelling;

    return _guard(() async {
      final statement = await _queryConn.prepare(sql);
      try {
        final subscription = statement.bind(null).listen((row) {
          if (!budget.full) {
            final values = [for (final value in row) _convert(value)];
            rows.add(values);
            budget.add(values);
          } else if (!truncated) {
            // Stop the server from sending the rest instead of downloading
            // rows we would throw away.
            truncated = true;
            cancelling = _cancelBackend().catchError((_) {});
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
        // A cancel still in flight would interrupt the next statement.
        await cancelling;
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
