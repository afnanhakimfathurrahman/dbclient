import 'dart:async';
import 'dart:io';

import 'package:mysql_client/exception.dart';
import 'package:mysql_client/mysql_client.dart';

import '../driver.dart';
import '../sql_dialect.dart';

/// MySQL and MariaDB via mysql_client.
///
/// Like the Postgres driver it keeps two connections: one for statements
/// (cancellable with KILL QUERY) and one for metadata, so browsing works
/// while a query runs.
class MySqlDriver implements SqlDriver {
  MySqlDriver(this.config);

  @override
  final ConnectionConfig config;

  @override
  Set<SqlFeature> get features => const {
    SqlFeature.constraints,
    SqlFeature.foreignKeys,
    SqlFeature.indexes,
    SqlFeature.triggers,
    SqlFeature.routines,
    SqlFeature.rowEditing,
    SqlFeature.transactions,
  };

  @override
  SqlDialect get dialect => const MySqlDialect();

  static const _timeout = Duration(seconds: 15);

  /// Server error for a query stopped by KILL QUERY.
  static const _interrupted = 1317;

  String? _password;
  MySQLConnection? _query;
  MySQLConnection? _meta;
  int? _queryConnectionId;
  bool _running = false;

  bool get _tls => config.tlsMode != TlsMode.disable;

  MySQLConnection get _queryConn =>
      _query ?? (throw const DriverException('Not connected'));
  MySQLConnection get _metaConn =>
      _meta ?? (throw const DriverException('Not connected'));

  Future<MySQLConnection> _open() async {
    final connection = await MySQLConnection.createConnection(
      host: config.host,
      port: config.port,
      userName: config.username,
      password: _password ?? '',
      secure: _tls,
      databaseName: config.database.isEmpty ? null : config.database,
    ).timeout(_timeout);
    await connection.connect(timeoutMs: _timeout.inMilliseconds);
    return connection;
  }

  @override
  Future<void> connect(String? password) => _guard(() async {
    _password = password;
    _meta = await _open();
    _query = await _open();
    final id = await _queryConn.execute('SELECT CONNECTION_ID()');
    _queryConnectionId = int.tryParse(id.rows.first.colAt(0) ?? '');
  });

  @override
  Future<void> close() async {
    for (final connection in [_query, _meta]) {
      try {
        await connection?.close();
      } catch (_) {
        // Already closed.
      }
    }
    _query = null;
    _meta = null;
  }

  @override
  Future<Duration> ping() => _guard(() async {
    final watch = Stopwatch()..start();
    await _metaConn.execute('SELECT 1');
    return watch.elapsed;
  });

  @override
  Future<void> cancel() async {
    final id = _queryConnectionId;
    if (!_running || id == null) return;
    await _guard(() => _metaConn.execute('KILL QUERY $id'));
  }

  @override
  Future<QueryResult> execute(String sql, {int maxRows = 10000}) =>
      _guard(() async {
        final watch = Stopwatch()..start();
        _running = true;
        Future<void>? cancelling;
        try {
          final result = await _queryConn.execute(sql, null, true);
          if (result.numOfColumns == 0) {
            return QueryResult(
              columns: const [],
              rows: const [],
              affectedRows: result.affectedRows.toInt(),
              elapsed: watch.elapsed,
              truncated: false,
            );
          }
          final columns = result.cols.toList();
          final rows = <List<Object?>>[];
          final budget = RowBudget(maxRows: maxRows);
          var truncated = false;
          try {
            await for (final row in result.rowsStream) {
              if (!budget.full) {
                final values = [
                  for (final (i, column) in columns.indexed)
                    _decode(row.colAt(i), column.type.intVal),
                ];
                rows.add(values);
                budget.add(values);
              } else if (!truncated) {
                // Stop the query on the server, then drain what's in flight
                // so the connection stays usable.
                truncated = true;
                cancelling = cancel().catchError((_) {});
              }
            }
          } on MySQLServerException catch (e) {
            if (!(truncated && e.errorCode == _interrupted)) rethrow;
          }
          return QueryResult(
            columns: [
              for (final column in columns)
                ResultColumn(
                  name: column.name,
                  dataType: _typeName(column.type.intVal),
                ),
            ],
            rows: rows,
            affectedRows: 0,
            elapsed: watch.elapsed,
            truncated: truncated,
          );
        } finally {
          // A KILL QUERY still in flight would hit the next statement.
          await cancelling;
          _running = false;
        }
      });

