import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../drivers/postgres/postgres_sql.dart';
import '../../state/workspace_tabs.dart';
import '../../state/providers.dart';
import '../connections/connection_dialog.dart';

/// Connection list with a lazily loaded, DBeaver-style object tree:
/// schema → Tables/Views/… folders → object → Columns/Indexes/… folders.
class NavigatorPane extends ConsumerStatefulWidget {
  const NavigatorPane({super.key, this.onEditorOpened});

  /// Called after an editor tab was opened from the tree (closes the drawer
  /// on phones).
  final VoidCallback? onEditorOpened;

  @override
  ConsumerState<NavigatorPane> createState() => _NavigatorPaneState();
}

class _NavigatorPaneState extends ConsumerState<NavigatorPane> {
  final _expanded = <String>{};
  final _filterController = TextEditingController();
  String _filter = '';

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _toggle(String key) => setState(() {
    if (!_expanded.remove(key)) _expanded.add(key);
  });

  Future<void> _toggleConnection(ConnectionConfig config) async {
    final key = 'c:${config.id}';
    if (_expanded.contains(key)) {
      _toggle(key);
      return;
    }
    final driver = await connectWithPrompt(context, ref, config);
    if (driver != null && mounted) setState(() => _expanded.add(key));
  }

  Future<void> _openEditor(
    ConnectionConfig config, {
    String initialText = '',
  }) async {
    final driver = await connectWithPrompt(context, ref, config);
    if (driver == null || !mounted) return;
    ref
        .read(workspaceTabsProvider.notifier)
        .open(config.id, initialText: initialText);
    widget.onEditorOpened?.call();
  }

  Future<void> _disconnect(ConnectionConfig config) async {
    setState(() => _expanded.removeWhere((k) => k.contains(config.id)));
    await ref.read(sessionsProvider.notifier).disconnect(config.id);
  }

  void _refresh(ConnectionConfig config) => invalidateMetadata(ref, config.id);

