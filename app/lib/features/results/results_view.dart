import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../drivers/export.dart';
import '../../drivers/value_format.dart';
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
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
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
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),

          if (result.hasResultSet) ...[
            const SizedBox(width: 12),
            Text('·', style: TextStyle(color: scheme.outlineVariant)),
            const SizedBox(width: 12),
            Text(
              '${result.columns.length} cols',
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              ),
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
                  Icon(Icons.warning_amber_rounded,
                      size: 12, color: Colors.amber.shade700),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.table_chart_outlined,
                          size: 12, color: scheme.primary),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.data_object_rounded,
                          size: 12, color: scheme.primary),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.file_download_outlined,
                          size: 13, color: scheme.onSurfaceVariant),
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
                    child: Icon(Icons.error_outline_rounded, size: 20, color: scheme.error),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
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
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: scheme.onSurface),
                ),
                const SizedBox(height: 2),
                Text(
                  error.detail!,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
              ],
              if (error.hint != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline_rounded, size: 16, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Hint: ${error.hint!}',
                          style: TextStyle(fontSize: 12, color: scheme.onSurface),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (error.position != null) ...[
                Text('Position: character ${error.position}', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
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
                color: scheme.primary.withValues(alpha: 0.15),
                border: Border.all(color: scheme.primary, width: 1.5),
              )
            : null,
        child: text == null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'NULL',
                  style: monoBadgeStyle.copyWith(
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                    color: scheme.outline,
                  ),
                ),
              )
            : Text(
                text.replaceAll('\n', '↵'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: monoStyle.copyWith(
                  color: isNumber ? scheme.primary : null,
                ),
              ),
      ),
    );
  }
}
