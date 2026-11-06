import 'package:db_client/drivers/sql_splitter.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> texts(String sql) => [for (final s in splitSql(sql)) s.text];

void main() {
  group('splitSql', () {
    test('splits on top-level semicolons', () {
      expect(texts('select 1; select 2;'), ['select 1', 'select 2']);
    });

    test('keeps a final statement without semicolon', () {
      expect(texts('select 1;\nselect 2'), ['select 1', 'select 2']);
    });

    test('ignores empty and comment-only segments', () {
      expect(texts(';;\n-- just a comment\n;\n/* block */;'), isEmpty);
    });

    test('ignores semicolons inside string literals', () {
      expect(texts("select 'a;b'; select 'it''s;'"), [
        "select 'a;b'",
        "select 'it''s;'",
      ]);
    });

    test('handles backslash escapes in E strings', () {
      expect(texts(r"select E'a\';b'; select 2"), [
        r"select E'a\';b'",
        'select 2',
      ]);
    });

    test('ignores semicolons inside quoted identifiers', () {
      expect(texts('select 1 as "a;b"; select 2'), [
        'select 1 as "a;b"',
        'select 2',
      ]);
    });

    test('ignores semicolons inside comments', () {
      expect(texts('select 1 -- a;b\n; select /* x; /* nested; */ y; */ 2'), [
        'select 1 -- a;b',
        'select /* x; /* nested; */ y; */ 2',
      ]);
    });

    test('keeps dollar-quoted function bodies intact', () {
      const fn = r'''
create function f() returns int as $body$
begin
  perform 1;
  return 2;
end;
$body$ language plpgsql''';
      expect(texts('$fn;\nselect f();'), [fn.trim(), 'select f()']);
    });

    test('anonymous dollar quotes', () {
      expect(texts(r'do $$ begin perform 1; end $$; select 1'), [
        r'do $$ begin perform 1; end $$',
        'select 1',
      ]);
    });

    test(r'does not treat $1 parameters as dollar quotes', () {
      expect(texts(r'select $1; select $2'), [r'select $1', r'select $2']);
    });
  });

  group('statementAt', () {
    const script = 'select 1;\n\nselect 2;\nselect 3';

    test('finds the statement containing the cursor', () {
      expect(statementAt(script, 3)?.text, 'select 1');
      expect(statementAt(script, script.indexOf('2'))?.text, 'select 2');
      expect(statementAt(script, script.length)?.text, 'select 3');
    });

    test('cursor right after a semicolon picks that statement', () {
      expect(statementAt(script, script.indexOf(';') + 1)?.text, 'select 1');
    });

    test('cursor in blank lines picks the previous statement', () {
      expect(statementAt(script, script.indexOf('\n\n') + 1)?.text, 'select 1');
    });

    test('returns null for an empty script', () {
      expect(statementAt('  -- nothing\n', 0), isNull);
    });
  });
}
