/// MongoDB values as text, in mongosh syntax:
/// `{ _id: ObjectId('…'), at: ISODate('…'), n: Long('5') }`.
///
/// [formatMongo] writes it and [parseMongo] reads it back to the same BSON
/// types (int32 vs Long, double vs Decimal128…), so editing a document as
/// text doesn't change the types of fields left alone. The parser also takes
/// plain and Extended JSON, single quotes, unquoted keys, trailing commas,
/// `/regex/flags` and the legacy `NumberLong(…)` style.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:fixnum/fixnum.dart';
import 'package:mongo_dart/mongo_dart.dart'
    show BsonBinary, DbRef, JsCode, ObjectId, Timestamp;
import 'package:uuid/uuid.dart';

/// Formats a decoded BSON value. [indent] null gives one line.
String formatMongo(Object? value, {String? indent = '  '}) {
  final out = StringBuffer();
  _write(out, value, indent, 0);
  return out.toString();
}

/// Short single-line text for a value, for grids and tree rows.
String formatMongoInline(Object? value) => formatMongo(value, indent: null);

/// Type label shown next to values in the document view.
String mongoTypeName(Object? value) => switch (value) {
  null => 'Null',
  bool() => 'Boolean',
  Int64() => 'Int64',
  int() => 'Int32',
  double() => 'Double',
  Decimal() => 'Decimal128',
  String() => 'String',
  ObjectId() => 'ObjectId',
  DateTime() => 'Date',
  Timestamp() => 'Timestamp',
  UuidValue() => 'UUID',
  BsonBinary() => 'Binary',
  RegExp() => 'RegExp',
  JsCode() => 'Code',
  DbRef() => 'DBRef',
  Map() => 'Object',
  List() => 'Array',
  _ => value.runtimeType.toString(),
};

final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

void _write(StringBuffer out, Object? value, String? indent, int depth) {
  String pad(int d) => indent == null ? '' : indent * d;
  final newline = indent == null ? ' ' : '\n';

  switch (value) {
    case null:
      out.write('null');
    case bool():
      out.write(value);
    case Int64():
      out.write("Long('$value')");
    case int():
      out.write(value);
    case double():
      out.write(_formatDouble(value));
    case Decimal():
      out.write("Decimal128('$value')");
    case String():
      out.write(jsonEncode(value));
    case ObjectId():
      out.write("ObjectId('${value.oid}')");
    case DateTime():
      out.write("ISODate('${value.toUtc().toIso8601String()}')");
    case Timestamp():
      out.write('Timestamp(${value.seconds}, ${value.increment})');
    case UuidValue():
      out.write("UUID('${value.uuid}')");
    case BsonBinary():
      out.write("BinData(${value.subType}, '${base64Encode(value.byteList)}')");
    case RegExp():
      final flags = [
        if (!value.isCaseSensitive) 'i',
        if (value.isMultiLine) 'm',
        if (value.isDotAll) 's',
      ].join();
      out.write('/${value.pattern.replaceAll('/', r'\/')}/$flags');
    case JsCode():
      out.write('Code(${jsonEncode(value.code)})');
    case DbRef():
      out.write('DBRef(${jsonEncode(value.collection)}, ');
      _write(out, value.id, null, 0);
      if (value.db != null) out.write(', ${jsonEncode(value.db)}');
      out.write(')');
    case Map():
      if (value.isEmpty) {
        out.write('{}');
        return;
      }
      out.write('{$newline');
      var first = true;
      for (final MapEntry(:key, value: v) in value.entries) {
        if (!first) out.write(',$newline');
        first = false;
        final name = '$key';
        out
          ..write(pad(depth + 1))
          ..write(_identifier.hasMatch(name) ? name : jsonEncode(name))
          ..write(': ');
        _write(out, v, indent, depth + 1);
      }
      out.write('$newline${pad(depth)}}');
    case List():
      if (value.isEmpty) {
        out.write('[]');
        return;
      }
      out.write('[$newline');
      for (final (i, v) in value.indexed) {
        if (i > 0) out.write(',$newline');
        out.write(pad(depth + 1));
        _write(out, v, indent, depth + 1);
      }
      out.write('$newline${pad(depth)}]');
    default:
      out.write(jsonEncode('$value'));
  }
}

/// Doubles keep a decimal point so they read back as doubles, not int32.
String _formatDouble(double value) {
  if (value.isNaN) return 'NaN';
  if (value.isInfinite) return value.isNegative ? '-Infinity' : 'Infinity';
  final text = value.toString();
  return text.contains(RegExp('[.eE]')) ? text : '$text.0';
}