  /// DML runs in one transaction. Note that MySQL commits implicitly around
  /// DDL (CREATE, ALTER…), so schema changes can't be rolled back.
  @override
  Future<void> executeAll(List<String> statements) => _guard(() async {
    await _queryConn.execute('START TRANSACTION');
    try {
      for (final sql in statements) {
        await _queryConn.execute(sql);
      }
      await _queryConn.execute('COMMIT');
    } catch (_) {
      try {
        await _queryConn.execute('ROLLBACK');
      } catch (_) {
        // Keep the original error.
      }
      rethrow;
    }
  });

  /// The text protocol sends every value as text; numbers are converted so
  /// they sort, align and export as numbers. DECIMAL stays text to keep its
  /// precision.
  static Object? _decode(String? value, int type) {
    if (value == null) return null;
    return switch (type) {
      1 || 2 || 3 || 8 || 9 || 13 => int.tryParse(value) ?? value,
      4 || 5 => double.tryParse(value) ?? value,
      _ => value,
    };
  }

  static String _typeName(int type) => switch (type) {
    0 || 246 => 'decimal',
    1 => 'tinyint',
    2 => 'smallint',
    3 => 'int',
    4 => 'float',
    5 => 'double',
    7 || 17 => 'timestamp',
    8 => 'bigint',
    9 => 'mediumint',
    10 || 14 => 'date',
    11 || 19 => 'time',
    12 || 18 => 'datetime',
    13 => 'year',
    15 || 253 => 'varchar',
    16 => 'bit',
    245 => 'json',
    247 => 'enum',
    248 => 'set',
    249 || 250 || 251 || 252 => 'blob/text',
    254 => 'char',
    255 => 'geometry',
    _ => 'type $type',
  };

  // Metadata ----------------------------------------------------------------

  String _lit(String value) => dialect.quoteLiteral(value);

  /// Runs a metadata query; rows as nullable strings.
  Future<List<List<String?>>> _select(String sql) => _guard(() async {
    final result = await _metaConn.execute(sql);
    return [
      for (final row in result.rows)
        [for (var i = 0; i < result.numOfColumns; i++) row.colAt(i)],
    ];
  });

  @override
  Future<List<String>> listSchemas() async => [
    for (final row in await _select(
      'SELECT schema_name FROM information_schema.schemata '
      "WHERE schema_name NOT IN ('information_schema', 'performance_schema', "
      "'sys') ORDER BY schema_name",
    ))
      row[0]!,
  ];

  @override
  Future<List<DbObject>> listObjects(String schema) async => [
    for (final row in await _select(
      'SELECT table_name, table_type, create_options '
      'FROM information_schema.tables '
      'WHERE table_schema = ${_lit(schema)} ORDER BY table_name',
    ))
      DbObject(
        schema: schema,
        name: row[0]!,
        kind: switch (row[1]) {
          'VIEW' || 'SYSTEM VIEW' => DbObjectKind.view,
          _ when (row[2] ?? '').contains('partitioned') =>
            DbObjectKind.partitionedTable,
          _ => DbObjectKind.table,
        },
      ),
  ];

  @override
  Future<List<ColumnInfo>> listColumns(String schema, String object) async => [
    for (final row in await _select(
      'SELECT column_name, column_type, is_nullable, column_default, '
      'column_key, column_comment, extra FROM information_schema.columns '
      'WHERE table_schema = ${_lit(schema)} AND table_name = ${_lit(object)} '
      'ORDER BY ordinal_position',
    ))
      ColumnInfo(
        name: row[0]!,
        dataType: row[1]!,
        nullable: row[2] == 'YES',
        defaultValue: _default(row[3], row[6]),
        isPrimaryKey: row[4] == 'PRI',
        comment: (row[5] ?? '').isEmpty ? null : row[5],
      ),
  ];

  /// Default plus extras such as auto_increment or ON UPDATE, without
  /// MySQL 8's DEFAULT_GENERATED marker.
  static String? _default(String? value, String? extra) {
    final rest = (extra ?? '').replaceAll('DEFAULT_GENERATED', '').trim();
    final parts = [?value, if (rest.isNotEmpty) rest];
    return parts.isEmpty ? null : parts.join(' ');
  }

