import 'dart:typed_data';

import 'package:db_client/drivers/driver.dart';
import 'package:db_client/state/data_editor.dart';
import 'package:flutter_test/flutter_test.dart';

DataEditController _editor() => DataEditController(
  schema: 'public',
  table: 'users',
  columns: const [
    ResultColumn(name: 'id', dataType: 'integer'),
    ResultColumn(name: 'name', dataType: 'text'),
    ResultColumn(name: 'tags', dataType: 'text[]'),
    ResultColumn(name: 'avatar', dataType: 'bytea'),
  ],
  baseRows: [
    [
      1,
      "O'Brien",
      ['a', 'b'],
      Uint8List.fromList([0xde, 0xad]),
    ],
    [2, 'Bob', null, null],
  ],
  keyColumns: const [0],
);

void main() {
  test('no changes, no statements', () {
    final editor = _editor();
    expect(editor.hasChanges, isFalse);
    expect(editor.buildStatements(), isEmpty);
  });

  test('update targets the row by its loaded primary key', () {
    final editor = _editor()
      ..setCell(1, 1, const CellValue('Robert'))
      ..setCell(1, 2, const CellValue('{x}'))
      // Already NULL: not a change.
      ..setCell(1, 3, const CellValue.nul())
      ..setCell(0, 3, const CellValue.nul());
    expect(editor.pendingCount, 2);
    expect(editor.rowChange(1), RowChange.updated);
    expect(editor.buildStatements(), [
      "UPDATE public.users SET avatar = NULL WHERE id = '1'::integer;",
      "UPDATE public.users SET name = 'Robert'::text, tags = '{x}'::text[] "
          "WHERE id = '2'::integer;",
    ]);
  });

  test('editing the key column still matches the original row', () {
    final editor = _editor()..setCell(0, 0, const CellValue('10'));
    expect(editor.buildStatements(), [
      "UPDATE public.users SET id = '10'::integer WHERE id = '1'::integer;",
    ]);
  });

  test('typing the original value back un-stages the cell', () {
    final editor = _editor()..setCell(0, 1, const CellValue('x'));
    expect(editor.hasChanges, isTrue);
    editor.setCell(0, 1, const CellValue("O'Brien"));
    expect(editor.hasChanges, isFalse);
  });

  test('edit text round-trips arrays, bytea and quotes', () {
    final editor = _editor();
    expect(editor.editTextAt(0, 1), "O'Brien");
    expect(editor.editTextAt(0, 2), '{"a","b"}');
    expect(editor.editTextAt(0, 3), r'\xdead');
    expect(editor.editTextAt(1, 2), isNull);
  });

  test('deleted rows drop their updates and come first', () {
    final editor = _editor()
      ..setCell(0, 1, const CellValue('x'))
      ..addRow()
      ..deleteRow(0);
    editor.setCell(2, 1, const CellValue('Carol'));
    expect(editor.rowChange(0), RowChange.deleted);
    expect(editor.pendingCount, 2);
    expect(editor.buildStatements(), [
      "DELETE FROM public.users WHERE id = '1'::integer;",
      "INSERT INTO public.users (name) VALUES ('Carol'::text);",
    ]);
  });

  test('a deleted row cannot be edited, and can be restored', () {
    final editor = _editor()..deleteRow(1);
    editor.setCell(1, 1, const CellValue('ignored'));
    expect(editor.stagedAt(1, 1), isNull);
    editor.restoreRow(1);
    expect(editor.hasChanges, isFalse);
  });

  test('an untouched new row inserts defaults; deleting it discards it', () {
    final editor = _editor();
    final row = editor.addRow();
    expect(editor.rowChange(row), RowChange.inserted);
    expect(editor.buildStatements(), [
      'INSERT INTO public.users DEFAULT VALUES;',
    ]);
    editor.deleteRow(row);
    expect(editor.hasChanges, isFalse);
    expect(editor.rowCount, 2);
  });

  test('revert and clear', () {
    final editor = _editor()
      ..setCell(0, 1, const CellValue('x'))
      ..revertCell(0, 1);
    expect(editor.hasChanges, isFalse);
    editor
      ..setCell(1, 1, const CellValue('y'))
      ..addRow()
      ..clear();
    expect(editor.hasChanges, isFalse);
    expect(editor.rowCount, 2);
  });
}
