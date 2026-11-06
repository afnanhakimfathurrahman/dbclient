/// Schema-aware SQL completion, free of Flutter so it can be tested.
///
/// Given the editor text and cursor, finds the word being typed and what
/// fits there: tables after FROM/JOIN, columns after `alias.`, columns of
/// the statement's tables elsewhere, plus keywords and functions.
library;

import '../../drivers/driver.dart';
import '../../drivers/sql_dialect.dart';
import '../../drivers/sql_splitter.dart';

enum SqlSuggestionKind { column, table, view, schema, keyword, function }

class SqlSuggestion {
  const SqlSuggestion({
    required this.label,
    required this.kind,
    String? insert,
    this.detail,
  }) : insert = insert ?? label;

  /// Shown and matched against what was typed.
  final String label;

  /// Inserted in place of the typed word (quoted identifiers, keyword case).
  final String insert;
  final SqlSuggestionKind kind;

  /// Type of a column, table of a column, kind of an object…
  final String? detail;
}

class SqlCompletion {
  const SqlCompletion({required this.input, required this.suggestions});

  /// The partial word before the cursor, replaced on accept.
  final String input;
  final List<SqlSuggestion> suggestions;
}

/// Metadata the completer can use. Lookups return null while not loaded
/// (they may start loading), so completion never waits on the network.
abstract class SqlCatalog {
  /// Schema used for unqualified names (search_path / current database).
  String? get defaultSchema;
  List<String>? schemas();
  List<DbObject>? objects(String schema);
  List<ColumnInfo>? columns(String schema, String table);
}

/// A table referenced in the statement, e.g. `public.users u`.
class TableRef {
  const TableRef({this.schema, required this.name, this.alias});

  final String? schema;
  final String name;
  final String? alias;
}

const _identChars = r'[A-Za-z0-9_$]';
final _identPart = RegExp(_identChars);

/// Keywords after which a table name is expected.
const _tableKeywords = {
  'FROM',
  'JOIN',
  'UPDATE',
  'INTO',
  'TABLE',
  'DESCRIBE',
  'DESC',
  'TRUNCATE',
};

/// Words that end a table reference instead of being its alias.
const _notAliases = {
  'WHERE', 'JOIN', 'INNER', 'LEFT', 'RIGHT', 'FULL', 'CROSS', 'OUTER', //
  'NATURAL', 'ON', 'USING', 'GROUP', 'ORDER', 'HAVING', 'LIMIT', 'OFFSET',
  'UNION', 'EXCEPT', 'INTERSECT', 'SET', 'VALUES', 'RETURNING', 'WINDOW',
  'FETCH', 'FOR', 'LATERAL', 'AS', 'SELECT', 'DEFAULT', 'FINAL', 'SAMPLE',
  'PREWHERE', 'FORMAT', 'SETTINGS', 'PARTITION', 'STRAIGHT_JOIN',
};

const _keywords = [
  'SELECT', 'FROM', 'WHERE', 'AND', 'OR', 'NOT', 'NULL', 'IS NULL', //
  'IS NOT NULL', 'IN', 'LIKE', 'BETWEEN', 'EXISTS', 'AS', 'DISTINCT',
  'JOIN', 'INNER JOIN', 'LEFT JOIN', 'RIGHT JOIN', 'FULL JOIN',
  'CROSS JOIN', 'ON', 'USING', 'GROUP BY', 'ORDER BY', 'HAVING', 'LIMIT',
  'OFFSET', 'ASC', 'DESC', 'UNION', 'UNION ALL', 'WITH', 'CASE', 'WHEN',
  'THEN', 'ELSE', 'END', 'INSERT INTO', 'VALUES', 'UPDATE', 'SET',
  'DELETE FROM', 'CREATE TABLE', 'CREATE INDEX', 'CREATE VIEW',
  'ALTER TABLE', 'DROP TABLE', 'TRUNCATE', 'BEGIN', 'COMMIT', 'ROLLBACK',
  'EXPLAIN', 'TRUE', 'FALSE', 'DEFAULT', 'PRIMARY KEY', 'FOREIGN KEY',
  'REFERENCES', 'UNIQUE', 'CHECK', 'INDEX', 'COLUMN', 'ADD', 'RENAME',
];

/// Engine-specific additions.
const _dialectKeywords = {
  PostgresDialect: ['ILIKE', 'RETURNING', 'ON CONFLICT', 'LATERAL'],
  MySqlDialect: [
    'SHOW TABLES',
    'SHOW CREATE TABLE',
    'DESCRIBE',
    'REPLACE INTO',
  ],
  ClickHouseDialect: ['PREWHERE', 'FINAL', 'SAMPLE', 'ARRAY JOIN', 'FORMAT'],
};