  @override
  Future<List<IndexInfo>> listIndexes(String schema, String object) async {
    final rows = await _select(
      'SELECT index_name, non_unique, column_name, sub_part, index_type '
      'FROM information_schema.statistics '
      'WHERE table_schema = ${_lit(schema)} AND table_name = ${_lit(object)} '
      'ORDER BY index_name, seq_in_index',
    );
    final byName = <String, List<List<String?>>>{};
    for (final row in rows) {
      byName.putIfAbsent(row[0]!, () => []).add(row);
    }
    final table = dialect.qualifiedName(schema, object);
    return [
      for (final MapEntry(key: name, value: parts) in byName.entries)
        () {
          final columns = [
            for (final p in parts)
              p[2] == null
                  ? '(expression)'
                  : '${dialect.quoteIdent(p[2]!)}'
                        '${p[3] == null ? '' : '(${p[3]})'}',
          ].join(', ');
          final unique = parts.first[1] == '0';
          final type = parts.first[4] ?? 'BTREE';
          return IndexInfo(
            name: name,
            isUnique: unique,
            isPrimary: name == 'PRIMARY',
            definition: name == 'PRIMARY'
                ? 'ALTER TABLE $table ADD PRIMARY KEY ($columns)'
                : 'CREATE ${switch (type) {
                        'FULLTEXT' => 'FULLTEXT ',
                        'SPATIAL' => 'SPATIAL ',
                        _ when unique => 'UNIQUE ',
                        _ => '',
                      }}INDEX ${dialect.quoteIdent(name)} ON $table ($columns)'
                      '${type == 'BTREE' || type == 'FULLTEXT' || type == 'SPATIAL' ? '' : ' USING $type'}',
          );
        }(),
    ];
  }

  @override
  Future<List<ConstraintInfo>> listConstraints(
    String schema,
    String object,
  ) async {
    final rows = await _select(
      'SELECT tc.constraint_name, tc.constraint_type, kcu.column_name, '
      'kcu.referenced_table_schema, kcu.referenced_table_name, '
      'kcu.referenced_column_name, rc.update_rule, rc.delete_rule '
      'FROM information_schema.table_constraints tc '
      'LEFT JOIN information_schema.key_column_usage kcu '
      '  ON kcu.constraint_schema = tc.constraint_schema '
      '  AND kcu.constraint_name = tc.constraint_name '
      '  AND kcu.table_name = tc.table_name '
      'LEFT JOIN information_schema.referential_constraints rc '
      '  ON rc.constraint_schema = tc.constraint_schema '
      '  AND rc.constraint_name = tc.constraint_name '
      '  AND rc.table_name = tc.table_name '
      'WHERE tc.table_schema = ${_lit(schema)} '
      'AND tc.table_name = ${_lit(object)} '
      'ORDER BY tc.constraint_name, kcu.ordinal_position',
    );
    // CHECK clauses live in their own view (MySQL 8.0.16+, MariaDB 10.2+).
    final checks = <String, String>{};
    try {
      for (final row in await _select(
        'SELECT constraint_name, check_clause '
        'FROM information_schema.check_constraints '
        'WHERE constraint_schema = ${_lit(schema)}',
      )) {
        checks[row[0]!] = row[1] ?? '';
      }
    } on DriverException {
      // Older servers: no CHECK constraints.
    }

    final byName = <String, List<List<String?>>>{};
    for (final row in rows) {
      byName.putIfAbsent(row[0]!, () => []).add(row);
    }
    String columns(List<List<String?>> parts, int index) => [
      for (final p in parts)
        if (p[index] != null) dialect.quoteIdent(p[index]!),
    ].join(', ');

    return [
      for (final MapEntry(key: name, value: parts) in byName.entries)
        if (switch (parts.first[1]) {
              'PRIMARY KEY' => ConstraintKind.primaryKey,
              'UNIQUE' => ConstraintKind.unique,
              'FOREIGN KEY' => ConstraintKind.foreignKey,
              'CHECK' => ConstraintKind.check,
              _ => null,
            }
            case final kind?)
          ConstraintInfo(
            name: name,
            kind: kind,
            referencedTable: kind == ConstraintKind.foreignKey
                ? '${parts.first[3]}.${parts.first[4]}'
                : null,
            definition: switch (kind) {
              ConstraintKind.primaryKey => 'PRIMARY KEY (${columns(parts, 2)})',
              ConstraintKind.unique => 'UNIQUE (${columns(parts, 2)})',
              ConstraintKind.check => 'CHECK (${checks[name] ?? '…'})',
              _ =>
                'FOREIGN KEY (${columns(parts, 2)}) REFERENCES '
                    '${dialect.qualifiedName(parts.first[3]!, parts.first[4]!)} '
                    '(${columns(parts, 5)})'
                    '${parts.first[7] == null || parts.first[7] == 'NO ACTION' || parts.first[7] == 'RESTRICT' ? '' : ' ON DELETE ${parts.first[7]}'}'
                    '${parts.first[6] == null || parts.first[6] == 'NO ACTION' || parts.first[6] == 'RESTRICT' ? '' : ' ON UPDATE ${parts.first[6]}'}',
            },
          ),
    ];
  }

  @override
  Future<List<TriggerInfo>> listTriggers(
    String schema,
    String object,
  ) async => [
    for (final row in await _select(
      'SELECT trigger_name, action_timing, event_manipulation, '
      'action_statement FROM information_schema.triggers '
      'WHERE event_object_schema = ${_lit(schema)} '
      'AND event_object_table = ${_lit(object)} ORDER BY trigger_name',
    ))
      TriggerInfo(
        name: row[0]!,
        enabled: true,
        definition:
            'CREATE TRIGGER ${dialect.quoteIdent(row[0]!)} ${row[1]} ${row[2]} '
            'ON ${dialect.qualifiedName(schema, object)} FOR EACH ROW\n${row[3]}',
      ),
  ];

  @override
  Future<List<PartitionInfo>> listPartitions(String s, String o) async =>
      const [];

  @override
  Future<List<RoutineInfo>> listRoutines(String schema) async => [
    for (final (i, row) in (await _select(
      'SELECT routine_name, routine_type, dtd_identifier '
      'FROM information_schema.routines '
      'WHERE routine_schema = ${_lit(schema)} ORDER BY routine_name',
    )).indexed)
      RoutineInfo(
        id: i,
        name: row[0]!,
        arguments: '',
        kind: row[1] == 'PROCEDURE'
            ? RoutineKind.procedure
            : RoutineKind.function,
        returnType: row[2],
        schema: schema,
      ),
  ];

  @override
  Future<String> routineDefinition(RoutineInfo routine) async {
    final kind = routine.kind == RoutineKind.procedure
        ? 'PROCEDURE'
        : 'FUNCTION';
    final rows = await _select(
      'SHOW CREATE $kind ${dialect.qualifiedName(routine.schema, routine.name)}',
    );
    final definition = rows.firstOrNull?.elementAtOrNull(2);
    if (definition == null) {
      throw const DriverException(
        'The definition is hidden: viewing it needs SHOW_ROUTINE or '
        'being the routine\'s definer',
      );
    }
    return '$definition;';
  }

  @override
  Future<String> ddl(String schema, String object) async {
    final type = await _select(
      'SELECT table_type FROM information_schema.tables '
      'WHERE table_schema = ${_lit(schema)} AND table_name = ${_lit(object)}',
    );
    final isView = type.firstOrNull?.first?.contains('VIEW') ?? false;
    final rows = await _select(
      'SHOW CREATE ${isView ? 'VIEW' : 'TABLE'} '
      '${dialect.qualifiedName(schema, object)}',
    );
    final text = rows.firstOrNull?.elementAtOrNull(1) ?? '';
    return text.endsWith(';') ? text : '$text;';
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on DriverException {
      rethrow;
    } on MySQLServerException catch (e) {
      throw DriverException(e.message, code: '${e.errorCode}');
    } on MySQLClientException catch (e) {
      if (e.message.contains('does not support SSL')) {
        throw const DriverException(
          "This server doesn't offer TLS. Set TLS to \"Disable\" (MySQL 8 "
          'users with the default caching_sha2_password login need TLS).',
        );
      }
      if (e.message.contains('caching_sha2_password')) {
        throw const DriverException(
          'This server uses MySQL 8\'s default login (caching_sha2_password), '
          'which this app supports only over TLS. Set TLS to "Require" '
          '(MySQL 8 enables TLS by default).',
        );
      }
      throw DriverException(e.message);
    } on SocketException catch (e) {
      throw DriverException(
        'Cannot reach ${config.host}:${config.port} — '
        '${e.osError?.message ?? e.message}',
      );
    } on TimeoutException {
      throw DriverException(
        'Timed out connecting to ${config.host}:${config.port}',
      );
    } on HandshakeException catch (e) {
      throw DriverException('TLS handshake failed: ${e.message}');
    }
  }
}
