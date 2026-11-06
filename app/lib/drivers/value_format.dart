import 'dart:convert';
import 'dart:typed_data';

/// Converts a decoded database value into display text.
///
/// Returns null for SQL NULL so the grid can style it separately.
String? formatValue(Object? value, {int maxBytes = 64}) {
  return switch (value) {
    null => null,
    String() => value,
    DateTime() => _formatDateTime(value),
    Uint8List() => _formatBytes(value, maxBytes),
    Map() || List() => _tryJson(value),
    _ => value.toString(),
  };
}

/// Full-length text for the value viewer and clipboard: nothing is truncated
/// and JSON is pretty-printed.
String formatValueFull(Object? value) {
  return switch (value) {
    null => 'NULL',
    Uint8List() => _formatBytes(value, value.length),
    Map() || List() => _tryJson(value, pretty: true),
    _ => formatValue(value)!,
  };
}

/// Longest text [formatCellText] returns, before its trailing '…'. A grid
/// cell shows far less; the rest would only cost layout time.
const cellTextMaxChars = 500;

/// Grid cell text: like [formatValue], but on one line (line breaks shown
/// as '↵', tabs as spaces) and cut to [maxChars] characters plus '…'. JSON
/// is only encoded up to the cut, so multi-megabyte documents stay cheap.
String? formatCellText(Object? value, {int maxChars = cellTextMaxChars}) {
  return switch (value) {
    null => null,
    String() => cellText(value, maxChars: maxChars),
    Uint8List() => _formatBytes(value, 64),
    Map() ||
    List() => cellText(_cappedJson(value, maxChars), maxChars: maxChars),
    _ => cellText(formatValue(value)!, maxChars: maxChars),
  };
}

/// [text] on one line and cut to [maxChars] characters plus '…'; returns
/// [text] itself when nothing changes.
String cellText(String text, {int maxChars = cellTextMaxChars}) {
  final cut = text.length > maxChars;
  var end = cut ? maxChars : text.length;
  // Don't split a surrogate pair.
  if (cut && end > 0 && _isHighSurrogate(text.codeUnitAt(end - 1))) end--;
  var plain = true;
  for (var i = 0; i < end; i++) {
    final c = text.codeUnitAt(i);
    if (c == 0x0A || c == 0x0D || c == 0x09) {
      plain = false;
      break;
    }
  }
  if (plain) return cut ? '${text.substring(0, end)}…' : text;

  final out = StringBuffer();
  var start = 0;
  for (var i = 0; i < end; i++) {
    final c = text.codeUnitAt(i);
    if (c != 0x0A && c != 0x0D && c != 0x09) continue;
    out.write(text.substring(start, i));
    start = i + 1;
    if (c == 0x09) {
      out.write(' ');
    } else if (c == 0x0A || i + 1 >= end || text.codeUnitAt(i + 1) != 0x0A) {
      // "\r\n" shows as one '↵'.
      out.write('↵');
    }
  }
  out.write(text.substring(start, end));
  if (cut) out.write('…');
  return out.toString();
}

bool _isHighSurrogate(int c) => c & 0xFC00 == 0xD800;

String _formatDateTime(DateTime value) {
  // Postgres returns timestamps as UTC DateTimes; show them without the 'Z'
  // ISO marker noise but keep microsecond precision when present.
  final iso = value.toIso8601String();
  return iso.endsWith('Z') ? '${iso.substring(0, iso.length - 1)}+00' : iso;
}

const _hexDigits = [
  0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, //
  0x38, 0x39, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66,
];

String _formatBytes(Uint8List bytes, int maxBytes) {
  final shown = bytes.length > maxBytes ? maxBytes : bytes.length;
  // '\x' then two hex digits per byte, built as char codes in one buffer.
  final codes = Uint8List(2 + shown * 2)
    ..[0] = 0x5C
    ..[1] = 0x78;
  for (var i = 0; i < shown; i++) {
    final b = bytes[i];
    codes[2 + i * 2] = _hexDigits[b >> 4];
    codes[3 + i * 2] = _hexDigits[b & 0x0F];
  }
  final hex = String.fromCharCodes(codes);
  return bytes.length > maxBytes ? '$hex… (${bytes.length} bytes)' : hex;
}

