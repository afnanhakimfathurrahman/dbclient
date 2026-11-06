/// Redis wire protocol (RESP2) pieces, free of I/O so they can be tested:
/// command encoding, an incremental reply parser, redis-cli style command
/// splitting and reply formatting.
library;

import 'dart:convert';
import 'dart:math';
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

/// Marks array elements a capped [RespParser] dropped; it is the last
/// element of the array it stands in.
class RespOmitted {
  const RespOmitted(this.count);

  final int count;

  @override
  bool operator ==(Object other) =>
      other is RespOmitted && other.count == count;

  @override
  int get hashCode => count.hashCode;

  @override
  String toString() => '… $count more';
}

/// Parses replies from a byte stream fed in arbitrary chunks.
///
/// Replies decode to: `String` (simple and bulk strings, UTF-8 with
/// malformed bytes replaced), `int`, `null` (nil), `List<Object?>`, or
/// [RespError].
///
/// With [maxArrayItems], an array keeps only its first elements, followed by
/// a [RespOmitted] with the number dropped; the dropped bytes are still
/// consumed, so the stream stays in sync.
class RespParser {
  RespParser({this.maxArrayItems});

  final int? maxArrayItems;

  /// Unconsumed bytes are `_data[_pos, _end)`; the buffer grows by doubling
  /// so a large reply arriving in many chunks is copied a bounded number of
  /// times.
  Uint8List _data = Uint8List(0);
  int _pos = 0;
  int _end = 0;

  /// How far the reply at [_pos] is known to be complete, and the elements
  /// still expected per nesting level, so a large reply is checked once
  /// rather than reparsed per chunk.
  int _scan = 0;
  final _expected = <int>[];

  /// Adds bytes and returns every reply now complete, in order.
  List<Object?> add(List<int> chunk) {
    _append(chunk);
    final replies = <Object?>[];
    while (_pos < _end) {
      if (_expected.isEmpty) {
        _scan = _pos;
        _expected.add(1);
      }
      if (!_complete()) break;
      replies.add(_read(keep: true));
    }
    if (_pos == _end) {
      _pos = _end = _scan = 0;
      // Don't hold on to a buffer grown for one large reply.
      if (_data.length > 1 << 20) _data = Uint8List(0);
    }
    return replies;
  }

  void _append(List<int> chunk) {
    if (_end + chunk.length > _data.length) {
      final live = _end - _pos;
      final needed = live + chunk.length;
      final data = needed <= _data.length ~/ 2
          ? _data
          : Uint8List(max(4096, max(needed, _data.length * 2)));
      data.setRange(0, live, _data, _pos);
      _data = data;
      _scan -= _pos;
      _pos = 0;
      _end = live;
    }
    _data.setRange(_end, _end + chunk.length, chunk);
    _end += chunk.length;
  }

  /// Advances [_scan] over whole elements of the reply at [_pos]; true once
  /// all of it is buffered.
  bool _complete() {
    while (_expected.isNotEmpty) {
      if (_expected.last == 0) {
        _expected.removeLast();
        continue;
      }
      final lineEnd = _lineEnd(_scan);
      if (lineEnd < 0) return false;
      final type = _data[_scan];
      var next = lineEnd + 2;
      int count() =>
          int.parse(latin1.decode(_data.sublist(_scan + 1, lineEnd)));
      if (type == 0x24) {
        // $: a bulk string, complete only with its payload.
        final length = count();
        if (length >= 0) {
          next += length + 2;
          if (next > _end) return false;
        }
      }
      _expected.last--;
      if (type == 0x2A) {
        // *: an array; its elements come next.
        final items = count();
        if (items > 0) _expected.add(items);
      }
      _scan = next;
    }
    return true;
  }

  /// Index of the CRLF ending the line at [from], or -1 if not buffered.
  int _lineEnd(int from) {
    for (var i = from; i < _end - 1; i++) {
      if (_data[i] == 13 && _data[i + 1] == 10) return i;
    }
    return -1;
  }

  /// Reads one buffered reply at [_pos] ([_complete] has checked it is all
  /// there); with [keep] false it is skipped without decoding.
  Object? _read({required bool keep}) {
    final lineEnd = _lineEnd(_pos);
    final line = latin1.decode(Uint8List.sublistView(_data, _pos, lineEnd));
    _pos = lineEnd + 2;
    final payload = line.substring(1);
    switch (line[0]) {
      case '+':
        return payload;
      case '-':
        return RespError(payload);
      case ':':
        return int.parse(payload);
      case r'$':
        final length = int.parse(payload);
        if (length < 0) return null;
        final text = keep
            ? utf8.decode(
                Uint8List.sublistView(_data, _pos, _pos + length),
                allowMalformed: true,
              )
            : null;
        _pos += length + 2;
        return text;
      case '*':
        final count = int.parse(payload);
        if (count < 0) return null;
        final kept = keep ? min(count, maxArrayItems ?? count) : 0;
        final items = <Object?>[
          for (var i = 0; i < kept; i++) _read(keep: true),
        ];
        for (var i = kept; i < count; i++) {
          _read(keep: false);
        }
        if (keep && kept < count) items.add(RespOmitted(count - kept));
        return keep ? items : null;
      default:
        throw FormatException('Unexpected RESP type "${line[0]}"');
    }
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

/// Formats a reply the way redis-cli prints it. With [maxChars], output
/// stops at about that many characters, ending in a note.
String formatRedisReply(Object? reply, {String indent = '', int? maxChars}) {
  final out = StringBuffer();
  if (!_writeReply(out, reply, indent, maxChars ?? -1)) {
    out.write('\n… output cut at $maxChars characters');
  }
  return out.toString();
}

/// Writes [reply] to [out]; false once [limit] (negative: none) is reached.
bool _writeReply(StringBuffer out, Object? reply, String indent, int limit) {
  bool fits() => limit < 0 || out.length < limit;
  switch (reply) {
    case null:
      out.write('(nil)');
    case int():
      out.write('(integer) $reply');
    case RespError():
      out.write('(error) ${reply.message}');
    case String():
      final room = limit < 0 ? reply.length : max(0, limit - out.length);
      if (reply.length > room) {
        out.write(jsonEncode(reply.substring(0, room)));
        return false;
      }
      out.write(jsonEncode(reply));
    case RespOmitted():
      out.write('… ${reply.count} more');
    case List() when reply.isEmpty:
      out.write('(empty array)');
    case List():
      final width = '${reply.length}'.length;
      for (final (i, item) in reply.indexed) {
        if (i > 0) out.write('\n$indent');
        if (item is RespOmitted) {
          out.write('${' ' * width}  … ${item.count} more');
          break;
        }
        final prefix = '${'${i + 1}'.padLeft(width)}) ';
        out.write(prefix);
        if (!_writeReply(out, item, indent + ' ' * prefix.length, limit) ||
            !fits()) {
          return false;
        }
      }
    default:
      out.write('$reply');
  }
  return fits();
}
