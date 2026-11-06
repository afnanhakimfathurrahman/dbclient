import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:shared_preferences/shared_preferences.dart';

import '../app/theme.dart';
import '../data/app_database.dart';
import '../data/repositories.dart';
import '../data/secret_store.dart';
import '../drivers/document.dart';
import '../drivers/driver.dart';
import '../drivers/key_value.dart';
import '../drivers/registry.dart';
import 'workspace_tabs.dart';

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

  /// Connects in flight, so concurrent calls (a double-click, or opening an
  /// editor while the tree connects) share one driver instead of leaking one.
  final _pending = <String, Future<DatabaseDriver>>{};

  Future<DatabaseDriver> connect(ConnectionConfig config, String? password) {
    final existing = state[config.id];
    if (existing?.status == SessionStatus.connected) {
      return Future.value(existing!.driver!);
    }
    if (_pending[config.id] case final pending?) return pending;
    final future = _connect(config, password);
    _pending[config.id] = future;
    future.whenComplete(() {
      if (identical(_pending[config.id], future)) _pending.remove(config.id);
    }).ignore();
    return future;
  }

  Future<DatabaseDriver> _connect(
    ConnectionConfig config,
    String? password,
  ) async {
    // A fresh instance, so a disconnect (or a newer connect) while this one
    // is in flight can be told apart from it.
    // ignore: prefer_const_constructors
    final connecting = Session(SessionStatus.connecting);
    state = {...state, config.id: connecting};
    final driver = createDriver(config);
    try {
      await driver.connect(password);
    } catch (e) {
      await driver.close();
      if (identical(state[config.id], connecting)) {
        state = {
          ...state,
          config.id: Session(SessionStatus.failed, error: '$e'),
        };
      }
      rethrow;
    }
    if (!identical(state[config.id], connecting)) {
      // Disconnected meanwhile: don't bring the session back.
      await driver.close();
      throw StateError('Disconnected while connecting');
    }
    state = {
      ...state,
      config.id: Session(SessionStatus.connected, driver: driver),
    };
    return driver;
  }

  Future<void> disconnect(String connectionId) async {
    final session = state[connectionId];
    state = {...state}..remove(connectionId);
    _pending.remove(connectionId);
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

/// The SQL driver for a connection, or null if not connected or not a
/// relational engine. The metadata providers below use this.
final sqlDriverProvider = Provider.family<SqlDriver?, String>((ref, id) {
  final driver = ref.watch(driverProvider(id));
  return driver is SqlDriver ? driver : null;
});

/// Bumped per connection by a refresh. Metadata providers watch their own
/// connection's entry, so refreshing one connection reloads only its
/// metadata.
class MetadataEpochNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() => const {};

  void bump(String connectionId) =>
      state = {...state, connectionId: (state[connectionId] ?? 0) + 1};
}

final metadataEpochProvider =
    NotifierProvider<MetadataEpochNotifier, Map<String, int>>(
      MetadataEpochNotifier.new,
    );

void _watchEpoch(Ref ref, String connectionId) =>
    ref.watch(metadataEpochProvider.select((e) => e[connectionId]));

final schemasProvider = FutureProvider.family<List<String>, String>((
  ref,
  connectionId,
) async {
  _watchEpoch(ref, connectionId);
  final driver = ref.watch(sqlDriverProvider(connectionId));
  if (driver == null) return const [];
  return driver.listSchemas();
});

final objectsProvider =
    FutureProvider.family<List<DbObject>, (String connectionId, String schema)>(
      (ref, key) async {
        _watchEpoch(ref, key.$1);
        final driver = ref.watch(sqlDriverProvider(key.$1));
        if (driver == null) return const [];
        return driver.listObjects(key.$2);
      },
    );

/// Identifies a table-like object on a connection.
typedef RelationKey = (String connectionId, String schema, String object);

