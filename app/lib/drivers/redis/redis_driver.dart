import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../driver.dart';
import '../key_value.dart';
import 'resp.dart';

/// One Redis connection with pipelining: commands are written immediately
/// and replies matched to them in order.
class RedisConnection {
  RedisConnection._(this._socket) {
    _socket.listen(
      (data) {
        for (final reply in _parser.add(data)) {
          if (_pending.isNotEmpty) _pending.removeFirst().complete(reply);
        }
      },
      onError: (Object e) => _fail(DriverException('Connection error: $e')),
      onDone: () => _fail(const DriverException('Connection closed')),
    );
  }

  static Future<RedisConnection> open(ConnectionConfig config) async {
    try {
      final socket = config.tlsMode == TlsMode.disable
          ? await Socket.connect(
              config.host,
              config.port,
              timeout: const Duration(seconds: 15),
            )
          : await SecureSocket.connect(
              config.host,
              config.port,
              timeout: const Duration(seconds: 15),
              // "Require" encrypts without verifying the certificate.
              onBadCertificate: (_) => config.tlsMode == TlsMode.require,
            );
      socket.setOption(SocketOption.tcpNoDelay, true);
      return RedisConnection._(socket);
    } on SocketException catch (e) {
      throw DriverException(
        'Cannot reach ${config.host}:${config.port} — '
        '${e.osError?.message ?? e.message}',
      );
    } on HandshakeException catch (e) {
      throw DriverException('TLS handshake failed: ${e.message}');
    }
  }

  final Socket _socket;
  final _parser = RespParser();
  final _pending = Queue<Completer<Object?>>();
  DriverException? _closed;

  /// Sends [args]; the reply may be a [RespError] (not thrown).
  Future<Object?> send(List<String> args) {
    if (_closed case final error?) return Future.error(error);
    final completer = Completer<Object?>();
    _pending.add(completer);
    _socket.add(encodeCommand(args));
    return completer.future;
  }

  void _fail(DriverException error) {
    _closed ??= error;
    while (_pending.isNotEmpty) {
      _pending.removeFirst().completeError(error);
    }
  }

  void close() {
    _fail(const DriverException('Connection closed'));
    _socket.destroy();
  }
}

/// Redis (standalone or a single node; cluster redirects are not followed).
///
/// Browsing uses one connection; the console gets its own, so a blocking
/// command there (BLPOP, SUBSCRIBE…) can't stall browsing and can be
/// cancelled by closing it.
class RedisDriver implements KeyValueDriver {
  RedisDriver(this.config);

  @override
  final ConnectionConfig config;

  String? _password;
  RedisConnection? _browser;
  int _browserDb = 0;
  RedisConnection? _console;
  int _consoleDb = 0;

  int get _defaultDb => int.tryParse(config.database) ?? 0;

  /// Opens, authenticates and selects the default database.
  Future<RedisConnection> _open() async {
    final connection = await RedisConnection.open(config);
    try {
      if (_password?.isNotEmpty ?? false) {
        _check(
          await connection.send([
            'AUTH',
            if (config.username.isNotEmpty) config.username,
            _password!,
          ]),
        );
      }
      if (_defaultDb != 0) {
        _check(await connection.send(['SELECT', '$_defaultDb']));
      }
      _check(await connection.send(['PING']));
      return connection;
    } catch (_) {
      connection.close();
      rethrow;
    }
  }

  static Object? _check(Object? reply) {
    if (reply is RespError) {
      final code = reply.message.split(' ').first;
      throw DriverException(reply.message, code: code);
    }
    return reply;
  }

  @override
  Future<void> connect(String? password) async {
    _password = password;
    _browser = await _open();
    _browserDb = _defaultDb;
  }

  @override
  Future<void> close() async {
    _browser?.close();
    _console?.close();
    _browser = null;
    _console = null;
  }

  @override
  Future<Duration> ping() async {
    final watch = Stopwatch()..start();
    await run(_browserDb, ['PING']);
    return watch.elapsed;
  }

  /// Aborts a running console command by dropping its connection; the next
  /// console command reconnects.
  @override
  Future<void> cancel() async {
    _console?.close();
    _console = null;
  }

  /// Serializes sends on the browser connection (see [_send]).
  Future<void> _sendLock = Future.value();

  /// Sends [args] on the browser connection in [db]. Sends take turns, and
  /// a database switch waits for its SELECT to succeed before the command
  /// goes out, so a command never runs in the wrong database. Replies are
  /// still pipelined: a send doesn't wait for earlier replies.
  Future<Object?> _send(int db, List<String> args) async {
    final connection = _browser;
    if (connection == null) throw const DriverException('Not connected');
    final previous = _sendLock;
    final done = Completer<void>();
    _sendLock = done.future;
    final Future<Object?> reply;
    try {
      await previous;
      if (db != _browserDb) {
        _check(await connection.send(['SELECT', '$db']));
        _browserDb = db;
      }
      reply = connection.send(args);
    } finally {
      done.complete();
    }
    return reply;
  }

  @override
  Future<Object?> run(int db, List<String> args) async =>
      _check(await _send(db, args));

  @override
  Future<Object?> console(int db, List<String> args) async {
    var connection = _console;
    if (connection == null) {
      connection = _console = await _open();
      _consoleDb = _defaultDb;
    }
    if (db != _consoleDb) {
      final selected = await connection.send(['SELECT', '$db']);
      if (selected is RespError) return selected;
      _consoleDb = db;
    }
    final reply = await connection.send(args);
    if (args.length > 1 &&
        args.first.toUpperCase() == 'SELECT' &&
        reply is! RespError) {
      _consoleDb = int.tryParse(args[1]) ?? _consoleDb;
    }
    return reply;
  }

