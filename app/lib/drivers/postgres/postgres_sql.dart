/// PostgreSQL SQL text helpers: identifier/literal quoting and DDL builders.
///
/// Postgres has no built-in "show create table", so DDL is assembled from
/// catalog metadata here. Kept free of I/O so it can be unit-tested.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../driver.dart';
import '../value_format.dart';

/// Quotes an identifier unless it is a plain lowercase name that isn't a
/// reserved word.
String quoteIdent(String name) {
  if (RegExp(r'^[a-z_][a-z0-9_$]*$').hasMatch(name) &&
      !_reservedWords.contains(name)) {
    return name;
  }
  return '"${name.replaceAll('"', '""')}"';
}

String qualifiedName(String schema, String name) =>
    '${quoteIdent(schema)}.${quoteIdent(name)}';

String quoteLiteral(String value) => "'${value.replaceAll("'", "''")}'";

/// Text a user edits for a decoded value: what Postgres accepts as input for
/// a column of [dataType] (arrays as `{…}`, JSON compact, bytea in full).
/// Null for SQL NULL.
String? pgEditText(Object? value, String dataType) => switch (value) {
  null => null,
  // Before List: bytea decodes to Uint8List, which is a List.
  Uint8List() => formatValue(value, maxBytes: value.length),
  List() when dataType.endsWith('[]') => pgArrayLiteral(value),
  Map() || List() => jsonEncode(value),
  _ => formatValue(value),
};

/// Postgres array input syntax, e.g. `{1,"a b",NULL}`.
String pgArrayLiteral(List<Object?> values) {
  final items = values.map((v) {
    if (v == null) return 'NULL';
    if (v is List) return pgArrayLiteral(v);
    final text = pgEditText(v, '')!;
    return '"${text.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
  });
  return '{${items.join(',')}}';
}

/// A typed SQL literal from input text: `'42'::integer`, or NULL. Postgres
/// parses the text as it would user input, so this works for any type.
String pgTypedLiteral(String? text, String dataType) {
  if (text == null) return 'NULL';
  final literal = quoteLiteral(text);
  return dataType.isEmpty ? literal : '$literal::$dataType';
}

class PgColumnDdl {
  const PgColumnDdl({
    required this.name,
    required this.type,
    required this.notNull,
    this.defaultExpr,
    this.identity = '',
    this.generated = '',
    this.comment,
  });

  final String name;
  final String type;
  final bool notNull;

  /// Default expression; for generated columns, the generation expression.
  final String? defaultExpr;

  /// `pg_attribute.attidentity`: '' (none), 'a' (always), 'd' (by default).
  final String identity;

  /// `pg_attribute.attgenerated`: '' (none), 's' (stored), 'v' (virtual).
  final String generated;
  final String? comment;
}

String buildPgTableDdl({
  required String schema,
  required String name,
  required List<PgColumnDdl> columns,
  List<ConstraintInfo> constraints = const [],
  List<IndexInfo> indexes = const [],
  List<TriggerInfo> triggers = const [],
  String? partitionKey,
  String? partitionOf,
  String? partitionBound,
  String? foreignServer,
  String? comment,
}) {
  final table = qualifiedName(schema, name);
  final out = StringBuffer();

  if (partitionOf != null) {
    // Columns and most constraints are inherited from the parent.
    out.write('CREATE TABLE $table PARTITION OF $partitionOf\n');
    out.write('    ${partitionBound ?? 'DEFAULT'}');
    if (partitionKey != null) out.write('\n    PARTITION BY $partitionKey');
    out.write(';\n');
  } else {
    out.write(foreignServer != null ? 'CREATE FOREIGN TABLE' : 'CREATE TABLE');
    out.write(' $table (\n');
    final lines = [
      for (final c in columns) '    ${_columnDefinition(c)}',
      for (final c in constraints)
        '    CONSTRAINT ${quoteIdent(c.name)} ${c.definition}',
    ];
    out.write(lines.join(',\n'));
    out.write('\n)');
    if (partitionKey != null) out.write('\nPARTITION BY $partitionKey');
    if (foreignServer != null) {
      out.write('\nSERVER ${quoteIdent(foreignServer)}');
    }
    out.write(';\n');
  }

  _writeComments(out, 'TABLE', table, comment, columns);
  // A partition's indexes are created from the parent's.
  if (partitionOf == null) {
    _writeStatements(out, [for (final i in indexes) i.definition]);
  }
  _writeStatements(out, [for (final t in triggers) t.definition]);
  return out.toString();
}

