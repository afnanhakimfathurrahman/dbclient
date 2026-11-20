/// DBeaver-style filter for the Data tab: the user types a WHERE condition
/// (optionally followed by ORDER BY) and the table is re-queried with it.
library;

import '../drivers/driver.dart';
import '../drivers/sql_dialect.dart';

final _orderBy = RegExp(r'\border\s+by\b', caseSensitive: false);
final _leadingWhere = RegExp(r'^where\b\s*', caseSensitive: false);
final _trailingSemicolons = RegExp(r'[\s;]+$');

/// [filter] without a leading WHERE, trailing semicolons or surrounding
/// whitespace; empty means no filter.
String normalizeFilter(String filter) => filter
    .trim()
    .replaceFirst(_leadingWhere, '')
    .replaceFirst(_trailingSemicolons, '');

/// The Data tab query: `SELECT *` from the table, filtered by [filter] (a
/// WHERE condition, an `ORDER BY …` clause, or a condition followed by
/// one), at most [limit] rows.
String buildSelectSql(
  SqlDialect dialect,
  String schema,
  String table, {
  String filter = '',
  required int limit,
}) {
  final clause = normalizeFilter(filter);
  final buffer = StringBuffer(
    'SELECT * FROM ${dialect.qualifiedName(schema, table)}',
  );
  if (clause.isNotEmpty) {
    buffer.write(clause.startsWith(_orderBy) ? ' ' : ' WHERE ');
    // On its own line so a trailing "-- comment" can't swallow the LIMIT.
    buffer.write('$clause\n');
  } else {
    buffer.write(' ');
  }
  buffer.write('LIMIT $limit');
  return buffer.toString();
}

/// `column = value` (or `<>`) for "Filter by value"; NULL uses IS [NOT] NULL.
String valueCondition(
  SqlDialect dialect,
  ResultColumn column,
  Object? value, {
  bool exclude = false,
}) {
  final name = dialect.quoteIdent(column.name);
  if (value == null) return '$name IS ${exclude ? 'NOT ' : ''}NULL';
  final literal = dialect.typedLiteral(
    dialect.editText(value, column.dataType),
    column.dataType,
  );
  return '$name ${exclude ? '<>' : '='} $literal';
}

/// [filter] narrowed by [condition] (AND), keeping any ORDER BY at the end.
String addCondition(String filter, String condition) {
  final clause = normalizeFilter(filter);
  final order = _orderBy.allMatches(clause).lastOrNull;
  final where = (order == null ? clause : clause.substring(0, order.start))
      .trim();
  final orderBy = order == null ? '' : ' ${clause.substring(order.start)}';
  if (where.isEmpty) return '$condition$orderBy';
  return '($where) AND $condition$orderBy';
}