/// Parses mongosh-style text into BSON-ready Dart values. Throws
/// [FormatException] with the position of the problem.
Object? parseMongo(String text) {
  final parser = _Parser(text);
  final value = parser.value();
  parser.skipSpace();
  if (!parser.atEnd) parser.fail('Unexpected text after the value');
  return _fromExtendedJson(value);
}

/// [parseMongo] for something that must be a document, e.g. a filter.
/// Empty text is `{}`.
Map<String, dynamic> parseMongoDocument(String text, {String what = 'value'}) {
  if (text.trim().isEmpty) return {};
  final value = parseMongo(text);
  if (value is! Map<String, dynamic>) {
    throw FormatException('The $what must be a document: { … }');
  }
  return value;
}

class _Parser {
  _Parser(this.text);

  final String text;
  int pos = 0;

  bool get atEnd => pos >= text.length;
  String get char => text[pos];

  Never fail(String message) {
    final before = text.substring(0, pos.clamp(0, text.length));
    final line = '\n'.allMatches(before).length + 1;
    final column = pos - (before.lastIndexOf('\n') + 1) + 1;
    throw FormatException('$message (line $line, column $column)');
  }

  void skipSpace() {
    while (!atEnd) {
      if (char.trim().isEmpty) {
        pos++;
      } else if (text.startsWith('//', pos)) {
        final end = text.indexOf('\n', pos);
        pos = end < 0 ? text.length : end;
      } else if (text.startsWith('/*', pos)) {
        final end = text.indexOf('*/', pos + 2);
        if (end < 0) fail('Unclosed comment');
        pos = end + 2;
      } else {
        return;
      }
    }
  }

  void expect(String token) {
    skipSpace();
    if (!text.startsWith(token, pos)) fail('Expected "$token"');
    pos += token.length;
  }

  bool accept(String token) {
    skipSpace();
    if (!text.startsWith(token, pos)) return false;
    pos += token.length;
    return true;
  }

  Object? value() {
    skipSpace();
    if (atEnd) fail('Expected a value');
    return switch (char) {
      '{' => object(),
      '[' => array(),
      '"' || "'" => string(),
      '/' => regex(),
      _ when RegExp(r'[-+0-9.]').hasMatch(char) => number(),
      _ => word(),
    };
  }

  Map<String, dynamic> object() {
    expect('{');
    final map = <String, dynamic>{};
    while (!accept('}')) {
      skipSpace();
      final key = char == '"' || char == "'" ? string() : identifier();
      expect(':');
      map[key] = value();
      if (!accept(',')) {
        expect('}');
        break;
      }
    }
    return map;
  }

  List<Object?> array() {
    expect('[');
    final list = <Object?>[];
    while (!accept(']')) {
      list.add(value());
      if (!accept(',')) {
        expect(']');
        break;
      }
    }
    return list;
  }

  String identifier() {
    final match = RegExp(r'[A-Za-z_$][A-Za-z0-9_$.]*').matchAsPrefix(text, pos);
    if (match == null) fail('Expected a field name');
    pos = match.end;
    return match.group(0)!;
  }

  String string() {
    final quote = char;
    pos++;
    final out = StringBuffer();
    while (true) {
      if (atEnd) fail('Unclosed string');
      final c = char;
      pos++;
      if (c == quote) return out.toString();
      if (c != r'\') {
        out.write(c);
        continue;
      }
      if (atEnd) fail('Unclosed string');
      final e = char;
      pos++;
      switch (e) {
        case 'n':
          out.write('\n');
        case 't':
          out.write('\t');
        case 'r':
          out.write('\r');
        case 'b':
          out.write('\b');
        case 'f':
          out.write('\f');
        case 'u':
          if (pos + 4 > text.length) fail('Bad \\u escape');
          final code = int.tryParse(text.substring(pos, pos + 4), radix: 16);
          if (code == null) fail('Bad \\u escape');
          out.writeCharCode(code);
          pos += 4;
        default:
          out.write(e); // \" \' \\ \/
      }
    }
  }

  Object number() {
    final match = RegExp(
      r'[-+]?(Infinity|NaN|(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?)',
    ).matchAsPrefix(text, pos);
    if (match == null) fail('Invalid number');
    pos = match.end;
    final raw = match.group(0)!;
    if (raw.endsWith('Infinity')) {
      return raw.startsWith('-') ? double.negativeInfinity : double.infinity;
    }
    if (raw.endsWith('NaN')) return double.nan;
    if (raw.contains(RegExp('[.eE]'))) return double.parse(raw);
    // Like mongosh: integers are int32 when they fit, else Long.
    final big = BigInt.parse(raw);
    return big.isValidInt ? big.toInt() : fail('Integer out of range');
  }

