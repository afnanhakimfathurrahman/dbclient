import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../drivers/value_format.dart';
import '../../state/workspace_tabs.dart';

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
    return SizedBox(
      height: 36,
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
                      ? Icons.error_outline
                      : (o.result?.hasResultSet ?? false)
                      ? Icons.table_rows_outlined
                      : Icons.check,
                  size: 16,
                  color: o.error != null ? scheme.error : null,
                ),
                label: Text('${i + 1}'),
                tooltip: o.sql,
              ),
            ),
          if (tab.running)
            const Padding(
              padding: EdgeInsets.all(6),
              child: SizedBox.square(
                dimension: 16,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parts = <String>[
      if (result.hasResultSet)
        '${result.rows.length} row(s)${result.truncated ? ' — limit reached, more rows not fetched' : ''}'
      else
        '${result.affectedRows} row(s) affected',
      '${result.elapsed.inMilliseconds} ms',
    ];
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Text(
        parts.join('  ·  '),
        style: theme.textTheme.bodySmall?.copyWith(
          color: result.truncated ? Colors.orange.shade700 : null,
        ),
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
      padding: const EdgeInsets.all(16),
      child: SelectionArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error.message,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (error.code != null) Text('SQL state: ${error.code}'),
            if (error.detail != null) Text('Detail: ${error.detail}'),
            if (error.hint != null) Text('Hint: ${error.hint}'),
            if (error.position != null) Text('Position: ${error.position}'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: scheme.surfaceContainerHighest,
              child: Text(outcome.sql, style: monoStyle),
            ),
          ],
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
  const ResultGrid({super.key, required this.result});

  final QueryResult result;

  @override
  State<ResultGrid> createState() => _ResultGridState();
}

class _ResultGridState extends State<ResultGrid> {
  static const _rowHeight = 26.0;
  static const _headerHeight = 40.0;

  late final List<double> _widths = _measureColumns();
  late List<int> _order = List.generate(widget.result.rows.length, (i) => i);
  int? _sortColumn;
  bool _ascending = true;
  (int row, int column)? _selected;
  final _focusNode = FocusNode();

  QueryResult get result => widget.result;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
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

  Object? _valueAt(int row, int column) => result.rows[_order[row]][column];

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
  }

  void _copySelected() {
    final selected = _selected;
    if (selected == null) return;
    _copy(formatValueFull(_valueAt(selected.$1, selected.$2)));
  }

  String _rowAsTsv(int row) => [
    for (var c = 0; c < result.columns.length; c++)
      formatValue(_valueAt(row, c)) ?? '',
  ].join('\t');

  Future<void> _showCellMenu(Offset position, int row, int column) async {
    setState(() => _selected = (row, column));
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'value', child: Text('Copy value')),
        PopupMenuItem(value: 'row', child: Text('Copy row')),
        PopupMenuItem(value: 'view', child: Text('View value…')),
      ],
    );
    switch (action) {
      case 'value':
        _copy(formatValueFull(_valueAt(row, column)));
      case 'row':
        _copy(_rowAsTsv(row));
      case 'view':
        _showValue(row, column);
    }
  }

  void _showValue(int row, int column) {
    final value = _valueAt(row, column);
    final text = formatValueFull(value);
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
    final rowCount = result.rows.length;
    final numberWidth = math.max(44.0, '$rowCount'.length * 8.0 + 20);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyC, control: true):
            _copySelected,
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            _copySelected,
      },
      child: Focus(
        focusNode: _focusNode,
        child: TableView.builder(
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
              return TableViewCell(
                child: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  color: scheme.surfaceContainerHigh,
                  child: Text(
                    '$row',
                    style: monoStyle.copyWith(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
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
                  Text(
                    info.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (info.dataType.isNotEmpty)
                    Text(
                      info.dataType,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            if (sorted)
              Icon(
                _ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 14,
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(int row, int column) {
    final scheme = Theme.of(context).colorScheme;
    final value = _valueAt(row, column);
    final text = formatValue(value);
    final selected = _selected == (row, column);
    final isNumber = value is num;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _focusNode.requestFocus();
        setState(() => _selected = (row, column));
      },
      onDoubleTap: () => _showValue(row, column),
      onSecondaryTapDown: (d) => _showCellMenu(d.globalPosition, row, column),
      onLongPressStart: (d) => _showCellMenu(d.globalPosition, row, column),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: isNumber ? Alignment.centerRight : Alignment.centerLeft,
        decoration: selected
            ? BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.6),
                border: Border.all(color: scheme.primary),
              )
            : null,
        child: Text(
          text == null ? 'NULL' : text.replaceAll('\n', '↵'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: monoStyle.copyWith(
            fontStyle: text == null ? FontStyle.italic : null,
            color: text == null ? scheme.outline : null,
          ),
        ),
      ),
    );
  }
}
