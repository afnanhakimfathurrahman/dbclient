import 'package:db_client/drivers/driver.dart';
import 'package:db_client/state/workspace_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

StatementOutcome _select(String sql) => StatementOutcome(
  sql,
  result: const QueryResult(
    columns: [ResultColumn(name: 'n', dataType: 'int')],
    rows: [
      [1],
      [2],
    ],
    affectedRows: 0,
    elapsed: Duration.zero,
    truncated: false,
  ),
);

StatementOutcome _update(String sql) => StatementOutcome(
  sql,
  result: const QueryResult(
    columns: [],
    rows: [],
    affectedRows: 3,
    elapsed: Duration.zero,
    truncated: false,
  ),
);

void main() {
  test('only the newest result sets of a script keep their rows', () {
    final outcomes = <StatementOutcome>[];
    for (var i = 0; i < 5; i++) {
      outcomes
        ..add(_select('select $i'))
        ..add(_update('update $i'));
      EditorTab.releaseOldRows(outcomes);
    }
    final selects = outcomes.where((o) => o.sql.startsWith('select')).toList();
    expect(
      [for (final o in selects) o.rowsReleased],
      [true, true, false, false, false],
    );
    expect(selects.first.result!.rows, isEmpty);
    expect(selects.first.result!.columns.single.name, 'n');
    expect(selects.last.result!.rows, hasLength(2));
    // Statements without a result set are left alone.
    expect(outcomes.where((o) => o.rowsReleased), hasLength(2));
  });
}
