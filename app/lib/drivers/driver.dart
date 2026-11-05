/// Engine-agnostic driver interface and shared models.
///
/// The UI only talks to [DatabaseDriver]; each engine (Postgres today,
/// MySQL/SQLite/ClickHouse/Mongo later) provides its own implementation.
library;

enum DatabaseEngine {
  postgres('PostgreSQL', 5432);

  const DatabaseEngine(this.label, this.defaultPort);

  final String label;
  final int defaultPort;
}

enum TlsMode {
  disable('Disable'),
  require('Require (no verification)'),
  verifyFull('Verify full');

  const TlsMode(this.label);

  final String label;
}

/// Saved connection settings. The password is never part of this object;
/// it lives in secure storage and is passed separately when connecting.
class ConnectionConfig {
  const ConnectionConfig({
    required this.id,
    required this.name,
    required this.engine,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.tlsMode,
    required this.color,
    required this.savePassword,
  });

  final String id;
  final String name;
  final DatabaseEngine engine;
  final String host;
  final int port;
  final String database;
  final String username;
  final TlsMode tlsMode;

  /// ARGB color used to tag the connection in the UI.
  final int color;
  final bool savePassword;

  String get displayAddress => '$username@$host:$port/$database';

  ConnectionConfig copyWith({
    String? name,
    DatabaseEngine? engine,
    String? host,
    int? port,
    String? database,
    String? username,
    TlsMode? tlsMode,
    int? color,
    bool? savePassword,
  }) {
    return ConnectionConfig(
      id: id,
      name: name ?? this.name,
      engine: engine ?? this.engine,
      host: host ?? this.host,
      port: port ?? this.port,
      database: database ?? this.database,
      username: username ?? this.username,
      tlsMode: tlsMode ?? this.tlsMode,
      color: color ?? this.color,
      savePassword: savePassword ?? this.savePassword,
    );
  }
}

enum DbObjectKind {
  table('Table'),
  partitionedTable('Partitioned table'),
  view('View'),
  materializedView('Materialized view'),
  foreignTable('Foreign table');

  const DbObjectKind(this.label);

  final String label;
}

class DbObject {
  const DbObject({
    required this.schema,
    required this.name,
    required this.kind,
  });

  final String schema;
  final String name;
  final DbObjectKind kind;
}

class ColumnInfo {
  const ColumnInfo({
    required this.name,
    required this.dataType,
    required this.nullable,
    required this.isPrimaryKey,
    this.defaultValue,
  });

  final String name;
  final String dataType;
  final bool nullable;
  final bool isPrimaryKey;
  final String? defaultValue;
}

class ResultColumn {
  const ResultColumn({required this.name, required this.dataType});

  final String name;
  final String dataType;
}

class QueryResult {
  const QueryResult({
    required this.columns,
    required this.rows,
    required this.affectedRows,
    required this.elapsed,
    required this.truncated,
  });

  final List<ResultColumn> columns;
  final List<List<Object?>> rows;
  final int affectedRows;
  final Duration elapsed;

  /// True when the statement returned more rows than the fetch limit and the
  /// rest were skipped.
  final bool truncated;

  bool get hasResultSet => columns.isNotEmpty;
}

class DriverException implements Exception {
  const DriverException(
    this.message, {
    this.code,
    this.detail,
    this.hint,
    this.position,
  });

  final String message;
  final String? code;
  final String? detail;
  final String? hint;

  /// 1-based character position of the error in the statement, if known.
  final int? position;

  @override
  String toString() {
    final buffer = StringBuffer(message);
    if (detail != null) buffer.write('\nDetail: $detail');
    if (hint != null) buffer.write('\nHint: $hint');
    return buffer.toString();
  }
}

abstract class DatabaseDriver {
  ConnectionConfig get config;

  Future<void> connect(String? password);
  Future<void> close();
  Future<Duration> ping();

  Future<List<String>> listSchemas();
  Future<List<DbObject>> listObjects(String schema);
  Future<List<ColumnInfo>> listColumns(String schema, String object);

  /// Runs a single statement. At most [maxRows] rows are kept; when the limit
  /// is hit the statement is cancelled on the server and the result is
  /// marked [QueryResult.truncated].
  Future<QueryResult> execute(String sql, {int maxRows = 10000});

  /// Cancels the statement currently running in [execute], if any.
  Future<void> cancel();
}
