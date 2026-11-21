import 'package:db_client/ai/sql_assistant.dart';
import 'package:db_client/drivers/driver.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSchemaSource implements SchemaSource {
  FakeSchemaSource(this.tables);

  /// schema -> table -> column names.
  final Map<String, Map<String, List<String>>> tables;
  final columnRequests = <String>[];

  @override
  Future<List<String>> schemas() async => tables.keys.toList();

  @override
  Future<List<DbObject>> objects(String schema) async => [
    for (final name in tables[schema]!.keys)
      DbObject(schema: schema, name: name, kind: DbObjectKind.table),
  ];

  @override
  Future<List<ColumnInfo>> columns(String schema, String object) async {
    columnRequests.add('$schema.$object');
    return [
      for (final (i, name) in tables[schema]![object]!.indexed)
        ColumnInfo(
          name: name,
          dataType: i == 0 ? 'integer' : 'text',
          nullable: i != 0,
          isPrimaryKey: i == 0,
        ),
    ];
  }
}

SqlRequest request(String instruction, {String? currentSql}) => SqlRequest(
  instruction: instruction,
  engine: DatabaseEngine.postgres,
  defaultSchema: 'public',
  currentSql: currentSql,
);

void main() {
  group('describeSchema', () {
    test('lists tables with columns', () async {
      final source = FakeSchemaSource({
        'public': {
          'customers': ['id', 'name'],
          'orders': ['id', 'customer_id'],
        },
      });
      final schema = await SqlAssistant.describeSchema(
        source,
        request('count orders'),
      );
      expect(
        schema,
        'table public.customers(id integer PK, name text)\n'
        'table public.orders(id integer PK, customer_id text)',
      );
    });

    test('details mentioned tables first when there are many', () async {
      final many = {
        for (var i = 0; i < SqlAssistant.maxDetailedTables + 10; i++)
          't$i': ['id'],
      };
      final source = FakeSchemaSource({
        'public': {...many, 'invoices': ['id', 'total']},
      });
      final schema = await SqlAssistant.describeSchema(
        source,
        request('sum of invoice totals'),
      );
      expect(source.columnRequests, contains('public.invoices'));
      expect(
        source.columnRequests,
        hasLength(SqlAssistant.maxDetailedTables),
      );
      expect(schema, contains('table public.invoices(id integer PK, total text)'));
      expect(schema, contains('Other tables (columns not shown): '));
    });

    test('puts the default schema before others', () async {
      final source = FakeSchemaSource({
        for (var i = 0; i < SqlAssistant.maxSchemas; i++) 's$i': {'a$i': ['id']},
        'public': {'users': ['id']},
      });
      final schema = await SqlAssistant.describeSchema(source, request('x'));
      expect(schema, contains('public.users'));
    });
  });

  group('userPrompt', () {
    test('includes the current query and the error', () {
      final prompt = SqlAssistant.userPrompt(
        const SqlRequest(
          instruction: 'fix it',
          engine: DatabaseEngine.mysql,
          currentSql: 'SELEC 1',
          lastError: 'syntax error',
        ),
        'table t(id int)',
      );
      expect(prompt, contains('table t(id int)'));
      expect(prompt, contains('```sql\nSELEC 1\n```'));
      expect(prompt, contains('syntax error'));
      expect(prompt.trimRight(), endsWith('Request: fix it'));
    });
  });

  group('parseReply', () {
    test('takes the code block and the text around it', () {
      final s = SqlAssistant.parseReply(
        'Here you go:\n```sql\nSELECT *\nFROM t;\n```\nIt selects all rows.',
      );
      expect(s.sql, 'SELECT *\nFROM t;');
      expect(s.explanation, 'Here you go: It selects all rows.');
    });

    test('accepts a fence without a language', () {
      expect(SqlAssistant.parseReply('```\nSELECT 1\n```').sql, 'SELECT 1');
    });

    test('takes a reply without a fence as SQL', () {
      final s = SqlAssistant.parseReply('  SELECT 1;  ');
      expect(s.sql, 'SELECT 1;');
      expect(s.explanation, isEmpty);
    });
  });
}
