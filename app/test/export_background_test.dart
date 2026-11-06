import 'dart:convert';
import 'dart:isolate';

import 'package:db_client/drivers/driver.dart';
import 'package:db_client/drivers/export.dart';
import 'package:db_client/drivers/sql_dialect.dart';
import 'package:flutter_test/flutter_test.dart';

QueryResult _result(List<List<Object?>> rows) => QueryResult(
  columns: const [
    ResultColumn(name: 'id', dataType: 'int4'),
    ResultColumn(name: 'v', dataType: 'text'),
  ],
  rows: rows,
  affectedRows: 0,
  truncated: false,
  elapsed: Duration.zero,
);

void main() {
  test('background export matches export, in every format', () async {
    final result = _result([
      [1, 'a'],
      [2, null],
      [
        3,
        {'k': 'v'},
      ],
    ]);
    for (final format in ExportFormat.values) {
      final expected = ResultExporter.export(
        result,
        format,
        tableName: 't',
        dialect: const MySqlDialect(),
      );
      expect(
        await ResultExporter.exportInBackground(
          result,
          format,
          tableName: 't',
          dialect: const MySqlDialect(),
        ),
        expected,
      );
      expect(
        utf8.decode(
          await ResultExporter.exportBytesInBackground(
            result,
            format,
            tableName: 't',
            dialect: const MySqlDialect(),
          ),
        ),
        expected,
      );
    }
  });

  test('values an isolate cannot receive are exported here', () async {
    final port = ReceivePort();
    addTearDown(port.close);
    final result = _result([
      [1, port],
    ]);
    expect(
      await ResultExporter.exportInBackground(result, ExportFormat.csv),
      ResultExporter.export(result, ExportFormat.csv),
    );
  });
}