/// Builds a provider that loads per-object metadata (columns, indexes…) with
/// [load] while the connection is open.
FutureProviderFamily<List<T>, RelationKey> _objectMetadata<T>(
  Future<List<T>> Function(SqlDriver driver, String schema, String object) load,
) {
  return FutureProvider.family<List<T>, RelationKey>((ref, key) async {
    _watchEpoch(ref, key.$1);
    final driver = ref.watch(sqlDriverProvider(key.$1));
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
      _watchEpoch(ref, key.$1);
      final driver = ref.watch(sqlDriverProvider(key.$1));
      if (driver == null) return const [];
      return driver.listRoutines(key.$2);
    });

/// Drops a connection's cached metadata for a refresh; other connections
/// keep theirs.
void invalidateMetadata(WidgetRef ref, String connectionId) =>
    ref.read(metadataEpochProvider.notifier).bump(connectionId);

final ddlProvider = FutureProvider.family<String, RelationKey>((
  ref,
  key,
) async {
  _watchEpoch(ref, key.$1);
  final driver = ref.watch(sqlDriverProvider(key.$1));
  if (driver == null) return '';
  return driver.ddl(key.$2, key.$3);
});

/// Preferences loaded once at startup; overridden in `main`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override in main()'),
);

class AppThemeNotifier extends Notifier<AppThemePreset> {
  static const _key = 'themePreset';

  @override
  AppThemePreset build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final saved = AppThemePreset.values.asNameMap()[prefs.getString(_key)];
    if (saved != null) return saved;
    // Earlier builds stored only light/dark.
    return prefs.getString('themeMode') == 'light'
        ? AppThemePreset.vsCodeLight
        : AppThemePreset.vsCodeDark;
  }

  void select(AppThemePreset preset) {
    state = preset;
    ref.read(sharedPreferencesProvider).setString(_key, preset.name);
  }
}

final appThemeProvider = NotifierProvider<AppThemeNotifier, AppThemePreset>(
  AppThemeNotifier.new,
);

/// Rows loaded by the inspector's Data tab. Kept for the session (not
/// saved): a changed limit applies to tables opened afterwards too.
class DataRowLimitNotifier extends Notifier<int> {
  @override
  int build() => InspectorTab.defaultRowLimit;

  void set(int limit) => state = limit;
}

final dataRowLimitProvider = NotifierProvider<DataRowLimitNotifier, int>(
  DataRowLimitNotifier.new,
);

/// The document-store driver for a connection, or null if not connected or
/// not a document engine.
final documentDriverProvider = Provider.family<DocumentDriver?, String>((
  ref,
  id,
) {
  final driver = ref.watch(driverProvider(id));
  return driver is DocumentDriver ? driver : null;
});

final documentDatabasesProvider = FutureProvider.family<List<String>, String>((
  ref,
  connectionId,
) async {
  _watchEpoch(ref, connectionId);
  final driver = ref.watch(documentDriverProvider(connectionId));
  if (driver == null) return const [];
  return driver.listDatabases();
});

final collectionsProvider =
    FutureProvider.family<
      List<CollectionInfo>,
      (String connectionId, String database)
    >((ref, key) async {
      _watchEpoch(ref, key.$1);
      final driver = ref.watch(documentDriverProvider(key.$1));
      if (driver == null) return const [];
      return driver.listCollections(key.$2);
    });

/// The key-value driver for a connection, or null if not connected or not
/// a key-value engine.
final keyValueDriverProvider = Provider.family<KeyValueDriver?, String>((
  ref,
  id,
) {
  final driver = ref.watch(driverProvider(id));
  return driver is KeyValueDriver ? driver : null;
});

/// Redis databases with their key counts (0 for empty ones).
final redisDatabasesProvider =
    FutureProvider.family<List<(int db, int keys)>, String>((
      ref,
      connectionId,
    ) async {
      _watchEpoch(ref, connectionId);
      final driver = ref.watch(keyValueDriverProvider(connectionId));
      if (driver == null) return const [];
      final count = await driver.databaseCount();
      final keys = await driver.keyCounts();
      return [for (var db = 0; db < count; db++) (db, keys[db] ?? 0)];
    });