const _functions = [
  'COUNT', 'SUM', 'AVG', 'MIN', 'MAX', 'COALESCE', 'NULLIF', 'CAST', //
  'LOWER', 'UPPER', 'LENGTH', 'TRIM', 'SUBSTRING', 'CONCAT', 'REPLACE',
  'ROUND', 'ABS', 'NOW', 'CURRENT_DATE', 'CURRENT_TIMESTAMP', 'EXTRACT',
  'ROW_NUMBER', 'RANK', 'LAG', 'LEAD',
];

/// Completion at [cursor] in [text], or null when nothing fits (inside a
/// string or comment, or no partial word and no qualifier).
SqlCompletion? completeSql({
  required String text,
  required int cursor,
  required SqlCatalog catalog,
  required SqlDialect dialect,
  int limit = 60,
}) {
  if (cursor < 0 || cursor > text.length) return null;

  // Work within the statement around the cursor.
  // Raw offsets (the statement's text is trimmed); the cursor may sit just
  // past the statement while typing at its end.
  final statement = statementAt(text, cursor);
  final start = (statement?.start ?? 0).clamp(0, cursor);
  final end = statement == null
      ? text.length
      : (statement.end > cursor ? statement.end : cursor).clamp(0, text.length);
  final stmt = text.substring(start, end);
  final at = (cursor - start).clamp(0, stmt.length);
  final before = stmt.substring(0, at);
  if (_insideStringOrComment(before)) return null;

  // The partial word, and a qualifier if it follows a dot.
  var i = before.length;
  while (i > 0 && _identPart.hasMatch(before[i - 1])) {
    i--;
  }
  final input = before.substring(i);
  String? qualifier;
  if (i > 0 && before[i - 1] == '.') {
    qualifier = _identifierBefore(before, i - 1);
  }
  if (input.isEmpty && qualifier == null) return null;

  final refs = parseTableRefs(stmt);
  final suggestions = <SqlSuggestion>[];
  String quote(String name) => _completionName(name, dialect);

  void addColumns(TableRef ref, {bool withTable = false}) {
    final schema = ref.schema ?? catalog.defaultSchema;
    if (schema == null) return;
    for (final column
        in catalog.columns(schema, ref.name) ?? const <ColumnInfo>[]) {
      suggestions.add(
        SqlSuggestion(
          label: column.name,
          insert: quote(column.name),
          kind: SqlSuggestionKind.column,
          detail: withTable
              ? '${ref.alias ?? ref.name} · ${column.dataType}'
              : column.dataType,
        ),
      );
    }
  }

  void addTables(String? schema) {
    final target = schema ?? catalog.defaultSchema;
    if (target == null) return;
    for (final object in catalog.objects(target) ?? const <DbObject>[]) {
      suggestions.add(
        SqlSuggestion(
          label: object.name,
          insert: quote(object.name),
          kind:
              object.kind == DbObjectKind.view ||
                  object.kind == DbObjectKind.materializedView
              ? SqlSuggestionKind.view
              : SqlSuggestionKind.table,
          detail: schema == null
              ? object.kind.label
              : '$target · ${object.kind.label}',
        ),
      );
    }
  }

  void addSchemas() {
    for (final schema in catalog.schemas() ?? const <String>[]) {
      suggestions.add(
        SqlSuggestion(
          label: schema,
          insert: quote(schema),
          kind: SqlSuggestionKind.schema,
          detail: 'schema',
        ),
      );
    }
  }

  void addKeywords() {
    // Match the user's case: "sel" completes to "select".
    final lower = input.isNotEmpty && input == input.toLowerCase();
    String cased(String word) => lower ? word.toLowerCase() : word;
    for (final keyword in [
      ..._keywords,
      ...?_dialectKeywords[dialect.runtimeType],
    ]) {
      suggestions.add(
        SqlSuggestion(
          label: keyword,
          insert: cased(keyword),
          kind: SqlSuggestionKind.keyword,
        ),
      );
    }
    for (final function in _functions) {
      suggestions.add(
        SqlSuggestion(
          label: function,
          insert: '${cased(function)}(',
          kind: SqlSuggestionKind.function,
          detail: 'function',
        ),
      );
    }
  }

  if (qualifier != null) {
    // alias.col / table.col, else schema.table.
    // An alias wins, then a schema (in "FROM sales.|" the half-typed
    // "sales" also parses as a table), then a table name.
    final q = qualifier.toLowerCase();
    final byAlias = refs.where((r) => r.alias?.toLowerCase() == q).firstOrNull;
    final schema = catalog
        .schemas()
        ?.where((s) => s.toLowerCase() == q)
        .firstOrNull;
    final byName = refs.where((r) => r.name.toLowerCase() == q).firstOrNull;
    if (byAlias != null) {
      addColumns(byAlias);
    } else if (schema != null) {
      addTables(schema);
    } else if (byName != null) {
      addColumns(byName);
    } else {
      // A table used without an alias in the statement but not yet parsed,
      // e.g. while typing "SELECT users." before FROM.
      final schema = catalog.defaultSchema;
      final object = schema == null
          ? null
          : catalog
                .objects(schema)
                ?.where((o) => o.name.toLowerCase() == q)
                .firstOrNull;
      if (object != null) addColumns(TableRef(name: object.name));
    }
  } else if (_tableKeywords.contains(
    _previousKeyword(before.substring(0, i)),
  )) {
    addTables(null);
    addSchemas();
  } else {
    for (final ref in refs) {
      addColumns(ref, withTable: refs.length > 1);
    }
    addKeywords();
    addTables(null);
  }

  final needle = input.toLowerCase();
  final matched = <SqlSuggestion>[];
  final seen = <String>{};
  for (final s in suggestions) {
    final label = s.label.toLowerCase();
    if (!label.startsWith(needle) || label == needle) continue;
    if (seen.add('${s.kind.name}:${s.label}')) matched.add(s);
  }
  // Columns and tables before keywords, then shorter (closer) names first;
  // the sort is stable, so catalog order breaks ties.
  int rank(SqlSuggestion s) => switch (s.kind) {
    SqlSuggestionKind.column => 0,
    SqlSuggestionKind.table || SqlSuggestionKind.view => 1,
    SqlSuggestionKind.schema => 2,
    SqlSuggestionKind.keyword => 3,
    SqlSuggestionKind.function => 4,
  };
  matched.sort((a, b) => rank(a).compareTo(rank(b)));
  if (matched.isEmpty) return null;
  return SqlCompletion(input: input, suggestions: matched.take(limit).toList());
}

