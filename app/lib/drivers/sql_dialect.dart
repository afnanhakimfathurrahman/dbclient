/// How an engine spells identifiers and values in generated SQL (data
/// preview, row edits, "Query in SQL editor").
library;

import 'dart:typed_data';

import 'postgres/postgres_sql.dart' as pg;
import 'value_format.dart';

abstract class SqlDialect {
  const SqlDialect();

  String quoteIdent(String name);

  String qualifiedName(String schema, String name) =>
      '${quoteIdent(schema)}.${quoteIdent(name)}';

  String quoteLiteral(String text);

  /// A literal for a column of [dataType] from input text; null is NULL.
  String typedLiteral(String? text, String dataType);

  /// Text a user edits for a loaded value; null for NULL.
  String? editText(Object? value, String dataType);
}

/// PostgreSQL: "identifiers" and typed literals ('42'::integer).
class PostgresDialect extends SqlDialect {
  const PostgresDialect();

  @override
  String quoteIdent(String name) => pg.quoteIdent(name);

  @override
  String quoteLiteral(String text) => pg.quoteLiteral(text);

  @override
  String typedLiteral(String? text, String dataType) =>
      pg.pgTypedLiteral(text, dataType);

  @override
  String? editText(Object? value, String dataType) =>
      pg.pgEditText(value, dataType);
}

/// ClickHouse: double-quoted identifiers like PostgreSQL, but string
/// literals treat backslash as an escape.
class ClickHouseDialect extends PostgresDialect {
  const ClickHouseDialect();

  @override
  String quoteLiteral(String text) =>
      "'${text.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";

  @override
  String typedLiteral(String? text, String dataType) =>
      text == null ? 'NULL' : quoteLiteral(text);
}

/// MySQL and MariaDB: `backtick` identifiers; string literals escape
/// backslashes (the default sql_mode); the server converts strings to the
/// column's type, so no casts are needed.
class MySqlDialect extends SqlDialect {
  const MySqlDialect();

  @override
  String quoteIdent(String name) => '`${name.replaceAll('`', '``')}`';

  @override
  String quoteLiteral(String text) =>
      "'${text.replaceAll(r'\', r'\\').replaceAll("'", "''")}'";

  /// Values arrive as text and MySQL converts strings to the column type.
  @override
  String typedLiteral(String? text, String dataType) =>
      text == null ? 'NULL' : quoteLiteral(text);

  @override
  String? editText(Object? value, String dataType) => switch (value) {
    null => null,
    Uint8List() => formatValue(value, maxBytes: value.length),
    // MySQL DATETIME has no zone and no "T".
    DateTime() =>
      value.toIso8601String().replaceFirst('T', ' ').replaceFirst('Z', ''),
    _ => formatValue(value),
  };
}

const postgresDialect = PostgresDialect();
