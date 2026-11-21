/// Turns a plain-language request into SQL with an [AiClient], grounded in
/// the connection's schema. Only metadata (schema, table and column names
/// and types) is sent, never row data.
library;

import '../drivers/driver.dart';
import 'ai_client.dart';

/// Metadata the assistant describes to the model.
abstract class SchemaSource {
  Future<List<String>> schemas();
  Future<List<DbObject>> objects(String schema);
  Future<List<ColumnInfo>> columns(String schema, String object);
}

class SqlRequest {
  const SqlRequest({
    required this.instruction,
    required this.engine,
    this.currentSql,
    this.lastError,
    this.defaultSchema,
  });

  /// What the user asked for.
  final String instruction;
  final DatabaseEngine engine;

  /// The query in the editor, to modify or explain.
  final String? currentSql;

  /// The error from the last run, to fix.
  final String? lastError;

  /// The schema unqualified names resolve to (PostgreSQL `public`, the
  /// MySQL/ClickHouse database of the connection).
  final String? defaultSchema;
}

class SqlSuggestion {
  const SqlSuggestion({required this.sql, required this.explanation});

  final String sql;
  final String explanation;
}

class SqlAssistant {
  SqlAssistant(this.client, this.source);

  final AiClient client;
  final SchemaSource source;

  /// Schemas described at most; mentioned and default ones come first.
  static const maxSchemas = 8;

  /// Tables listed by name at most.
  static const maxTables = 300;

  /// Tables described with their columns at most; mentioned ones first.
  static const maxDetailedTables = 40;

  Future<SqlSuggestion> suggest(SqlRequest request) async {
    final schema = await describeSchema(source, request);
    final reply = await client.complete(
      system: systemPrompt(request.engine),
      user: userPrompt(request, schema),
    );
    return parseReply(reply);
  }

  static String systemPrompt(DatabaseEngine engine) =>
      '''
You are an expert ${engine.label} SQL assistant inside a database client.
Write SQL in the ${engine.label} dialect that does what the user asks.
- Use only the tables and columns in the schema provided. If the request cannot be answered with them, say so in an SQL comment instead of guessing names.
- Qualify tables with their schema when it is not the default one, and quote identifiers only when required.
- Prefer read-only queries. Only write statements that change data or structure (INSERT, UPDATE, DELETE, DROP, ALTER…) when the user explicitly asks for it.
- For a large or unbounded result, add a sensible LIMIT unless the user asks for all rows.
Reply with the SQL in a single ```sql code block, then at most two short sentences explaining it.''';

  static String userPrompt(SqlRequest request, String schema) {
    final buffer = StringBuffer()
      ..writeln('Database schema:')
      ..writeln(schema.isEmpty ? '(no tables found)' : schema);
    if (request.defaultSchema case final s? when s.isNotEmpty) {
      buffer.writeln('Default schema: $s');
    }
    final current = request.currentSql?.trim() ?? '';
    if (current.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Current query in the editor:')
        ..writeln('```sql')
        ..writeln(current)
        ..writeln('```');
    }
    final error = request.lastError?.trim() ?? '';
    if (error.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Running it failed with this error:')
        ..writeln(error);
    }
    buffer
      ..writeln()
      ..writeln('Request: ${request.instruction.trim()}');
    return buffer.toString();
  }

  /// A compact description of the schema: one line per table with its
  /// columns for the most relevant tables, names only for the rest.
  static Future<String> describeSchema(
    SchemaSource source,
    SqlRequest request,
  ) async {
    final hint = '${request.instruction} ${request.currentSql ?? ''}'
        .toLowerCase();
    bool mentioned(String name) =>
        name.length > 1 && hint.contains(name.toLowerCase());

    final schemas = await source.schemas();
    int schemaRank(String s) => mentioned(s)
        ? 0
        : s == request.defaultSchema
        ? 1
        : 2;
    final ordered = [...schemas]
      ..sort((a, b) => schemaRank(a).compareTo(schemaRank(b)));

    final tables = <DbObject>[];
    for (final schema in ordered.take(maxSchemas)) {
      if (tables.length >= maxTables) break;
      final objects = await source.objects(schema);
      tables.addAll(
        objects
            .where((o) => o.kind != DbObjectKind.sequence)
            .take(maxTables - tables.length),
      );
    }
    if (tables.isEmpty) return '';

    // Mentioned tables (also as singular/plural) get their columns first.
    int tableRank(DbObject o) {
      final name = o.name.toLowerCase();
      final stem = name.endsWith('s') ? name.substring(0, name.length - 1) : name;
      return mentioned(name) || mentioned(stem) ? 0 : 1;
    }

    final detailed = ([...tables]
          ..sort((a, b) => tableRank(a).compareTo(tableRank(b))))
        .take(maxDetailedTables)
        .toSet();

    final columns = <DbObject, List<ColumnInfo>>{};
    // A few at a time: metadata queries share one connection.
    final pending = detailed.toList();
    for (var i = 0; i < pending.length; i += 4) {
      final batch = pending.skip(i).take(4).toList();
      final results = await Future.wait([
        for (final t in batch)
          source
              .columns(t.schema, t.name)
              .catchError((Object _) => const <ColumnInfo>[]),
      ]);
      for (var j = 0; j < batch.length; j++) {
        columns[batch[j]] = results[j];
      }
    }

    final buffer = StringBuffer();
    final others = <String>[];
    for (final t in tables) {
      final name = t.schema.isEmpty ? t.name : '${t.schema}.${t.name}';
      final cols = columns[t];
      if (cols == null) {
        others.add(name);
        continue;
      }
      final kind = t.kind.isTable ? 'table' : t.kind.label.toLowerCase();
      final described = [
        for (final c in cols)
          [
            c.name,
            c.dataType,
            if (c.isPrimaryKey) 'PK',
            if (!c.nullable && !c.isPrimaryKey) 'NOT NULL',
          ].join(' '),
      ].join(', ');
      buffer.writeln('$kind $name($described)');
    }
    if (others.isNotEmpty) {
      buffer.writeln('Other tables (columns not shown): ${others.join(', ')}');
    }
    return buffer.toString().trimRight();
  }

  /// Splits a reply into the SQL code block and the explanation around it.
  /// A reply without a code block is taken as SQL.
  static SqlSuggestion parseReply(String reply) {
    final match = RegExp(
      r'```[ \t]*([A-Za-z0-9_-]*)[ \t]*\r?\n([\s\S]*?)```',
    ).firstMatch(reply);
    if (match == null) {
      return SqlSuggestion(sql: reply.trim(), explanation: '');
    }
    final explanation = reply.replaceRange(match.start, match.end, ' ').trim();
    return SqlSuggestion(
      sql: match.group(2)!.trim(),
      explanation: explanation.replaceAll(RegExp(r'\s*\n\s*'), ' '),
    );
  }
}
