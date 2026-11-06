/// SQL for creating databases, schemas and tables from the navigator, and
/// editor templates for objects that are easier to write by hand (views,
/// functions, sequences, indexes). Spelled per engine through [SqlDialect].
library;

import 'sql_dialect.dart';

/// One column of a table being created.
class NewColumn {
  const NewColumn({
    required this.name,
    required this.type,
    this.nullable = true,
    this.primaryKey = false,
    this.defaultValue,
  });

  final String name;
  final String type;
  final bool nullable;
  final bool primaryKey;

  /// Default expression, written as-is; null or empty for none.
  final String? defaultValue;
}

String buildCreateDatabaseSql(SqlDialect dialect, String name) =>
    'CREATE DATABASE ${dialect.quoteIdent(name)};';

String buildCreateSchemaSql(SqlDialect dialect, String name) =>
    'CREATE SCHEMA ${dialect.quoteIdent(name)};';

/// `CREATE TABLE` for [columns] (blank names or types are skipped); empty
/// when there is nothing to create yet. ClickHouse tables get a MergeTree
/// engine ordered by the primary key, and nullable columns `Nullable(T)`.
String buildCreateTableSql(
  SqlDialect dialect, {
  required String schema,
  required String table,
  required List<NewColumn> columns,
}) {
  final valid = [
    for (final c in columns)
      if (c.name.trim().isNotEmpty && c.type.trim().isNotEmpty) c,
  ];
  if (table.trim().isEmpty || valid.isEmpty) return '';
  final clickHouse = dialect is ClickHouseDialect;
  final keys = [
    for (final c in valid)
      if (c.primaryKey) dialect.quoteIdent(c.name.trim()),
  ];

  String definition(NewColumn c) {
    final type = c.type.trim();
    final notNull = c.primaryKey || !c.nullable;
    final buffer = StringBuffer(dialect.quoteIdent(c.name.trim()))..write(' ');
    if (clickHouse) {
      buffer.write(
        notNull || type.startsWith('Nullable(') ? type : 'Nullable($type)',
      );
    } else {
      buffer.write(type);
      if (notNull) buffer.write(' NOT NULL');
    }
    if (c.defaultValue?.trim() case final d? when d.isNotEmpty) {
      buffer.write(' DEFAULT $d');
    }
    return buffer.toString();
  }

  final lines = [
    for (final c in valid) definition(c),
    if (keys.isNotEmpty && !clickHouse) 'PRIMARY KEY (${keys.join(', ')})',
  ];
  final buffer = StringBuffer(
    'CREATE TABLE ${dialect.qualifiedName(schema, table.trim())} (\n'
    '  ${lines.join(',\n  ')}\n'
    ')',
  );
  if (clickHouse) {
    buffer.write(
      '\nENGINE = MergeTree\n'
      'ORDER BY ${keys.isEmpty ? 'tuple()' : '(${keys.join(', ')})'}',
    );
  }
  buffer.write(';');
  return buffer.toString();
}

/// Common column types offered while creating a table.
List<String> columnTypeSuggestions(SqlDialect dialect) => switch (dialect) {
  ClickHouseDialect() => const [
    'UInt8',
    'UInt32',
    'UInt64',
    'Int32',
    'Int64',
    'Float64',
    'Decimal(18, 2)',
    'String',
    'FixedString(16)',
    'UUID',
    'Bool',
    'Date',
    'DateTime',
    'DateTime64(3)',
    'LowCardinality(String)',
    'Array(String)',
    'Map(String, String)',
  ],
  MySqlDialect() => const [
    'INT',
    'BIGINT',
    'SMALLINT',
    'TINYINT(1)',
    'DECIMAL(10,2)',
    'DOUBLE',
    'VARCHAR(255)',
    'CHAR(36)',
    'TEXT',
    'LONGTEXT',
    'BOOLEAN',
    'DATE',
    'DATETIME',
    'TIMESTAMP',
    'JSON',
    'BLOB',
  ],
  _ => const [
    'integer',
    'bigint',
    'smallint',
    'serial',
    'bigserial',
    'text',
    'varchar(255)',
    'boolean',
    'numeric(10,2)',
    'double precision',
    'timestamp with time zone',
    'timestamp',
    'date',
    'jsonb',
    'uuid',
    'bytea',
  ],
};

/// Type of the `id` column a new table starts with.
String defaultKeyType(SqlDialect dialect) => switch (dialect) {
  ClickHouseDialect() => 'UInt64',
  MySqlDialect() => 'BIGINT',
  _ => 'bigint',
};

String createViewTemplate(SqlDialect dialect, String schema) =>
    'CREATE VIEW ${dialect.qualifiedName(schema, 'new_view')} AS\n'
    'SELECT *\n'
    'FROM ${dialect.qualifiedName(schema, 'table_name')};';

/// A minimal function to edit: plpgsql on PostgreSQL; on MySQL a single
/// RETURN body, which needs no DELIMITER change.
String createFunctionTemplate(SqlDialect dialect, String schema) {
  final name = dialect.qualifiedName(schema, 'new_function');
  if (dialect is MySqlDialect) {
    return 'CREATE FUNCTION $name(value INT)\n'
        'RETURNS INT\n'
        'DETERMINISTIC\n'
        'RETURN value * 2;';
  }
  return 'CREATE OR REPLACE FUNCTION $name(value integer)\n'
      'RETURNS integer\n'
      'LANGUAGE plpgsql\n'
      r'AS $$'
      '\nBEGIN\n'
      '  RETURN value * 2;\n'
      'END;\n'
      r'$$;';
}

String createSequenceTemplate(SqlDialect dialect, String schema) =>
    'CREATE SEQUENCE ${dialect.qualifiedName(schema, 'new_sequence')}\n'
    '  START WITH 1\n'
    '  INCREMENT BY 1;';

/// An index on [column] (or a placeholder) of a table: `CREATE INDEX` on
/// MySQL, a data-skipping index on ClickHouse.
String createIndexTemplate(
  SqlDialect dialect, {
  required String schema,
  required String table,
  String? column,
}) {
  final target = dialect.qualifiedName(schema, table);
  final name = dialect.quoteIdent('${table}_${column ?? 'column'}_idx');
  final col = dialect.quoteIdent(column ?? 'column_name');
  if (dialect is ClickHouseDialect) {
    return 'ALTER TABLE $target\n'
        '  ADD INDEX $name $col TYPE minmax GRANULARITY 1;';
  }
  return 'CREATE INDEX $name ON $target ($col);';
}
