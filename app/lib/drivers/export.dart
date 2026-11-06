import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'driver.dart';
import 'postgres/postgres_sql.dart' show pgArrayLiteral;
import 'sql_dialect.dart';
import 'value_format.dart';

enum ExportFormat {
  csv('CSV', 'Comma-separated values (.csv)', 'csv', 'text/csv'),
  json('JSON', 'Structured JSON objects (.json)', 'json', 'application/json'),
  markdown(
    'Markdown',
    'GitHub Flavored Markdown table (.md)',
    'md',
    'text/markdown',
  ),
  tsv(
    'TSV',
    'Tab-separated for spreadsheets (.tsv)',
    'tsv',
    'text/tab-separated-values',
  ),
  sql('SQL', 'INSERT statements (.sql)', 'sql', 'application/sql');

  const ExportFormat(
    this.label,
    this.description,
    this.extension,
    this.mimeType,
  );
  final String label;
  final String description;
  final String extension;
  final String mimeType;
}

/// Serializes a [QueryResult] to text. Unlike the grid, values are never
/// truncated (bytea is written in full).
class ResultExporter {
  /// [tableName] is the INSERT target for [ExportFormat.sql], written as-is,
  /// so pass it already quoted (see [SqlDialect.qualifiedName]). [dialect]
  /// decides how SQL INSERTs quote names and values.
  static String export(
    QueryResult result,
    ExportFormat format, {
    String tableName = 'records',
    SqlDialect dialect = postgresDialect,
  }) {
    return switch (format) {
      ExportFormat.csv => toCsv(result),
      ExportFormat.json => toJson(result),
      ExportFormat.markdown => toMarkdown(result),
      ExportFormat.tsv => toTsv(result),
      ExportFormat.sql => toSql(result, tableName: tableName, dialect: dialect),
    };
  }

  /// [export] on a background isolate, so thousands of rows don't stall the
  /// UI. Falls back to this isolate if a value can't be sent.
  static Future<String> exportInBackground(
    QueryResult result,
    ExportFormat format, {
    String tableName = 'records',
    SqlDialect dialect = postgresDialect,
  }) => _inBackground(
    () => export(result, format, tableName: tableName, dialect: dialect),
  );

  /// Like [exportInBackground], as UTF-8 bytes for writing to a file; the
  /// encoding happens in the isolate too.
  static Future<Uint8List> exportBytesInBackground(
    QueryResult result,
    ExportFormat format, {
    String tableName = 'records',
    SqlDialect dialect = postgresDialect,
  }) => _inBackground(
    () => utf8.encode(
      export(result, format, tableName: tableName, dialect: dialect),
    ),
  );

  static Future<T> _inBackground<T>(T Function() work) async {
    try {
      return await Isolate.run(work);
    } on ArgumentError {
      // An unsendable value (the message is checked before the isolate
      // starts); do the work here instead.
      return work();
    }
  }

  static String toCsv(QueryResult result) {
    return [
      result.columns.map((c) => _escapeCsv(c.name)).join(','),
      for (final row in result.rows)
        row.map((v) => _escapeCsv(_text(v) ?? '')).join(','),
    ].join('\n');
  }

  static String _escapeCsv(String value) {
    if (value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static String toJson(QueryResult result, {bool pretty = true}) {
    final names = _uniqueNames(result.columns);
    final list = [
      for (final row in result.rows)
        {for (var i = 0; i < names.length; i++) names[i]: _jsonValue(row[i])},
    ];
    final encoder = pretty
        ? const JsonEncoder.withIndent('  ')
        : const JsonEncoder();
    return encoder.convert(list);
  }

  /// Converts a value to something [JsonEncoder] accepts, keeping numbers,
  /// booleans and JSON structures native.
  static Object? _jsonValue(Object? value) => switch (value) {
    null || bool() || int() || String() => value,
    double() => value.isFinite ? value : value.toString(),
    Map() => {
      for (final e in value.entries) e.key.toString(): _jsonValue(e.value),
    },
    Uint8List() => _text(value),
    List() => [for (final v in value) _jsonValue(v)],
    _ => _text(value),
  };

  /// Column names made unique (`id`, `id_2`…), since JSON object keys can't
  /// repeat and `SELECT a.id, b.id` is common.
  static List<String> _uniqueNames(List<ResultColumn> columns) {
    final seen = <String>{};
    return [
      for (final c in columns)
        () {
          var name = c.name;
          for (var n = 2; !seen.add(name); n++) {
            name = '${c.name}_$n';
          }
          return name;
        }(),
    ];
  }

  static String toMarkdown(QueryResult result) {
    if (result.columns.isEmpty) return '';
    String cell(String text) => text
        .replaceAll('|', '\\|')
        .replaceAll('\r\n', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ');
    return [
      '| ${result.columns.map((c) => cell(c.name)).join(' | ')} |',
      '| ${result.columns.map((_) => '---').join(' | ')} |',
      for (final row in result.rows)
        '| ${row.map((v) => cell(_text(v) ?? 'NULL')).join(' | ')} |',
    ].join('\n');
  }

  static String toTsv(QueryResult result) {
    String cell(String text) => text.replaceAll(RegExp(r'[\t\r\n]+'), ' ');
    return [
      result.columns.map((c) => cell(c.name)).join('\t'),
      for (final row in result.rows)
        row.map((v) => cell(_text(v) ?? '')).join('\t'),
    ].join('\n');
  }

  static String toSql(
    QueryResult result, {
    String tableName = 'records',
    SqlDialect dialect = postgresDialect,
  }) {
    final columns = result.columns
        .map((c) => dialect.quoteIdent(c.name))
        .join(', ');
    return [
      for (final row in result.rows)
        'INSERT INTO $tableName ($columns) VALUES '
            '(${[for (final (i, v) in row.indexed) _sqlLiteral(v, result.columns[i].dataType, dialect)].join(', ')});',
    ].join('\n');
  }

  static String _sqlLiteral(
    Object? value,
    String dataType,
    SqlDialect dialect,
  ) => switch (value) {
    null => 'NULL',
    bool() => value ? 'TRUE' : 'FALSE',
    int() => '$value',
    double() => value.isFinite ? '$value' : dialect.quoteLiteral('$value'),
    // Postgres arrays decode to lists; JSON arrays are lists too, so only
    // array-typed columns get the '{…}' array literal.
    List() when dataType.endsWith('[]') => dialect.quoteLiteral(
      pgArrayLiteral(value),
    ),
    _ => dialect.quoteLiteral(_text(value)!),
  };

  /// Full, untruncated text of a value; null for SQL NULL.
  static String? _text(Object? value) =>
      formatValue(value, maxBytes: value is Uint8List ? value.length : 64);
}