  @override
  Future<int> databaseCount() async {
    try {
      final reply = await run(_browserDb, ['CONFIG', 'GET', 'databases']);
      if (reply is List && reply.length == 2) {
        return int.tryParse('${reply[1]}') ?? 16;
      }
    } on DriverException {
      // CONFIG is often disabled on managed Redis.
    }
    return 16;
  }

  @override
  Future<Map<int, int>> keyCounts() async {
    final info = await run(_browserDb, ['INFO', 'keyspace']) as String? ?? '';
    return {
      for (final match in RegExp(
        r'^db(\d+):keys=(\d+)',
        multiLine: true,
      ).allMatches(info))
        int.parse(match.group(1)!): int.parse(match.group(2)!),
    };
  }

  @override
  Future<KeyPage> scan(
    int db, {
    String pattern = '*',
    String cursor = '0',
    int count = 200,
  }) async {
    final names = <String>[];
    var next = cursor;
    // SCAN may return few or no keys per step on sparse matches; keep going
    // (bounded) until a page is filled or the scan completes.
    for (var step = 0; step < 50; step++) {
      final reply = await run(db, [
        'SCAN',
        next,
        'MATCH',
        pattern.isEmpty ? '*' : pattern,
        'COUNT',
        '$count',
      ]) as List;
      next = '${reply[0]}';
      names.addAll((reply[1] as List).cast<String>());
      if (next == '0' || names.length >= count) break;
    }
    // Type and TTL of every key, pipelined.
    final types = [
      for (final n in names) _send(db, ['TYPE', n]),
    ];
    final ttls = [
      for (final n in names) _send(db, ['TTL', n]),
    ];
    return KeyPage(
      keys: [
        for (final (i, name) in names.indexed)
          KeyInfo(
            name: name,
            type: '${await types[i]}',
            ttl: switch (await ttls[i]) {
              final int ttl => ttl,
              _ => -1,
            },
          ),
      ],
      cursor: next,
    );
  }

  @override
  Future<KeyData> read(int db, String key, {int limit = 500}) async {
    final type = '${await run(db, ['TYPE', key])}';
    if (type == 'none') {
      throw DriverException('Key "$key" no longer exists');
    }
    final ttl = await run(db, ['TTL', key]) as int;
    int? memory;
    try {
      memory = await run(db, ['MEMORY', 'USAGE', key]) as int?;
    } on DriverException {
      // MEMORY may be disabled.
    }

    Future<int> size(String command) async =>
        await run(db, [command, key]) as int;

    /// HSCAN/SSCAN until [limit] elements or the end.
    Future<List<String>> scanAll(String command) async {
      final out = <String>[];
      var cursor = '0';
      do {
        final reply =
            await run(db, [command, key, cursor, 'COUNT', '$limit']) as List;
        cursor = '${reply[0]}';
        out.addAll((reply[1] as List).cast<String>());
      } while (cursor != '0' &&
          out.length < limit * (command == 'HSCAN' ? 2 : 1));
      return out;
    }

    List<(String, String)> pairsOf(List<String> flat, int max) => [
      for (var i = 0; i + 1 < flat.length && i ~/ 2 < max; i += 2)
        (flat[i], flat[i + 1]),
    ];

    switch (type) {
      case 'string':
        return KeyData(
          key: key,
          type: type,
          ttl: ttl,
          memoryBytes: memory,
          length: await size('STRLEN'),
          text: await run(db, ['GET', key]) as String?,
        );
      case 'hash':
        return KeyData(
          key: key,
          type: type,
          ttl: ttl,
          memoryBytes: memory,
          length: await size('HLEN'),
          pairs: pairsOf(await scanAll('HSCAN'), limit),
        );
      case 'list':
        return KeyData(
          key: key,
          type: type,
          ttl: ttl,
          memoryBytes: memory,
          length: await size('LLEN'),
          items: (await run(db, ['LRANGE', key, '0', '${limit - 1}']) as List)
              .cast<String>(),
        );
      case 'set':
        final members = await scanAll('SSCAN');
        return KeyData(
          key: key,
          type: type,
          ttl: ttl,
          memoryBytes: memory,
          length: await size('SCARD'),
          items: members.take(limit).toList(),
        );
      case 'zset':
        return KeyData(
          key: key,
          type: type,
          ttl: ttl,
          memoryBytes: memory,
          length: await size('ZCARD'),
          pairs: pairsOf(
            (await run(db, [
              'ZRANGE',
              key,
              '0',
              '${limit - 1}',
              'WITHSCORES',
            ]) as List).cast<String>(),
            limit,
          ),
        );
      case 'stream':
        final raw = await run(db, [
          'XREVRANGE',
          key,
          '+',
          '-',
          'COUNT',
          '$limit',
        ]) as List;
        return KeyData(
          key: key,
          type: type,
          ttl: ttl,
          memoryBytes: memory,
          length: await size('XLEN'),
          entries: [
            for (final entry in raw.cast<List>())
              ('${entry[0]}', (entry[1] as List).cast<String>()),
          ],
        );
      case 'ReJSON-RL':
        final text = await run(db, ['JSON.GET', key]) as String?;
        return KeyData(
          key: key,
          type: type,
          ttl: ttl,
          memoryBytes: memory,
          length: text?.length ?? 0,
          text: text,
        );
      default:
        return KeyData(
          key: key,
          type: type,
          ttl: ttl,
          memoryBytes: memory,
          length: 0,
        );
    }
  }
}
