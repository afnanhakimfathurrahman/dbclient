import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Saved connections. Secrets are stored in secure storage, never here.
@DataClassName('ConnectionRow')
class Connections extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get engine => text()();
  TextColumn get host => text()();
  IntColumn get port => integer()();
  TextColumn get database => text()();
  TextColumn get username => text()();
  TextColumn get tlsMode => text()();
  IntColumn get color => integer()();
  BoolColumn get savePassword => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('HistoryRow')
class QueryHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get connectionId =>
      text().references(Connections, #id, onDelete: KeyAction.cascade)();
  TextColumn get sql => text()();
  DateTimeColumn get executedAt => dateTime()();
  IntColumn get durationMs => integer()();
  IntColumn get rowCount => integer().nullable()();
  TextColumn get error => text().nullable()();
}

@DriftDatabase(tables: [Connections, QueryHistory])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'db_client'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
