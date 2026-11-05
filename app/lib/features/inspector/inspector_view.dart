import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../../drivers/driver.dart';
import '../../drivers/postgres/postgres_sql.dart';
import '../../state/providers.dart';
import '../../state/workspace_tabs.dart';
import '../connections/connection_dialog.dart';
import '../editor/workspace.dart';
import '../results/export_dialog.dart';
import '../results/results_view.dart';

/// DBeaver-style object editor: data preview, metadata tables and DDL for
/// one table, view, materialized view or sequence.
class InspectorView extends ConsumerWidget {
  const InspectorView({super.key, required this.tab});

  final InspectorTab tab;

  RelationKey get _key =>
      (tab.connectionId, tab.object.schema, tab.object.name);

  String get _selectSql =>
      'SELECT * FROM ${qualifiedName(tab.object.schema, tab.object.name)} '
      'LIMIT ${InspectorTab.previewRows}';

  void _refresh(BuildContext context, WidgetRef ref) {
    final key = _key;
    ref
      ..invalidate(columnsProvider(key))
      ..invalidate(constraintsProvider(key))
      ..invalidate(indexesProvider(key))
      ..invalidate(triggersProvider(key))
      ..invalidate(partitionsProvider(key))
      ..invalidate(ddlProvider(key));
    _loadPreview(context, ref, force: true);
  }

  Future<void> _loadPreview(
    BuildContext context,
    WidgetRef ref, {
    bool force = false,
  }) async {
    if (tab.previewLoaded && !force) return;
    final config = (ref.read(connectionsProvider).value ?? const [])
        .where((c) => c.id == tab.connectionId)
        .firstOrNull;
    if (config == null) return;
    final driver = await connectWithPrompt(context, ref, config);
    if (driver != null) await tab.loadPreview(driver, _selectSql);
  }

  void _openInEditor(WidgetRef ref, String sql) {
    ref
        .read(workspaceTabsProvider.notifier)
        .open(tab.connectionId, initialText: sql);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final object = tab.object;
    final sections = _sectionsFor(object.kind);

    return DefaultTabController(
      length: sections.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: _kindColor(object.kind).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    _kindIcon(object.kind),
                    size: 16,
                    color: _kindColor(object.kind),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${object.schema}.${object.name}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: _kindColor(object.kind).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _kindColor(object.kind).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    object.kind.label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _kindColor(object.kind),
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                  ),
                  icon: const Icon(Icons.code_rounded, size: 15),
                  label: const Text(
                    'Query in SQL',
                    style: TextStyle(fontSize: 12),
                  ),
                  onPressed: () => _openInEditor(ref, '$_selectSql;'),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: () => _refresh(context, ref),
                ),
              ],
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final s in sections) Tab(text: s.label, height: 36)],
          ),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [for (final s in sections) _page(context, ref, s)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _page(BuildContext context, WidgetRef ref, _Section section) {
    final key = _key;
    return switch (section) {
      _Section.data => _DataPage(
        tab: tab,
        load: () => _loadPreview(context, ref),
      ),
      _Section.columns => _MetadataPage(
        value: ref.watch(columnsProvider(key)),
        empty: 'No columns',
        headers: const ['#', 'Name', 'Type', 'Not null', 'Default', 'PK'],
        row: (i, c) => [
          i + 1,
          c.name,
          c.dataType,
          !c.nullable,
          c.defaultValue,
          c.isPrimaryKey,
        ],
      ),
      _Section.constraints => _MetadataPage(
        value: ref.watch(constraintsProvider(key)),
        include: (c) => c.kind != ConstraintKind.foreignKey,
        empty: 'No constraints',
        headers: const ['Name', 'Type', 'Definition'],
        row: (_, c) => [c.name, c.kind.label, c.definition],
      ),
      _Section.foreignKeys => _MetadataPage(
        value: ref.watch(constraintsProvider(key)),
        include: (c) => c.kind == ConstraintKind.foreignKey,
        empty: 'No foreign keys',
        headers: const ['Name', 'References', 'Definition'],
        row: (_, c) => [c.name, c.referencedTable, c.definition],
      ),
      _Section.indexes => _MetadataPage(
        value: ref.watch(indexesProvider(key)),
        empty: 'No indexes',
        headers: const ['Name', 'Unique', 'Primary', 'Size', 'Definition'],
        row: (_, i) => [i.name, i.isUnique, i.isPrimary, i.size, i.definition],
      ),
      _Section.triggers => _MetadataPage(
        value: ref.watch(triggersProvider(key)),
        empty: 'No triggers',
        headers: const ['Name', 'Enabled', 'Definition'],
        row: (_, t) => [t.name, t.enabled, t.definition],
      ),
      _Section.partitions => _MetadataPage(
        value: ref.watch(partitionsProvider(key)),
        empty: 'No partitions',
        headers: const ['Name', 'Kind', 'Bound'],
        row: (_, p) => [p.object.name, p.object.kind.label, p.bound],
      ),
      _Section.ddl => _DdlPage(
        value: ref.watch(ddlProvider(key)),
        onOpenInEditor: (sql) => _openInEditor(ref, sql),
      ),
    };
  }

  static List<_Section> _sectionsFor(DbObjectKind kind) => switch (kind) {
    DbObjectKind.table => const [
      _Section.data,
      _Section.columns,
      _Section.constraints,
      _Section.foreignKeys,
      _Section.indexes,
      _Section.triggers,
      _Section.ddl,
    ],
    DbObjectKind.partitionedTable => const [
      _Section.data,
      _Section.columns,
      _Section.constraints,
      _Section.foreignKeys,
      _Section.indexes,
      _Section.triggers,
      _Section.partitions,
      _Section.ddl,
    ],
    DbObjectKind.view => const [
      _Section.data,
      _Section.columns,
      _Section.triggers,
      _Section.ddl,
    ],
    DbObjectKind.materializedView => const [
      _Section.data,
      _Section.columns,
      _Section.indexes,
      _Section.ddl,
    ],
    DbObjectKind.foreignTable => const [
      _Section.data,
      _Section.columns,
      _Section.constraints,
      _Section.ddl,
    ],
    DbObjectKind.sequence => const [_Section.data, _Section.ddl],
  };

  static IconData _kindIcon(DbObjectKind kind) => switch (kind) {
    DbObjectKind.table => Icons.table_chart_rounded,
    DbObjectKind.partitionedTable => Icons.view_module_rounded,
    DbObjectKind.view => Icons.visibility_rounded,
    DbObjectKind.materializedView => Icons.auto_awesome_motion_rounded,
    DbObjectKind.foreignTable => Icons.link_rounded,
    DbObjectKind.sequence => Icons.pin_rounded,
  };

  static Color _kindColor(DbObjectKind kind) => switch (kind) {
    DbObjectKind.table => const Color(0xFF0EA5E9),
    DbObjectKind.partitionedTable => const Color(0xFF3B82F6),
    DbObjectKind.view => const Color(0xFFA855F7),
    DbObjectKind.materializedView => const Color(0xFF8B5CF6),
    DbObjectKind.foreignTable => const Color(0xFF10B981),
    DbObjectKind.sequence => const Color(0xFFF59E0B),
  };
}

