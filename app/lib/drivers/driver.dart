/// Engine-agnostic driver interfaces and shared models.
///
/// Engines come in families with different models: relational engines
/// implement [SqlDriver], document stores [DocumentDriver] and key-value
/// stores [KeyValueDriver]. The UI picks views by [DatabaseEngine.family].
library;

import 'dart:typed_data';

import 'sql_dialect.dart';

/// How an engine models data; decides which views and drivers apply.
enum EngineFamily {
  relational('SQL'),
  document('Document'),
  keyValue('Key-value');

  const EngineFamily(this.label);

  final String label;
}

/// Every supported engine. Drivers are pure Dart and built in, so all of
/// them are available without a download.
enum DatabaseEngine {
  postgres(
    'PostgreSQL',
    EngineFamily.relational,
    defaultPort: 5432,
    defaultDatabase: 'postgres',
    defaultUsername: 'postgres',
  ),
  mysql(
    'MySQL',
    EngineFamily.relational,
    defaultPort: 3306,
    defaultDatabase: '',
    defaultUsername: 'root',
    databaseOptional: true,
  ),
  clickhouse(
    'ClickHouse',
    EngineFamily.relational,
    defaultPort: 8123,
    defaultTlsPort: 8443,
    defaultDatabase: 'default',
    defaultUsername: 'default',
  ),
  mongodb(
    'MongoDB',
    EngineFamily.document,
    defaultPort: 27017,
    defaultDatabase: 'admin',
    usernameOptional: true,
  ),
  redis(
    'Redis',
    EngineFamily.keyValue,
    defaultPort: 6379,
    defaultDatabase: '0',
    usernameOptional: true,
  );

  const DatabaseEngine(
    this.label,
    this.family, {
    required this.defaultPort,
    this._defaultTlsPort,
    required this.defaultDatabase,
    this.defaultUsername = '',
    this.usernameOptional = false,
    this.databaseOptional = false,
  });

  final String label;
  final EngineFamily family;
  final int defaultPort;
  final int? _defaultTlsPort;
  final String defaultDatabase;
  final String defaultUsername;

  /// Mongo and Redis often run without authentication.
  final bool usernameOptional;

  /// MySQL can connect without choosing a database.
  final bool databaseOptional;

  /// Some engines use a different port with TLS (ClickHouse HTTPS: 8443).
  int portFor({required bool tls}) =>
      tls ? (_defaultTlsPort ?? defaultPort) : defaultPort;
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
    this.options = const {},
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

  /// Engine-specific settings that have no column of their own, e.g. for
  /// MongoDB: `srv`, `authSource`, `params`. Never holds secrets.
  final Map<String, String> options;

  String get displayAddress {
    final user = username.isEmpty ? '' : '$username@';
    return switch (engine) {
      DatabaseEngine.redis => '$user$host:$port/db$database',
      DatabaseEngine.mongodb when options['srv'] == 'true' =>
        '$user$host/$database',
      _ => '$user$host:$port${database.isEmpty ? '' : '/$database'}',
    };
  }

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
    Map<String, String>? options,
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
      options: options ?? this.options,
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
    this.schema = '',
  });

  /// Engine-specific identifier used to fetch the definition.
  final int id;
  final String name;
  final String arguments;
  final RoutineKind kind;
  final String? returnType;

  /// Set by engines that look routines up by name (MySQL).
  final String schema;
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

/// Memory budget for the rows of one [SqlDriver.execute] result, as
/// estimated by [estimateValueSize]. The row cap alone doesn't bound memory:
/// 10,000 rows of multi-megabyte text, bytea or JSON would take gigabytes.
/// Values are never cut short (editing, export and the value viewer need
/// them whole); instead fetching stops once the kept rows exceed this.
const maxResultBytes = 64 * 1024 * 1024;

/// Rough in-memory size of a decoded value in bytes: text and binary by
/// length, collections recursively, anything else a small fixed cost. Cheap
/// enough to run on every fetched row.
int estimateValueSize(Object? value) => switch (value) {
  null => 8,
  // Dart strings take one or two bytes per code unit; count two.
  String() => 16 + value.length * 2,
  TypedData() => 16 + value.lengthInBytes,
  Map() => value.entries.fold(
    32,
    (sum, e) =>
        sum + 16 + estimateValueSize(e.key) + estimateValueSize(e.value),
  ),
  Iterable() => value.fold(16, (sum, v) => sum + 8 + estimateValueSize(v)),
  _ => 16,
};

/// Decides which fetched rows a result keeps: at most [maxRows] rows and,
/// once their estimated size reaches [maxBytes], no more. A row that is
/// offered while the budget is [full] means the result is truncated.
class RowBudget {
  RowBudget({required this.maxRows, this.maxBytes = maxResultBytes});

  final int maxRows;
  final int maxBytes;
  int _rows = 0;
  int _bytes = 0;

  /// Estimated size of the rows kept so far.
  int get bytes => _bytes;

  bool get full => _rows >= maxRows || _bytes >= maxBytes;

  /// Counts [row] as kept.
  void add(List<Object?> row) {
    _rows++;
    _bytes += estimateValueSize(row);
  }
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

/// Connection lifecycle shared by every engine. Each family adds its own
/// operations: [SqlDriver], [DocumentDriver] or [KeyValueDriver].
abstract class DatabaseDriver {
  ConnectionConfig get config;

  Future<void> connect(String? password);
  Future<void> close();
  Future<Duration> ping();

  /// Cancels the operation currently running, if any.
  Future<void> cancel();
}

/// Optional parts of the relational model. The navigator and inspector show
/// only what an engine supports.
enum SqlFeature {
  constraints,
  foreignKeys,
  indexes,
  triggers,
  partitions,
  routines,
  sequences,

  /// Add/edit/drop columns, constraints, indexes and triggers from the
  /// inspector. The dialogs generate PostgreSQL syntax.
  schemaEditing,

  /// Editing table rows in the Data tab (needs primary keys and UPDATE).
  rowEditing,

  /// [SqlDriver.executeAll] is atomic.
  transactions,
}

abstract class SqlDriver extends DatabaseDriver {
  Set<SqlFeature> get features;

  /// Quoting and literals for SQL the app generates.
  SqlDialect get dialect;

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

  /// Runs a single statement. At most [maxRows] rows are kept, and no more
  /// than about [maxResultBytes] of values (see [RowBudget]); when either
  /// limit is hit the statement is cancelled on the server and the result
  /// is marked [QueryResult.truncated]. The cancel has finished by the time
  /// the returned future completes, so it can't hit the next statement.
  Future<QueryResult> execute(String sql, {int maxRows = 10000});

  /// Runs [statements] in one transaction: either all of them take effect
  /// or, if any fails, none do. Without [SqlFeature.transactions] they run
  /// in order and stop at the first failure.
  Future<void> executeAll(List<String> statements);
}
