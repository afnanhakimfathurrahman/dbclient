import 'driver.dart';
import 'postgres/postgres_driver.dart';

DatabaseDriver createDriver(ConnectionConfig config) {
  return switch (config.engine) {
    DatabaseEngine.postgres => PostgresDriver(config),
  };
}
