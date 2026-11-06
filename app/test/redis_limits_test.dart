import 'dart:convert';
import 'dart:io';

import 'package:db_client/drivers/driver.dart';
import 'package:db_client/drivers/redis/redis_driver.dart';
import 'package:db_client/drivers/redis/resp.dart';
import 'package:db_client/features/keyvalue/redis_view.dart';
import 'package:flutter_test/flutter_test.dart';

/// An in-process Redis with one huge string and many keys, for the caps.
class _FakeRedis {
  _FakeRedis(this.keyCount, this.big);

  final int keyCount;
  final String big;
  late final ServerSocket _server;
  int get port => _server.port;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_serve);
  }

  Future<void> stop() => _server.close();

  void _serve(Socket socket) {
    final parser = RespParser();
    socket.listen((data) {
      for (final request in parser.add(data)) {
        final args = (request as List).cast<String>();
        final reply = switch (args.first.toUpperCase()) {
          'PING' => 'PONG',
          'KEYS' => [for (var i = 0; i < keyCount; i++) 'key:$i'],
          'TYPE' => 'string',
          'TTL' => -1,
          'MEMORY' => const RespError('ERR unknown command'),
          'STRLEN' => big.length,
          'GET' => big,
          'GETRANGE' => big.substring(
            int.parse(args[2]),
            int.parse(args[3]) + 1,
          ),
          _ => RespError("ERR unknown command '${args.first}'"),
        };
        socket.add(_encode(reply));
      }
    });
  }

  static List<int> _encode(Object? reply) => switch (reply) {
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

ConnectionConfig _config(int port) => ConnectionConfig(
  id: 't',
  name: 't',
  engine: DatabaseEngine.redis,
  host: '127.0.0.1',
  port: port,
  database: '0',
  username: '',
  tlsMode: TlsMode.disable,
  color: 0,
  savePassword: false,
);

void main() {
  group('RespParser with maxArrayItems', () {
    test('keeps the first items, marks the rest, stays in sync', () {
      final bytes = utf8.encode(
        '*5\r\n:1\r\n\$1\r\na\r\n*3\r\n:1\r\n:2\r\n:3\r\n:4\r\n:5\r\n'
        '+OK\r\n',
      );
      for (var split = 1; split < bytes.length; split++) {
        final parser = RespParser(maxArrayItems: 2);
        final replies = [
          ...parser.add(bytes.sublist(0, split)),
          ...parser.add(bytes.sublist(split)),
        ];
        expect(replies, [
          [1, 'a', const RespOmitted(3)],
          'OK',
        ], reason: 'split at $split');
      }
    });

    test('caps nested arrays too', () {
      final replies = RespParser(maxArrayItems: 2)
          .add(utf8.encode('*1\r\n*3\r\n:1\r\n:2\r\n:3\r\n'));
      expect(replies, [
        [
          [1, 2, const RespOmitted(1)],
        ],
      ]);
    });

    test('a reply fed byte by byte', () {
      final bytes = encodeCommand([for (var i = 0; i < 50; i++) 'v$i']);
      final parser = RespParser(maxArrayItems: 10);
      final replies = [
        for (final b in bytes) ...parser.add([b]),
      ];
      expect(replies, hasLength(1));
      expect(replies.single, [
        for (var i = 0; i < 10; i++) 'v$i',
        const RespOmitted(40),
      ]);
    });
  });

  test('formatRedisReply shows omissions and stops at maxChars', () {
    expect(formatRedisReply(['a', 'b', const RespOmitted(7)]), '''
1) "a"
2) "b"
   … 7 more''');
    final long = formatRedisReply([
      for (var i = 0; i < 1000; i++) 'value $i',
    ], maxChars: 200);
    expect(long.length, lessThan(300));
    expect(long, endsWith('… output cut at 200 characters'));
    final string = formatRedisReply('x' * 10000, maxChars: 100);
    expect(string, startsWith('"${'x' * 100}"'));
    expect(string, contains('output cut'));
  });

  test('redisDisplayText pretty-prints JSON and caps the length', () {
    expect(redisDisplayText('{"a":1}'), ('{\n  "a": 1\n}', false));
    expect(redisDisplayText('{"a":', tryJson: true), ('{"a":', false));
    expect(redisDisplayText('{"a":1}', tryJson: false), ('{"a":1}', false));
    expect(redisDisplayText('abcdef', maxChars: 3), ('abc', true));
  });

  group('driver', () {
    late _FakeRedis server;

    setUp(() async {
      server = _FakeRedis(
        RedisDriver.consoleMaxArrayItems + 2500,
        'y' * (RedisDriver.stringPreviewBytes + 10),
      );
      await server.start();
    });

    tearDown(() => server.stop());

    test('console caps huge array replies and stays in sync', () async {
      final driver = RedisDriver(_config(server.port));
      await driver.connect(null);
      final reply = await driver.console(0, ['KEYS', '*']) as List;
      expect(reply, hasLength(RedisDriver.consoleMaxArrayItems + 1));
      expect(reply.first, 'key:0');
      expect(reply.last, const RespOmitted(2500));
      expect(await driver.console(0, ['PING']), 'PONG');
      // Browsing isn't capped.
      expect(
        await driver.run(0, ['KEYS', '*']) as List,
        hasLength(RedisDriver.consoleMaxArrayItems + 2500),
      );
      await driver.close();
    });

    test('a large string is read in part', () async {
      final driver = RedisDriver(_config(server.port));
      await driver.connect(null);
      final data = await driver.read(0, 'big');
      expect(data.length, RedisDriver.stringPreviewBytes + 10);
      expect(data.text, hasLength(RedisDriver.stringPreviewBytes));
      expect(data.textTruncated, isTrue);
      await driver.close();
    });
  });
}
