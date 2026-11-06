import 'package:db_client/drivers/connection_uri.dart';
import 'package:db_client/drivers/driver.dart';
import 'package:db_client/drivers/export.dart';
import 'package:db_client/drivers/sql_dialect.dart';
import 'package:db_client/state/data_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mysql = MySqlDialect();

  test('MySQL quoting: backticks, backslash and quote escapes', () {
    expect(mysql.quoteIdent('order'), '`order`');
    expect(mysql.quoteIdent('we`ird'), '`we``ird`');
    expect(mysql.qualifiedName('shop', 'users'), '`shop`.`users`');
    expect(mysql.quoteLiteral(r"O'Brien \ co"), r"'O''Brien \\ co'");
    expect(mysql.typedLiteral(null, 'int'), 'NULL');
    expect(mysql.typedLiteral('42', 'int'), "'42'");
  });

  test('ClickHouse literals escape backslashes', () {
    expect(const ClickHouseDialect().quoteLiteral(r"a\b'c"), r"'a\\b\'c'");
  });

  test('row edits on MySQL use backticks and plain literals', () {
    final editor =
        DataEditController(
            schema: 'shop',
            table: 'users',
            columns: const [
              ResultColumn(name: 'id', dataType: 'int'),
              ResultColumn(name: 'name', dataType: 'varchar'),
            ],
            baseRows: const [
              [1, 'Ann'],
            ],
            keyColumns: const [0],
            dialect: mysql,
          )
          ..setCell(0, 1, const CellValue('Anne'))
          ..addRow();
    editor.setCell(1, 1, const CellValue('Bo'));
    expect(editor.buildStatements(), [
      "UPDATE `shop`.`users` SET `name` = 'Anne' WHERE `id` = '1';",
      "INSERT INTO `shop`.`users` (`name`) VALUES ('Bo');",
    ]);
  });

  test('SQL export in the MySQL dialect', () {
    final sql = ResultExporter.toSql(
      const QueryResult(
        columns: [ResultColumn(name: 'key', dataType: 'varchar')],
        rows: [
          [r'a\b'],
        ],
        affectedRows: 0,
        elapsed: Duration.zero,
        truncated: false,
      ),
      tableName: '`t`',
      dialect: mysql,
    );
    expect(sql, r"INSERT INTO `t` (`key`) VALUES ('a\\b');");
  });

  test('mysql:// and mariadb:// URIs', () {
    final p = parseConnectionUri(
      'mysql://app:pw@db.local:3307/shop?ssl-mode=REQUIRED',
    );
    expect(p.engine, DatabaseEngine.mysql);
    expect(p.port, 3307);
    expect(p.database, 'shop');
    expect(p.tlsMode, TlsMode.require);
    expect(
      parseConnectionUri('mariadb://root@localhost/').engine,
      DatabaseEngine.mysql,
    );
  });
}
