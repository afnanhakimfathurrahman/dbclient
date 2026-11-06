import 'dart:typed_data';

import 'package:db_client/drivers/value_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('null stays null so the grid can style it', () {
    expect(formatValue(null), isNull);
    expect(formatValueFull(null), 'NULL');
  });

  test('UTC timestamps show an explicit +00 offset', () {
    expect(
      formatValue(DateTime.utc(2026, 1, 2, 3, 4, 5)),
      '2026-01-02T03:04:05.000+00',
    );
  });

  test('bytes render as Postgres hex, truncated in the grid', () {
    final bytes = Uint8List.fromList(List.generate(100, (i) => i));
    expect(formatValue(Uint8List.fromList([0, 255])), r'\x00ff');
    expect(formatValue(bytes), endsWith('… (100 bytes)'));
    expect(formatValueFull(bytes), isNot(contains('…')));
  });

  test('json is compact in the grid and pretty in the viewer', () {
    final json = {
      'a': 1,
      'b': [true, null],
    };
    expect(formatValue(json), '{"a":1,"b":[true,null]}');
    expect(formatValueFull(json), contains('\n  "a": 1'));
  });

  test('other values use toString', () {
    expect(formatValue(42), '42');
    expect(formatValue(1.5), '1.5');
    expect(formatValue(true), 'true');
  });
}
