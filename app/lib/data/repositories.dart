import 'package:drift/drift.dart';

import '../drivers/driver.dart';
import 'app_database.dart';
import 'secret_store.dart';

class ConnectionRepository {
  ConnectionRepository(this._db, this._secrets);

  final AppDatabase _db;
  final SecretStore _secrets;

  Stream<List<ConnectionConfig>> watchAll() {
    final query = _db.select(_db.connections)
      ..orderBy([(c) => OrderingTerm.asc(c.name)]);
    return query.watch().map((rows) => rows.map(_fromRow).toList());
  }

  /// Saves the connection. A null [password] leaves the stored one untouched;
  /// when [ConnectionConfig.savePassword] is off any stored password is
  /// removed.
  Future<void> save(ConnectionConfig config, {String? password}) async {
    await _db
        .into(_db.connections)
        .insertOnConflictUpdate(
          ConnectionsCompanion.insert(
            id: config.id,
            name: config.name,
            engine: config.engine.name,
            host: config.host,
            port: config.port,
            database: config.database,
            username: config.username,
            tlsMode: config.tlsMode.name,
            color: config.color,
            savePassword: Value(config.savePassword),
          ),
        );
    if (!config.savePassword) {
      await _secrets.deletePassword(config.id);
    } else if (password != null) {
      await _secrets.writePassword(config.id, password);
    }
  }

  Future<void> delete(String id) async {
    await (_db.delete(_db.connections)..where((c) => c.id.equals(id))).go();
    await _secrets.deletePassword(id);
  }

  Future<String?> readPassword(String id) => _secrets.readPassword(id);

  ConnectionConfig _fromRow(ConnectionRow row) => ConnectionConfig(
    id: row.id,
    name: row.name,
    engine: DatabaseEngine.values.byName(row.engine),
    host: row.host,
    port: row.port,
    database: row.database,
    username: row.username,
    tlsMode: TlsMode.values.byName(row.tlsMode),
    color: row.color,
    savePassword: row.savePassword,
  );
}

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.connectionId,
    required this.sql,
    required this.executedAt,
    required this.duration,
    this.rowCount,
    this.error,
  });

  final int id;
  final String connectionId;
  final String sql;
  final DateTime executedAt;
  final Duration duration;
  final int? rowCount;
  final String? error;
}

class HistoryRepository {
  HistoryRepository(this._db);

  final AppDatabase _db;

  /// Entries kept per connection; older ones are pruned on insert.
  static const _keepPerConnection = 1000;

  Future<void> add({
    required String connectionId,
    required String sql,
    required Duration duration,
    int? rowCount,
    String? error,
  }) async {
    await _db
        .into(_db.queryHistory)
        .insert(
          QueryHistoryCompanion.insert(
            connectionId: connectionId,
            sql: sql,
            executedAt: DateTime.now(),
            durationMs: duration.inMilliseconds,
            rowCount: Value(rowCount),
            error: Value(error),
          ),
        );
    await _db.customStatement(
      'DELETE FROM query_history WHERE connection_id = ? AND id NOT IN '
      '(SELECT id FROM query_history WHERE connection_id = ? '
      'ORDER BY id DESC LIMIT $_keepPerConnection)',
      [connectionId, connectionId],
    );
  }

  Stream<List<HistoryEntry>> watch(String connectionId, {String filter = ''}) {
    final query = _db.select(_db.queryHistory)
      ..where((h) => h.connectionId.equals(connectionId))
      ..orderBy([(h) => OrderingTerm.desc(h.id)])
      ..limit(500);
    if (filter.isNotEmpty) {
      query.where((h) => h.sql.like('%$filter%'));
    }
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          HistoryEntry(
            id: r.id,
            connectionId: r.connectionId,
            sql: r.sql,
            executedAt: r.executedAt,
            duration: Duration(milliseconds: r.durationMs),
            rowCount: r.rowCount,
            error: r.error,
          ),
      ],
    );
  }

  Future<void> clear(String connectionId) => (_db.delete(
    _db.queryHistory,
  )..where((h) => h.connectionId.equals(connectionId))).go();
}
