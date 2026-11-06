import 'dart:convert';

import 'package:db_client/drivers/redis/resp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodes commands as bulk string arrays, UTF-8 lengths', () {
    expect(
      utf8.decode(encodeCommand(['SET', 'k', 'é'])),
      '*3\r\n\$3\r\nSET\r\n\$1\r\nk\r\n\$2\r\né\r\n',
    );
  });

  group('RespParser', () {
    test('every reply type', () {
      final parser = RespParser();
      final replies = parser.add(
        utf8.encode(
          '+OK\r\n-ERR wrong type\r\n:42\r\n\$5\r\nhello\r\n\$-1\r\n'
          '*2\r\n\$1\r\na\r\n*1\r\n:1\r\n*-1\r\n*0\r\n',
        ),
      );
      expect(replies, hasLength(8));
      expect(replies[0], 'OK');
      expect(replies[1], isA<RespError>());
      expect((replies[1] as RespError).message, 'ERR wrong type');
      expect(replies[2], 42);
      expect(replies[3], 'hello');
      expect(replies[4], isNull);
      expect(replies[5], [
        'a',
        [1],
      ]);
      expect(replies[6], isNull);
      expect(replies[7], isEmpty);
    });

    test('replies split across chunks at any byte', () {
      final bytes = utf8.encode('*2\r\n\$3\r\nfoo\r\n\$4\r\nbär\r\n:7\r\n');
      for (var split = 1; split < bytes.length; split++) {
        final parser = RespParser();
        final replies = [
          ...parser.add(bytes.sublist(0, split)),
          ...parser.add(bytes.sublist(split)),
        ];
        expect(replies, [
          ['foo', 'bär'],
          7,
        ], reason: 'split at $split');
      }
    });

    test('bulk strings may contain CRLF', () {
      expect(RespParser().add(utf8.encode('\$4\r\na\r\nb\r\n')), ['a\r\nb']);
    });
  });

  test('splits command lines like redis-cli', () {
    expect(splitRedisCommand('SET  key   value'), ['SET', 'key', 'value']);
    expect(splitRedisCommand('SET k "a b\\n\\x41"'), ['SET', 'k', 'a b\nA']);
    // Like redis-cli, a closing quote must end the argument.
    expect(() => splitRedisCommand("SET k 'it''s'"), throwsFormatException);
    expect(splitRedisCommand("SET k 'a\\'b'"), ['SET', 'k', "a'b"]);
    expect(splitRedisCommand('GET ""'), ['GET', '']);
    expect(splitRedisCommand('   '), isEmpty);
    expect(() => splitRedisCommand('GET "x'), throwsFormatException);
  });

  test('formats replies like redis-cli', () {
    expect(formatRedisReply(null), '(nil)');
    expect(formatRedisReply(3), '(integer) 3');
    expect(formatRedisReply('a"b'), r'"a\"b"');
    expect(formatRedisReply(const RespError('ERR x')), '(error) ERR x');
    expect(formatRedisReply([]), '(empty array)');
    expect(
      formatRedisReply([
        'a',
        ['b', 2],
      ]),
      '1) "a"\n2) 1) "b"\n   2) (integer) 2',
    );
  });
}
