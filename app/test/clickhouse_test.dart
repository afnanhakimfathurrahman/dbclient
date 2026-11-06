import 'package:db_client/drivers/clickhouse/clickhouse_driver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ClickHouseRowsParser', () {
    test('names, types, then rows', () {
      final parser = ClickHouseRowsParser(maxRows: 10);
      for (final line in [
        '["id","name","score"]',
        '["UInt64","String","Nullable(Float64)"]',
        '["1","alice",1.5]',
        '["2","bob",null]',
      ]) {
        expect(parser.add(line), isTrue);
      }
      expect(parser.columns.map((c) => c.name), ['id', 'name', 'score']);
      expect(parser.columns[2].dataType, 'Nullable(Float64)');
      expect(parser.rows, [
        ['1', 'alice', 1.5],
        ['2', 'bob', null],
      ]);
      expect(parser.truncated, isFalse);
    });

    test('an empty result still has columns', () {
      final parser = ClickHouseRowsParser(maxRows: 10)
        ..add('["n"]')
        ..add('["UInt8"]');
      expect(parser.columns, hasLength(1));
      expect(parser.rows, isEmpty);
    });

    test('stops one row past the limit and marks truncated', () {
      final parser = ClickHouseRowsParser(maxRows: 2)
        ..add('["n"]')
        ..add('["UInt8"]')
        ..add('[1]')
        ..add('[2]');
      expect(parser.add('[3]'), isFalse);
      expect(parser.rows, hasLength(2));
      expect(parser.truncated, isTrue);
    });

    test('an exception after rows started streaming is raised', () {
      final parser = ClickHouseRowsParser(maxRows: 10)
        ..add('["n"]')
        ..add('["UInt8"]');
      expect(
        () => parser.add(
          'Code: 395. DB::Exception: Value passed to throwIf is non-zero. '
          '(FUNCTION_THROW_IF_VALUE_IS_NON_ZERO) (version 24.3.1.1)',
        ),
        throwsA(
          isA<Exception>().having((e) => '$e', 'message', contains('throwIf')),
        ),
      );
    });
  });

  test('parseClickHouseError extracts code and message', () {
    final error = parseClickHouseError(
      'Code: 60. DB::Exception: Unknown table expression identifier '
      "'nope' in scope SELECT * FROM nope. (UNKNOWN_TABLE) "
      '(version 24.3.1.1 (official build))\n',
    );
    expect(error.code, '60');
    expect(error.message, startsWith('Unknown table expression identifier'));
    expect(error.message, endsWith('(UNKNOWN_TABLE)'));

    final auth = parseClickHouseError(
      'Code: 516. DB::Exception: default: Authentication failed: password is '
      'incorrect, or there is no user with such name. '
      '(AUTHENTICATION_FAILED) (version 23.8.2.7 (official build))',
    );
    expect(auth.code, '516');

    expect(parseClickHouseError('', status: 502).message, 'HTTP error 502');
  });
}
