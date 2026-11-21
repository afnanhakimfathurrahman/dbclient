/// Completion for the MongoDB editor, free of Flutter so it can be tested.
///
/// Suggests collections after `db.`, collection methods after
/// `db.<collection>.`, cursor methods after `).`, operators after `$`, and
/// field names inside documents. Results use the SQL completer's types so
/// the same popup shows them.
library;

import '../editor/sql_completion.dart';

/// Names the completer can use; null while not loaded.
abstract class MongoCatalog {
  List<String>? collections();

  /// Field paths seen in [collection]'s documents (`name`, `address.city`).
  List<String>? fields(String collection);
}

const _dbMethods = [
  ('getCollection', "getCollection('')"),
  ('runCommand', 'runCommand({ })'),
  ('adminCommand', 'adminCommand({ })'),
  ('getCollectionNames', 'getCollectionNames()'),
  ('createCollection', "createCollection('')"),
  ('stats', 'stats()'),
  ('dropDatabase', 'dropDatabase()'),
];

const _collectionMethods = [
  ('find', 'find({ })'),
  ('findOne', 'findOne({ })'),
  ('aggregate', 'aggregate([ ])'),
  ('countDocuments', 'countDocuments({ })'),
  ('estimatedDocumentCount', 'estimatedDocumentCount()'),
  ('distinct', "distinct('', { })"),
  ('insertOne', 'insertOne({ })'),
  ('insertMany', 'insertMany([ ])'),
  ('updateOne', 'updateOne({ }, { \$set: { } })'),
  ('updateMany', 'updateMany({ }, { \$set: { } })'),
  ('replaceOne', 'replaceOne({ }, { })'),
  ('deleteOne', 'deleteOne({ })'),
  ('deleteMany', 'deleteMany({ })'),
  ('findOneAndUpdate', 'findOneAndUpdate({ }, { \$set: { } })'),
  ('findOneAndReplace', 'findOneAndReplace({ }, { })'),
  ('findOneAndDelete', 'findOneAndDelete({ })'),
  ('getIndexes', 'getIndexes()'),
  ('createIndex', 'createIndex({ })'),
  ('dropIndex', "dropIndex('')"),
  ('stats', 'stats()'),
  ('drop', 'drop()'),
];

const _cursorMethods = [
  ('sort', 'sort({ })'),
  ('limit', 'limit(20)'),
  ('skip', 'skip(0)'),
  ('projection', 'projection({ })'),
  ('hint', 'hint({ })'),
  ('collation', 'collation({ locale: \'en\' })'),
  ('maxTimeMS', 'maxTimeMS(5000)'),
  ('count', 'count()'),
  ('explain', 'explain()'),
  ('toArray', 'toArray()'),
];

/// Query, update, aggregation stage and expression operators.
const _operators = [
  // Query.
  r'$eq', r'$ne', r'$gt', r'$gte', r'$lt', r'$lte', r'$in', r'$nin', //
  r'$and', r'$or', r'$nor', r'$not', r'$exists', r'$type', r'$regex',
  r'$options', r'$expr', r'$elemMatch', r'$size', r'$all', r'$text',
  r'$search', r'$mod', r'$near', r'$geoWithin',
  // Update.
  r'$set', r'$unset', r'$inc', r'$mul', r'$rename', r'$setOnInsert',
  r'$push', r'$pull', r'$addToSet', r'$pop', r'$currentDate', r'$min',
  r'$max', r'$each', r'$position',
  // Stages.
  r'$match', r'$project', r'$group', r'$sort', r'$limit', r'$skip',
  r'$unwind', r'$lookup', r'$addFields', r'$count', r'$facet',
  r'$replaceRoot', r'$sample', r'$out', r'$merge', r'$bucket',
  r'$sortByCount', r'$unionWith', r'$graphLookup',
  // Expressions and accumulators.
  r'$sum', r'$avg', r'$first', r'$last', r'$concat', r'$toLower',
  r'$toUpper', r'$substr', r'$dateToString', r'$cond', r'$ifNull',
  r'$size', r'$arrayElemAt', r'$toString', r'$toInt', r'$year',
  r'$month', r'$dayOfMonth',
];

