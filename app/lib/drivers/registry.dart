import 'clickhouse/clickhouse_driver.dart';
import 'driver.dart';
import 'postgres/postgres_driver.dart';

/// Engines offered when creating a connection.
const supportedEngines = [DatabaseEngine.postgres, DatabaseEngine.clickhouse];

DatabaseDriver createDriver(ConnectionConfig config) {
  return switch (config.engine) {
    DatabaseEngine.postgres => PostgresDriver(config),
    DatabaseEngine.clickhouse => ClickHouseDriver(config),
    DatabaseEngine.mongodb || DatabaseEngine.redis => throw UnsupportedError(
      '${config.engine.label} is not supported yet',
    ),
  };
}
