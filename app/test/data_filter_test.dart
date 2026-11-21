import 'package:db_client/drivers/driver.dart';
import 'package:db_client/drivers/sql_dialect.dart';
import 'package:db_client/state/data_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pg = postgresDialect;
  const mysql = MySqlDialect();

  group('buildSelectSql', () {
    test('no filter selects the whole table', () {
      expect(
        buildSelectSql(pg, 'public', 'users', limit: 21),
        'SELECT * FROM public.users LIMIT 21',
      );
    });

    test('a condition becomes the WHERE clause', () {
      expect(
        buildSelectSql(pg, 'public', 'users', filter: 'id > 10', limit: 5),
        'SELECT * FROM public.users WHERE id > 10\nLIMIT 5',
      );
    });

    test('a leading WHERE and trailing semicolons are dropped', () {
      expect(
        buildSelectSql(
          mysql,
          'shop',
          'users',
          filter: '  where name = \'Ann\' ;; ',
          limit: 5,
        ),
        "SELECT * FROM `shop`.`users` WHERE name = 'Ann'\nLIMIT 5",
      );
    });

    test('ORDER BY alone or after a condition', () {
      expect(
        buildSelectSql(pg, 's', 't', filter: 'order by id desc', limit: 5),
        'SELECT * FROM s.t order by id desc\nLIMIT 5',
      );
      expect(
        buildSelectSql(pg, 's', 't', filter: 'a = 1 ORDER BY b', limit: 5),
        'SELECT * FROM s.t WHERE a = 1 ORDER BY b\nLIMIT 5',
      );
    });

    test('a trailing comment cannot swallow the LIMIT', () {
      expect(
        buildSelectSql(pg, 's', 't', filter: 'a = 1 -- note', limit: 5),
        endsWith('-- note\nLIMIT 5'),
      );
    });
  });

  group('valueCondition', () {
    const id = ResultColumn(name: 'id', dataType: 'integer');
    const name = ResultColumn(name: 'name', dataType: 'varchar');

    test('equality with a dialect literal', () {
      expect(valueCondition(pg, id, 42), "id = '42'::integer");
      expect(valueCondition(mysql, name, "O'Brien"), "`name` = 'O''Brien'");
    });

    test('exclusion and NULL', () {
      expect(valueCondition(mysql, id, 7, exclude: true), "`id` <> '7'");
      expect(valueCondition(pg, name, null), 'name IS NULL');
      expect(
        valueCondition(pg, name, null, exclude: true),
        'name IS NOT NULL',
      );
    });
  });

  group('addCondition', () {
    test('starts a filter', () {
      expect(addCondition('', 'a = 1'), 'a = 1');
    });

    test('ANDs onto an existing condition', () {
      expect(addCondition('x > 1 OR y', 'a = 1'), '(x > 1 OR y) AND a = 1');
    });

    test('keeps ORDER BY last', () {
      expect(
        addCondition('x > 1 order by x', 'a = 1'),
        '(x > 1) AND a = 1 order by x',
      );
      expect(addCondition('ORDER BY x', 'a = 1'), 'a = 1 ORDER BY x');
    });
  });
}