/// Tables referenced after FROM/JOIN/UPDATE/INTO (and comma lists after
/// FROM), with their aliases.
List<TableRef> parseTableRefs(String statement) {
  final text = _stripStringsAndComments(statement);
  final name = r'(?:"[^"]+"|`[^`]+`|[A-Za-z_][A-Za-z0-9_$]*)';
  // An alias can't be a clause keyword: in "FROM t WHERE", WHERE isn't t's
  // alias.
  final notAlias = '(?!(?:${_notAliases.join('|')})\\b)';
  final ref = RegExp(
    '($name)(?:\\s*\\.\\s*($name))?(?:\\s+(?:AS\\s+)?$notAlias($name))?',
    caseSensitive: false,
  );
  final refs = <TableRef>[];
  final starts = RegExp(
    r'\b(FROM|JOIN|UPDATE|INTO|TABLE)\s+',
    caseSensitive: false,
  );
  for (final start in starts.allMatches(text)) {
    var pos = start.end;
    final isFrom = start.group(1)!.toUpperCase() == 'FROM';
    while (true) {
      final m = ref.matchAsPrefix(text, pos);
      if (m == null) break;
      final first = _unquote(m.group(1)!);
      final second = m.group(2) == null ? null : _unquote(m.group(2)!);
      final alias = m.group(3) == null ? null : _unquote(m.group(3)!);
      final matchEnd = m.end;
      if (!_notAliases.contains(first.toUpperCase()) &&
          first.toUpperCase() != 'SELECT') {
        refs.add(
          TableRef(
            schema: second == null ? null : first,
            name: second ?? first,
            alias: alias,
          ),
        );
      }
      // FROM a x, b y: continue after a comma.
      final rest = RegExp(r'\s*,\s*').matchAsPrefix(text, matchEnd);
      if (!isFrom || rest == null) break;
      pos = rest.end;
    }
  }
  return refs;
}

String _unquote(String name) =>
    (name.startsWith('"') && name.endsWith('"')) ||
        (name.startsWith('`') && name.endsWith('`'))
    ? name.substring(1, name.length - 1)
    : name;

