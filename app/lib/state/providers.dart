import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:shared_preferences/shared_preferences.dart';

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

/// Identifies a table-like object on a connection.
typedef RelationKey = (String connectionId, String schema, String object);

/// Builds a provider that loads per-object metadata (columns, indexes…) with
/// [load] while the connection is open.
FutureProviderFamily<List<T>, RelationKey> _objectMetadata<T>(
  Future<List<T>> Function(DatabaseDriver driver, String schema, String object)
  load,
) {
  return FutureProvider.family<List<T>, RelationKey>((ref, key) async {
    final driver = ref.watch(driverProvider(key.$1));
    if (driver == null) return const [];
    return load(driver, key.$2, key.$3);
  });
}

final columnsProvider = _objectMetadata((d, s, o) => d.listColumns(s, o));
final indexesProvider = _objectMetadata((d, s, o) => d.listIndexes(s, o));
final constraintsProvider = _objectMetadata(
  (d, s, o) => d.listConstraints(s, o),
);
final triggersProvider = _objectMetadata((d, s, o) => d.listTriggers(s, o));
final partitionsProvider = _objectMetadata((d, s, o) => d.listPartitions(s, o));

final routinesProvider =
    FutureProvider.family<
      List<RoutineInfo>,
      (String connectionId, String schema)
    >((ref, key) async {
      final driver = ref.watch(driverProvider(key.$1));
      if (driver == null) return const [];
      return driver.listRoutines(key.$2);
    });

/// Drops all cached metadata for a refresh.
void invalidateMetadata(WidgetRef ref, String connectionId) {
  ref.invalidate(schemasProvider(connectionId));
  ref.invalidate(objectsProvider);
  ref.invalidate(columnsProvider);
  ref.invalidate(indexesProvider);
  ref.invalidate(constraintsProvider);
  ref.invalidate(triggersProvider);
  ref.invalidate(partitionsProvider);
  ref.invalidate(routinesProvider);
  ref.invalidate(ddlProvider);
}

final ddlProvider = FutureProvider.family<String, RelationKey>((
  ref,
  key,
) async {
  final driver = ref.watch(driverProvider(key.$1));
  if (driver == null) return '';
  return driver.ddl(key.$2, key.$3);
});

/// Preferences loaded once at startup; overridden in `main`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override in main()'),
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'themeMode';

  @override
  ThemeMode build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_key);
    return ThemeMode.values.asNameMap()[saved] ?? ThemeMode.dark;
  }

  void toggle() {
    setMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }

  void setMode(ThemeMode mode) {
    state = mode;
    ref.read(sharedPreferencesProvider).setString(_key, mode.name);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