String buildPgViewDdl({
  required String schema,
  required String name,
  required String definition,
  bool materialized = false,
  List<IndexInfo> indexes = const [],
  String? comment,
}) {
  final view = qualifiedName(schema, name);
  final body = definition.trim();
  final out = StringBuffer()
    ..write(
      materialized
          ? 'CREATE MATERIALIZED VIEW $view AS\n'
          : 'CREATE OR REPLACE VIEW $view AS\n',
    )
    ..write(body.endsWith(';') ? body : '$body;')
    ..write('\n');
  _writeComments(
    out,
    materialized ? 'MATERIALIZED VIEW' : 'VIEW',
    view,
    comment,
    const [],
  );
  _writeStatements(out, [for (final i in indexes) i.definition]);
  return out.toString();
}

String buildPgSequenceDdl({
  required String schema,
  required String name,
  required String type,
  required int start,
  required int increment,
  required int min,
  required int max,
  required int cache,
  required bool cycle,
}) {
  return 'CREATE SEQUENCE ${qualifiedName(schema, name)}\n'
      '    AS $type\n'
      '    START WITH $start\n'
      '    INCREMENT BY $increment\n'
      '    MINVALUE $min\n'
      '    MAXVALUE $max\n'
      '    CACHE $cache\n'
      '    ${cycle ? 'CYCLE' : 'NO CYCLE'};\n';
}

/// Generates an `ALTER TABLE ... ADD COLUMN` statement.
String buildAddColumnSql({
  required String schema,
  required String table,
  required String name,
  required String type,
  bool notNull = false,
  String? defaultExpr,
  bool isPrimaryKey = false,
  String? comment,
}) {
  final target = qualifiedName(schema, table);
  final col = quoteIdent(name);
  final parts = ['ALTER TABLE $target ADD COLUMN $col $type'];
  if (defaultExpr != null && defaultExpr.trim().isNotEmpty) {
    parts.add('DEFAULT ${defaultExpr.trim()}');
  }
  if (notNull) {
    parts.add('NOT NULL');
  }
  if (isPrimaryKey) {
    parts.add('PRIMARY KEY');
  }
  final statements = ['${parts.join(' ')};'];
  if (comment != null && comment.trim().isNotEmpty) {
    statements.add(
      'COMMENT ON COLUMN $target.$col IS ${quoteLiteral(comment.trim())};',
    );
  }
  return statements.join('\n');
}

/// Generates an `ALTER TABLE ... DROP COLUMN` statement.
String buildDropColumnSql({
  required String schema,
  required String table,
  required String name,
  bool cascade = false,
}) {
  final target = qualifiedName(schema, table);
  final col = quoteIdent(name);
  return 'ALTER TABLE $target DROP COLUMN $col${cascade ? ' CASCADE' : ''};';
}

