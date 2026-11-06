import 'clickhouse/clickhouse_driver.dart';
import 'driver.dart';
import 'mongodb/mongodb_driver.dart';
import 'postgres/postgres_driver.dart';

/// Engines offered when creating a connection.
const supportedEngines = [
  DatabaseEngine.postgres,
  DatabaseEngine.clickhouse,
  DatabaseEngine.mongodb,
];

DatabaseDriver createDriver(ConnectionConfig config) {
  return switch (config.engine) {
    DatabaseEngine.postgres => PostgresDriver(config),
    DatabaseEngine.clickhouse => ClickHouseDriver(config),
    DatabaseEngine.mongodb => MongoDriver(config),
    DatabaseEngine.redis => throw UnsupportedError(
      '${config.engine.label} is not supported yet',
    ),
  };
}
