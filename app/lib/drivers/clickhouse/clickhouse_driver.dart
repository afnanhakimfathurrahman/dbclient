import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:uuid/uuid.dart';

import '../driver.dart';
import '../sql_dialect.dart';

/// ClickHouse over its HTTP interface (port 8123, or 8443 with TLS).
///
/// HTTP is stateless; editor statements share a server session so `SET`
/// and temporary tables persist, while metadata queries run outside it
/// (a session serves one query at a time).
class ClickHouseDriver implements SqlDriver {
  ClickHouseDriver(this.config);

  @override
  final ConnectionConfig config;

  @override
  Set<SqlFeature> get features => const {SqlFeature.indexes};

  @override
  SqlDialect get dialect => const ClickHouseDialect();

  static const _format = 'JSONCompactEachRowWithNamesAndTypes';

  String? _password;
  final _sessionId = const Uuid().v4();
  bool _connected = false;

  /// The editor statement in flight, for [cancel].
  String? _runningQueryId;
  http.Client? _runningClient;

  bool get _tls => config.tlsMode != TlsMode.disable;

  http.Client _newClient() {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    if (config.tlsMode == TlsMode.require) {
      // "Require" encrypts without verifying the certificate.
      client.badCertificateCallback = (_, _, _) => true;
    }
    return IOClient(client);
  }

  Uri _uri(Map<String, String> params) => Uri(
    scheme: _tls ? 'https' : 'http',
    host: config.host,
    port: config.port,
    path: '/',
    queryParameters: {
      if (config.database.isNotEmpty) 'database': config.database,
      'default_format': _format,
      ...params,
    },
  );

  Map<String, String> get _headers => {
    'X-ClickHouse-User': config.username.isEmpty ? 'default' : config.username,
    if (_password?.isNotEmpty ?? false) 'X-ClickHouse-Key': _password!,
  };

  @override
  Future<void> connect(String? password) async {
    _password = password;
    // Validates host, credentials and database in one round trip.
    await _query('SELECT 1');
    _connected = true;
  }

  @override
  Future<void> close() async {
    _connected = false;
    _runningClient?.close();
  }

  @override
  Future<Duration> ping() async {
    final watch = Stopwatch()..start();
    await _query('SELECT 1');
    return watch.elapsed;
  }

