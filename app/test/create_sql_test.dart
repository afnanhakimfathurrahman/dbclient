import 'package:db_client/drivers/create_sql.dart';
import 'package:db_client/drivers/sql_dialect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pg = PostgresDialect();
  const mysql = MySqlDialect();
  const clickHouse = ClickHouseDialect();

  const columns = [
    NewColumn(name: 'id', type: 'bigint', primaryKey: true),
    NewColumn(name: 'Full Name', type: 'text', nullable: false),
    NewColumn(name: 'status', type: 'text', defaultValue: "'new'"),
  ];

  test('CREATE DATABASE and SCHEMA quote names per dialect', () {
    expect(buildCreateDatabaseSql(pg, 'shop'), 'CREATE DATABASE shop;');
    expect(
      buildCreateDatabaseSql(pg, 'My "DB"'),
      'CREATE DATABASE "My ""DB""";',
    );
    expect(buildCreateDatabaseSql(mysql, 'a`b'), 'CREATE DATABASE `a``b`;');
    expect(
      buildCreateDatabaseSql(clickHouse, 'Logs'),
      'CREATE DATABASE "Logs";',
    );
    expect(buildCreateSchemaSql(pg, 'select'), 'CREATE SCHEMA "select";');
  });

  test('PostgreSQL CREATE TABLE with primary key, NOT NULL and default', () {
    expect(
      buildCreateTableSql(
        pg,
        schema: 'public',
        table: 'Orders',
        columns: columns,
      ),
      'CREATE TABLE public."Orders" (\n'
      '  id bigint NOT NULL,\n'
      '  "Full Name" text NOT NULL,\n'
      "  status text DEFAULT 'new',\n"
      '  PRIMARY KEY (id)\n'
      ');',
    );
  });

  test('MySQL CREATE TABLE uses backticks', () {
    expect(
      buildCreateTableSql(
        mysql,
        schema: 'shop',
        table: 'we`ird',
        columns: const [
          NewColumn(name: 'a', type: 'INT', primaryKey: true),
          NewColumn(name: 'b', type: 'INT', primaryKey: true),
          NewColumn(name: 'note', type: 'TEXT'),
        ],
      ),
      'CREATE TABLE `shop`.`we``ird` (\n'
      '  `a` INT NOT NULL,\n'
      '  `b` INT NOT NULL,\n'
      '  `note` TEXT,\n'
      '  PRIMARY KEY (`a`, `b`)\n'
      ');',
    );
  });

  test('ClickHouse CREATE TABLE has an engine and Nullable types', () {
    expect(
      buildCreateTableSql(
        clickHouse,
        schema: 'default',
        table: 'events',
        columns: const [
          NewColumn(name: 'id', type: 'UInt64', primaryKey: true),
          NewColumn(name: 'Kind', type: 'String'),
          NewColumn(name: 'n', type: 'Nullable(Int32)'),
          NewColumn(
            name: 'at',
            type: 'DateTime',
            nullable: false,
            defaultValue: 'now()',
          ),
        ],
      ),
      'CREATE TABLE "default".events (\n'
      '  id UInt64,\n'
      '  "Kind" Nullable(String),\n'
      '  n Nullable(Int32),\n'
      '  at DateTime DEFAULT now()\n'
      ')\n'
      'ENGINE = MergeTree\n'
      'ORDER BY (id);',
    );
  });

  test('ClickHouse table without a key is ordered by tuple()', () {
    expect(
      buildCreateTableSql(
        clickHouse,
        schema: 'logs',
        table: 't',
        columns: const [NewColumn(name: 'x', type: 'String', nullable: false)],
      ),
      'CREATE TABLE logs.t (\n'
      '  x String\n'
      ')\n'
      'ENGINE = MergeTree\n'
      'ORDER BY tuple();',
    );
  });

  test('blank columns are skipped; nothing to create gives empty SQL', () {
    expect(
      buildCreateTableSql(
        pg,
        schema: 'public',
        table: 't',
        columns: const [NewColumn(name: ' ', type: 'text')],
      ),
      '',
    );
    expect(
      buildCreateTableSql(pg, schema: 'public', table: '', columns: columns),
      '',
    );
  });

  test('editor templates are dialect-quoted', () {
    expect(
      createViewTemplate(mysql, 'shop'),
      startsWith('CREATE VIEW `shop`.`new_view` AS'),
    );
    expect(
      createFunctionTemplate(pg, 'My Schema'),
      contains(r'"My Schema".new_function'),
    );
    expect(createFunctionTemplate(pg, 'public'), contains('LANGUAGE plpgsql'));
    expect(
      createFunctionTemplate(mysql, 'shop'),
      contains('RETURN value * 2;'),
    );
    expect(
      createSequenceTemplate(pg, 'public'),
      startsWith('CREATE SEQUENCE public.new_sequence'),
    );
    expect(
      createIndexTemplate(
        mysql,
        schema: 'shop',
        table: 'users',
        column: 'email',
      ),
      'CREATE INDEX `users_email_idx` ON `shop`.`users` (`email`);',
    );
    expect(
      createIndexTemplate(
        clickHouse,
        schema: 'db',
        table: 'events',
        column: 'at',
      ),
      'ALTER TABLE db.events\n  ADD INDEX events_at_idx at TYPE minmax GRANULARITY 1;',
    );
  });
}