enum _Section {
  data('Data'),
  columns('Columns'),
  constraints('Constraints'),
  foreignKeys('Foreign Keys'),
  indexes('Indexes'),
  triggers('Triggers'),
  partitions('Partitions'),
  ddl('DDL');

  const _Section(this.label);

  final String label;
}

class _DataPage extends StatefulWidget {
  const _DataPage({required this.tab, required this.load});

  final InspectorTab tab;
  final Future<void> Function() load;

  @override
  State<_DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<_DataPage> {
  @override
  void initState() {
    super.initState();
    // Load lazily, the first time the Data tab is shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    return ListenableBuilder(
      listenable: tab,
      builder: (context, _) {
        final preview = tab.preview;
        if (tab.busy && preview == null) {
          return const Center(child: CircularProgressIndicator());
        }
        if (tab.previewError case final error?) {
          return _CenteredMessage(error.toString(), isError: true);
        }
        if (preview == null) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tab.busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ResultGrid(key: ObjectKey(preview), result: preview),
            ),
            _Footer(
              preview.truncated
                  ? 'First ${preview.rows.length} rows — use "Query in SQL '
                        'editor" to filter or see more'
                  : '${preview.rows.length} row(s)',
              trailing: preview.rows.isEmpty
                  ? null
                  : TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      icon: const Icon(Icons.file_download_outlined, size: 14),
                      label: const Text('Export…'),
                      onPressed: () => showExportDialog(
                        context,
                        result: preview,
                        defaultTableName: qualifiedName(
                          tab.object.schema,
                          tab.object.name,
                        ),
                        fileName: tab.object.name,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// A metadata list (columns, indexes…) shown in the result grid, so it gets
/// sorting, copy and the value viewer for free.
class _MetadataPage<T> extends StatelessWidget {
  const _MetadataPage({
    required this.value,
    required this.headers,
    required this.row,
    required this.empty,
    this.include,
  });

  final AsyncValue<List<T>> value;
  final List<String> headers;
  final List<Object?> Function(int index, T item) row;
  final String empty;
  final bool Function(T item)? include;

  @override
  Widget build(BuildContext context) {
    return value.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _CenteredMessage('$e', isError: true),
      data: (all) {
        final items = include == null ? all : all.where(include!).toList();
        if (items.isEmpty) return _CenteredMessage(empty);
        final result = QueryResult(
          columns: [
            for (final h in headers) ResultColumn(name: h, dataType: ''),
          ],
          rows: [for (final (i, item) in items.indexed) row(i, item)],
          affectedRows: 0,
          elapsed: Duration.zero,
          truncated: false,
        );
        return ResultGrid(key: ObjectKey(items), result: result);
      },
    );
  }
}

class _DdlPage extends StatefulWidget {
  const _DdlPage({required this.value, required this.onOpenInEditor});

  final AsyncValue<String> value;
  final void Function(String sql) onOpenInEditor;

  @override
  State<_DdlPage> createState() => _DdlPageState();
}

class _DdlPageState extends State<_DdlPage> {
  final _controller = CodeLineEditingController();

  @override
  void initState() {
    super.initState();
    _syncText();
  }

  @override
  void didUpdateWidget(_DdlPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncText();
  }

  void _syncText() {
    final ddl = widget.value.value;
    if (ddl != null && _controller.text != ddl) _controller.text = ddl;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.value.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _CenteredMessage('$e', isError: true),
      data: (ddl) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: ddl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('DDL copied'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.code, size: 16),
                    label: const Text('Open in SQL editor'),
                    onPressed: () => widget.onOpenInEditor(ddl),
                  ),
                ],
              ),
            ),
            const Divider(),
            Expanded(child: SqlEditor(controller: _controller, readOnly: true)),
          ],
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer(this.text, {this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 28,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.text, {this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SelectableText(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isError ? scheme.error : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