  /// Runs [sql] and returns all rows; for metadata. Named parameters are
  /// passed as `{name:String}` placeholders.
  Future<QueryResult> _query(
    String sql, {
    Map<String, String> params = const {},
    bool inSession = false,
    int maxRows = 1 << 30,
  }) async {
    final queryId = const Uuid().v4();
    final client = _newClient();
    if (inSession) {
      _runningQueryId = queryId;
      _runningClient = client;
    }
    final watch = Stopwatch()..start();
    try {
      final request =
          http.Request(
              'POST',
              _uri({
                'query_id': queryId,
                if (inSession) ...{
                  'session_id': _sessionId,
                  'session_timeout': '3600',
                },
                for (final e in params.entries) 'param_${e.key}': e.value,
              }),
            )
            ..headers.addAll(_headers)
            ..body = sql;
      final response = await client
          .send(request)
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw DriverException(
              'Timed out connecting to ${config.host}:${config.port}',
            ),
          );
      if (response.statusCode != 200) {
        throw parseClickHouseError(
          await response.stream.bytesToString(),
          status: response.statusCode,
        );
      }

      final parser = ClickHouseRowsParser(maxRows: maxRows);
      final lines = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      await for (final line in lines) {
        if (!parser.add(line)) {
          // Row limit reached: drop the connection and stop the query.
          if (inSession) unawaited(_kill(queryId));
          break;
        }
      }
      return QueryResult(
        columns: parser.columns,
        rows: parser.rows,
        affectedRows: _writtenRows(response.headers['x-clickhouse-summary']),
        elapsed: watch.elapsed,
        truncated: parser.truncated,
      );
    } on SocketException catch (e) {
      throw DriverException(
        'Cannot reach ${config.host}:${config.port} — '
        '${e.osError?.message ?? e.message}',
      );
    } on HandshakeException catch (e) {
      throw DriverException('TLS handshake failed: ${e.message}');
    } on http.ClientException catch (e) {
      if (inSession && _runningQueryId == null) {
        // Closed by [cancel].
        throw const DriverException('Query cancelled', code: 'CANCELLED');
      }
      throw DriverException(e.message);
    } finally {
      client.close();
      if (inSession && _runningQueryId == queryId) {
        _runningQueryId = null;
        _runningClient = null;
      }
    }
  }

  static int _writtenRows(String? summary) {
    if (summary == null) return 0;
    try {
      final json = jsonDecode(summary) as Map<String, dynamic>;
      return int.tryParse('${json['written_rows'] ?? 0}') ?? 0;
    } on FormatException {
      return 0;
    }
  }

  Future<void> _kill(String queryId) async {
    try {
      await _query(
        'KILL QUERY WHERE query_id = {id:String} ASYNC',
        params: {'id': queryId},
      );
    } on DriverException {
      // Best effort: the query may already have finished.
    }
  }

  @override
  Future<QueryResult> execute(String sql, {int maxRows = 10000}) {
    if (!_connected) throw const DriverException('Not connected');
    return _query(sql, inSession: true, maxRows: maxRows);
  }

  /// ClickHouse has no multi-statement transactions: statements run in
  /// order and stop at the first failure.
  @override
  Future<void> executeAll(List<String> statements) async {
    for (final sql in statements) {
      await execute(sql);
    }
  }

  @override
  Future<void> cancel() async {
    final queryId = _runningQueryId;
    if (queryId == null) return;
    _runningQueryId = null;
    _runningClient?.close();
    await _kill(queryId);
  }

  List<List<Object?>> _rows(QueryResult r) => r.rows;

  @override
  Future<List<String>> listSchemas() async => [
    for (final row in _rows(
      await _query(
        'SELECT name FROM system.databases '
        "WHERE name NOT IN ('INFORMATION_SCHEMA', 'information_schema') "
        'ORDER BY name',
      ),
    ))
      row[0] as String,
  ];

  @override
  Future<List<DbObject>> listObjects(String schema) async => [
    for (final row in _rows(
      await _query(
        'SELECT name, engine FROM system.tables '
        'WHERE database = {db:String} ORDER BY name',
        params: {'db': schema},
      ),
    ))
      DbObject(
        schema: schema,
        name: row[0] as String,
        kind: switch (row[1] as String) {
          'View' || 'LiveView' || 'WindowView' => DbObjectKind.view,
          'MaterializedView' => DbObjectKind.materializedView,
          _ => DbObjectKind.table,
        },
      ),
  ];

  @override
  Future<List<ColumnInfo>> listColumns(String schema, String object) async => [
    for (final row in _rows(
      await _query(
        'SELECT name, type, default_kind, default_expression, '
        'is_in_primary_key, comment FROM system.columns '
        'WHERE database = {db:String} AND table = {t:String} '
        'ORDER BY position',
        params: {'db': schema, 't': object},
      ),
    ))
      ColumnInfo(
        name: row[0] as String,
        dataType: row[1] as String,
        nullable: (row[1] as String).startsWith('Nullable('),
        defaultValue: (row[2] as String).isEmpty ? null : '${row[2]} ${row[3]}',
        isPrimaryKey: '${row[4]}' == '1',
        comment: (row[5] as String).isEmpty ? null : row[5] as String,
      ),
  ];

  /// The sorting key (ClickHouse's primary index) plus data-skipping
  /// indexes.
  @override
  Future<List<IndexInfo>> listIndexes(String schema, String object) async {
    final params = {'db': schema, 't': object};
    final keys = await _query(
      'SELECT sorting_key, primary_key FROM system.tables '
      'WHERE database = {db:String} AND name = {t:String}',
      params: params,
    );
    final skipping = await _query(
      'SELECT name, expr, type_full, granularity '
      'FROM system.data_skipping_indices '
      'WHERE database = {db:String} AND table = {t:String} ORDER BY name',
      params: params,
    );
    return [
      for (final row in keys.rows)
        if ((row[0] as String).isNotEmpty)
          IndexInfo(
            name: 'sorting key',
            definition:
                'ORDER BY (${row[0]})'
                '${(row[1] as String).isNotEmpty && row[1] != row[0] ? ' PRIMARY KEY (${row[1]})' : ''}',
            isUnique: false,
            isPrimary: true,
          ),
      for (final row in skipping.rows)
        IndexInfo(
          name: row[0] as String,
          definition:
              'INDEX ${row[0]} ${row[1]} TYPE ${row[2]} GRANULARITY ${row[3]}',
          isUnique: false,
          isPrimary: false,
        ),
    ];
  }

  @override
  Future<List<ConstraintInfo>> listConstraints(String s, String o) async =>
      const [];

  @override
  Future<List<TriggerInfo>> listTriggers(String s, String o) async => const [];

  @override
  Future<List<PartitionInfo>> listPartitions(String s, String o) async =>
      const [];

  @override
  Future<List<RoutineInfo>> listRoutines(String schema) async => const [];

  @override
  Future<String> routineDefinition(RoutineInfo routine) =>
      throw UnsupportedError('ClickHouse has no stored routines');

  @override
  Future<String> ddl(String schema, String object) async {
    final result = await _query(
      'SHOW CREATE TABLE ${dialect.qualifiedName(schema, object)}',
    );
    final text = result.rows.firstOrNull?.firstOrNull as String? ?? '';
    return text.trimRight().endsWith(';') ? text : '$text;';
  }
}