  Future<void> _delete(ConnectionConfig config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete connection?'),
        content: Text(
          '"${config.name}" and its query history will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _disconnect(config);
    ref.read(workspaceTabsProvider.notifier).closeForConnection(config.id);
    await ref.read(connectionRepositoryProvider).delete(config.id);
  }

  Future<void> _edit(ConnectionConfig config) async {
    final updated = await showConnectionDialog(context, existing: config);
    // Reconnect so the new settings take effect.
    if (updated != null && ref.read(sessionsProvider).containsKey(config.id)) {
      await _disconnect(config);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connections = ref.watch(connectionsProvider);
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
            child: Row(
              children: [
                Text('Connections', style: theme.textTheme.titleSmall),
                const Spacer(),
                IconButton(
                  tooltip: 'New connection',
                  icon: const Icon(Icons.add),
                  onPressed: () => showConnectionDialog(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: TextField(
              controller: _filterController,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Filter objects',
                border: const OutlineInputBorder(),
                suffixIcon: _filter.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => setState(() {
                          _filterController.clear();
                          _filter = '';
                        }),
                      ),
              ),
              onChanged: (v) =>
                  setState(() => _filter = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: connections.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _Message('Could not load connections: $e'),
              data: (list) => list.isEmpty
                  ? _EmptyConnections(
                      onAdd: () => showConnectionDialog(context),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        for (final config in list) ..._connectionNodes(config),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _connectionNodes(ConnectionConfig config) {
    final session = ref.watch(sessionsProvider.select((s) => s[config.id]));
    final key = 'c:${config.id}';
    final expanded =
        _expanded.contains(key) && session?.status == SessionStatus.connected;

    return [
      _TreeRow(
        depth: 0,
        expanded: expanded,
        leading: _StatusDot(color: Color(config.color), session: session),
        label: config.name,
        subtitle: config.displayAddress,
        onTap: () => _toggleConnection(config),
        trailing: PopupMenuButton<String>(
          tooltip: 'Actions',
          icon: const Icon(Icons.more_vert, size: 18),
          onSelected: (action) => switch (action) {
            'editor' => _openEditor(config),
            'connect' => _toggleConnection(config),
            'disconnect' => _disconnect(config),
            'refresh' => _refresh(config),
            'edit' => _edit(config),
            'delete' => _delete(config),
            _ => null,
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'editor', child: Text('New SQL editor')),
            if (session?.status == SessionStatus.connected) ...[
              const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
              const PopupMenuItem(
                value: 'disconnect',
                child: Text('Disconnect'),
              ),
            ] else
              const PopupMenuItem(value: 'connect', child: Text('Connect')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'edit', child: Text('Edit…')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
      if (session?.status == SessionStatus.failed)
        Padding(
          padding: const EdgeInsets.fromLTRB(36, 0, 8, 4),
          child: Text(
            session!.error ?? 'Connection failed',
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        ),
      if (expanded) ..._schemaNodes(config),
    ];
  }

  List<Widget> _schemaNodes(ConnectionConfig config) {
    final schemas = ref.watch(schemasProvider(config.id));
    return schemas.when(
      loading: () => [const _Loading(depth: 1)],
      error: (e, _) => [_ErrorRow(depth: 1, error: e)],
      data: (list) => [
        for (final schema in list) ...[
          _TreeRow(
            depth: 1,
            expanded: _isSchemaExpanded(config, schema),
            leading: const Icon(Icons.account_tree_outlined, size: 16),
            label: schema,
            onTap: () => _toggle('s:${config.id}:$schema'),
          ),
          if (_isSchemaExpanded(config, schema))
            ..._schemaFolders(config, schema),
        ],
      ],
    );
  }

  /// Schemas auto-expand while filtering so matches are visible.
  bool _isSchemaExpanded(ConnectionConfig config, String schema) =>
      _filter.isNotEmpty || _expanded.contains('s:${config.id}:$schema');

  /// Tables, Views, … folders of a schema, followed by Functions.
  List<Widget> _schemaFolders(ConnectionConfig config, String schema) {
    final objects = ref.watch(objectsProvider((config.id, schema)));
    return objects.when(
      loading: () => [const _Loading(depth: 2)],
      error: (e, _) => [_ErrorRow(depth: 2, error: e)],
      data: (list) {
        final widgets = <Widget>[];
        for (final folder in _relationFolders) {
          final all = [
            for (final o in list)
              if (folder.kinds.contains(o.kind)) o,
          ];
          if (all.isEmpty && folder.hideWhenEmpty) continue;
          final visible = _filter.isEmpty
              ? all
              : [
                  for (final o in all)
                    if (o.name.toLowerCase().contains(_filter)) o,
                ];
          // While filtering, only folders with matches show, already open.
          if (_filter.isNotEmpty && visible.isEmpty) continue;
          final key = 'f:${config.id}:$schema:${folder.label}';
          final open = _filter.isNotEmpty || _expanded.contains(key);
          widgets.add(
            _FolderRow(
              depth: 2,
              label: folder.label,
              count: visible.length,
              expanded: open,
              onTap: () => _toggle(key),
            ),
          );
          if (open) {
            for (final object in visible) {
              widgets.addAll(_objectNode(config, object, depth: 3));
            }
          }
        }
        if (_filter.isEmpty) widgets.addAll(_routinesFolder(config, schema));
        return widgets;
      },
    );
  }

  String _objectKey(ConnectionConfig config, DbObject object) =>
      'o:${config.id}:${object.schema}:${object.name}';

  /// A table-like object and, when expanded, its Columns/Indexes/… folders.
  /// [detail] is shown beside the name (used for partition bounds).
  List<Widget> _objectNode(
    ConnectionConfig config,
    DbObject object, {
    required int depth,
    String? detail,
  }) {
    final key = _objectKey(config, object);
    final folders = _foldersFor(object.kind);
    final open = folders.isNotEmpty && _expanded.contains(key);
    return [
      _TreeRow(
        depth: depth,
        expanded: folders.isEmpty ? null : open,
        leading: Icon(_objectIcon(object.kind), size: 16),
        label: object.name,
        detail: detail,
        tooltip: detail == null
            ? object.kind.label
            : '${object.kind.label}\n$detail',
        onTap: folders.isEmpty ? null : () => _toggle(key),
        onDoubleTap: () => _openInspector(config, object),
        onContextMenu: (position) => _showObjectMenu(position, config, object),
      ),
      if (open)
        for (final folder in folders)
          ..._objectFolder(config, object, folder, depth + 1),
    ];
  }

  List<Widget> _objectFolder(
    ConnectionConfig config,
    DbObject object,
    _ObjectFolder folder,
    int depth,
  ) {
    final key = '${_objectKey(config, object)}:${folder.name}';
    final open = _expanded.contains(key);
    return [
      _FolderRow(
        depth: depth,
        label: folder.label,
        expanded: open,
        onTap: () => _toggle(key),
      ),
      if (open) ..._folderItems(config, object, folder, depth + 1),
    ];
  }

  List<Widget> _folderItems(
    ConnectionConfig config,
    DbObject object,
    _ObjectFolder folder,
    int depth,
  ) {
    final key = (config.id, object.schema, object.name);
    return switch (folder) {
      _ObjectFolder.columns => _load(
        ref.watch(columnsProvider(key)),
        depth,
        (list) => [
          for (final column in list)
            _TreeRow(
              depth: depth,
              leading: Icon(
                column.isPrimaryKey ? Icons.key : Icons.view_column_outlined,
                size: 14,
                color: column.isPrimaryKey ? Colors.amber.shade700 : null,
              ),
              label: column.name,
              detail: '${column.dataType}${column.nullable ? '' : ' not null'}',
              tooltip: column.defaultValue == null
                  ? null
                  : 'default ${column.defaultValue}',
            ),
        ],
      ),
      _ObjectFolder.constraints || _ObjectFolder.foreignKeys => _load(
        ref.watch(constraintsProvider(key)),
        depth,
        (list) => [
          for (final c in list)
            if ((c.kind == ConstraintKind.foreignKey) ==
                (folder == _ObjectFolder.foreignKeys))
              _TreeRow(
                depth: depth,
                leading: Icon(
                  _constraintIcon(c.kind),
                  size: 14,
                  color: c.kind == ConstraintKind.primaryKey
                      ? Colors.amber.shade700
                      : null,
                ),
                label: c.name,
                detail: c.referencedTable == null
                    ? c.kind.label
                    : '→ ${c.referencedTable}',
                tooltip: c.definition,
                onDoubleTap: () => _openEditor(
                  config,
                  initialText:
                      'ALTER TABLE ${_qualified(object)}\n'
                      '  ADD CONSTRAINT ${quoteIdent(c.name)} ${c.definition};',
                ),
              ),
        ],
      ),
      _ObjectFolder.indexes => _load(
        ref.watch(indexesProvider(key)),
        depth,
        (list) => [
          for (final index in list)
            _TreeRow(
              depth: depth,
              leading: Icon(
                index.isPrimary ? Icons.key : Icons.bolt_outlined,
                size: 14,
                color: index.isPrimary ? Colors.amber.shade700 : null,
              ),
              label: index.name,
              detail: [
                if (index.isUnique && !index.isPrimary) 'unique',
                ?index.size,
              ].join(' · '),
              tooltip: index.definition,
              onDoubleTap: () =>
                  _openEditor(config, initialText: '${index.definition};'),
            ),
        ],
      ),
      _ObjectFolder.triggers => _load(
        ref.watch(triggersProvider(key)),
        depth,
        (list) => [
          for (final trigger in list)
            _TreeRow(
              depth: depth,
              leading: Icon(
                Icons.flash_on_outlined,
                size: 14,
                color: trigger.enabled ? null : Colors.grey,
              ),
              label: trigger.name,
              detail: trigger.enabled ? null : 'disabled',
              tooltip: trigger.definition,
              onDoubleTap: () =>
                  _openEditor(config, initialText: '${trigger.definition};'),
            ),
        ],
      ),
      _ObjectFolder.partitions => _load(
        ref.watch(partitionsProvider(key)),
        depth,
        (list) => [
          for (final partition in list)
            ..._objectNode(
              config,
              partition.object,
              depth: depth,
              detail: partition.bound,
            ),
        ],
      ),
    };
  }

  List<Widget> _routinesFolder(ConnectionConfig config, String schema) {
    final key = 'f:${config.id}:$schema:Functions';
    final open = _expanded.contains(key);
    final routines = open
        ? ref.watch(routinesProvider((config.id, schema)))
        : null;
    return [
      _FolderRow(
        depth: 2,
        label: 'Functions',
        count: routines?.value?.length,
        expanded: open,
        onTap: () => _toggle(key),
      ),
      if (routines != null)
        ..._load(
          routines,
          3,
          (list) => [
            for (final routine in list)
              _TreeRow(
                depth: 3,
                leading: Icon(
                  routine.kind == RoutineKind.procedure
                      ? Icons.settings_suggest_outlined
                      : Icons.functions,
                  size: 14,
                ),
                label: '${routine.name}(${routine.arguments})',
                detail: routine.returnType ?? 'procedure',
                tooltip: 'Double-click to open the definition',
                onDoubleTap: () => _openRoutine(config, routine),
              ),
          ],
        ),
    ];
  }

  Future<void> _openRoutine(
    ConnectionConfig config,
    RoutineInfo routine,
  ) async {
    final driver = ref.read(driverProvider(config.id));
    if (driver == null) return;
    try {
      final definition = await driver.routineDefinition(routine);
      await _openEditor(config, initialText: definition);
    } on DriverException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  /// Loading spinner, error row, "Empty" message, or the built rows.
  List<Widget> _load<T>(
    AsyncValue<List<T>> value,
    int depth,
    List<Widget> Function(List<T> items) build,
  ) {
    return value.when(
      loading: () => [_Loading(depth: depth)],
      error: (e, _) => [_ErrorRow(depth: depth, error: e)],
      data: (items) {
        final rows = build(items);
        return rows.isEmpty ? [_Message('Empty', depth: depth)] : rows;
      },
    );
  }

  String _qualified(DbObject object) =>
      qualifiedName(object.schema, object.name);

  void _openInspector(ConnectionConfig config, DbObject object) {
    ref.read(workspaceTabsProvider.notifier).openInspector(config.id, object);
    widget.onEditorOpened?.call();
  }

  Future<void> _showObjectMenu(
    Offset position,
    ConnectionConfig config,
    DbObject object,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: const [
        PopupMenuItem(value: 'open', child: Text('Open')),
        PopupMenuItem(value: 'query', child: Text('Query in SQL editor')),
        PopupMenuItem(value: 'copy', child: Text('Copy name')),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'open':
        _openInspector(config, object);
      case 'query':
        await _openEditor(
          config,
          initialText: 'SELECT * FROM ${_qualified(object)} LIMIT 100;',
        );
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _qualified(object)));
    }
  }

  List<_ObjectFolder> _foldersFor(DbObjectKind kind) => switch (kind) {
    DbObjectKind.table => const [
      _ObjectFolder.columns,
      _ObjectFolder.constraints,
      _ObjectFolder.foreignKeys,
      _ObjectFolder.indexes,
      _ObjectFolder.triggers,
    ],
    DbObjectKind.partitionedTable => const [
      _ObjectFolder.columns,
      _ObjectFolder.constraints,
      _ObjectFolder.foreignKeys,
      _ObjectFolder.indexes,
      _ObjectFolder.triggers,
      _ObjectFolder.partitions,
    ],
    DbObjectKind.view => const [_ObjectFolder.columns, _ObjectFolder.triggers],
    DbObjectKind.materializedView => const [
      _ObjectFolder.columns,
      _ObjectFolder.indexes,
    ],
    DbObjectKind.foreignTable => const [
      _ObjectFolder.columns,
      _ObjectFolder.constraints,
    ],
    DbObjectKind.sequence => const [],
  };

  IconData _objectIcon(DbObjectKind kind) => switch (kind) {
    DbObjectKind.table => Icons.table_chart_outlined,
    DbObjectKind.partitionedTable => Icons.view_module_outlined,
    DbObjectKind.view => Icons.visibility_outlined,
    DbObjectKind.materializedView => Icons.auto_awesome_motion_outlined,
    DbObjectKind.foreignTable => Icons.link,
    DbObjectKind.sequence => Icons.pin_outlined,
  };

  IconData _constraintIcon(ConstraintKind kind) => switch (kind) {
    ConstraintKind.primaryKey => Icons.key,
    ConstraintKind.unique => Icons.fingerprint,
    ConstraintKind.check => Icons.rule,
    ConstraintKind.foreignKey => Icons.call_made,
    ConstraintKind.exclusion => Icons.block,
  };
}

/// Schema-level folders grouping relations by kind, in DBeaver's order.
class _RelationFolder {
  const _RelationFolder(this.label, this.kinds, {this.hideWhenEmpty = false});

  final String label;
  final Set<DbObjectKind> kinds;
  final bool hideWhenEmpty;
}

const _relationFolders = [
  _RelationFolder('Tables', {
    DbObjectKind.table,
    DbObjectKind.partitionedTable,
  }),
  _RelationFolder('Foreign Tables', {
    DbObjectKind.foreignTable,
  }, hideWhenEmpty: true),
  _RelationFolder('Views', {DbObjectKind.view}),
  _RelationFolder('Materialized Views', {DbObjectKind.materializedView}),
  _RelationFolder('Sequences', {DbObjectKind.sequence}),
];

/// Folders under a table-like object.
enum _ObjectFolder {
  columns('Columns'),
  constraints('Constraints'),
  foreignKeys('Foreign Keys'),
  indexes('Indexes'),
  triggers('Triggers'),
  partitions('Partitions');

  const _ObjectFolder(this.label);

  final String label;
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.depth,
    required this.label,
    required this.expanded,
    required this.onTap,
    this.count,
  });

  final int depth;
  final String label;
  final bool expanded;
  final VoidCallback onTap;

  /// Item count, when known.
  final int? count;

  @override
  Widget build(BuildContext context) {
    return _TreeRow(
      depth: depth,
      expanded: expanded,
      leading: Icon(
        expanded ? Icons.folder_open_outlined : Icons.folder_outlined,
        size: 16,
        color: Colors.amber.shade600,
      ),
      label: label,
      detail: count?.toString(),
      onTap: onTap,
    );
  }
}

class _TreeRow extends StatelessWidget {
  const _TreeRow({
    required this.depth,
    required this.leading,
    required this.label,
    this.expanded,
    this.subtitle,
    this.detail,
    this.tooltip,
    this.trailing,
    this.onTap,
    this.onDoubleTap,
    this.onContextMenu,
  });

  final int depth;

  /// Null for leaf rows (no chevron).
  final bool? expanded;
  final Widget leading;
  final String label;
  final String? subtitle;
  final String? detail;
  final String? tooltip;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  /// Right-click on desktop, long-press on touch; gets the global position.
  final void Function(Offset position)? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapDown: onContextMenu == null
          ? null
          : (d) => onContextMenu!(d.globalPosition),
      onLongPress: onContextMenu == null
          ? null
          : () {
              final box = context.findRenderObject() as RenderBox?;
              onContextMenu!(
                box?.localToGlobal(box.size.centerLeft(Offset.zero)) ??
                    Offset.zero,
              );
            },
      child: Padding(
        padding: EdgeInsets.only(left: 4.0 + depth * 12, right: 4),
        child: SizedBox(
          height: subtitle == null ? 28 : 44,
          child: Row(
            children: [
              SizedBox(
                width: 18,
                child: expanded == null
                    ? null
                    : Icon(
                        expanded! ? Icons.expand_more : Icons.chevron_right,
                        size: 16,
                      ),
              ),
              leading,
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (detail != null)
                Flexible(
                  child: Text(
                    detail!,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
    return tooltip == null ? row : Tooltip(message: tooltip!, child: row);
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, required this.session});

  final Color color;
  final Session? session;

  @override
  Widget build(BuildContext context) {
    if (session?.status == SessionStatus.connecting) {
      return const SizedBox.square(
        dimension: 12,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    final connected = session?.status == SessionStatus.connected;
    return Tooltip(
      message: switch (session?.status) {
        SessionStatus.connected => 'Connected',
        SessionStatus.failed => 'Connection failed',
        _ => 'Disconnected',
      },
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected ? color : null,
          border: Border.all(color: color, width: 2),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading({required this.depth});

  final int depth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 22.0 + depth * 12, top: 6, bottom: 6),
      child: const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.depth, required this.error});

  final int depth;
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 22.0 + depth * 12,
        right: 8,
        top: 4,
        bottom: 4,
      ),
      child: Text(
        '$error',
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.depth = 0});

  final String text;
  final int depth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 22.0 + depth * 12,
        top: 6,
        bottom: 6,
        right: 8,
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _EmptyConnections extends StatelessWidget {
  const _EmptyConnections({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storage_outlined, size: 40),
            const SizedBox(height: 12),
            const Text('No connections yet', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('New connection'),
            ),
          ],
        ),
      ),
    );
  }
}