const _values = [
  ('ObjectId', "ObjectId('')"),
  ('ISODate', "ISODate('')"),
  ('NumberLong', "NumberLong('')"),
  ('NumberDecimal', "NumberDecimal('')"),
  ('true', 'true'),
  ('false', 'false'),
  ('null', 'null'),
];

final _wordChar = RegExp(r'[A-Za-z0-9_$.]');
final _collectionRef = RegExp(
  r'''db\s*\.\s*(?:getCollection\s*\(\s*['"]([^'"]+)['"]\s*\)|([A-Za-z_$][\w$]*))''',
);

/// Completion at [cursor] in [text], or null when nothing fits (inside a
/// string or comment, or nothing typed and no `.` / `$` trigger).
SqlCompletion? completeMongo({
  required String text,
  required int cursor,
  required MongoCatalog catalog,
  int limit = 60,
}) {
  if (cursor < 0 || cursor > text.length) return null;
  final before = text.substring(0, cursor);
  final context = _context(before);
  if (context == _Where.comment) return null;

  // getCollection('us|') completes inside the string.
  final inString = RegExp(
    r'''getCollection\s*\(\s*['"]([\w.$-]*)$''',
  ).firstMatch(before);
  if (context == _Where.string) {
    if (inString == null) return null;
    final input = inString.group(1)!;
    return _result(input, [
      for (final c in catalog.collections() ?? const <String>[])
        SqlSuggestion(label: c, kind: SqlSuggestionKind.table),
    ], limit);
  }

  var start = cursor;
  while (start > 0 && _wordChar.hasMatch(text[start - 1])) {
    start--;
  }
  final word = text.substring(start, cursor);
  final dot = word.lastIndexOf('.');
  // "db.us" → qualifier "db", input "us".
  final qualifier = dot < 0 ? null : word.substring(0, dot);
  final input = dot < 0 ? word : word.substring(dot + 1);

  // ").sort", or ".sort" on the next line — a method on a call's result.
  if (qualifier != null && qualifier.isEmpty) {
    final chain = text.substring(0, start);
    if (_lastCode(chain) != ')') return null;
    final afterGetCollection = RegExp(
      r'db\s*\.\s*getCollection\s*\([^()]*\)\s*$',
    ).hasMatch(chain);
    return _result(
      input,
      afterGetCollection
          ? _methods(_collectionMethods, 'collection')
          : _methods(_cursorMethods, 'cursor'),
      limit,
    );
  }

  if (qualifier != null) {
    if (qualifier == 'db') {
      return _result(input, [
        for (final c in catalog.collections() ?? const <String>[])
          SqlSuggestion(label: c, kind: SqlSuggestionKind.table),
        for (final (name, insert) in _dbMethods)
          SqlSuggestion(
            label: name,
            insert: insert,
            kind: SqlSuggestionKind.function,
            detail: 'db',
          ),
      ], limit);
    }
    if (qualifier.startsWith('db.') && !qualifier.startsWith(r'$')) {
      return _result(input, _methods(_collectionMethods, 'collection'), limit);
    }
    // A field path inside a document: "address.ci".
    if (context == _Where.key) {
      return _fieldResult(before, qualifier, input, catalog, limit);
    }
    return null;
  }

  if (input.startsWith(r'$')) {
    final collection = _currentCollection(before);
    return _result(input, [
      for (final op in _operators.toSet())
        SqlSuggestion(label: op, kind: SqlSuggestionKind.keyword),
      // "$field" references in aggregation expressions.
      if (context == _Where.value && collection != null)
        for (final f in catalog.fields(collection) ?? const <String>[])
          SqlSuggestion(
            label: '\$$f',
            kind: SqlSuggestionKind.column,
            detail: collection,
          ),
    ], limit);
  }

  if (input.isEmpty) return null;

  if (context == _Where.key) {
    return _fieldResult(before, null, input, catalog, limit);
  }
  if (context == _Where.top) {
    return _result(input, const [
      SqlSuggestion(label: 'db', kind: SqlSuggestionKind.keyword),
      SqlSuggestion(label: 'show collections', kind: SqlSuggestionKind.keyword),
      SqlSuggestion(label: 'show dbs', kind: SqlSuggestionKind.keyword),
      SqlSuggestion(label: 'use', kind: SqlSuggestionKind.keyword),
    ], limit);
  }
  return _result(input, [
    for (final (name, insert) in _values)
      SqlSuggestion(label: name, insert: insert, kind: SqlSuggestionKind.function),
  ], limit);
}