  RegExp regex() {
    pos++; // opening /
    final out = StringBuffer();
    while (true) {
      if (atEnd) fail('Unclosed regular expression');
      final c = char;
      pos++;
      if (c == '/') break;
      if (c == r'\' && !atEnd) {
        // Keep escapes for the regex engine, except an escaped slash.
        final e = char;
        pos++;
        out.write(e == '/' ? '/' : '\\$e');
        continue;
      }
      out.write(c);
    }
    final flags = RegExp(r'[a-z]*').matchAsPrefix(text, pos)!.group(0)!;
    pos += flags.length;
    return RegExp(
      out.toString(),
      caseSensitive: !flags.contains('i'),
      multiLine: flags.contains('m'),
      dotAll: flags.contains('s'),
    );
  }

  /// Keywords and constructor calls: true, ObjectId('…'), new Date(…)…
  Object? word() {
    accept('new ');
    final match = RegExp(r'[A-Za-z_$][A-Za-z0-9_$.]*').matchAsPrefix(text, pos);
    if (match == null) fail('Unexpected character "$char"');
    pos = match.end;
    final name = match.group(0)!;
    switch (name) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null' || 'undefined':
        return null;
      case 'Infinity':
        return double.infinity;
      case 'NaN':
        return double.nan;
    }

    expect('(');
    final args = <Object?>[];
    while (!accept(')')) {
      args.add(value());
      if (!accept(',')) {
        expect(')');
        break;
      }
    }
    String text0() {
      if (args.isEmpty || args.first is! String && args.first is! num) {
        fail('$name(…) needs a value');
      }
      return '${args.first}';
    }

    try {
      return switch (name) {
        'ObjectId' || 'ObjectID' =>
          args.isEmpty ? ObjectId() : ObjectId.fromHexString(text0()),
        'ISODate' || 'Date' =>
          args.isEmpty
              ? DateTime.now().toUtc()
              : args.first is num
              ? DateTime.fromMillisecondsSinceEpoch(
                  (args.first as num).toInt(),
                  isUtc: true,
                )
              : _parseDate(text0()),
        'Long' || 'NumberLong' => Int64.parseInt(text0()),
        'Int32' || 'NumberInt' => int.parse(text0()),
        'Double' => double.parse(text0()),
        'Decimal128' || 'NumberDecimal' => Decimal.parse(text0()),
        'UUID' => UuidValue.withValidation(text0()),
        'Timestamp' =>
          args.first is Map
              ? Timestamp(
                  (args.first as Map)['t'] as int,
                  (args.first as Map)['i'] as int,
                )
              : Timestamp(args[0] as int, args[1] as int),
        'BinData' => BsonBinary.from(
          base64Decode(args[1] as String),
          subType: args[0] as int,
        ),
        'Code' => JsCode(text0()),
        'DBRef' => DbRef(args[0] as String, args[1] as Object),
        _ => fail('Unknown type $name(…)'),
      };
    } on FormatException {
      rethrow;
    } catch (e) {
      fail('Invalid $name(…): $e');
    }
  }
}

/// Converts Extended JSON wrappers (`{"$oid": "…"}`, `{"$date": …}`…) left
/// in parsed text into BSON values, recursively.
Object? _fromExtendedJson(Object? value) {
  if (value is List) return [for (final v in value) _fromExtendedJson(v)];
  if (value is! Map<String, dynamic>) return value;
  if (value.length == 1) {
    final MapEntry(:key, value: inner) = value.entries.first;
    switch (key) {
      case r'$oid' when inner is String:
        return ObjectId.fromHexString(inner);
      case r'$date':
        return switch (inner) {
          String() => _parseDate(inner),
          int() => DateTime.fromMillisecondsSinceEpoch(inner, isUtc: true),
          {r'$numberLong': final String ms} =>
            DateTime.fromMillisecondsSinceEpoch(int.parse(ms), isUtc: true),
          _ => value,
        };
      case r'$numberLong' when inner is String:
        return Int64.parseInt(inner);
      case r'$numberInt' when inner is String:
        return int.parse(inner);
      case r'$numberDouble' when inner is String:
        return double.parse(inner);
      case r'$numberDecimal' when inner is String:
        return Decimal.parse(inner);
      case r'$uuid' when inner is String:
        return UuidValue.withValidation(inner);
    }
  }
  return {for (final e in value.entries) e.key: _fromExtendedJson(e.value)};
}

/// Bytes of a [BsonBinary] value, e.g. for a hex viewer.
Uint8List binaryBytes(BsonBinary value) => value.byteList;

/// ISO date as mongosh reads it: without a zone, the time is UTC (not the
/// local time zone, as [DateTime.parse] would assume).
DateTime _parseDate(String text) {
  final parsed = DateTime.parse(text);
  if (parsed.isUtc || RegExp(r'[+-]\d\d:?\d\d$').hasMatch(text.trim())) {
    return parsed.toUtc();
  }
  return DateTime.utc(
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
}
