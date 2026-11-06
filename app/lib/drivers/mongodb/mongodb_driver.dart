import 'dart:async';
import 'dart:io';

import 'package:mongo_dart/mongo_dart.dart' as mongo;

import '../document.dart';
import '../driver.dart';

/// MongoDB via mongo_dart (server 3.6+).
///
/// A mongo_dart `Db` is bound to one database (its connection manager can't
/// be shared, and switching `databaseName` would race concurrent
/// operations), so one is opened per database on first use; all
/// authenticate against the same auth database. Only a few are kept open.
class MongoDriver implements DocumentDriver {
  MongoDriver(this.config);

  @override
  final ConnectionConfig config;

  static const _openTimeout = Duration(seconds: 20);

  /// Open database connections kept; idle ones beyond this are closed,
  /// least recently used first.
  static const _maxOpen = 3;

  String? _password;

  /// Open connections, least recently used first.
  final _dbs = <String, Future<mongo.Db>>{};

  /// Operations running per database.
  final _busy = <String, int>{};

  /// Database used for connect, ping and listing databases; kept open.
  String get _home => config.database.isEmpty ? 'admin' : config.database;

  bool get _srv => config.options['srv'] == 'true';

  /// Database used for authentication: explicit option, else the
  /// connection's database (MongoDB's own default).
  String get _authSource =>
      config.options['authSource'] ??
      (config.database.isEmpty ? 'admin' : config.database);

  String _uriFor(String database) {
    final host = config.host;
    final hasPort = host.contains(',') || RegExp(r':\d+$').hasMatch(host);
    final hosts = _srv || hasPort ? host : '$host:${config.port}';
    final auth = config.username.isEmpty
        ? ''
        : '${Uri.encodeComponent(config.username)}:'
              '${Uri.encodeComponent(_password ?? '')}@';
    final params = [
      if (config.username.isNotEmpty)
        'authSource=${Uri.encodeQueryComponent(_authSource)}',
      if (config.options['params'] case final p? when p.isNotEmpty) p,
    ];
    return '${_srv ? 'mongodb+srv' : 'mongodb'}://$auth$hosts/'
        '${Uri.encodeComponent(database)}'
        '${params.isEmpty ? '' : '?${params.join('&')}'}';
  }

  Future<mongo.Db> _db(String database) => _dbs.putIfAbsent(database, () async {
    try {
      final db = await mongo.Db.create(_uriFor(database));
      await db
          .open(
            secure: config.tlsMode != TlsMode.disable,
            tlsAllowInvalidCertificates: config.tlsMode == TlsMode.require,
          )
          .timeout(_openTimeout);
      return db;
    } catch (_) {
      // Let the next call retry instead of caching the failure.
      unawaited(_dbs.remove(database)?.then((_) {}, onError: (_) {}));
      rethrow;
    }
  });

  Future<mongo.DbCollection> _collection(String database, String name) async =>
      (await _db(database)).collection(name);

  @override
  Future<void> connect(String? password) async {
    _password = password;
    await _guard(() async {
      final db = await _db(_home);
      await db.runCommand({'ping': 1});
    });
  }

  @override
  Future<void> close() async {
    final dbs = _dbs.values.toList();
    _dbs.clear();
    for (final db in dbs) {
      try {
        await (await db).close();
      } catch (_) {
        // Already failed or closed.
      }
    }
  }

  @override
  Future<Duration> ping() => _guard(() async {
    final watch = Stopwatch()..start();
    final db = await _db(_home);
    await db.runCommand({'ping': 1});
    return watch.elapsed;
  });

  /// mongo_dart can't interrupt a running operation.
  @override
  Future<void> cancel() async {}

  @override
  Future<List<String>> listDatabases() => _guard(() async {
    final db = await _db(_home);
    try {
      final names = [for (final name in await db.listDatabases()) '$name']
        ..sort();
      return names;
    } on Object {
      // Users limited to one database may not list the others.
      return [config.database];
    }
  });

  @override
  Future<List<CollectionInfo>> listCollections(String database) =>
      _guardIn(database, () async {
        final infos = await (await _db(database)).getCollectionInfos();
        return [
          for (final info in infos)
            if (info['name'] case final String name
                when !name.startsWith('system.'))
              CollectionInfo(
                name: name,
                kind: switch (info['type']) {
                  'view' => CollectionKind.view,
                  'timeseries' => CollectionKind.timeseries,
                  _ => CollectionKind.collection,
                },
              ),
        ]..sort((a, b) => a.name.compareTo(b.name));
      });

