import 'package:db_client/drivers/driver.dart';
import 'package:db_client/drivers/sql_dialect.dart';
import 'package:db_client/features/editor/sql_completion.dart';
import 'package:flutter_test/flutter_test.dart';

class _Catalog implements SqlCatalog {
  @override
  String? get defaultSchema => 'public';

  @override
  List<String>? schemas() => ['public', 'sales'];

  @override
  List<DbObject>? objects(String schema) => switch (schema) {
    'public' => const [
      DbObject(schema: 'public', name: 'users', kind: DbObjectKind.table),
      DbObject(schema: 'public', name: 'user_roles', kind: DbObjectKind.table),
      DbObject(schema: 'public', name: 'Orders', kind: DbObjectKind.table),
      DbObject(schema: 'public', name: 'active_users', kind: DbObjectKind.view),
    ],
    'sales' => const [
      DbObject(schema: 'sales', name: 'invoices', kind: DbObjectKind.table),
    ],
    _ => null,
  };

  @override
  List<ColumnInfo>? columns(String schema, String table) =>
      switch ((schema, table)) {
        ('public', 'users') => const [
          ColumnInfo(
            name: 'id',
            dataType: 'integer',
            nullable: false,
            isPrimaryKey: true,
          ),
          ColumnInfo(
            name: 'email',
            dataType: 'text',
            nullable: false,
            isPrimaryKey: false,
          ),
          ColumnInfo(
            name: 'created_at',
            dataType: 'timestamptz',
            nullable: true,
            isPrimaryKey: false,
          ),
        ],
        ('public', 'Orders') => const [
          ColumnInfo(
            name: 'id',
            dataType: 'integer',
            nullable: false,
            isPrimaryKey: true,
          ),
          ColumnInfo(
            name: 'user_id',
            dataType: 'integer',
            nullable: false,
            isPrimaryKey: false,
          ),
          ColumnInfo(
            name: 'Total',
            dataType: 'numeric',
            nullable: true,
            isPrimaryKey: false,
          ),
        ],
        ('sales', 'invoices') => const [
          ColumnInfo(
            name: 'amount',
            dataType: 'numeric',
            nullable: true,
            isPrimaryKey: false,
          ),
        ],
        _ => null, // not loaded yet
      };
}

/// Completes at the `|` marker.
SqlCompletion? _complete(
  String marked, {
  SqlDialect dialect = postgresDialect,
}) {
  final cursor = marked.indexOf('|');
  return completeSql(
    text: marked.replaceFirst('|', ''),
    cursor: cursor,
    catalog: _Catalog(),
    dialect: dialect,
  );
}

List<String> _labels(String marked, {SqlDialect dialect = postgresDialect}) => [
  for (final s
      in _complete(marked, dialect: dialect)?.suggestions ??
          const <SqlSuggestion>[])
    s.label,
];

void main() {
  test('tables after FROM and JOIN', () {
    expect(_labels('SELECT * FROM us|'), ['users', 'user_roles']);
    expect(_labels('select * from users u join |x'.replaceFirst('|x', 'o|')), [
      'Orders',
    ]);
    expect(_labels('SELECT * FROM users, ac|'), ['active_users']);
  });

  test('schema-qualified tables', () {
    expect(_labels('SELECT * FROM sales.|'), ['invoices']);
  });

  test('columns after an alias or table name', () {
    expect(_labels('SELECT u.| FROM users u'), ['id', 'email', 'created_at']);
    expect(_labels('SELECT u.em| FROM users AS u'), ['email']);
    expect(
      _labels('SELECT o.| FROM users u JOIN "Orders" o ON o.user_id = u.id'),
      ['id', 'user_id', 'Total'],
    );
    expect(_labels('SELECT users.cr| FROM users'), ['created_at']);
    expect(_labels('SELECT i.am| FROM sales.invoices i'), ['amount']);
  });

  test('columns of the statement come before keywords', () {
    final labels = _labels('SELECT * FROM users WHERE cr|');
    expect(labels.first, 'created_at');
    expect(labels, contains('CREATE TABLE'));
  });

  test('keyword case follows the typing', () {
    final lower = _complete('sel|')!;
    expect(lower.suggestions.first.insert, 'select');
    final upper = _complete('SEL|')!;
    expect(upper.suggestions.first.insert, 'SELECT');
    expect(
      _complete('SELECT * FROM users ORD|')!.suggestions.map((s) => s.label),
      contains('ORDER BY'),
    );
  });

  test('names needing quotes are quoted per dialect', () {
    final pg = _complete('SELECT * FROM Or|')!;
    expect(pg.suggestions.single.insert, '"Orders"');
    expect(pg.input, 'Or');
    final my = _complete('SELECT * FROM Or|', dialect: const MySqlDialect())!;
    expect(my.suggestions.single.insert, 'Orders');
  });

  test('only the statement under the cursor counts', () {
    expect(_labels('SELECT * FROM users u;\nSELECT u.| FROM "Orders" u'), [
      'id',
      'user_id',
      'Total',
    ]);
  });

  test('nothing inside strings, comments, or with no partial word', () {
    expect(_complete("SELECT 'us|"), isNull);
    expect(_complete('SELECT 1 -- us|'), isNull);
    expect(_complete('SELECT |'), isNull);
    expect(_complete('SELECT * FROM users WHERE email = "x|'), isNull);
  });

  test('tables not loaded yet give no columns, without failing', () {
    expect(_labels('SELECT u.| FROM user_roles u'), isEmpty);
  });

  test('parseTableRefs', () {
    final refs = parseTableRefs(
      'SELECT * FROM public.users u LEFT JOIN "Orders" AS o ON o.id = u.id '
      "WHERE x = 'FROM fake f'",
    );
    expect(
      [for (final r in refs) (r.schema, r.name, r.alias)],
      [('public', 'users', 'u'), (null, 'Orders', 'o')],
    );
    expect(
      [
        for (final r in parseTableRefs('select * from a where b = 1'))
          (r.name, r.alias),
      ],
      [('a', null)],
    );
  });
}
