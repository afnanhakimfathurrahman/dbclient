/// Splits a SQL script into statements on top-level semicolons.
///
/// Understands the PostgreSQL lexical rules that can hide a semicolon:
/// single-quoted strings (including E'' escapes), quoted identifiers,
/// dollar-quoted bodies, `--` line comments and nested `/* */` comments.
library;

class SqlStatement {
  const SqlStatement(this.text, this.start, this.end);

  /// Statement text, trimmed, without the trailing semicolon.
  final String text;

  /// Offsets into the original script covering the statement and its
  /// terminating semicolon (if any). Used to find the statement under the
  /// cursor.
  final int start;
  final int end;
}

List<SqlStatement> splitSql(String script) {
  final statements = <SqlStatement>[];
  var segmentStart = 0;
  var i = 0;
  final n = script.length;

  void addSegment(int endExclusive, int segmentEnd) {
    final raw = script.substring(segmentStart, endExclusive);
    if (_hasCode(raw)) {
      final leading = raw.length - raw.trimLeft().length;
      statements.add(
        SqlStatement(raw.trim(), segmentStart + leading, segmentEnd),
      );
    }
  }

  while (i < n) {
    final c = script[i];
    final next = i + 1 < n ? script[i + 1] : '';

    if (c == '-' && next == '-') {
      i = _skipLineComment(script, i);
    } else if (c == '/' && next == '*') {
      i = _skipBlockComment(script, i);
    } else if (c == "'") {
      final escapes = i > 0 && (script[i - 1] == 'E' || script[i - 1] == 'e');
      i = _skipQuoted(script, i, "'", backslashEscapes: escapes);
    } else if (c == '"') {
      i = _skipQuoted(script, i, '"', backslashEscapes: false);
    } else if (c == r'$') {
      final tag = _dollarTagAt(script, i);
      if (tag != null) {
        final close = script.indexOf(tag, i + tag.length);
        i = close == -1 ? n : close + tag.length;
      } else {
        i++;
      }
    } else if (c == ';') {
      addSegment(i, i + 1);
      i++;
      segmentStart = i;
    } else {
      i++;
    }
  }
  addSegment(n, n);
  return statements;
}

/// Returns the statement containing [offset], or the closest one before it
/// when the cursor sits in whitespace between statements.
SqlStatement? statementAt(String script, int offset) {
  final statements = splitSql(script);
  if (statements.isEmpty) return null;
  SqlStatement? candidate;
  for (final s in statements) {
    if (offset < s.start) break;
    candidate = s;
    if (offset <= s.end) return s;
  }
  return candidate ?? statements.first;
}

int _skipLineComment(String s, int i) {
  final end = s.indexOf('\n', i);
  return end == -1 ? s.length : end + 1;
}

int _skipBlockComment(String s, int i) {
  var depth = 0;
  while (i < s.length) {
    if (s.startsWith('/*', i)) {
      depth++;
      i += 2;
    } else if (s.startsWith('*/', i)) {
      depth--;
      i += 2;
      if (depth == 0) return i;
    } else {
      i++;
    }
  }
  return s.length;
}

int _skipQuoted(
  String s,
  int i,
  String quote, {
  required bool backslashEscapes,
}) {
  i++;
  while (i < s.length) {
    final c = s[i];
    if (backslashEscapes && c == r'\') {
      i += 2;
    } else if (c == quote) {
      // A doubled quote is an escaped quote, not the end of the literal.
      if (i + 1 < s.length && s[i + 1] == quote) {
        i += 2;
      } else {
        return i + 1;
      }
    } else {
      i++;
    }
  }
  return s.length;
}

final _dollarTag = RegExp(r'\$([A-Za-z_][A-Za-z0-9_]*)?\$');

String? _dollarTagAt(String s, int i) {
  // `$1` is a parameter placeholder, not a tag; the regex requires a
  // non-digit start so it won't match.
  if (i > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(s[i - 1])) return null;
  final match = _dollarTag.matchAsPrefix(s, i);
  return match?.group(0);
}

bool _hasCode(String segment) {
  var i = 0;
  while (i < segment.length) {
    final c = segment[i];
    if (c.trim().isEmpty) {
      i++;
    } else if (segment.startsWith('--', i)) {
      i = _skipLineComment(segment, i);
    } else if (segment.startsWith('/*', i)) {
      i = _skipBlockComment(segment, i);
    } else {
      return true;
    }
  }
  return false;
}
