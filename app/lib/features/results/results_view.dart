import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../drivers/export.dart';
import '../../drivers/value_format.dart';
import '../../state/data_editor.dart';
import '../../state/workspace_tabs.dart';
import 'export_dialog.dart';

/// Results of the tab's last run: a grid for result sets, a message for
/// other statements, or the error.
class ResultsView extends StatelessWidget {
  const ResultsView({super.key, required this.tab});

  final EditorTab tab;

  @override
  Widget build(BuildContext context) {
    final outcomes = tab.outcomes;
    if (outcomes.isEmpty) {
      return _Placeholder(
        child: tab.running
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Running…'),
                ],
              )
            : const Text('Run a query to see results here.'),
      );
    }

    final index = tab.selectedOutcome.clamp(0, outcomes.length - 1);
    final outcome = outcomes[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (outcomes.length > 1 || tab.running)
          _OutcomeBar(tab: tab, selected: index),
        Expanded(
          child: switch (outcome) {
            StatementOutcome(error: final error?) => _ErrorPanel(
              outcome: outcome,
              error: error,
            ),
            StatementOutcome(result: final result?) when result.hasResultSet =>
              ResultGrid(key: ObjectKey(result), result: result),
            StatementOutcome(result: final result?) => _Placeholder(
              child: Text(
                'Statement executed. ${result.affectedRows} row(s) affected.',
              ),
            ),
            _ => const SizedBox.shrink(),
          },
        ),
        if (outcome.result case final result?) _StatusBar(result: result),
      ],
    );
  }
}

class _OutcomeBar extends StatelessWidget {
  const _OutcomeBar({required this.tab, required this.selected});