/// Generates `ALTER TABLE` statements to modify a column's name, type, nullability,
/// default expression, or comment.
String buildAlterColumnSql({
  required String schema,
  required String table,
  required String oldName,
  String? newName,
  String? oldType,
  String? newType,
  bool? oldNotNull,
  bool? newNotNull,
  String? oldDefault,
  String? newDefault,
  String? comment,

  /// Conversion expression for a type change Postgres can't cast implicitly,
  /// e.g. `amount::numeric`.
  String? using,
}) {
  final target = qualifiedName(schema, table);
  final statements = <String>[];
  var currentName = oldName;

  if (newName != null && newName.isNotEmpty && newName != oldName) {
    statements.add(
      'ALTER TABLE $target RENAME COLUMN ${quoteIdent(oldName)} TO ${quoteIdent(newName)};',
    );
    currentName = newName;
  }

  final col = quoteIdent(currentName);

  if (newType != null &&
      newType.isNotEmpty &&
      (oldType == null || newType != oldType)) {
    final usingClause = (using != null && using.trim().isNotEmpty)
        ? ' USING ${using.trim()}'
        : '';
    statements.add(
      'ALTER TABLE $target ALTER COLUMN $col TYPE $newType$usingClause;',
    );
  }

  if (newNotNull != null && (oldNotNull == null || newNotNull != oldNotNull)) {
    statements.add(
      'ALTER TABLE $target ALTER COLUMN $col ${newNotNull ? 'SET NOT NULL' : 'DROP NOT NULL'};',
    );
  }

  if (newDefault != oldDefault) {
    if (newDefault != null && newDefault.trim().isNotEmpty) {
      statements.add(
        'ALTER TABLE $target ALTER COLUMN $col SET DEFAULT ${newDefault.trim()};',
      );
    } else if (oldDefault != null && oldDefault.trim().isNotEmpty) {
      statements.add('ALTER TABLE $target ALTER COLUMN $col DROP DEFAULT;');
    }
  }

  if (comment != null) {
    statements.add(
      comment.trim().isEmpty
          ? 'COMMENT ON COLUMN $target.$col IS NULL;'
          : 'COMMENT ON COLUMN $target.$col IS ${quoteLiteral(comment.trim())};',
    );
  }

  return statements.join('\n');
}

/// Generates an `ALTER TABLE ... ADD CONSTRAINT` statement.
String buildAddConstraintSql({
  required String schema,
  required String table,
  String? name,
  required ConstraintKind kind,
  List<String> columns = const [],
  String? expression,
  String? referencedSchema,
  String? referencedTable,
  List<String> referencedColumns = const [],
  String? onDelete,
  String? onUpdate,
}) {
  final target = qualifiedName(schema, table);
  final nameClause = (name != null && name.trim().isNotEmpty)
      ? 'CONSTRAINT ${quoteIdent(name.trim())} '
      : '';

  final String body;
  switch (kind) {
    case ConstraintKind.primaryKey:
      final cols = columns.map(quoteIdent).join(', ');
      body = 'PRIMARY KEY ($cols)';
    case ConstraintKind.unique:
      final cols = columns.map(quoteIdent).join(', ');
      body = 'UNIQUE ($cols)';
    case ConstraintKind.check:
      final expr = expression?.trim() ?? '';
      body = 'CHECK ($expr)';
    case ConstraintKind.foreignKey:
      final cols = columns.map(quoteIdent).join(', ');
      final refTarget = qualifiedName(
        referencedSchema != null && referencedSchema.isNotEmpty
            ? referencedSchema
            : schema,
        referencedTable ?? '',
      );
      // Without columns, the referenced table's primary key is used.
      final refCols = referencedColumns.isEmpty
          ? ''
          : ' (${referencedColumns.map(quoteIdent).join(', ')})';
      final onDelClause =
          (onDelete != null &&
              onDelete.isNotEmpty &&
              onDelete.toUpperCase() != 'NO ACTION')
          ? ' ON DELETE $onDelete'
          : '';
      final onUpdClause =
          (onUpdate != null &&
              onUpdate.isNotEmpty &&
              onUpdate.toUpperCase() != 'NO ACTION')
          ? ' ON UPDATE $onUpdate'
          : '';
      body =
          'FOREIGN KEY ($cols) REFERENCES $refTarget$refCols$onDelClause$onUpdClause';
    case ConstraintKind.exclusion:
      body = 'EXCLUDE (${expression ?? ''})';
  }

  return 'ALTER TABLE $target ADD $nameClause$body;';
}

