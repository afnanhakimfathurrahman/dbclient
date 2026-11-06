import 'dart:convert';
import 'dart:typed_data';

import 'package:db_client/drivers/driver.dart';
import 'package:db_client/drivers/export.dart';
import 'package:flutter_test/flutter_test.dart';

QueryResult _result(List<ResultColumn> columns, List<List<Object?>> rows) =>
    QueryResult(
      columns: columns,
      rows: rows,
      affectedRows: rows.length,
      truncated: false,
      elapsed: const Duration(milliseconds: 15),
    );

void main() {
  const columns = [
    ResultColumn(name: 'id', dataType: 'int4'),
    ResultColumn(name: 'name', dataType: 'text'),
    ResultColumn(name: 'active', dataType: 'bool'),
  ];
  final result = _result(columns, const [
    [1, 'Alice', true],
    [2, 'Bob, Jr.', false],
    [3, null, null],
  ]);

  test('toCsv formats headers and escapes commas', () {
    final csv = ResultExporter.toCsv(result);
    final lines = csv.split('\n');
    expect(lines[0], 'id,name,active');
    expect(lines[1], '1,Alice,true');
    expect(lines[2], '2,"Bob, Jr.",false');
    expect(lines[3], '3,,');
  });

  test('toCsv keeps trailing whitespace and quotes newlines', () {
    final csv = ResultExporter.toCsv(
      _result(const [ResultColumn(name: 'v', dataType: 'text')], const [
        ['a\nb'],
        ['ends with space '],
      ]),
    );
    expect(csv, 'v\n"a\nb"\nends with space ');
  });

  test('toJson exports valid JSON array of objects', () {
    final jsonStr = ResultExporter.toJson(result);
    expect(jsonStr, contains('"id": 1'));
    expect(jsonStr, contains('"name": "Alice"'));
    expect(jsonStr, contains('"active": true'));
    expect(jsonStr, contains('"name": "Bob, Jr."'));
  });

  test('toJson handles non-JSON values and duplicate column names', () {
    final decoded = jsonDecode(
      ResultExporter.toJson(
        _result(
          const [
            ResultColumn(name: 'id', dataType: 'integer'),
            ResultColumn(name: 'id', dataType: 'integer'),
            ResultColumn(name: 'ts', dataType: 'timestamp with time zone'),
            ResultColumn(name: 'b', dataType: 'bytea'),
            ResultColumn(name: 'doc', dataType: 'jsonb'),
            ResultColumn(name: 'f', dataType: 'double precision'),
          ],
          [
            [
              1,
              2,
              DateTime.utc(2026, 1, 2, 3, 4, 5),
              Uint8List.fromList(List.filled(100, 0xab)),
              {
                'a': [1, 2],
              },
              double.infinity,
            ],
          ],
        ),
      ),
    );
    final row = (decoded as List).single as Map;
    expect(row['id'], 1);
    expect(row['id_2'], 2);
    expect(row['ts'], '2026-01-02T03:04:05.000+00');
    // Exports never truncate bytea, unlike the grid.
    expect(row['b'], '\\x${'ab' * 100}');
    expect(row['doc'], {
      'a': [1, 2],
    });
    expect(row['f'], 'Infinity');
  });

  test('toMarkdown exports markdown table', () {
    final md = ResultExporter.toMarkdown(result);
    expect(md, contains('| id | name | active |'));
    expect(md, contains('| --- | --- | --- |'));
    expect(md, contains('| 1 | Alice | true |'));
    expect(md, contains('| 3 | NULL | NULL |'));
  });

  test('toTsv exports tab-delimited records', () {
    final tsv = ResultExporter.toTsv(result);
    final lines = tsv.split('\n');
    expect(lines[0], 'id\tname\tactive');
    expect(lines[1], '1\tAlice\ttrue');
  });

  test('toSql generates INSERT statements', () {
    final sql = ResultExporter.toSql(result, tableName: 'public.users');
    expect(
      sql,
      contains(
        "INSERT INTO public.users (id, name, active) VALUES (1, 'Alice', TRUE);",
      ),
    );
    expect(
      sql,
      contains(
        'INSERT INTO public.users (id, name, active) VALUES (3, NULL, NULL);',
      ),
    );
  });

  test('toSql quotes identifiers and writes valid literals', () {
    final sql = ResultExporter.toSql(
      _result(
        const [
          ResultColumn(name: 'user', dataType: 'text'),
          ResultColumn(name: 'tags', dataType: 'text[]'),
          ResultColumn(name: 'doc', dataType: 'jsonb'),
          ResultColumn(name: 'f', dataType: 'double precision'),
        ],
        const [
          [
            "O'Brien",
            ['a"b', null, 'c'],
            [1, 2],
            double.nan,
          ],
        ],
      ),
      tableName: 'x',
    );
    expect(
      sql,
      'INSERT INTO x ("user", tags, doc, f) VALUES '
      '(\'O\'\'Brien\', \'{"a\\"b",NULL,"c"}\', \'[1,2]\', \'NaN\');',
    );
  });
}
