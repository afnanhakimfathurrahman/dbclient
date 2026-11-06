import 'package:flutter/foundation.dart';

import '../drivers/driver.dart';
import '../drivers/postgres/postgres_sql.dart';
import '../drivers/value_format.dart';

/// How a row differs from what was loaded.
enum RowChange { none, updated, inserted, deleted }

/// A staged cell value: input [text] for Postgres, or SQL NULL when null.
class CellValue {
  const CellValue(this.text);
  const CellValue.nul() : text = null;

  final String? text;
}

/// Staged edits to a table's rows: updated cells, inserted rows and deleted
/// rows, kept until [buildStatements] is applied (Save) or [clear]ed
/// (Revert). Nothing touches the database here.
///
/// Rows are addressed by data index: `0 ..< baseRows.length` are the loaded
/// rows, followed by inserted rows. Loaded rows are identified in SQL by
/// their primary key ([keyColumns]), using the values as loaded, so editing
/// a key column still updates the right row.
class DataEditController extends ChangeNotifier {
  DataEditController({
    required this.schema,
    required this.table,
    required this.columns,
    required this.baseRows,
    required this.keyColumns,
  }) : assert(keyColumns.isNotEmpty);

  final String schema;
  final String table;
  final List<ResultColumn> columns;
  final List<List<Object?>> baseRows;

  /// Indexes into [columns] of the primary key.
  final List<int> keyColumns;

  final _updates = <int, Map<int, CellValue>>{};
  final _deleted = <int>{};
  final _inserted = <Map<int, CellValue>>[];

  int get rowCount => baseRows.length + _inserted.length;

  bool isInserted(int row) => row >= baseRows.length;

  /// Rows with at least one staged change.
  int get pendingCount =>
      _deleted.length +
      _inserted.length +
      _updates.keys.where((r) => !_deleted.contains(r)).length;

  bool get hasChanges => pendingCount > 0;

  RowChange rowChange(int row) {
    if (isInserted(row)) return RowChange.inserted;
    if (_deleted.contains(row)) return RowChange.deleted;
    if (_updates.containsKey(row)) return RowChange.updated;
    return RowChange.none;
  }

  /// The staged value of a cell, or null if it isn't changed (for inserted
  /// rows: null means the column gets its DEFAULT).
  CellValue? stagedAt(int row, int column) => isInserted(row)
      ? _inserted[row - baseRows.length][column]
      : _updates[row]?[column];

  /// Text to start editing a cell with; null for NULL.
  String? editTextAt(int row, int column) {
    if (stagedAt(row, column) case final staged?) return staged.text;
    if (isInserted(row)) return null;
    return pgEditText(baseRows[row][column], columns[column].dataType);
  }

  void setCell(int row, int column, CellValue value) {
    if (isInserted(row)) {
      _inserted[row - baseRows.length][column] = value;
    } else {
      if (_deleted.contains(row)) return;
      final original = pgEditText(
        baseRows[row][column],
        columns[column].dataType,
      );
      final cells = _updates.putIfAbsent(row, () => {});
      // Typing the original value back un-stages the cell.
      if (value.text == original) {
        cells.remove(column);
        if (cells.isEmpty) _updates.remove(row);
      } else {
        cells[column] = value;
      }
    }
    notifyListeners();
  }

  void revertCell(int row, int column) {
    if (isInserted(row)) {
      _inserted[row - baseRows.length].remove(column);
    } else {
      _updates[row]?.remove(column);
      if (_updates[row]?.isEmpty ?? false) _updates.remove(row);
    }
    notifyListeners();
  }

  /// Adds an empty row (all columns DEFAULT) and returns its index.
  int addRow() {
    _inserted.add({});
    notifyListeners();
    return rowCount - 1;
  }

  /// Marks a loaded row for deletion, or discards an inserted one.
  void deleteRow(int row) {
    if (isInserted(row)) {
      _inserted.removeAt(row - baseRows.length);
    } else {
      _deleted.add(row);
    }
    notifyListeners();
  }

  void restoreRow(int row) {
    if (_deleted.remove(row)) notifyListeners();
  }

  void clear() {
    _updates.clear();
    _deleted.clear();
    _inserted.clear();
    notifyListeners();
  }

  /// The SQL that applies every staged change, meant to run in one
  /// transaction: deletes first (so a deleted key can be re-inserted), then
  /// updates, then inserts.
  List<String> buildStatements() {
    final target = qualifiedName(schema, table);
    String column(int c) => quoteIdent(columns[c].name);
    String value(int c, CellValue v) =>
        pgTypedLiteral(v.text, columns[c].dataType);
    String where(int row) => keyColumns
        .map((c) {
          final key = baseRows[row][c];
          return key == null
              ? '${column(c)} IS NULL'
              : '${column(c)} = '
                    '${pgTypedLiteral(pgEditText(key, columns[c].dataType), columns[c].dataType)}';
        })
        .join(' AND ');

    final rows = _deleted.toList()..sort();
    final updated = _updates.keys.where((r) => !_deleted.contains(r)).toList()
      ..sort();
    return [
      for (final row in rows) 'DELETE FROM $target WHERE ${where(row)};',
      for (final row in updated)
        'UPDATE $target SET '
            '${[for (final MapEntry(key: c, value: v) in _updates[row]!.entries) '${column(c)} = ${value(c, v)}'].join(', ')} '
            'WHERE ${where(row)};',
      for (final cells in _inserted)
        cells.isEmpty
            ? 'INSERT INTO $target DEFAULT VALUES;'
            : 'INSERT INTO $target '
                  '(${cells.keys.map(column).join(', ')}) VALUES '
                  '(${[for (final MapEntry(key: c, value: v) in cells.entries) value(c, v)].join(', ')});',
    ];
  }

  /// Display text for a cell including staged changes: null for NULL.
  String? displayTextAt(int row, int column) {
    if (stagedAt(row, column) case final staged?) return staged.text;
    if (isInserted(row)) return null;
    return formatValue(baseRows[row][column]);
  }
}
