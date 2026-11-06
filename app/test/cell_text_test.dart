import 'dart:convert';
import 'dart:typed_data';

import 'package:db_client/drivers/clickhouse/clickhouse_driver.dart';
import 'package:db_client/drivers/driver.dart';
import 'package:db_client/drivers/value_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatCellText', () {
    test('short values match formatValue', () {
      final values = <Object?>[
        null,
        'plain',
        42,
        1.5,
        true,
        DateTime.utc(2026, 1, 2),
        Uint8List.fromList([0, 15, 16, 255]),
        {
          'a': 1,
          'b': [true, null, 2.5],
          'c': {'d': 'x"y\\z\u0001\b\f\t'},
        },
        ['😀', '\ud800', 'x\udc00'],
        [DateTime.utc(2026), DateTime.utc(2027)],
        {1: 'non-string key'},
        [double.nan],
      ];
      for (final value in values) {
        expect(formatCellText(value), formatValue(value), reason: '$value');
      }
    });

    test('long JSON is a capped prefix of jsonEncode', () {
      final doc = {
        'items': [
          for (var i = 0; i < 5000; i++) {'id': i, 'name': 'item "$i"\n'},
        ],
      };
      final full = jsonEncode(doc);
      final text = formatCellText(doc, maxChars: 100)!;
      expect(text, hasLength(101));
      expect(text, endsWith('…'));
      expect(full, startsWith(text.substring(0, 100)));
    });

    test('long collections JSON cannot encode are capped too', () {
      final list = [for (var i = 0; i < 1000; i++) DateTime.utc(2026)];
      final text = formatCellText(list, maxChars: 50)!;
      expect(text, hasLength(51));
      expect(list.toString(), startsWith(text.substring(0, 50)));
    });

    test('text goes on one line and is capped', () {
      expect(formatCellText('a\nb\r\nc\rd\te'), 'a↵b↵c↵d e');
      expect(formatCellText('x' * 600), '${'x' * 500}…');
      expect(formatCellText('ab\ncd', maxChars: 3), 'ab↵…');
      // A surrogate pair is not split.
      expect(formatCellText('a😀', maxChars: 2), 'a…');
    });

    test('unchanged text is returned as is', () {
      const text = 'nothing to do';
      expect(identical(cellText(text), text), isTrue);
    });

    test('bytes keep the 64-byte grid cap', () {
      final bytes = Uint8List(1000);
      expect(formatCellText(bytes), formatValue(bytes));
      expect(formatCellText(bytes), endsWith('… (1000 bytes)'));
    });
  });

  test('bytes hex output is unchanged', () {
    final bytes = Uint8List.fromList(List.generate(256, (i) => i));
    final expected = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    expect(formatValueFull(bytes), '\\x$expected');
    expect(formatValue(Uint8List(0)), '\\x');
  });

  group('row budget', () {
    test('estimates grow with the data', () {
      expect(estimateValueSize('x' * 1000), greaterThan(2000));
      expect(estimateValueSize(Uint8List(1000)), greaterThan(1000));
      expect(
        estimateValueSize({
          'a': ['x' * 1000],
        }),
        greaterThan(2000),
      );
      expect(estimateValueSize(42), lessThan(64));
    });

    test('stops at the row cap', () {
      final budget = RowBudget(maxRows: 2);
      budget.add([1]);
      expect(budget.full, isFalse);
      budget.add([2]);
      expect(budget.full, isTrue);
    });

    test('stops once the kept rows exceed the byte budget', () {
      final budget = RowBudget(maxRows: 100, maxBytes: 10000);
      budget.add(['x' * 3000]);
      expect(budget.full, isFalse);
      budget.add(['x' * 3000]);
      expect(budget.full, isTrue);
      expect(budget.bytes, greaterThanOrEqualTo(10000));
    });

    test('ClickHouse rows stop at the byte budget', () {
      final parser = ClickHouseRowsParser(maxRows: 100, maxBytes: 5000)
        ..add('["v"]')
        ..add('["String"]');
      final row = jsonEncode(['x' * 2000]);
      expect(parser.add(row), isTrue);
      expect(parser.add(row), isTrue);
      expect(parser.add(row), isFalse);
      expect(parser.rows, hasLength(2));
      expect(parser.truncated, isTrue);
    });
  });
}
