// Integration tests against a real PostgreSQL server. Read-only: they never
// create, modify or delete anything.
//
// Skipped unless PG_TEST_HOST is set. Configure with:
//   PG_TEST_HOST, PG_TEST_PORT (5432), PG_TEST_DB, PG_TEST_USER,
//   PG_TEST_PASSWORD, PG_TEST_TLS (disable|require|verifyFull),
//   PG_TEST_SCHEMA (optional, a schema expected to contain tables)
@Tags(['integration'])
library;

import 'dart:io';

import 'package:db_client/drivers/driver.dart';
import 'package:db_client/drivers/postgres/postgres_driver.dart';
import 'package:db_client/drivers/value_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final env = Platform.environment;
  final host = env['PG_TEST_HOST'];
  final skip = host == null ? 'PG_TEST_HOST not set' : null;

  late PostgresDriver driver;

  setUpAll(() async {
    if (host == null) return;
    driver = PostgresDriver(
      ConnectionConfig(
        id: 'integration-test',
        name: 'integration',
        engine: DatabaseEngine.postgres,
        host: host,
        port: int.parse(env['PG_TEST_PORT'] ?? '5432'),
        database: env['PG_TEST_DB'] ?? 'postgres',
        username: env['PG_TEST_USER'] ?? 'postgres',
        tlsMode: TlsMode.values.byName(env['PG_TEST_TLS'] ?? 'disable'),
        color: 0,
        savePassword: false,
      ),
    );
    await driver.connect(env['PG_TEST_PASSWORD']);
  });

  tearDownAll(() async {
    if (host != null) await driver.close();
  });

  test('ping', () async {
    expect(await driver.ping(), lessThan(const Duration(seconds: 10)));
  }, skip: skip);

  test('browse schemas, objects and columns', () async {
    final schemas = await driver.listSchemas();
    expect(schemas, isNotEmpty);
    expect(schemas, isNot(contains('information_schema')));

    final schema = env['PG_TEST_SCHEMA'] ?? schemas.first;
    expect(schemas, contains(schema));

    final objects = await driver.listObjects(schema);
    if (env['PG_TEST_SCHEMA'] != null) expect(objects, isNotEmpty);
    if (objects.isEmpty) return;

    final columns = await driver.listColumns(schema, objects.first.name);
    expect(columns, isNotEmpty);
    expect(columns.every((c) => c.dataType.isNotEmpty), isTrue);
  }, skip: skip);

  test('select from a real table', () async {
    final schema = env['PG_TEST_SCHEMA'];
    if (schema == null) return;
    final objects = await driver.listObjects(schema);
    final table = objects.firstWhere(
      (o) => o.kind == DbObjectKind.table,
      orElse: () => objects.first,
    );
    final quoted = '"${schema.replaceAll('"', '""')}"."${table.name.replaceAll('"', '""')}"';
    final result = await driver.execute('SELECT * FROM $quoted LIMIT 20');
    expect(result.hasResultSet, isTrue);
    expect(result.columns, isNotEmpty);
    for (final row in result.rows) {
      for (final value in row) {
        formatValue(value); // must not throw for any real column type
      }
    }
  }, skip: skip);

  test('result columns carry names and type names', () async {
    final result = await driver.execute(
      "SELECT 1 AS n, NULL::text AS t, now() AS ts, 'x' AS s",
    );
    expect(result.columns.map((c) => c.name), ['n', 't', 'ts', 's']);
    expect(result.columns[0].dataType, 'integer');
    expect(result.columns[1].dataType, 'text');
    expect(result.columns[2].dataType, 'timestamp with time zone');
    expect(result.rows.single[0], 1);
    expect(result.rows.single[1], isNull);
  }, skip: skip);

  test('many types decode and format', () async {
    final result = await driver.execute('''
      SELECT '{"a": [1, 2]}'::jsonb, '\\xdeadbeef'::bytea, 12.50::numeric,
             interval '1 day 2 hours', ARRAY[1, 2, 3], ARRAY['a', NULL],
             '2026-01-02'::date, '12:34'::time, gen_random_uuid(),
             '192.168.0.1'::inet, true, 3.14::float8, 'a'::"char",
             int4range(1, 5), point(1, 2)
    ''');
    final row = result.rows.single;
    expect(row.length, 15);
    for (final value in row) {
      expect(formatValue(value), isNotNull);
    }
  }, skip: skip);

  test('statement without a result set reports no columns', () async {
    final result = await driver.execute('SET statement_timeout = 0');
    expect(result.hasResultSet, isFalse);
  }, skip: skip);

  test('row limit truncates and cancels the rest', () async {
    final watch = Stopwatch()..start();
    final result = await driver.execute(
      'SELECT g, md5(g::text) FROM generate_series(1, 5000000) g',
      maxRows: 1000,
    );
    expect(result.truncated, isTrue);
    expect(result.rows, hasLength(1000));
    expect(watch.elapsed, lessThan(const Duration(seconds: 30)));

    // Connection stays usable after the cancel.
    final after = await driver.execute('SELECT 42');
    expect(after.rows.single.single, 42);
  }, skip: skip);

  test('cancel stops a running statement', () async {
    final running = driver.execute('SELECT pg_sleep(30)');
    await Future<void>.delayed(const Duration(seconds: 2));
    final watch = Stopwatch()..start();
    await driver.cancel();
    await expectLater(
      running,
      throwsA(isA<DriverException>().having((e) => e.code, 'code', '57014')),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));

    final after = await driver.execute('SELECT 1');
    expect(after.rows.single.single, 1);
  }, skip: skip);

  test('server errors map to DriverException with details', () async {
    await expectLater(
      driver.execute('SELECT * FROM surely_no_such_table_xyz'),
      throwsA(
        isA<DriverException>()
            .having((e) => e.code, 'code', '42P01')
            .having((e) => e.position, 'position', isNotNull),
      ),
    );
    final after = await driver.execute('SELECT 1');
    expect(after.rows.single.single, 1);
  }, skip: skip);
}