List<SqlSuggestion> _methods(List<(String, String)> methods, String detail) => [
  for (final (name, insert) in methods)
    SqlSuggestion(
      label: name,
      insert: insert,
      kind: SqlSuggestionKind.function,
      detail: detail,
    ),
];

SqlCompletion? _fieldResult(
  String before,
  String? qualifier,
  String input,
  MongoCatalog catalog,
  int limit,
) {
  final collection = _currentCollection(before);
  if (collection == null) return null;
  final prefix = qualifier == null ? '' : '$qualifier.';
  final fields = catalog.fields(collection) ?? const <String>[];
  return _result(input, [
    for (final f in fields)
      if (f.startsWith(prefix) && !f.substring(prefix.length).contains('.'))
        SqlSuggestion(
          label: f.substring(prefix.length),
          kind: SqlSuggestionKind.column,
          detail: collection,
        ),
  ], limit);
}

/// The collection of the statement being written: the last `db.x` before
/// the cursor.
String? _currentCollection(String before) {
  final match = _collectionRef.allMatches(before).lastOrNull;
  if (match == null) return null;
  final name = match.group(1) ?? match.group(2)!;
  return _dbMethods.any((m) => m.$1 == name) ? null : name;
}

/// Suggestions starting with [input] (case-insensitive), then containing
/// it; exact duplicates of what's typed are dropped.
SqlCompletion? _result(String input, List<SqlSuggestion> all, int limit) {
  final lower = input.toLowerCase();
  final prefix = <SqlSuggestion>[];
  final contains = <SqlSuggestion>[];
  final seen = <String>{};
  for (final s in all) {
    if (!seen.add(s.label)) continue;
    final label = s.label.toLowerCase();
    if (label == lower) continue;
    if (label.startsWith(lower)) {
      prefix.add(s);
    } else if (lower.isNotEmpty && label.contains(lower)) {
      contains.add(s);
    }
  }
  final suggestions = [...prefix, ...contains].take(limit).toList();
  if (suggestions.isEmpty) return null;
  return SqlCompletion(input: input, suggestions: suggestions);
}

enum _Where { top, key, value, string, comment }

/// Where the end of [before] is: in a string or comment, at a document key,
/// at a value, or at statement level.
_Where _context(String before) {
  final stack = <String>[];
  String? quote;
  var lastCode = '';
  for (var i = 0; i < before.length; i++) {
    final c = before[i];
    if (quote != null) {
      if (c == r'\') {
        i++;
      } else if (c == quote) {
        quote = null;
        lastCode = c;
      }
      continue;
    }
    if (before.startsWith('//', i)) {
      final end = before.indexOf('\n', i);
      if (end < 0) return _Where.comment;
      i = end;
      continue;
    }
    if (before.startsWith('/*', i)) {
      final end = before.indexOf('*/', i + 2);
      if (end < 0) return _Where.comment;
      i = end + 1;
      continue;
    }
    if (c == '"' || c == "'" || c == '`') {
      quote = c;
      continue;
    }
    if ('([{'.contains(c)) stack.add(c);
    if (')]}'.contains(c) && stack.isNotEmpty) stack.removeLast();
    if (c.trim().isNotEmpty) lastCode = c;
  }
  if (quote != null) return _Where.string;
  if (stack.isEmpty) return _Where.top;
  if (stack.last != '{') return _Where.value;
  // Inside { }: a key follows "{" or ",", a value follows ":".
  final word = RegExp(r'[A-Za-z0-9_$.]*$').firstMatch(before)!.group(0)!;
  final head = before.substring(0, before.length - word.length).trimRight();
  final previous = head.isEmpty ? lastCode : head[head.length - 1];
  return previous == '{' || previous == ',' ? _Where.key : _Where.value;
}

/// Last character of [text] that isn't whitespace, or ''.
String _lastCode(String text) {
  final trimmed = text.trimRight();
  return trimmed.isEmpty ? '' : trimmed[trimmed.length - 1];
}