/// Generates an `ALTER TABLE ... DROP CONSTRAINT` statement.
String buildDropConstraintSql({
  required String schema,
  required String table,
  required String name,
  bool cascade = false,
}) {
  final target = qualifiedName(schema, table);
  return 'ALTER TABLE $target DROP CONSTRAINT ${quoteIdent(name)}${cascade ? ' CASCADE' : ''};';
}

/// Generates statement(s) to alter/rename/replace a constraint.
String buildAlterConstraintSql({
  required String schema,
  required String table,
  required String oldName,
  String? newName,
  String? newDefinition,
}) {
  final target = qualifiedName(schema, table);
  final targetName = newName ?? oldName;

  if (newDefinition != null && newDefinition.trim().isNotEmpty) {
    return 'ALTER TABLE $target DROP CONSTRAINT ${quoteIdent(oldName)},\n'
        '    ADD CONSTRAINT ${quoteIdent(targetName)} ${newDefinition.trim()};';
  }

  if (newName != null && newName.isNotEmpty && newName != oldName) {
    return 'ALTER TABLE $target RENAME CONSTRAINT ${quoteIdent(oldName)} TO ${quoteIdent(newName)};';
  }

  return '';
}

/// Generates a `CREATE INDEX` statement.
String buildCreateIndexSql({
  required String schema,
  required String table,
  required String name,
  required List<String> columns,
  String method = 'btree',
  bool isUnique = false,
  String? predicate,
}) {
  final target = qualifiedName(schema, table);
  final idx = quoteIdent(name);
  final cols = columns.map(quoteIdent).join(', ');
  final uniqueClause = isUnique ? 'UNIQUE ' : '';
  final methodClause = method.isNotEmpty && method.toLowerCase() != 'btree'
      ? ' USING $method'
      : '';
  final whereClause = (predicate != null && predicate.trim().isNotEmpty)
      ? ' WHERE ${predicate.trim()}'
      : '';
  return 'CREATE ${uniqueClause}INDEX $idx ON $target$methodClause ($cols)$whereClause;';
}

/// Generates a `DROP INDEX` statement.
String buildDropIndexSql({
  required String schema,
  required String name,
  bool cascade = false,
}) {
  final idx = qualifiedName(schema, name);
  return 'DROP INDEX $idx${cascade ? ' CASCADE' : ''};';
}

/// Generates an `ALTER INDEX ... RENAME TO` statement.
String buildAlterIndexSql({
  required String schema,
  required String oldName,
  required String newName,
}) {
  final idx = qualifiedName(schema, oldName);
  return 'ALTER INDEX $idx RENAME TO ${quoteIdent(newName)};';
}

/// Generates a `CREATE TRIGGER` statement.
String buildCreateTriggerSql({
  required String schema,
  required String table,
  required String name,
  required String timing,
  required List<String> events,
  String forEach = 'ROW',
  required String functionName,
  String? condition,
}) {
  final target = qualifiedName(schema, table);
  final trg = quoteIdent(name);
  final eventStr = events.join(' OR ');
  final whenClause = (condition != null && condition.trim().isNotEmpty)
      ? ' WHEN (${condition.trim()})'
      : '';
  final funcCall = functionName.trim().endsWith('()')
      ? functionName.trim()
      : '${functionName.trim()}()';
  return 'CREATE TRIGGER $trg\n'
      '    $timing $eventStr\n'
      '    ON $target\n'
      '    FOR EACH $forEach$whenClause\n'
      '    EXECUTE FUNCTION $funcCall;';
}

/// Generates a `DROP TRIGGER` statement.
String buildDropTriggerSql({
  required String schema,
  required String table,
  required String name,
  bool cascade = false,
}) {
  final target = qualifiedName(schema, table);
  final trg = quoteIdent(name);
  return 'DROP TRIGGER $trg ON $target${cascade ? ' CASCADE' : ''};';
}

