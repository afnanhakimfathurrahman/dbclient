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

String _formatDateTime(DateTime value) {
  // Postgres returns timestamps as UTC DateTimes; show them without the 'Z'
  // ISO marker noise but keep microsecond precision when present.
  final iso = value.toIso8601String();
  return iso.endsWith('Z') ? '${iso.substring(0, iso.length - 1)}+00' : iso;
}

String _formatBytes(Uint8List bytes, int maxBytes) {
  final shown = bytes.length > maxBytes ? bytes.sublist(0, maxBytes) : bytes;
  final hex = shown.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  final suffix = bytes.length > maxBytes ? '… (${bytes.length} bytes)' : '';
  return '\\x$hex$suffix';
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
