import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_database.dart';
import '../data/repositories.dart';
import '../data/secret_store.dart';
import '../drivers/driver.dart';
import '../drivers/registry.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final connectionRepositoryProvider = Provider<ConnectionRepository>(
  (ref) => ConnectionRepository(ref.watch(appDatabaseProvider), SecretStore()),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(ref.watch(appDatabaseProvider)),
);

final connectionsProvider = StreamProvider<List<ConnectionConfig>>(
  (ref) => ref.watch(connectionRepositoryProvider).watchAll(),
);

enum SessionStatus { connecting, connected, failed }

class Session {
  const Session(this.status, {this.driver, this.error});

  final SessionStatus status;
  final DatabaseDriver? driver;
  final String? error;
}

/// Live connections, keyed by connection id. A missing key means
/// disconnected.
class SessionsNotifier extends Notifier<Map<String, Session>> {
  @override
  Map<String, Session> build() {
    ref.onDispose(() {
      for (final session in state.values) {
        session.driver?.close();
      }
    });
    return const {};
  }

  Future<DatabaseDriver> connect(
    ConnectionConfig config,
    String? password,
  ) async {
    final existing = state[config.id];
    if (existing?.status == SessionStatus.connected) return existing!.driver!;

    state = {...state, config.id: const Session(SessionStatus.connecting)};
    final driver = createDriver(config);
    try {
      await driver.connect(password);
      state = {
        ...state,
        config.id: Session(SessionStatus.connected, driver: driver),
      };
      return driver;
    } catch (e) {
      await driver.close();
      state = {...state, config.id: Session(SessionStatus.failed, error: '$e')};
      rethrow;
    }
  }

  Future<void> disconnect(String connectionId) async {
    final session = state[connectionId];
    state = {...state}..remove(connectionId);
    await session?.driver?.close();
  }

  DatabaseDriver? driverFor(String connectionId) => state[connectionId]?.driver;
}

final sessionsProvider =
    NotifierProvider<SessionsNotifier, Map<String, Session>>(
      SessionsNotifier.new,
    );

/// Driver for a connection, or null while not connected. Watching this
/// instead of the whole sessions map keeps unrelated trees from reloading.
final driverProvider = Provider.family<DatabaseDriver?, String>(
  (ref, connectionId) =>
      ref.watch(sessionsProvider.select((s) => s[connectionId]?.driver)),
);

final schemasProvider = FutureProvider.family<List<String>, String>((
  ref,
  connectionId,
) async {
  final driver = ref.watch(driverProvider(connectionId));
  if (driver == null) return const [];
  return driver.listSchemas();
});

final objectsProvider =
    FutureProvider.family<List<DbObject>, (String connectionId, String schema)>(
      (ref, key) async {
        final driver = ref.watch(driverProvider(key.$1));
        if (driver == null) return const [];
        return driver.listObjects(key.$2);
      },
    );

final columnsProvider =
    FutureProvider.family<
      List<ColumnInfo>,
      (String connectionId, String schema, String object)
    >((ref, key) async {
      final driver = ref.watch(driverProvider(key.$1));
      if (driver == null) return const [];
      return driver.listColumns(key.$2, key.$3);
    });
