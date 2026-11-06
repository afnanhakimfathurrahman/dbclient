/// Redis wire protocol (RESP2) pieces, free of I/O so they can be tested:
/// command encoding, an incremental reply parser, redis-cli style command
/// splitting and reply formatting.
library;

import 'dart:convert';
import 'dart:typed_data';

/// An error reply (`-ERR …`). Returned by the parser, thrown by clients.
class RespError implements Exception {
  const RespError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Encodes a command as a RESP array of bulk strings.
Uint8List encodeCommand(List<String> args) {
  final out = BytesBuilder(copy: false)
    ..add(ascii.encode('*${args.length}\r\n'));
  for (final arg in args) {
    final bytes = utf8.encode(arg);
    out
      ..add(ascii.encode('\$${bytes.length}\r\n'))
      ..add(bytes)
      ..add(const [13, 10]);
  }
  return out.toBytes();
}

/// Parses replies from a byte stream fed in arbitrary chunks.
///
/// Replies decode to: `String` (simple and bulk strings, UTF-8 with
/// malformed bytes replaced), `int`, `null` (nil), `List<Object?>`, or
/// [RespError].
class RespParser {
  final _buffer = BytesBuilder();
  Uint8List _data = Uint8List(0);
  int _pos = 0;

  /// Adds bytes and returns every reply now complete, in order.
  List<Object?> add(List<int> chunk) {
    if (_pos > 0) {
      // Drop consumed bytes before appending.
      _buffer.add(Uint8List.sublistView(_data, _pos));
      _pos = 0;
    } else if (_data.isNotEmpty) {
      _buffer.add(_data);
    }
    _buffer.add(chunk);
    _data = _buffer.takeBytes();

    final replies = <Object?>[];
    while (true) {
      final start = _pos;
      final (complete, value) = _read();
      if (!complete) {
        _pos = start;
        break;
      }
      replies.add(value);
    }
    return replies;
  }

  /// Reads one reply at [_pos]; `(false, null)` if more bytes are needed.
  (bool, Object?) _read() {
    final line = _line();
    if (line == null) return (false, null);
    final payload = line.substring(1);
    switch (line[0]) {
      case '+':
        return (true, payload);
      case '-':
        return (true, RespError(payload));
      case ':':
        return (true, int.parse(payload));
      case r'$':
        final length = int.parse(payload);
        if (length < 0) return (true, null);
        if (_data.length < _pos + length + 2) return (false, null);
        final text = utf8.decode(
          Uint8List.sublistView(_data, _pos, _pos + length),
          allowMalformed: true,
        );
        _pos += length + 2;
        return (true, text);
      case '*':
        final count = int.parse(payload);
        if (count < 0) return (true, null);
        final items = <Object?>[];
        for (var i = 0; i < count; i++) {
          final (complete, value) = _read();
          if (!complete) return (false, null);
          items.add(value);
        }
        return (true, items);
      default:
        throw FormatException('Unexpected RESP type "${line[0]}"');
    }
  }

  /// The next CRLF-terminated line (without CRLF), or null if incomplete.
  String? _line() {
    for (var i = _pos; i < _data.length - 1; i++) {
      if (_data[i] == 13 && _data[i + 1] == 10) {
        final line = latin1.decode(Uint8List.sublistView(_data, _pos, i));
        _pos = i + 2;
        return line;
      }
    }
    return null;
  }
}

/// Splits a command line like redis-cli: spaces separate arguments; double
/// quotes allow escapes (`\n`, `\"`, `\xHH`), single quotes are literal.
List<String> splitRedisCommand(String line) {
  final args = <String>[];
  final current = StringBuffer();
  var inArg = false;
  var i = 0;
  while (i < line.length) {
    final c = line[i];
    if (c == '"' || c == "'") {
      inArg = true;
      final quote = c;
      i++;
      var closed = false;
      while (i < line.length) {
        final d = line[i];
        if (d == quote) {
          closed = true;
          i++;
          break;
        }
        if (quote == '"' && d == r'\' && i + 1 < line.length) {
          final e = line[i + 1];
          i += 2;
          switch (e) {
            case 'n':
              current.write('\n');
            case 'r':
              current.write('\r');
            case 't':
              current.write('\t');
            case 'x' when i + 1 < line.length:
              final code = int.tryParse(line.substring(i, i + 2), radix: 16);
              if (code == null) {
                current.write(r'\x');
              } else {
                current.writeCharCode(code);
                i += 2;
              }
            default:
              current.write(e);
          }
          continue;
        }
        if (quote == "'" &&
            d == r'\' &&
            i + 1 < line.length &&
            line[i + 1] == "'") {
          current.write("'");
          i += 2;
          continue;
        }
        current.write(d);
        i++;
      }
      if (!closed) throw const FormatException('Unbalanced quotes');
      // A quote must end the argument.
      if (i < line.length && line[i].trim().isNotEmpty) {
        throw const FormatException(
          'Closing quote must be followed by a space',
        );
      }
    } else if (c.trim().isEmpty) {
      if (inArg) {
        args.add(current.toString());
        current.clear();
        inArg = false;
      }
      i++;
    } else {
      inArg = true;
      current.write(c);
      i++;
    }
  }
  if (inArg) args.add(current.toString());
  return args;
}

/// Formats a reply the way redis-cli prints it.
String formatRedisReply(Object? reply, {String indent = ''}) {
  return switch (reply) {
    null => '(nil)',
    int() => '(integer) $reply',
    RespError() => '(error) ${reply.message}',
    String() => jsonEncode(reply),
    List() when reply.isEmpty => '(empty array)',
    List() => () {
      final width = '${reply.length}'.length;
      final out = StringBuffer();
      for (final (i, item) in reply.indexed) {
        final number = '${i + 1}'.padLeft(width);
        final prefix = '$number) ';
        if (i > 0) out.write('\n$indent');
        out
          ..write(prefix)
          ..write(formatRedisReply(item, indent: indent + ' ' * prefix.length));
      }
      return out.toString();
    }(),
    _ => '$reply',
  };
}