  final EditorTab tab;
  final int selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        children: [
          for (final (i, o) in tab.outcomes.indexed)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                selected: i == selected,
                onSelected: (_) => tab.selectedOutcome = i,
                avatar: Icon(
                  o.error != null
                      ? Icons.error_outline_rounded
                      : (o.result?.hasResultSet ?? false)
                      ? Icons.table_rows_rounded
                      : Icons.check_circle_outline_rounded,
                  size: 15,
                  color: o.error != null
                      ? scheme.error
                      : (o.result?.hasResultSet ?? false)
                      ? scheme.primary
                      : const Color(0xFF10B981),
                ),
                label: Text(
                  o.error != null
                      ? '#${i + 1} Error'
                      : (o.result?.hasResultSet ?? false)
                      ? '#${i + 1} (${o.result!.rows.length} rows)'
                      : '#${i + 1} (${o.result?.affectedRows ?? 0} affected)',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                tooltip: o.sql,
              ),
            ),
          if (tab.running)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.result});

  final QueryResult result;

  void _quickExport(BuildContext context, ExportFormat format) {
    final text = ResultExporter.export(result, format);
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${format.label} copied to clipboard (${result.rows.length} rows)',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          // Row count badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                result.hasResultSet
                    ? Icons.table_rows_rounded
                    : Icons.check_rounded,
                size: 13,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                result.hasResultSet
                    ? '${result.rows.length} rows'
                    : '${result.affectedRows} affected',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Text('·', style: TextStyle(color: scheme.outlineVariant)),
          const SizedBox(width: 12),

          // Duration badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 13,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                '${result.elapsed.inMilliseconds} ms',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),

          if (result.hasResultSet) ...[
            const SizedBox(width: 12),
            Text('·', style: TextStyle(color: scheme.outlineVariant)),
            const SizedBox(width: 12),
            Text(
              '${result.columns.length} cols',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],

          if (result.truncated) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: Colors.amber.shade700.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 12,
                    color: Colors.amber.shade700,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Limit reached (more rows available)',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),

          // Export actions
          if (result.hasResultSet && result.rows.isNotEmpty) ...[
            Tooltip(
              message: 'Copy CSV to clipboard',
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _quickExport(context, ExportFormat.csv),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.table_chart_outlined,
                        size: 12,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'CSV',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Copy JSON to clipboard',
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => _quickExport(context, ExportFormat.json),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.data_object_rounded,
                        size: 12,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'JSON',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: 'Export options (Markdown, SQL, TSV...)',
              child: InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => showExportDialog(
                  context,
                  result: result,
                  fileName: 'query_result',
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.file_download_outlined,
                        size: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'Export...',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.outcome, required this.error});

  final StatementOutcome outcome;
  final DriverException error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: SelectionArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: scheme.error.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 20,
                      color: scheme.error,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      error.message,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (error.code != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: scheme.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        'SQLSTATE ${error.code}',
                        style: monoBadgeStyle.copyWith(color: scheme.error),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (error.detail != null) ...[
                Text(
                  'Detail:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  error.detail!,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (error.hint != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Colors.amber.shade700.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 16,
                        color: Colors.amber.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Hint: ${error.hint!}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (error.position != null) ...[
                Text(
                  'Position: character ${error.position}',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Text(outcome.sql, style: monoStyle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DefaultTextStyle.merge(
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        child: child,
      ),
    );
  }
}

/// Virtualized result grid with a pinned header row and row-number column.
/// Also used by the inspector to show metadata tables.
class ResultGrid extends StatefulWidget {
  const ResultGrid({
    super.key,
    required this.result,
    this.editor,
    this.onSelectedRowChanged,
  });

  final QueryResult result;

  /// When set, cells can be edited and rows added or deleted; changes are
  /// staged in the controller. Its base rows must be [result]'s rows.
  final DataEditController? editor;

  /// Reports the selected row as a data index (see [DataEditController]).
  final ValueChanged<int?>? onSelectedRowChanged;

  @override
  State<ResultGrid> createState() => _ResultGridState();
}

class _ResultGridState extends State<ResultGrid> {
  static const _rowHeight = 26.0;
  static const _headerHeight = 40.0;

  /// Longer or multi-line values are edited in a dialog instead of inline.
  static const _inlineEditMaxLength = 200;

  late final List<double> _widths = _measureColumns();
  late List<int> _order = List.generate(widget.result.rows.length, (i) => i);
  int? _sortColumn;
  bool _ascending = true;
  (int row, int column)? _selected;
  final _focusNode = FocusNode();
  final _vertical = ScrollController();

  // Inline cell editing.
  (int row, int column)? _editing;
  String? _editInitial;
  final _editController = TextEditingController();
  final _editFocus = FocusNode();

  late int _lastRowCount = _rowCount;

  QueryResult get result => widget.result;
  DataEditController? get editor => widget.editor;

  int get _rowCount => editor?.rowCount ?? result.rows.length;

  @override
  void initState() {
    super.initState();
    _editFocus.addListener(() {
      // Clicking elsewhere keeps what was typed, like a spreadsheet.
      if (!_editFocus.hasFocus && _editing != null) _commitEdit();
    });
    editor?.addListener(_onEditorChanged);
  }

  @override
  void didUpdateWidget(ResultGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editor != editor) {
      oldWidget.editor?.removeListener(_onEditorChanged);
      editor?.addListener(_onEditorChanged);
    }
  }

  @override
  void dispose() {
    editor?.removeListener(_onEditorChanged);
    _focusNode.dispose();
    _vertical.dispose();
    _editController.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  void _onEditorChanged() {
    final count = _rowCount;
    final added = count > _lastRowCount;
    _lastRowCount = count;
    setState(() {
      // A row deleted below the selection can leave it out of range.
      if (_selected case (final row, _) when row >= count) _select(null);
    });
    if (added) {
      // Show and select the new row.
      _select((count - 1, 0));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_vertical.hasClients) {
          _vertical.jumpTo(_vertical.position.maxScrollExtent);
        }
      });
    }
  }

  void _select((int, int)? cell) {
    _selected = cell;
    widget.onSelectedRowChanged?.call(cell == null ? null : _dataRow(cell.$1));
  }

  /// Display row → data row: loaded rows follow the sort order, inserted
  /// rows stay at the end.
  int _dataRow(int row) => row < _order.length ? _order[row] : row;

  bool _canEdit(int row) =>
      editor != null && editor!.rowChange(_dataRow(row)) != RowChange.deleted;

  Future<void> _startEdit(int row, int column) async {
    final editor = this.editor;
    if (editor == null || !_canEdit(row)) return;
    final text = editor.editTextAt(_dataRow(row), column);
    if (text != null &&
        (text.contains('\n') || text.length > _inlineEditMaxLength)) {
      return _editInDialog(row, column);
    }
    setState(() {
      _select((row, column));
      _editing = (row, column);
      _editInitial = text;
      _editController.text = text ?? '';
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _editController.text.length,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocus.requestFocus();
    });
  }

  void _commitEdit() {
    final editing = _editing;
    if (editing == null) return;
    final text = _editController.text;
    _editing = null;
    // Opening a NULL cell and leaving it empty is not a change.
    final unchanged =
        text == _editInitial || (_editInitial == null && text.isEmpty);
    if (!unchanged) {
      editor?.setCell(_dataRow(editing.$1), editing.$2, CellValue(text));
    }
    setState(() {});
    _focusNode.requestFocus();
  }

  void _cancelEdit() {
    setState(() => _editing = null);
    _focusNode.requestFocus();
  }

  Future<void> _editInDialog(int row, int column) async {
    final editor = this.editor;
    if (editor == null || !_canEdit(row)) return;
    final data = _dataRow(row);
    final info = result.columns[column];
    final value = await showDialog<CellValue>(
      context: context,
      builder: (_) => _CellEditDialog(
        title: '${info.name}  (${info.dataType})',
        initial: editor.editTextAt(data, column),
      ),
    );
    if (value != null) editor.setCell(data, column, value);
  }

  void _deleteSelectedRow() {
    final selected = _selected;
    if (selected == null || editor == null) return;
    editor!.deleteRow(_dataRow(selected.$1));
  }

  /// Width from header and a sample of rows, ~7.5px per character.
  List<double> _measureColumns() {
    final sample = result.rows.take(200);
    return [
      for (final (i, column) in result.columns.indexed)
        (math.max(
                      math.max(column.name.length, column.dataType.length),
                      sample.fold<int>(
                        0,
                        (m, row) =>
                            math.max(m, (formatValue(row[i]) ?? 'NULL').length),
                      ),
                    ) *
                    7.5 +
                28)
            .clamp(70.0, 420.0),
    ];
  }

  void _sortBy(int column) {
    setState(() {
      if (_sortColumn == column) {
        if (!_ascending) {
          // Third click clears the sort.
          _sortColumn = null;
          _order = List.generate(result.rows.length, (i) => i);
          return;
        }
        _ascending = false;
      } else {
        _sortColumn = column;
        _ascending = true;
      }
      final rows = result.rows;
      _order.sort((a, b) {
        final cmp = _compare(rows[a][column], rows[b][column]);
        return _ascending ? cmp : -cmp;
      });
    });
  }

  /// NULLs sort last; mixed types fall back to text comparison.
  static int _compare(Object? a, Object? b) {
    if (a == null || b == null) {
      return a == null ? (b == null ? 0 : 1) : -1;
    }
    if (a is num && b is num) return a.compareTo(b);
    if (a is DateTime && b is DateTime) return a.compareTo(b);
    if (a is bool && b is bool) return a == b ? 0 : (a ? 1 : -1);
    return (formatValue(a) ?? '').compareTo(formatValue(b) ?? '');
  }

  /// The loaded value; null for inserted rows.
  Object? _valueAt(int row, int column) {
    final data = _dataRow(row);
    return data < result.rows.length ? result.rows[data][column] : null;
  }

  /// Full text of a cell as currently shown, including staged edits.
  String _fullTextAt(int row, int column) {
    if (editor?.stagedAt(_dataRow(row), column) case final staged?) {
      return staged.text ?? 'NULL';
    }
    return formatValueFull(_valueAt(row, column));
  }

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
  }

  void _copySelected() {
    final selected = _selected;
    if (selected == null) return;
    _copy(_fullTextAt(selected.$1, selected.$2));
  }

  String _rowAsTsv(int row) => [
    for (var c = 0; c < result.columns.length; c++)
      editor?.displayTextAt(_dataRow(row), c) ??
          formatValue(_valueAt(row, c)) ??
          '',
  ].join('\t');

  Future<void> _showCellMenu(Offset position, int row, int column) async {
    setState(() => _select((row, column)));
    final editor = this.editor;
    final data = _dataRow(row);
    final change = editor?.rowChange(data);
    final staged = editor?.stagedAt(data, column) != null;
    final editable = _canEdit(row);
    final error = Theme.of(context).colorScheme.error;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        if (editable) ...[
          const PopupMenuItem(value: 'edit', child: Text('Edit cell')),
          const PopupMenuItem(
            value: 'editDialog',
            child: Text('Edit in dialog…'),
          ),
          const PopupMenuItem(value: 'null', child: Text('Set to NULL')),
          if (staged)
            const PopupMenuItem(value: 'revert', child: Text('Revert cell')),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(value: 'value', child: Text('Copy value')),
        const PopupMenuItem(value: 'row', child: Text('Copy row')),
        const PopupMenuItem(value: 'view', child: Text('View value…')),
        if (editor != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'addRow', child: Text('Add row')),
          if (change == RowChange.deleted)
            const PopupMenuItem(value: 'restoreRow', child: Text('Restore row'))
          else
            PopupMenuItem(
              value: 'deleteRow',
              child: Text('Delete row', style: TextStyle(color: error)),
            ),
        ],
      ],
    );
    switch (action) {
      case 'edit':
        _startEdit(row, column);
      case 'editDialog':
        _editInDialog(row, column);
      case 'null':
        editor?.setCell(data, column, const CellValue.nul());
      case 'revert':
        editor?.revertCell(data, column);
      case 'addRow':
        editor?.addRow();
      case 'deleteRow':
        editor?.deleteRow(data);
      case 'restoreRow':
        editor?.restoreRow(data);
      case 'value':
        _copy(_fullTextAt(row, column));
      case 'row':
        _copy(_rowAsTsv(row));
      case 'view':
        _showValue(row, column);
    }
  }

  void _showValue(int row, int column) {
    final text = _fullTextAt(row, column);
    final columnInfo = result.columns[column];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${columnInfo.name}  (${columnInfo.dataType})'),
        content: SizedBox(
          width: 640,
          height: 400,
          child: SingleChildScrollView(
            child: SelectableText(text, style: monoStyle),
          ),
        ),
        actions: [
          TextButton(onPressed: () => _copy(text), child: const Text('Copy')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final border = BorderSide(
      color: scheme.outlineVariant.withValues(alpha: 0.6),
    );
    final rowCount = _rowCount;
    final numberWidth = math.max(44.0, '$rowCount'.length * 8.0 + 20);

    void editSelected() {
      if (_selected case (final row, final column)) _startEdit(row, column);
    }

    return CallbackShortcuts(
      // While a cell is being typed in, keys belong to its text field.
      bindings: _editing != null
          ? const {}
          : {
              const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                  _copySelected,
              const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
                  _copySelected,
              if (editor != null) ...{
                const SingleActivator(LogicalKeyboardKey.enter): editSelected,
                const SingleActivator(LogicalKeyboardKey.f2): editSelected,
                const SingleActivator(LogicalKeyboardKey.delete):
                    _deleteSelectedRow,
              },
            },
      child: Focus(
        focusNode: _focusNode,
        child: TableView.builder(
          verticalDetails: ScrollableDetails.vertical(controller: _vertical),
          pinnedRowCount: 1,
          pinnedColumnCount: 1,
          rowCount: rowCount + 1,
          columnCount: result.columns.length + 1,
          diagonalDragBehavior: DiagonalDragBehavior.free,
          columnBuilder: (index) => TableSpan(
            extent: FixedTableSpanExtent(
              index == 0 ? numberWidth : _widths[index - 1],
            ),
            foregroundDecoration: TableSpanDecoration(
              border: TableSpanBorder(trailing: border),
            ),
          ),
          rowBuilder: (index) => TableSpan(
            extent: FixedTableSpanExtent(
              index == 0 ? _headerHeight : _rowHeight,
            ),
            backgroundDecoration: TableSpanDecoration(
              color: index == 0
                  ? scheme.surfaceContainerHigh
                  : (index.isEven ? scheme.surfaceContainerLowest : null),
            ),
            foregroundDecoration: TableSpanDecoration(
              border: TableSpanBorder(trailing: border),
            ),
          ),
          cellBuilder: (context, vicinity) {
            final row = vicinity.row;
            final column = vicinity.column;
            if (row == 0) {
              return TableViewCell(
                child: column == 0
                    ? const SizedBox.shrink()
                    : _header(column - 1),
              );
            }
            if (column == 0) {
              final change =
                  editor?.rowChange(_dataRow(row - 1)) ?? RowChange.none;
              final marker = _changeColor(change, scheme);
              return TableViewCell(
                child: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    border: marker == null
                        ? null
                        : Border(left: BorderSide(color: marker, width: 3)),
                  ),
                  child: Text(
                    switch (change) {
                      RowChange.inserted => '+',
                      RowChange.deleted => '−',
                      _ => '$row',
                    },
                    style: monoStyle.copyWith(
                      fontSize: 11,
                      fontWeight: change == RowChange.none
                          ? null
                          : FontWeight.w700,
                      color: marker ?? scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }
            return TableViewCell(child: _cell(row - 1, column - 1));
          },
        ),
      ),
    );
  }

  Widget _header(int column) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = result.columns[column];
    final sorted = _sortColumn == column;

    return InkWell(
      onTap: () => _sortBy(column),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          info.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: sorted ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                      ),
                      if (sorted) ...[
                        const SizedBox(width: 4),
                        Icon(
                          _ascending
                              ? Icons.arrow_upward_rounded
                              : Icons.arrow_downward_rounded,
                          size: 13,
                          color: scheme.primary,
                        ),
                      ],
                    ],
                  ),
                  if (info.dataType.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        info.dataType,
                        overflow: TextOverflow.ellipsis,
                        style: monoBadgeStyle.copyWith(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const _insertedColor = Color(0xFF10B981);

  /// Marker color for a changed row; null when unchanged.
  static Color? _changeColor(RowChange change, ColorScheme scheme) =>
      switch (change) {
        RowChange.none => null,
        RowChange.updated => Colors.amber.shade700,
        RowChange.inserted => _insertedColor,
        RowChange.deleted => scheme.error,
      };

  Widget _cell(int row, int column) {
    final scheme = Theme.of(context).colorScheme;
    final data = _dataRow(row);
    final change = editor?.rowChange(data) ?? RowChange.none;
    final staged = editor?.stagedAt(data, column);
    final value = _valueAt(row, column);
    final selected = _selected == (row, column);

    if (_editing == (row, column)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.primary, width: 1.5),
        ),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _cancelEdit,
          },
          child: TextField(
            controller: _editController,
            focusNode: _editFocus,
            style: monoStyle,
            decoration: const InputDecoration.collapsed(hintText: ''),
            onSubmitted: (_) => _commitEdit(),
          ),
        ),
      );
    }

    // What to show: the staged value, DEFAULT for an untouched cell of a new
    // row, or the loaded value.
    final isDefault = change == RowChange.inserted && staged == null;
    final text = staged != null ? staged.text : formatValue(value);
    final isNumber = staged == null && value is num;

    final Color? background = switch (change) {
      RowChange.deleted => scheme.error.withValues(alpha: 0.10),
      RowChange.inserted => _insertedColor.withValues(alpha: 0.10),
      _ when staged != null => Colors.amber.withValues(alpha: 0.18),
      _ => null,
    };

    Widget badge(String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: monoBadgeStyle.copyWith(
          fontSize: 10,
          fontStyle: FontStyle.italic,
          color: scheme.outline,
        ),
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _focusNode.requestFocus();
        setState(() => _select((row, column)));
      },
      onDoubleTap: () =>
          editor != null ? _startEdit(row, column) : _showValue(row, column),
      onSecondaryTapDown: (d) => _showCellMenu(d.globalPosition, row, column),
      onLongPressStart: (d) => _showCellMenu(d.globalPosition, row, column),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: isNumber ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.15) : background,
          border: selected
              ? Border.all(color: scheme.primary, width: 1.5)
              : null,
        ),
        child: isDefault
            ? badge('DEFAULT')
            : text == null
            ? badge('NULL')
            : Text(
                text.replaceAll('\n', '↵'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle.copyWith(
                  color: change == RowChange.deleted
                      ? scheme.onSurfaceVariant
                      : isNumber
                      ? scheme.primary
                      : null,
                  decoration: change == RowChange.deleted
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
      ),
    );
  }
}

/// Multi-line editor for long values (JSON, text), with a NULL option.
class _CellEditDialog extends StatefulWidget {
  const _CellEditDialog({required this.title, required this.initial});

  final String title;
  final String? initial;

  @override
  State<_CellEditDialog> createState() => _CellEditDialogState();
}

class _CellEditDialogState extends State<_CellEditDialog> {
  late final _controller = TextEditingController(text: widget.initial ?? '');
  late bool _isNull = widget.initial == null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 640,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_isNull,
                autofocus: true,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: monoStyle,
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('NULL'),
              value: _isNull,
              onChanged: (v) => setState(() => _isNull = v ?? false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(
            context,
          ).pop(_isNull ? const CellValue.nul() : CellValue(_controller.text)),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