/// Parses `JSONCompactEachRowWithNamesAndTypes` output line by line: a row
/// of names, a row of types, then one JSON array per row.
class ClickHouseRowsParser {
  ClickHouseRowsParser({required this.maxRows});

  final int maxRows;
  List<String>? _names;
  List<ResultColumn> columns = const [];
  final rows = <List<Object?>>[];
  bool truncated = false;

  /// Consumes a line; false once the row limit is exceeded (stop reading).
  /// Throws [DriverException] when the server reports an error mid-stream.
  bool add(String line) {
    if (line.isEmpty) return true;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      // ClickHouse appends a plain-text exception if a query fails after
      // results started streaming.
      throw parseClickHouseError(line);
    }
    if (decoded is! List) throw parseClickHouseError(line);

    if (_names == null) {
      _names = [for (final n in decoded) '$n'];
      return true;
    }
    if (columns.isEmpty && _names!.isNotEmpty) {
      columns = [
        for (final (i, name) in _names!.indexed)
          ResultColumn(
            name: name,
            dataType: i < decoded.length ? '${decoded[i]}' : '',
          ),
      ];
      return true;
    }
    if (rows.length >= maxRows) {
      truncated = true;
      return false;
    }
    rows.add(decoded);
    return true;
  }
}

/// Turns a ClickHouse error body such as
/// `Code: 60. DB::Exception: Table default.x does not exist. (UNKNOWN_TABLE)
/// (version 24.3.1.1)` into a [DriverException] with the numeric code.
DriverException parseClickHouseError(String body, {int? status}) {
  final text = body.trim();
  final match = RegExp(
    // The version suffix nests parentheses: "(version 24.3 (official build))".
    r'Code:\s*(\d+)\.\s*(?:DB::Exception:\s*)?(.*?)(?:\s*\(version .*\))?\s*$',
    dotAll: true,
  ).firstMatch(text);
  if (match == null) {
    return DriverException(
      text.isEmpty ? 'HTTP error ${status ?? ''}'.trim() : text,
    );
  }
  return DriverException(match.group(2)!.trim(), code: match.group(1));
}
