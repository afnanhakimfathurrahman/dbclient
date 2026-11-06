import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:two_dimensional_scrollables/two_dimensional_scrollables.dart';

import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../drivers/postgres/postgres_sql.dart';
import '../../drivers/sql_splitter.dart';
import '../../drivers/value_format.dart';
import '../../state/data_editor.dart';
import '../../state/providers.dart';
import '../../state/workspace_tabs.dart';
import '../connections/connection_dialog.dart';
import '../editor/workspace.dart';
import '../results/export_dialog.dart';
import '../results/results_view.dart';
import 'dialogs/column_dialog.dart';
import 'dialogs/constraint_dialog.dart';
import 'dialogs/drop_confirm_dialog.dart';
import 'dialogs/index_dialog.dart';
import 'dialogs/save_changes_dialog.dart';
import 'dialogs/trigger_dialog.dart';

/// DBeaver-style object editor: data preview, metadata tables and DDL for
/// one table, view, materialized view or sequence.
class InspectorView extends ConsumerWidget {
  const InspectorView({super.key, required this.tab});

  final InspectorTab tab;

  RelationKey get _key =>
      (tab.connectionId, tab.object.schema, tab.object.name);

  String _selectSql(int limit) =>
      'SELECT * FROM ${qualifiedName(tab.object.schema, tab.object.name)} '
      'LIMIT $limit';

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
    final driver = await connectSqlWithPrompt(context, ref, config);
    if (driver != null) {
      // One extra row tells whether the table has more than the limit.
      await tab.loadPreview(driver, _selectSql(tab.rowLimit + 1));
    }
  }

  void _openInEditor(WidgetRef ref, String sql) {
    ref
        .read(workspaceTabsProvider.notifier)
        .open(tab.connectionId, initialText: sql);
  }

  /// Runs [statements] in one transaction. Throws if not connected, so the
  /// calling dialog stays open and shows why nothing happened.
  Future<void> _executeAll(
    BuildContext context,
    WidgetRef ref,
    List<String> statements,
  ) async {
    final config = (ref.read(connectionsProvider).value ?? const [])
        .where((c) => c.id == tab.connectionId)
        .firstOrNull;
    final driver = config == null
        ? null
        : await connectSqlWithPrompt(context, ref, config);
    if (driver == null) throw const DriverException('Not connected');
    await driver.executeAll(statements);
  }

  /// True if there are no unsaved row edits, or the user agrees to drop them.
  Future<bool> _confirmDiscard(BuildContext context) async {
    final count = tab.editor?.pendingCount ?? 0;
    if (count == 0) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: Text(
          '$count edited ${count == 1 ? 'row' : 'rows'} in '
          '${tab.object.name} will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  Future<void> _executeDdl(
    BuildContext context,
    WidgetRef ref,
    String sql, {
    String? successMessage,
  }) async {
    // One transaction, so a multi-statement change never half-applies.
    await _executeAll(context, ref, [for (final s in splitSql(sql)) s.text]);

    if (context.mounted) {
      if (successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      _refresh(context, ref);
      invalidateMetadata(ref, tab.connectionId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final object = tab.object;
    final features = _features(ref);
    final sections = [
      for (final s in _sectionsFor(object.kind))
        if (s.feature == null || features.contains(s.feature)) s,
    ];

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
                  onPressed: () =>
                      _openInEditor(ref, '${_selectSql(tab.rowLimit)};'),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  onPressed: () async {
                    if (await _confirmDiscard(context) && context.mounted) {
                      _refresh(context, ref);
                    }
                  },
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
    final object = tab.object;
    // The schema dialogs generate PostgreSQL syntax.
    final editable = _features(ref).contains(SqlFeature.schemaEditing);
    final canManageColumns =
        editable &&
        (object.kind.isTable || object.kind == DbObjectKind.foreignTable);
    // Foreign tables can't have PK/UNIQUE/FK constraints.
    final canManageConstraints = editable && object.kind.isTable;
    final canManageForeignKeys = editable && object.kind.isTable;
    final canManageIndexes =
        editable &&
        (object.kind.isTable || object.kind == DbObjectKind.materializedView);
    final canManageTriggers =
        editable && (object.kind.isTable || object.kind == DbObjectKind.view);

    return switch (section) {
      _Section.data => _DataPage(
        tab: tab,
        load: () => _loadPreview(context, ref),
        reload: () => _loadPreview(context, ref, force: true),
        changeLimit: (limit) async {
          if (limit == tab.rowLimit || !await _confirmDiscard(context)) {
            return false;
          }
          tab.rowLimit = limit;
          ref.read(dataRowLimitProvider.notifier).set(limit);
          if (context.mounted) await _loadPreview(context, ref, force: true);
          return true;
        },
        save: (statements) => _executeAll(context, ref, statements),
        openInEditor: (sql) => _openInEditor(ref, sql),
      ),
      _Section.columns => _ManageableMetadataPage<ColumnInfo>(
        value: ref.watch(columnsProvider(key)),
        itemLabel: 'Column',
        empty: 'No columns',
        headers: const ['Name', 'Type', 'Not null', 'Default', 'PK'],
        row: (_, c) => [
          c.name,
          c.dataType,
          !c.nullable,
          c.defaultValue,
          c.isPrimaryKey,
        ],
        canManage: canManageColumns,
        onAdd: () => showColumnDialog(
          context,
          schema: object.schema,
          table: object.name,
          onExecute: (sql) =>
              _executeDdl(context, ref, sql, successMessage: 'Column added'),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
        onEdit: (col) => showColumnDialog(
          context,
          schema: object.schema,
          table: object.name,
          existing: col,
          onExecute: (sql) =>
              _executeDdl(context, ref, sql, successMessage: 'Column updated'),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
        onDelete: (col) => showDropConfirmDialog(
          context,
          title: 'Drop column "${col.name}"?',
          message:
              'Are you sure you want to drop column "${col.name}" from table "${object.schema}.${object.name}"? All data in this column will be lost.',
          objectName: col.name,
          objectType: 'Column',
          hasCascade: true,
          buildSql: (cascade) => buildDropColumnSql(
            schema: object.schema,
            table: object.name,
            name: col.name,
            cascade: cascade,
          ),
          onExecute: (sql) =>
              _executeDdl(context, ref, sql, successMessage: 'Column dropped'),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
      ),
      _Section.constraints => _ManageableMetadataPage<ConstraintInfo>(
        value: ref.watch(constraintsProvider(key)),
        include: (c) => c.kind != ConstraintKind.foreignKey,
        itemLabel: 'Constraint',
        empty: 'No constraints',
        headers: const ['Name', 'Type', 'Definition'],
        row: (_, c) => [c.name, c.kind.label, c.definition],
        canManage: canManageConstraints,
        onAdd: () => showConstraintDialog(
          context,
          schema: object.schema,
          table: object.name,
          columns: ref.read(columnsProvider(key)).value ?? const [],
          onExecute: (sql) => _executeDdl(
            context,
            ref,
            sql,
            successMessage: 'Constraint added',
          ),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
        onEdit: (c) => showConstraintDialog(
          context,
          schema: object.schema,
          table: object.name,
          existing: c,
          columns: ref.read(columnsProvider(key)).value ?? const [],
          onExecute: (sql) => _executeDdl(
            context,
            ref,
            sql,
            successMessage: 'Constraint updated',
          ),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
        onDelete: (c) => showDropConfirmDialog(
          context,
          title: 'Drop constraint "${c.name}"?',
          message:
              'Are you sure you want to drop constraint "${c.name}" from table "${object.schema}.${object.name}"?',
          objectName: c.name,
          objectType: 'Constraint',
          hasCascade: true,
          buildSql: (cascade) => buildDropConstraintSql(
            schema: object.schema,
            table: object.name,
            name: c.name,
            cascade: cascade,
          ),
          onExecute: (sql) => _executeDdl(
            context,
            ref,
            sql,
            successMessage: 'Constraint dropped',
          ),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
      ),
      _Section.foreignKeys => _ManageableMetadataPage<ConstraintInfo>(
        value: ref.watch(constraintsProvider(key)),
        include: (c) => c.kind == ConstraintKind.foreignKey,
        itemLabel: 'Foreign Key',
        empty: 'No foreign keys',
        headers: const ['Name', 'References', 'Definition'],
        row: (_, c) => [c.name, c.referencedTable, c.definition],
        canManage: canManageForeignKeys,
        onAdd: () => showConstraintDialog(
          context,
          schema: object.schema,
          table: object.name,
          columns: ref.read(columnsProvider(key)).value ?? const [],
          initialKind: ConstraintKind.foreignKey,
          onExecute: (sql) => _executeDdl(
            context,
            ref,
            sql,
            successMessage: 'Foreign key added',
          ),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
        onEdit: (c) => showConstraintDialog(
          context,
          schema: object.schema,
          table: object.name,
          existing: c,
          columns: ref.read(columnsProvider(key)).value ?? const [],
          initialKind: ConstraintKind.foreignKey,
          onExecute: (sql) => _executeDdl(
            context,
            ref,
            sql,
            successMessage: 'Foreign key updated',
          ),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
        onDelete: (c) => showDropConfirmDialog(
          context,
          title: 'Drop foreign key "${c.name}"?',
          message:
              'Are you sure you want to drop foreign key "${c.name}" from table "${object.schema}.${object.name}"?',
          objectName: c.name,
          objectType: 'Foreign Key',
          hasCascade: true,
          buildSql: (cascade) => buildDropConstraintSql(
            schema: object.schema,
            table: object.name,
            name: c.name,
            cascade: cascade,
          ),
          onExecute: (sql) => _executeDdl(
            context,
            ref,
            sql,
            successMessage: 'Foreign key dropped',
          ),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
      ),
      _Section.indexes => _ManageableMetadataPage<IndexInfo>(
        value: ref.watch(indexesProvider(key)),
        itemLabel: 'Index',
        empty: 'No indexes',
        headers: const ['Name', 'Unique', 'Primary', 'Size', 'Definition'],
        row: (_, i) => [i.name, i.isUnique, i.isPrimary, i.size, i.definition],
        canManage: canManageIndexes,
        onAdd: () => showIndexDialog(
          context,
          schema: object.schema,
          table: object.name,
          columns: ref.read(columnsProvider(key)).value ?? const [],
          onExecute: (sql) =>
              _executeDdl(context, ref, sql, successMessage: 'Index created'),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
        onEdit: (i) => showIndexDialog(
          context,
          schema: object.schema,
          table: object.name,
          existing: i,
          columns: ref.read(columnsProvider(key)).value ?? const [],
          onExecute: (sql) =>
              _executeDdl(context, ref, sql, successMessage: 'Index updated'),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
        onDelete: (i) => showDropConfirmDialog(
          context,
          title: 'Drop index "${i.name}"?',
          message:
              'Are you sure you want to drop index "${i.name}" from schema "${object.schema}"?',
          objectName: i.name,
          objectType: 'Index',
          hasCascade: true,
          buildSql: (cascade) => buildDropIndexSql(
            schema: object.schema,
            name: i.name,
            cascade: cascade,
          ),
          onExecute: (sql) =>
              _executeDdl(context, ref, sql, successMessage: 'Index dropped'),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
      ),
      _Section.triggers => _ManageableMetadataPage<TriggerInfo>(
        value: ref.watch(triggersProvider(key)),
        itemLabel: 'Trigger',
        empty: 'No triggers',
        headers: const ['Name', 'Enabled', 'Definition'],
        row: (_, t) => [t.name, t.enabled, t.definition],
        canManage: canManageTriggers,
        onAdd: () => showTriggerDialog(
          context,
          schema: object.schema,
          table: object.name,
          isView: object.kind == DbObjectKind.view,
          onExecute: (sql) =>
              _executeDdl(context, ref, sql, successMessage: 'Trigger created'),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
        onEdit: (t) => showTriggerDialog(
          context,
          schema: object.schema,
          table: object.name,
          existing: t,
          onExecute: (sql) =>
              _executeDdl(context, ref, sql, successMessage: 'Trigger updated'),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
        onDelete: (t) => showDropConfirmDialog(
          context,
          title: 'Drop trigger "${t.name}"?',
          message:
              'Are you sure you want to drop trigger "${t.name}" from table "${object.schema}.${object.name}"?',
          objectName: t.name,
          objectType: 'Trigger',
          hasCascade: true,
          buildSql: (cascade) => buildDropTriggerSql(
            schema: object.schema,
            table: object.name,
            name: t.name,
            cascade: cascade,
          ),
          onExecute: (sql) =>
              _executeDdl(context, ref, sql, successMessage: 'Trigger dropped'),
          onOpenInSql: (sql) => _openInEditor(ref, sql),
        ),
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

  Set<SqlFeature> _features(WidgetRef ref) =>
      ref.watch(sqlDriverProvider(tab.connectionId))?.features ?? const {};

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
  constraints('Constraints', SqlFeature.constraints),
  foreignKeys('Foreign Keys', SqlFeature.foreignKeys),
  indexes('Indexes', SqlFeature.indexes),
  triggers('Triggers', SqlFeature.triggers),
  partitions('Partitions', SqlFeature.partitions),
  ddl('DDL');

  const _Section(this.label, [this.feature]);

  final String label;

  /// Shown only for engines with this feature; null means always.
  final SqlFeature? feature;
}

class _DataPage extends StatefulWidget {
  const _DataPage({
    required this.tab,
    required this.load,
    required this.reload,
    required this.changeLimit,
    required this.save,
    required this.openInEditor,
  });

  final InspectorTab tab;
  final Future<void> Function() load;

  /// Re-queries the data, asking first if there are unsaved edits.
  final Future<void> Function() reload;

  /// Applies a new row limit and reloads; false if not applied (unchanged,
  /// or the user kept unsaved edits).
  final Future<bool> Function(int limit) changeLimit;
  final Future<void> Function(List<String> statements) save;
  final void Function(String sql) openInEditor;

  @override
  State<_DataPage> createState() => _DataPageState();
}

class _DataPageState extends State<_DataPage> {
  int? _selectedRow;

  Future<void> _save(DataEditController editor) async {
    final saved = await showSaveChangesDialog(
      context,
      table: '${widget.tab.object.schema}.${widget.tab.object.name}',
      changeCount: editor.pendingCount,
      statements: editor.buildStatements(),
      onExecute: widget.save,
      onOpenInSql: widget.openInEditor,
    );
    if (saved ?? false) {
      editor.clear();
      await widget.reload();
    }
  }

  Widget _toolbar(DataEditController? editor) {
    final scheme = Theme.of(context).colorScheme;
    const compact = VisualDensity.compact;
    final small = ButtonStyle(
      visualDensity: compact,
      padding: WidgetStateProperty.all(
        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12)),
    );
    final selected = _selectedRow;
    final selectedDeleted =
        selected != null && editor?.rowChange(selected) == RowChange.deleted;
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          if (editor == null)
            Expanded(
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      widget.tab.readOnlyReason ?? 'Read-only',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            FilledButton.tonalIcon(
              style: small,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Add row'),
              onPressed: editor.addRow,
            ),
            const SizedBox(width: 6),
            OutlinedButton.icon(
              style: small.copyWith(
                foregroundColor: selectedDeleted
                    ? null
                    : WidgetStateProperty.all(scheme.error),
              ),
              icon: Icon(
                selectedDeleted
                    ? Icons.restore_rounded
                    : Icons.delete_outline_rounded,
                size: 15,
              ),
              label: Text(selectedDeleted ? 'Restore row' : 'Delete row'),
              onPressed: selected == null || selected >= editor.rowCount
                  ? null
                  : () => selectedDeleted
                        ? editor.restoreRow(selected)
                        : editor.deleteRow(selected),
            ),
            const Spacer(),
            if (editor.hasChanges) ...[
              Text(
                '${editor.pendingCount} unsaved',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber.shade700,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                style: small,
                onPressed: editor.clear,
                child: const Text('Revert'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                style: small,
                icon: const Icon(Icons.save_outlined, size: 15),
                label: const Text('Save'),
                onPressed: () => _save(editor),
              ),
            ],
          ],
          const SizedBox(width: 12),
          _RowLimitField(
            limit: widget.tab.rowLimit,
            onChanged: widget.changeLimit,
          ),
        ],
      ),
    );
  }

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
        final editor = tab.editor;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(editor),
            const Divider(height: 1),
            if (tab.busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ResultGrid(
                key: ObjectKey(preview),
                result: preview,
                editor: editor,
                onSelectedRowChanged: (row) =>
                    setState(() => _selectedRow = row),
              ),
            ),
            _Footer(
              preview.truncated
                  ? 'First ${preview.rows.length} rows — more in the table; '
                        'raise "Rows" or use "Query in SQL" to filter'
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

/// "Rows [20]" box for the Data tab's row limit. Enter applies; leaving the
/// field or entering something invalid restores the current limit.
class _RowLimitField extends StatefulWidget {
  const _RowLimitField({required this.limit, required this.onChanged});

  final int limit;
  final Future<bool> Function(int limit) onChanged;

  @override
  State<_RowLimitField> createState() => _RowLimitFieldState();
}

class _RowLimitFieldState extends State<_RowLimitField> {
  late final _controller = TextEditingController(text: '${widget.limit}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _reset();
    });
  }

  @override
  void didUpdateWidget(_RowLimitField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.limit != widget.limit && !_focus.hasFocus) _reset();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _reset() => _controller.text = '${widget.limit}';

  Future<void> _submit(String text) async {
    final limit = int.tryParse(text.trim());
    if (limit == null || limit < 1 || limit > InspectorTab.maxRowLimit) {
      _reset();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Row limit must be between 1 and ${InspectorTab.maxRowLimit}',
          ),
        ),
      );
      return;
    }
    if (!await widget.onChanged(limit) && mounted) _reset();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Rows to load (press Enter to apply)',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Rows',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            height: 28,
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              style: monoStyle.copyWith(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
              onSubmitted: _submit,
            ),
          ),
        ],
      ),
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

class _ManageableMetadataPage<T> extends StatefulWidget {
  const _ManageableMetadataPage({
    super.key,
    required this.value,
    required this.itemLabel,
    required this.headers,
    required this.row,
    required this.empty,
    this.include,
    this.onAdd,
    this.onEdit,
    this.onDelete,
    this.canManage = true,
    this.nameOf,
  });

  final AsyncValue<List<T>> value;
  final String itemLabel;
  final List<String> headers;
  final List<Object?> Function(int index, T item) row;
  final String empty;
  final bool Function(T item)? include;
  final VoidCallback? onAdd;
  final void Function(T item)? onEdit;
  final void Function(T item)? onDelete;
  final bool canManage;
  final String Function(T item)? nameOf;

  @override
  State<_ManageableMetadataPage<T>> createState() =>
      _ManageableMetadataPageState<T>();
}

class _ManageableMetadataPageState<T>
    extends State<_ManageableMetadataPage<T>> {
  static const _rowHeight = 28.0;
  static const _headerHeight = 36.0;

  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  String _filter = '';
  int? _sortColumn;
  bool _ascending = true;
  int? _selectedIndex;

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _getItemName(T item) {
    if (widget.nameOf != null) return widget.nameOf!(item);
    if (item is ColumnInfo) return item.name;
    if (item is ConstraintInfo) return item.name;
    if (item is IndexInfo) return item.name;
    if (item is TriggerInfo) return item.name;
    if (item is PartitionInfo) return item.object.name;
    return item.toString();
  }

  void _sortBy(int column) {
    setState(() {
      if (_sortColumn == column) {
        if (!_ascending) {
          _sortColumn = null;
          return;
        }
        _ascending = false;
      } else {
        _sortColumn = column;
        _ascending = true;
      }
    });
  }

  static int _compare(Object? a, Object? b) {
    if (a == null || b == null) {
      return a == null ? (b == null ? 0 : 1) : -1;
    }
    if (a is num && b is num) return a.compareTo(b);
    if (a is DateTime && b is DateTime) return a.compareTo(b);
    if (a is bool && b is bool) return a == b ? 0 : (a ? 1 : -1);
    return (formatValue(a) ?? '').compareTo(formatValue(b) ?? '');
  }

  List<T> _processItems(List<T> all) {
    var items = widget.include == null
        ? all
        : all.where(widget.include!).toList();

    if (_filter.isNotEmpty) {
      final q = _filter.toLowerCase();
      items = items.where((item) {
        final cells = widget.row(0, item);
        return cells.any(
          (c) => (formatValue(c) ?? '').toLowerCase().contains(q),
        );
      }).toList();
    }

    if (_sortColumn != null) {
      final col = _sortColumn!;
      items = [...items]
        ..sort((a, b) {
          final rowA = widget.row(0, a);
          final rowB = widget.row(0, b);
          final valA = col < rowA.length ? rowA[col] : null;
          final valB = col < rowB.length ? rowB[col] : null;
          final cmp = _compare(valA, valB);
          return _ascending ? cmp : -cmp;
        });
    }

    return items;
  }

  List<double> _measureColumns(List<T> displayed) {
    final sample = displayed.take(100).toList();
    return [
      for (var col = 0; col < widget.headers.length; col++)
        (math.max(
                      widget.headers[col].length,
                      sample.fold<int>(0, (m, item) {
                        final cells = widget.row(0, item);
                        final val = col < cells.length ? cells[col] : null;
                        return math.max(m, (formatValue(val) ?? '').length);
                      }),
                    ) *
                    7.5 +
                28)
            .clamp(70.0, 480.0),
    ];
  }

  Future<void> _showRowMenu(
    Offset position,
    T item,
    int rowIndex,
    List<T> displayed,
  ) async {
    setState(() => _selectedIndex = rowIndex);
    final scheme = Theme.of(context).colorScheme;

    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        if (widget.canManage && widget.onEdit != null)
          const PopupMenuItem(
            value: 'edit',
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 16),
                SizedBox(width: 8),
                Text('Edit...'),
              ],
            ),
          ),
        if (widget.canManage && widget.onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: scheme.error,
                ),
                const SizedBox(width: 8),
                Text('Delete...', style: TextStyle(color: scheme.error)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'copy_name',
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 16),
              SizedBox(width: 8),
              Text('Copy name'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy_row',
          child: Row(
            children: [
              Icon(Icons.table_rows_outlined, size: 16),
              SizedBox(width: 8),
              Text('Copy row'),
            ],
          ),
        ),
      ],
    );

    if (action == null) return;
    if (!mounted) return;
    switch (action) {
      case 'edit':
        widget.onEdit?.call(item);
      case 'delete':
        widget.onDelete?.call(item);
      case 'copy_name':
        Clipboard.setData(ClipboardData(text: _getItemName(item)));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Name copied'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      case 'copy_row':
        final cells = widget.row(rowIndex, item);
        final tsv = cells.map((c) => formatValue(c) ?? '').join('\t');
        Clipboard.setData(ClipboardData(text: tsv));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Row copied'),
              duration: Duration(seconds: 1),
            ),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.value.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _CenteredMessage('$e', isError: true),
      data: (all) {
        final originalItems = widget.include == null
            ? all
            : all.where(widget.include!).toList();
        final displayed = _processItems(all);
        final selectedItem =
            (_selectedIndex != null &&
                _selectedIndex! >= 0 &&
                _selectedIndex! < displayed.length)
            ? displayed[_selectedIndex!]
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(context, displayed, selectedItem),
            const Divider(height: 1),
            Expanded(
              child: displayed.isEmpty
                  ? _buildEmpty(context, originalItems.isEmpty)
                  : _buildGrid(context, displayed),
            ),
            _Footer(
              '${displayed.length} ${widget.itemLabel.toLowerCase()}(s)'
              '${selectedItem != null ? ' · Selected: ${_getItemName(selectedItem)}' : ''}',
            ),
          ],
        );
      },
    );
  }

  Widget _buildToolbar(
    BuildContext context,
    List<T> displayed,
    T? selectedItem,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          if (widget.canManage && widget.onAdd != null) ...[
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(
                'Add ${widget.itemLabel}',
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: widget.onAdd,
            ),
            const SizedBox(width: 6),
          ],
          if (widget.canManage && widget.onEdit != null) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: const Text('Edit', style: TextStyle(fontSize: 12)),
              onPressed: selectedItem != null
                  ? () => widget.onEdit!(selectedItem)
                  : null,
            ),
            const SizedBox(width: 6),
          ],
          if (widget.canManage && widget.onDelete != null) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.error,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 14),
              label: const Text('Delete', style: TextStyle(fontSize: 12)),
              onPressed: selectedItem != null
                  ? () => widget.onDelete!(selectedItem)
                  : null,
            ),
          ],
          const Spacer(),
          SizedBox(
            width: 190,
            height: 28,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Filter ${widget.itemLabel.toLowerCase()}s...',
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: scheme.onSurfaceVariant,
                ),
                prefixIcon: const Icon(Icons.search_rounded, size: 14),
                prefixIconConstraints: const BoxConstraints(minWidth: 26),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 12),
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _filter = '';
                            _selectedIndex = null;
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 0,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
              onChanged: (v) => setState(() {
                _filter = v.trim();
                _selectedIndex = null;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, bool isOriginalEmpty) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (!isOriginalEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_off_rounded,
              size: 40,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              'No matching ${widget.itemLabel.toLowerCase()}s found',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                _searchController.clear();
                setState(() => _filter = '');
              },
              child: const Text('Clear filter'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _iconForLabel(widget.itemLabel),
              size: 46,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 12),
            Text(
              widget.empty,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (widget.canManage && widget.onAdd != null)
              FilledButton.tonalIcon(
                icon: const Icon(Icons.add_rounded, size: 16),
                label: Text('Add ${widget.itemLabel}'),
                onPressed: widget.onAdd,
              ),
          ],
        ),
      ),
    );
  }

  static IconData _iconForLabel(String label) => switch (label.toLowerCase()) {
    'column' => Icons.view_column_outlined,
    'constraint' => Icons.shield_outlined,
    'foreign key' => Icons.link_rounded,
    'index' => Icons.key_rounded,
    'trigger' => Icons.bolt_rounded,
    _ => Icons.table_chart_outlined,
  };

  Widget _buildGrid(BuildContext context, List<T> displayed) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final border = BorderSide(
      color: scheme.outlineVariant.withValues(alpha: 0.6),
    );

    final widths = _measureColumns(displayed);
    final hasActions =
        widget.canManage && (widget.onEdit != null || widget.onDelete != null);
    final totalColumns = widget.headers.length + (hasActions ? 2 : 1);
    final rowCount = displayed.length;

    return Focus(
      focusNode: _focusNode,
      child: TableView.builder(
        pinnedRowCount: 1,
        pinnedColumnCount: 1,
        rowCount: rowCount + 1,
        columnCount: totalColumns,
        diagonalDragBehavior: DiagonalDragBehavior.free,
        columnBuilder: (index) {
          final double extent;
          if (index == 0) {
            extent = 44.0;
          } else if (hasActions && index == totalColumns - 1) {
            extent = 76.0;
          } else {
            extent = widths[index - 1];
          }
          return TableSpan(
            extent: FixedTableSpanExtent(extent),
            foregroundDecoration: TableSpanDecoration(
              border: TableSpanBorder(trailing: border),
            ),
          );
        },
        rowBuilder: (index) {
          final isSelected =
              index > 0 &&
              _selectedIndex != null &&
              _selectedIndex == index - 1;
          return TableSpan(
            extent: FixedTableSpanExtent(
              index == 0 ? _headerHeight : _rowHeight,
            ),
            backgroundDecoration: TableSpanDecoration(
              color: index == 0
                  ? scheme.surfaceContainerHigh
                  : isSelected
                  ? scheme.primary.withValues(alpha: 0.12)
                  : (index.isEven ? scheme.surfaceContainerLowest : null),
            ),
            foregroundDecoration: TableSpanDecoration(
              border: TableSpanBorder(trailing: border),
            ),
          );
        },
        cellBuilder: (context, vicinity) {
          final row = vicinity.row;
          final column = vicinity.column;

          if (row == 0) {
            if (column == 0) {
              return TableViewCell(
                child: Container(
                  alignment: Alignment.center,
                  color: scheme.surfaceContainerHigh,
                  child: Text(
                    '#',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }
            if (hasActions && column == totalColumns - 1) {
              return TableViewCell(
                child: Container(
                  alignment: Alignment.center,
                  color: scheme.surfaceContainerHigh,
                  child: Text(
                    'Actions',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              );
            }
            return TableViewCell(child: _headerCell(column - 1));
          }

          final item = displayed[row - 1];
          final isSelected = _selectedIndex == row - 1;

          if (column == 0) {
            return TableViewCell(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _focusNode.requestFocus();
                  setState(() => _selectedIndex = row - 1);
                },
                child: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  color: isSelected
                      ? scheme.primary.withValues(alpha: 0.14)
                      : scheme.surfaceContainerHigh,
                  child: Text(
                    '$row',
                    style: monoStyle.copyWith(
                      fontSize: 11,
                      color: isSelected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            );
          }

          if (hasActions && column == totalColumns - 1) {
            return TableViewCell(
              child: Container(
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.onEdit != null)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 14),
                        tooltip: 'Edit',
                        splashRadius: 14,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 24,
                          height: 24,
                        ),
                        onPressed: () => widget.onEdit!(item),
                      ),
                    if (widget.onDelete != null)
                      IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          size: 14,
                          color: scheme.error,
                        ),
                        tooltip: 'Delete',
                        splashRadius: 14,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 24,
                          height: 24,
                        ),
                        onPressed: () => widget.onDelete!(item),
                      ),
                  ],
                ),
              ),
            );
          }

          return TableViewCell(
            child: _contentCell(
              item: item,
              rowIndex: row - 1,
              colIndex: column - 1,
              displayed: displayed,
            ),
          );
        },
      ),
    );
  }

  Widget _headerCell(int colIndex) {
    final scheme = Theme.of(context).colorScheme;
    final header = widget.headers[colIndex];
    final isSorted = _sortColumn == colIndex;

    return InkWell(
      onTap: () => _sortBy(colIndex),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                header,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                  color: isSorted ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
            if (isSorted) ...[
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
      ),
    );
  }

  Widget _contentCell({
    required T item,
    required int rowIndex,
    required int colIndex,
    required List<T> displayed,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final cells = widget.row(rowIndex, item);
    final val = colIndex < cells.length ? cells[colIndex] : null;

    final Widget child;
    if (val is bool) {
      child = Container(
        alignment: Alignment.centerLeft,
        child: val
            ? const Icon(Icons.check_rounded, size: 15, color: Colors.green)
            : Icon(
                Icons.remove_rounded,
                size: 14,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
      );
    } else if (val == null) {
      child = Container(
        alignment: Alignment.centerLeft,
        child: Text(
          '—',
          style: TextStyle(
            fontSize: 11,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
        ),
      );
    } else {
      final text = formatValue(val) ?? '';
      child = Container(
        alignment: val is num ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: monoStyle.copyWith(fontSize: 11.5, color: scheme.onSurface),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _focusNode.requestFocus();
        setState(() => _selectedIndex = rowIndex);
      },
      onDoubleTap: widget.canManage && widget.onEdit != null
          ? () => widget.onEdit!(item)
          : null,
      onSecondaryTapDown: (d) =>
          _showRowMenu(d.globalPosition, item, rowIndex, displayed),
      // Touch screens have no right click.
      onLongPressStart: (d) =>
          _showRowMenu(d.globalPosition, item, rowIndex, displayed),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: child,
      ),
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