String _tryJson(Object value, {bool pretty = false}) {
  try {
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(value)
        : jsonEncode(value);
  } on JsonUnsupportedObjectError {
    return value.toString();
  }
}

/// Compact JSON for [value] like [jsonEncode], but writing stops once the
/// text is longer than [maxChars], so the result is a prefix of the full
/// encoding at least [maxChars] long (or all of it). Values JSON can't
/// encode fall back to a prefix of `toString()`, as [formatValue] does.
String _cappedJson(Object value, int maxChars) {
  final json = _CappedWriter(maxChars, json: true);
  if (json.write(value)) return json.out.toString();
  final text = _CappedWriter(maxChars, json: false)..write(value);
  return text.out.toString();
}

/// Writes collections as compact JSON or, with `json: false`, the way
/// their `toString()` does, until the output is over [maxChars].
class _CappedWriter {
  _CappedWriter(this.maxChars, {required this.json});

  final int maxChars;
  final bool json;
  final out = StringBuffer();

  bool get _full => out.length > maxChars;

  /// Writes [value]; false if it can't be encoded as JSON. Stops early
  /// (returning true) once the output is over [maxChars].
  bool write(Object? value) {
    if (_full) return true;
    switch (value) {
      case String():
        json ? _writeString(value) : _writeRaw(value);
      case List():
        out.write('[');
        for (var i = 0; i < value.length; i++) {
          if (_full) return true;
          if (i > 0) out.write(json ? ',' : ', ');
          if (!write(value[i])) return false;
        }
        out.write(']');
      case Map():
        out.write('{');
        var first = true;
        for (final MapEntry(:key, value: v) in value.entries) {
          if (_full) return true;
          if (!first) out.write(json ? ',' : ', ');
          first = false;
          if (json) {
            if (key is! String) return false;
            _writeString(key);
            out.write(':');
          } else {
            write(key);
            out.write(': ');
          }
          if (!write(v)) return false;
        }
        out.write('}');
      case null || bool() || int():
        out.write(value);
      case double() when value.isFinite || !json:
        out.write(value);
      default:
        // jsonEncode would call toJson(); values from drivers have none.
        if (json) return false;
        _writeRaw(value.toString());
    }
    return true;
  }

  void _writeRaw(String s) {
    final room = maxChars + 1 - out.length;
    out.write(s.length > room ? s.substring(0, room) : s);
  }

  /// A quoted, escaped string the way [JsonEncoder] writes it, stopping at
  /// the cap.
  void _writeString(String s) {
    out.write('"');
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      if (out.length + (i - start) > maxChars) {
        out.write(s.substring(start, i));
        return;
      }
      final c = s.codeUnitAt(i);
      String? escape;
      if (c < 0x20) {
        escape = switch (c) {
          0x08 => r'\b',
          0x09 => r'\t',
          0x0A => r'\n',
          0x0C => r'\f',
          0x0D => r'\r',
          _ => '\\u00${c.toRadixString(16).padLeft(2, '0')}',
        };
      } else if (c == 0x22) {
        escape = r'\"';
      } else if (c == 0x5C) {
        escape = r'\\';
      } else if (c & 0xF800 == 0xD800) {
        // Lone surrogates are escaped; pairs are written as they are.
        final lead = c < 0xDC00;
        final paired = lead
            ? i + 1 < s.length && s.codeUnitAt(i + 1) & 0xFC00 == 0xDC00
            : i > 0 && _isHighSurrogate(s.codeUnitAt(i - 1));
        if (!paired) escape = '\\u${c.toRadixString(16)}';
      }
      if (escape == null) continue;
      out
        ..write(s.substring(start, i))
        ..write(escape);
      start = i + 1;
    }
    out
      ..write(s.substring(start))
      ..write('"');
  }
}
