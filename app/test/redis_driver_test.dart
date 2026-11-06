import 'dart:io';

import 'package:db_client/drivers/driver.dart';
import 'package:db_client/drivers/redis/redis_driver.dart';
import 'package:db_client/drivers/redis/resp.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal in-process Redis speaking RESP2, enough to exercise the driver:
/// per-connection selected db, AUTH, and a few data commands.
class _FakeRedis {
  _FakeRedis(this.password);

  final String? password;
  final dbs = <int, Map<String, String>>{};
  late final ServerSocket _server;
  int get port => _server.port;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_serve);
  }

  Future<void> stop() => _server.close();

  void _serve(Socket socket) {
    final parser = RespParser();
    var db = 0;
    var authed = password == null;
    socket.listen((data) {
      for (final request in parser.add(data)) {
        final args = (request as List).cast<String>();
        final name = args.first.toUpperCase();
        Object? reply;
        if (!authed && name != 'AUTH') {
          reply = const RespError('NOAUTH Authentication required.');
        } else {
          final store = dbs.putIfAbsent(db, () => {});
          reply = switch (name) {
            'AUTH' =>
              args.last == password
                  ? (() {
                      authed = true;
                      return 'OK';
                    })()
                  : const RespError('WRONGPASS invalid username-password pair'),
            'PING' => 'PONG',
            'SELECT' =>
              (int.tryParse(args[1]) ?? 99) < 16
                  ? (() {
                      db = int.parse(args[1]);
                      return 'OK';
                    })()
                  : const RespError('ERR DB index is out of range'),
            'SET' => (() {
              store[args[1]] = args[2];
              return 'OK';
            })(),
            'GET' => store[args[1]],
            'STRLEN' => store[args[1]]?.length ?? 0,
            'TYPE' => store.containsKey(args[1]) ? 'string' : 'none',
            'TTL' => store.containsKey(args[1]) ? -1 : -2,
            'MEMORY' => const RespError('ERR unknown command'),
            'SCAN' => ['0', store.keys.toList()],
            'CONFIG' => ['databases', '16'],
            'INFO' =>
              '# Keyspace\r\n${[for (final e in dbs.entries)
                if (e.value.isNotEmpty) 'db${e.key}:keys=${e.value.length},expires=0'].join('\r\n')}\r\n',
            _ => RespError("ERR unknown command '${args.first}'"),
          };
        }
        socket.add(_encode(reply));
      }
    });
  }

  static List<int> _encode(Object? reply) => switch (reply) {
    null => '\$-1\r\n'.codeUnits,
    RespError() => '-${reply.message}\r\n'.codeUnits,
    int() => ':$reply\r\n'.codeUnits,
    String() => encodeCommand([reply]).sublist('*1\r\n'.length),
    List() => [
      ...'*${reply.length}\r\n'.codeUnits,
      for (final item in reply) ..._encode(item),
    ],
    _ => throw StateError('$reply'),
  };
}

ConnectionConfig _config(int port, {String database = '0'}) => ConnectionConfig(
  id: 't',
  name: 't',
  engine: DatabaseEngine.redis,
  host: '127.0.0.1',
  port: port,
  database: database,
  username: '',
  tlsMode: TlsMode.disable,
  color: 0,
  savePassword: false,
);

void main() {
  late _FakeRedis server;

  setUp(() async {
    server = _FakeRedis('secret');
    await server.start();
  });

  tearDown(() => server.stop());

  test('authenticates, and a wrong password fails to connect', () async {
    final driver = RedisDriver(_config(server.port));
    await driver.connect('secret');
    expect(await driver.run(0, ['PING']), 'PONG');
    await driver.close();

    final wrong = RedisDriver(_config(server.port));
    await expectLater(
      wrong.connect('nope'),
      throwsA(
        isA<DriverException>().having((e) => e.code, 'code', 'WRONGPASS'),
      ),
    );
  });

  test('commands run in the database they name, even interleaved', () async {
    final driver = RedisDriver(_config(server.port));
    await driver.connect('secret');
    // Fired together: each must land in its own database.
    await Future.wait([
      driver.run(1, ['SET', 'k', 'one']),
      driver.run(2, ['SET', 'k', 'two']),
      driver.run(1, ['SET', 'j', 'one-j']),
      driver.run(0, ['SET', 'k', 'zero']),
    ]);
    expect(server.dbs[0], {'k': 'zero'});
    expect(server.dbs[1], {'k': 'one', 'j': 'one-j'});
    expect(server.dbs[2], {'k': 'two'});
    expect(await driver.keyCounts(), {0: 1, 1: 2, 2: 1});
    await driver.close();
  });

  test('a failed database switch never runs the command elsewhere', () async {
    final driver = RedisDriver(_config(server.port));
    await driver.connect('secret');
    await expectLater(
      driver.run(42, ['SET', 'oops', 'x']),
      throwsA(isA<DriverException>()),
    );
    expect(server.dbs.values.any((s) => s.containsKey('oops')), isFalse);
    // Still usable, still in the original database.
    await driver.run(0, ['SET', 'fine', 'y']);
    expect(server.dbs[0], {'fine': 'y'});
    await driver.close();
  });

  test('scan pipelines TYPE and TTL; read gets a string', () async {
    final driver = RedisDriver(_config(server.port));
    await driver.connect('secret');
    for (var i = 0; i < 30; i++) {
      await driver.run(3, ['SET', 'user:$i', 'v$i']);
    }
    final page = await driver.scan(3);
    expect(page.done, isTrue);
    expect(page.keys, hasLength(30));
    expect(page.keys.every((k) => k.type == 'string' && k.ttl == -1), isTrue);

    final data = await driver.read(3, 'user:7');
    expect(data.text, 'v7');
    expect(data.length, 2);
    expect(data.memoryBytes, isNull); // MEMORY unsupported here: tolerated
    await expectLater(
      driver.read(3, 'missing'),
      throwsA(isA<DriverException>()),
    );
    await driver.close();
  });

  test('console returns error replies instead of throwing', () async {
    final driver = RedisDriver(_config(server.port));
    await driver.connect('secret');
    expect(await driver.console(0, ['NOPE']), isA<RespError>());
    expect(await driver.console(5, ['SET', 'c', '1']), 'OK');
    expect(server.dbs[5], {'c': '1'});
    await driver.close();
  });
}