/// Generates statement(s) to rename, enable or disable a trigger.
String buildAlterTriggerSql({
  required String schema,
  required String table,
  required String oldName,
  String? newName,
  bool? enabled,
}) {
  final target = qualifiedName(schema, table);
  final statements = <String>[];
  var currentName = oldName;

  if (newName != null && newName.isNotEmpty && newName != oldName) {
    statements.add(
      'ALTER TRIGGER ${quoteIdent(oldName)} ON $target RENAME TO ${quoteIdent(newName)};',
    );
    currentName = newName;
  }

  if (enabled != null) {
    statements.add(
      'ALTER TABLE $target ${enabled ? 'ENABLE' : 'DISABLE'} TRIGGER ${quoteIdent(currentName)};',
    );
  }

  return statements.join('\n');
}

String _columnDefinition(PgColumnDdl c) {
  final parts = [quoteIdent(c.name), c.type];
  if (c.identity.isNotEmpty) {
    parts.add(
      c.identity == 'a'
          ? 'GENERATED ALWAYS AS IDENTITY'
          : 'GENERATED BY DEFAULT AS IDENTITY',
    );
  } else if (c.generated.isNotEmpty && c.defaultExpr != null) {
    parts.add(
      'GENERATED ALWAYS AS (${c.defaultExpr}) '
      '${c.generated == 's' ? 'STORED' : 'VIRTUAL'}',
    );
  } else {
    if (c.defaultExpr != null) parts.add('DEFAULT ${c.defaultExpr}');
    if (c.notNull) parts.add('NOT NULL');
  }
  return parts.join(' ');
}

void _writeComments(
  StringBuffer out,
  String objectType,
  String qualified,
  String? comment,
  List<PgColumnDdl> columns,
) {
  final lines = [
    if (comment != null)
      'COMMENT ON $objectType $qualified IS ${quoteLiteral(comment)};',
    for (final c in columns)
      if (c.comment != null)
        'COMMENT ON COLUMN $qualified.${quoteIdent(c.name)} '
            'IS ${quoteLiteral(c.comment!)};',
  ];
  if (lines.isNotEmpty) out.write('\n${lines.join('\n')}\n');
}

void _writeStatements(StringBuffer out, List<String> statements) {
  if (statements.isEmpty) return;
  out.write('\n');
  for (final s in statements) {
    final trimmed = s.trim();
    out.write(trimmed.endsWith(';') ? '$trimmed\n' : '$trimmed;\n');
  }
}

/// Reserved and type/function-name keywords that can't be used as bare
/// identifiers (PostgreSQL appendix C).
const _reservedWords = {
  'all', 'analyse', 'analyze', 'and', 'any', 'array', 'as', 'asc', //
  'asymmetric', 'authorization', 'binary', 'both', 'case', 'cast', 'check',
  'collate', 'collation', 'column', 'concurrently', 'constraint', 'create',
  'cross', 'current_catalog', 'current_date', 'current_role',
  'current_schema', 'current_time', 'current_timestamp', 'current_user',
  'default', 'deferrable', 'desc', 'distinct', 'do', 'else', 'end',
  'except', 'false', 'fetch', 'for', 'foreign', 'freeze', 'from', 'full',
  'grant', 'group', 'having', 'ilike', 'in', 'initially', 'inner',
  'intersect', 'into', 'is', 'isnull', 'join', 'lateral', 'leading', 'left',
  'like', 'limit', 'localtime', 'localtimestamp', 'natural', 'not',
  'notnull', 'null', 'offset', 'on', 'only', 'or', 'order', 'outer',
  'overlaps', 'placing', 'primary', 'references', 'returning', 'right',
  'select', 'session_user', 'similar', 'some', 'symmetric', 'system_user',
  'table', 'tablesample', 'then', 'to', 'trailing', 'true', 'union',
  'unique', 'user', 'using', 'variadic', 'verbose', 'when', 'where',
  'window', 'with',
};