/// The identifier ending just before [end] (a dot), unquoted.
String? _identifierBefore(String text, int end) {
  if (end > 0 && (text[end - 1] == '"' || text[end - 1] == '`')) {
    final quote = text[end - 1];
    final open = text.lastIndexOf(quote, end - 2);
    return open < 0 ? null : text.substring(open + 1, end - 1);
  }
  var i = end;
  while (i > 0 && _identPart.hasMatch(text[i - 1])) {
    i--;
  }
  return i == end ? null : text.substring(i, end);
}

/// The last keyword-like word before the partial word, uppercased; commas
/// after FROM keep the table context ("FROM a, b").
String? _previousKeyword(String text) {
  final words = RegExp(r'[A-Za-z_]+|,')
      .allMatches(_stripStringsAndComments(text))
      .toList();
  if (words.isEmpty) return null;
  final last = words.last.group(0)!;
  if (last == ',') {
    // In "FROM a x, |" the clause keyword before the list decides.
    for (final w in words.reversed) {
      final word = w.group(0)!.toUpperCase();
      if (_tableKeywords.contains(word)) return word;
      if (_notAliases.contains(word) || word == 'SELECT') return word;
    }
    return null;
  }
  return last.toUpperCase();
}

/// Whether [text] ends inside a string literal, quoted identifier or
/// comment.
bool _insideStringOrComment(String text) {
  String? open; // ', ", `, --, /*
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    switch (open) {
      case null:
        if (c == "'" || c == '"' || c == '`') {
          open = c;
        } else if (text.startsWith('--', i)) {
          open = '--';
        } else if (text.startsWith('/*', i)) {
          open = '/*';
          i++;
        }
      case '--':
        if (c == '\n') open = null;
      case '/*':
        if (text.startsWith('*/', i)) {
          open = null;
          i++;
        }
      default:
        if (c == open) open = null;
    }
  }
  // A quoted identifier being typed ("Us) is also not completed.
  return open != null;
}

/// [text] with string contents and comments blanked out, so keywords inside
/// them aren't mistaken for clauses. Quoted identifiers are kept.
String _stripStringsAndComments(String text) {
  final out = StringBuffer();
  var i = 0;
  while (i < text.length) {
    if (text[i] == "'") {
      final close = text.indexOf("'", i + 1);
      final stop = close < 0 ? text.length : close + 1;
      out.write(' ' * (stop - i));
      i = stop;
    } else if (text.startsWith('--', i)) {
      final close = text.indexOf('\n', i);
      final stop = close < 0 ? text.length : close;
      out.write(' ' * (stop - i));
      i = stop;
    } else if (text.startsWith('/*', i)) {
      final close = text.indexOf('*/', i + 2);
      final stop = close < 0 ? text.length : close + 2;
      out.write(' ' * (stop - i));
      i = stop;
    } else {
      out.write(text[i]);
      i++;
    }
  }
  return out.toString();
}

/// How a name is inserted: bare when the engine allows it, else quoted.
String _completionName(String name, SqlDialect dialect) {
  final plain = RegExp(r'^[A-Za-z_][A-Za-z0-9_$]*$').hasMatch(name);
  return switch (dialect) {
    // MySQL names are case-insensitive for columns; quote only when needed.
    MySqlDialect() when plain && !_mysqlReserved.contains(name.toUpperCase()) =>
      name,
    _ => dialect.quoteIdent(name),
  };
}

const _mysqlReserved = {
  'ADD', 'ALL', 'ALTER', 'AND', 'AS', 'ASC', 'BETWEEN', 'BY', 'CASE', //
  'CHECK', 'COLUMN', 'CONSTRAINT', 'CREATE', 'CROSS', 'DATABASE', 'DEFAULT',
  'DELETE', 'DESC', 'DISTINCT', 'DROP', 'ELSE', 'EXISTS', 'FALSE', 'FOR',
  'FOREIGN', 'FROM', 'GROUP', 'HAVING', 'IN', 'INDEX', 'INNER', 'INSERT',
  'INTERVAL', 'INTO', 'IS', 'JOIN', 'KEY', 'KEYS', 'LEFT', 'LIKE', 'LIMIT',
  'MATCH', 'NOT', 'NULL', 'ON', 'OR', 'ORDER', 'OUTER', 'PRIMARY', 'RANGE',
  'READ', 'REFERENCES', 'RIGHT', 'SELECT', 'SET', 'SHOW', 'TABLE', 'THEN',
  'TO', 'TRUE', 'UNION', 'UNIQUE', 'UPDATE', 'USE', 'USING', 'VALUES',
  'WHEN', 'WHERE', 'WITH', 'RANK', 'ROW', 'ROWS', 'GROUPS', 'WINDOW',
};