  @override
  Future<DocumentPage> find(
    String database,
    String collection, {
    Map<String, dynamic> filter = const {},
    Map<String, dynamic>? projection,
    Map<String, dynamic>? sort,
    int skip = 0,
    int limit = 20,
  }) => _guardIn(database, () async {
    final watch = Stopwatch()..start();
    final coll = await _collection(database, collection);
    // One extra document tells whether there are more.
    final docs = await coll
        .modernFind(
          filter: filter,
          projection: projection == null || projection.isEmpty
              ? null
              : Map<String, Object>.from(projection),
          sort: sort == null || sort.isEmpty
              ? null
              : Map<String, Object>.from(sort),
          skip: skip > 0 ? skip : null,
          limit: limit + 1,
        )
        .toList();
    return DocumentPage(
      documents: docs.take(limit).toList(),
      elapsed: watch.elapsed,
      hasMore: docs.length > limit,
    );
  });

  @override
  Future<DocumentPage> aggregate(
    String database,
    String collection,
    List<Map<String, dynamic>> pipeline, {
    int limit = 20,
  }) => _guardIn(database, () async {
    final watch = Stopwatch()..start();
    final coll = await _collection(database, collection);
    final docs = await coll.modernAggregate([
      ...pipeline,
      {r'$limit': limit + 1},
    ]).toList();
    return DocumentPage(
      documents: docs.take(limit).toList(),
      elapsed: watch.elapsed,
      hasMore: docs.length > limit,
    );
  });

  @override
  Future<int> count(
    String database,
    String collection, [
    Map<String, dynamic> filter = const {},
  ]) => _guardIn(
    database,
    () async => (await _collection(database, collection)).count(filter),
  );

  @override
  Future<List<Map<String, dynamic>>> listIndexes(
    String database,
    String collection,
  ) => _guardIn(
    database,
    () async => (await _collection(database, collection)).getIndexes(),
  );

  @override
  Future<Object?> insertOne(
    String database,
    String collection,
    Map<String, dynamic> document,
  ) => _guardIn(database, () async {
    final result = await (await _collection(
      database,
      collection,
    )).insertOne(document);
    _checkWrite(result);
    return result.id ?? document['_id'];
  });

  @override
  Future<void> updateOne(
    String database,
    String collection,
    Map<String, dynamic> filter,
    Map<String, dynamic> update,
  ) => _guardIn(database, () async {
    final result = await (await _collection(
      database,
      collection,
    )).updateOne(filter, update);
    _checkWrite(result);
    if (result.nMatched == 0) {
      throw const DriverException(
        'No document matched: it may have been deleted or its _id changed. '
        'Refresh and try again.',
      );
    }
  });

  @override
  Future<void> deleteOne(
    String database,
    String collection,
    Map<String, dynamic> filter,
  ) => _guardIn(database, () async {
    final result = await (await _collection(
      database,
      collection,
    )).deleteOne(filter);
    _checkWrite(result);
    if (result.nRemoved == 0) {
      throw const DriverException(
        'No document matched: it may already have been deleted.',
      );
    }
  });

  void _checkWrite(mongo.WriteResult result) {
    if (result.writeError case final error?) {
      throw DriverException(
        error.errmsg ?? 'Write failed',
        code: error.code?.toString(),
      );
    }
  }

  /// [_guard] for an operation on [database]: its connection is marked in
  /// use meanwhile, and idle ones beyond [_maxOpen] are closed after.
  Future<T> _guardIn<T>(String database, Future<T> Function() body) async {
    _busy[database] = (_busy[database] ?? 0) + 1;
    // Most recently used last.
    if (_dbs.remove(database) case final db?) _dbs[database] = db;
    try {
      return await _guard(body);
    } finally {
      if ((_busy[database] = _busy[database]! - 1) == 0) _busy.remove(database);
      _closeIdle();
    }
  }

  /// Closes the least recently used connections beyond [_maxOpen], except
  /// the home database's and any in use.
  void _closeIdle() {
    if (_dbs.length <= _maxOpen) return;
    final idle = [
      for (final name in _dbs.keys)
        if (name != _home && !_busy.containsKey(name)) name,
    ];
    for (final name in idle.take(_dbs.length - _maxOpen)) {
      final db = _dbs.remove(name)!;
      unawaited(
        db.then((db) => db.close()).then((_) {}, onError: (Object _) {}),
      );
    }
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on DriverException {
      rethrow;
    } on mongo.MongoDartError catch (e) {
      throw DriverException(e.message, code: e.errorCodeName ?? e.errorCode);
    } on SocketException catch (e) {
      throw DriverException(
        'Cannot reach ${config.host} — ${e.osError?.message ?? e.message}',
      );
    } on TimeoutException {
      throw DriverException('Timed out connecting to ${config.host}');
    } on Map catch (e) {
      // Server replies with ok: 0 surface as maps.
      throw DriverException(
        '${e['errmsg'] ?? e['err'] ?? e}',
        code: '${e['codeName'] ?? e['code'] ?? ''}'.ifEmpty,
      );
    } catch (e) {
      throw DriverException('$e');
    }
  }
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}
