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
  foreignTable('Foreign table'),
  sequence('Sequence');

  const DbObjectKind(this.label);

  final String label;

  bool get isTable => this == table || this == partitionedTable;
}

class IndexInfo {
  const IndexInfo({
    required this.name,
    required this.definition,
    required this.isUnique,
    required this.isPrimary,
    this.size,
  });

  final String name;

  /// Full `CREATE INDEX` statement.
  final String definition;
  final bool isUnique;
  final bool isPrimary;

  /// Human-readable on-disk size, e.g. "16 kB".
  final String? size;
}

enum ConstraintKind {
  primaryKey('Primary key'),
  unique('Unique'),
  check('Check'),
  foreignKey('Foreign key'),
  exclusion('Exclusion');

  const ConstraintKind(this.label);

  final String label;
}

class ConstraintInfo {
  const ConstraintInfo({
    required this.name,
    required this.kind,
    required this.definition,
    this.referencedTable,
  });

  final String name;
  final ConstraintKind kind;

  /// Constraint body, e.g. `PRIMARY KEY (id)` or `CHECK (qty > 0)`.
  final String definition;

  /// For foreign keys, the referenced table (schema-qualified if needed).
  final String? referencedTable;
}

class TriggerInfo {
  const TriggerInfo({
    required this.name,
    required this.definition,
    required this.enabled,
  });

  final String name;

  /// Full `CREATE TRIGGER` statement.
  final String definition;
  final bool enabled;
}

class PartitionInfo {
  const PartitionInfo({required this.object, required this.bound});

  /// The partition itself; may be partitioned again (sub-partitions).
  final DbObject object;

  /// Partition bound, e.g. `FOR VALUES FROM ('2024-01-01') TO ('2024-04-01')`.
  final String bound;
}

enum RoutineKind { function, procedure }

class RoutineInfo {
  const RoutineInfo({
    required this.id,
    required this.name,
    required this.arguments,
    required this.kind,
    this.returnType,
  });

  /// Engine-specific identifier used to fetch the definition.
  final int id;
  final String name;
  final String arguments;
  final RoutineKind kind;
  final String? returnType;
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
    this.comment,
  });

  final String name;
  final String dataType;
  final bool nullable;
  final bool isPrimaryKey;
  final String? defaultValue;
  final String? comment;
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
  Future<List<IndexInfo>> listIndexes(String schema, String object);

  /// All constraints including foreign keys.
  Future<List<ConstraintInfo>> listConstraints(String schema, String object);
  Future<List<TriggerInfo>> listTriggers(String schema, String object);
  Future<List<PartitionInfo>> listPartitions(String schema, String object);
  Future<List<RoutineInfo>> listRoutines(String schema);

  /// Full `CREATE` statement for a routine from [listRoutines].
  Future<String> routineDefinition(RoutineInfo routine);

  /// `CREATE` statement(s) for a table, view, materialized view or sequence,
  /// including its comments, indexes and triggers.
  Future<String> ddl(String schema, String object);

  /// Runs a single statement. At most [maxRows] rows are kept; when the limit
  /// is hit the statement is cancelled on the server and the result is
  /// marked [QueryResult.truncated].
  Future<QueryResult> execute(String sql, {int maxRows = 10000});

  /// Runs [statements] in one transaction: either all of them take effect
  /// or, if any fails, none do. Used for schema changes.
  Future<void> executeAll(List<String> statements);

  /// Cancels the statement currently running in [execute], if any.
  Future<void> cancel();
}
