import 'clickhouse/clickhouse_driver.dart';
import 'driver.dart';
import 'mongodb/mongodb_driver.dart';
import 'mysql/mysql_driver.dart';
import 'postgres/postgres_driver.dart';
import 'redis/redis_driver.dart';

/// Engines offered when creating a connection.
const supportedEngines = [
  DatabaseEngine.postgres,
  DatabaseEngine.mysql,
  DatabaseEngine.clickhouse,
  DatabaseEngine.mongodb,
  DatabaseEngine.redis,
];

DatabaseDriver createDriver(ConnectionConfig config) {
  return switch (config.engine) {
    DatabaseEngine.postgres => PostgresDriver(config),
    DatabaseEngine.mysql => MySqlDriver(config),
    DatabaseEngine.clickhouse => ClickHouseDriver(config),
    DatabaseEngine.mongodb => MongoDriver(config),
    DatabaseEngine.redis => RedisDriver(config),
  };
}
