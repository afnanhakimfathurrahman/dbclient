import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../drivers/create_sql.dart';
import '../../drivers/document.dart';
import '../../drivers/driver.dart';
import '../../drivers/sql_dialect.dart';
import '../../drivers/sql_splitter.dart';
import '../../state/workspace_tabs.dart';
import '../../state/providers.dart';
import '../connections/connection_dialog.dart';
import '../inspector/dialogs/column_dialog.dart';
import '../inspector/dialogs/constraint_dialog.dart';
import '../inspector/dialogs/index_dialog.dart';
import '../inspector/dialogs/trigger_dialog.dart';
import 'create_dialogs.dart';

/// A context menu entry: label and what it does.
typedef _MenuAction = (String label, Future<void> Function() run);

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

  /// Applies the filter once typing pauses: each change rebuilds the tree
  /// and may load the objects of every schema.
  Timer? _filterDebounce;

  void _setFilter(String value) {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() => _filter = value.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
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

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
    );
  }

  /// Shows [actions] as a context menu at [position] and runs the chosen one.
  Future<void> _contextMenu(Offset position, List<_MenuAction> actions) async {
    final index = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem(value: i, child: Text(actions[i].$1)),
      ],
    );
    if (index != null && mounted) await actions[index].$2();
  }

  /// Context menu handler for [actions]; null (no menu) when there are none.
  void Function(Offset)? _menuFor(List<_MenuAction> actions) =>
      actions.isEmpty ? null : (position) => _contextMenu(position, actions);

  /// Runs DDL from a create dialog and reloads the connection's tree. A
  /// single statement runs on its own (CREATE DATABASE can't run inside a
  /// transaction); several run in one transaction. Throws if not connected,
  /// so the dialog stays open and shows why.
  Future<void> _executeDdl(
    ConnectionConfig config,
    String sql, {
    required String successMessage,
  }) async {
    final driver = await connectSqlWithPrompt(context, ref, config);
    if (driver == null) throw const DriverException('Not connected');
    final statements = [for (final s in splitSql(sql)) s.text];
    if (statements.length == 1) {
      await driver.execute(statements.single);
    } else {
      await driver.executeAll(statements);
    }
    invalidateMetadata(ref, config.id);
    _notify(successMessage);
  }

  void _openSql(ConnectionConfig config, String sql) =>
      _openEditor(config, initialText: sql);

  /// Create actions of a connection row, while connected.
  List<_MenuAction> _connectionActions(ConnectionConfig config) {
    final postgres = config.engine == DatabaseEngine.postgres;
    final driver = ref.watch(sqlDriverProvider(config.id));
    return switch (config.engine.family) {
      EngineFamily.relational when driver != null => [
        (
          'Create database…',
          () async {
            final created = await showCreateNamedDialog(
              context,
              title: 'Create Database',
              subtitle: config.name,
              icon: Icons.storage_rounded,
              fieldLabel: 'Database name',
              buildSql: (name) => buildCreateDatabaseSql(driver.dialect, name),
              onExecute: (sql) => _executeDdl(
                config,
                sql,
                successMessage: postgres
                    // The tree shows the schemas of the connected database.
                    ? 'Database created. To browse it, edit the connection '
                          'and set it as the database.'
                    : 'Database created',
              ),
              onOpenInSql: (sql) => _openSql(config, sql),
            );
            if (created == true && !postgres) _expandConnection(config);
          },
        ),
        if (postgres)
          (
            'Create schema…',
            () async {
              final created = await showCreateNamedDialog(
                context,
                title: 'Create Schema',
                subtitle: '${config.name} · ${config.database}',
                icon: Icons.account_tree_outlined,
                fieldLabel: 'Schema name',
                buildSql: (name) => buildCreateSchemaSql(driver.dialect, name),
                onExecute: (sql) =>
                    _executeDdl(config, sql, successMessage: 'Schema created'),
                onOpenInSql: (sql) => _openSql(config, sql),
              );
              if (created == true) _expandConnection(config);
            },
          ),
      ],
      EngineFamily.document
          when ref.watch(documentDriverProvider(config.id)) != null =>
        [('Create database…', () => _createCollection(config))],
      _ => const [],
    };
  }

  void _expandConnection(ConnectionConfig config) {
    if (mounted) setState(() => _expanded.add('c:${config.id}'));
  }

  /// MongoDB: a collection in [database], or a new database with its first
  /// collection when [database] is null.
  Future<void> _createCollection(
    ConnectionConfig config, [
    String? database,
  ]) async {
    String? created;
    await showCreateCollectionDialog(
      context,
      database: database,
      onCreate: (database, collection) async {
        final driver = ref.read(documentDriverProvider(config.id));
        if (driver == null) throw const DriverException('Not connected');
        await driver.createCollection(database, collection);
        created = database;
        invalidateMetadata(ref, config.id);
        _notify('Collection "$collection" created');
      },
    );
    if (created case final name? when mounted) {
      setState(
        () => _expanded
          ..add('c:${config.id}')
          ..add('s:${config.id}:$name'),
      );
    }
  }

  /// Create actions of a schema (database on MySQL and ClickHouse), or of
  /// one of its folders when [folder] is given ("Tables", "Views"…).
  List<_MenuAction> _schemaActions(
    ConnectionConfig config,
    String schema, [
    String? folder,
  ]) {
    final driver = ref.watch(sqlDriverProvider(config.id));
    if (driver == null) return const [];
    final dialect = driver.dialect;
    bool show(String name) => folder == null || folder == name;
    return [
      if (show('Tables'))
        (
          'Create table…',
          () async {
            final created = await showCreateTableDialog(
              context,
              dialect: dialect,
              schema: schema,
              onExecute: (sql) =>
                  _executeDdl(config, sql, successMessage: 'Table created'),
              onOpenInSql: (sql) => _openSql(config, sql),
            );
            if (created == true && mounted) {
              setState(
                () => _expanded
                  ..add('s:${config.id}:$schema')
                  ..add('f:${config.id}:$schema:Tables'),
              );
            }
          },
        ),
      if (show('Views'))
        (
          'Create view…',
          () => _openEditor(
            config,
            initialText: createViewTemplate(dialect, schema),
          ),
        ),
      if (show('Functions') && driver.features.contains(SqlFeature.routines))
        (
          'Create function…',
          () => _openEditor(
            config,
            initialText: createFunctionTemplate(dialect, schema),
          ),
        ),
      if (show('Sequences') && driver.features.contains(SqlFeature.sequences))
        (
          'Create sequence…',
          () => _openEditor(
            config,
            initialText: createSequenceTemplate(dialect, schema),
          ),
        ),
    ];
  }

  /// Create actions of a Columns/Indexes/… folder under [object]. With
  /// [SqlFeature.schemaEditing] they open the inspector's dialogs (which
  /// generate PostgreSQL); otherwise only indexes get an editor template.
  List<_MenuAction> _objectFolderActions(
    ConnectionConfig config,
    DbObject object,
    _ObjectFolder folder,
  ) {
    final driver = ref.watch(sqlDriverProvider(config.id));
    if (driver == null) return const [];
    final key = (config.id, object.schema, object.name);
    final kind = object.kind;
    Future<List<ColumnInfo>> columns() async {
      try {
        return await ref.read(columnsProvider(key).future);
      } on Object {
        return const [];
      }
    }

    Future<void> execute(String sql, String message) =>
        _executeDdl(config, sql, successMessage: message);
    void openSql(String sql) => _openSql(config, sql);

    if (!driver.features.contains(SqlFeature.schemaEditing)) {
      return [
        if (folder == _ObjectFolder.indexes && kind.isTable)
          (
            'Create index…',
            () async {
              final list = await columns();
              await _openEditor(
                config,
                initialText: createIndexTemplate(
                  driver.dialect,
                  schema: object.schema,
                  table: object.name,
                  column: list.firstOrNull?.name,
                ),
              );
            },
          ),
      ];
    }
    // Which objects can have what, as in the inspector.
    return switch (folder) {
      _ObjectFolder.columns
          when kind.isTable || kind == DbObjectKind.foreignTable =>
        [
          (
            'Add column…',
            () async => showColumnDialog(
              context,
              schema: object.schema,
              table: object.name,
              onExecute: (sql) => execute(sql, 'Column added'),
              onOpenInSql: openSql,
            ),
          ),
        ],
      _ObjectFolder.constraints ||
      _ObjectFolder.foreignKeys when kind.isTable => [
        (
          folder == _ObjectFolder.foreignKeys
              ? 'Add foreign key…'
              : 'Add constraint…',
          () async {
            final list = await columns();
            if (!mounted) return;
            final foreignKey = folder == _ObjectFolder.foreignKeys;
            await showConstraintDialog(
              context,
              schema: object.schema,
              table: object.name,
              columns: list,
              initialKind: foreignKey ? ConstraintKind.foreignKey : null,
              onExecute: (sql) => execute(
                sql,
                foreignKey ? 'Foreign key added' : 'Constraint added',
              ),
              onOpenInSql: openSql,
            );
          },
        ),
      ],
      _ObjectFolder.indexes
          when kind.isTable || kind == DbObjectKind.materializedView =>
        [
          (
            'Create index…',
            () async {
              final list = await columns();
              if (!mounted) return;
              await showIndexDialog(
                context,
                schema: object.schema,
                table: object.name,
                columns: list,
                onExecute: (sql) => execute(sql, 'Index created'),
                onOpenInSql: openSql,
              );
            },
          ),
        ],
      _ObjectFolder.triggers when kind.isTable || kind == DbObjectKind.view => [
        (
          'Create trigger…',
          () async => showTriggerDialog(
            context,
            schema: object.schema,
            table: object.name,
            isView: kind == DbObjectKind.view,
            onExecute: (sql) => execute(sql, 'Trigger created'),
            onOpenInSql: openSql,
          ),
        ),
      ],
      _ => const [],
    };
  }

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
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
            child: Row(
              children: [
                Text(
                  'CONNECTIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'New connection',
                  icon: const Icon(Icons.add, size: 18),
                  onPressed: () => showConnectionDialog(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: TextField(
              controller: _filterController,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: Icon(
                  Icons.search,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                hintText: 'Filter schemas, tables...',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                suffixIcon: _filter.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 14),
                        onPressed: () => setState(() {
                          _filterDebounce?.cancel();
                          _filterController.clear();
                          _filter = '';
                        }),
                      ),
              ),
              onChanged: _setFilter,
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
        subtitle: '${config.engine.label} · ${config.displayAddress}',
        onTap: () => _toggleConnection(config),
        onContextMenu: _menuFor(_connectionActions(config)),
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
            if (config.engine.family == EngineFamily.relational)
              const PopupMenuItem(
                value: 'editor',
                child: Text('New SQL editor'),
              ),
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
      if (expanded)
        ...switch (config.engine.family) {
          EngineFamily.relational => _schemaNodes(config),
          EngineFamily.document => _documentNodes(config),
          EngineFamily.keyValue => _redisNodes(config),
        },
    ];
  }

  /// Redis: numbered databases with key counts; empty ones are dimmed.
  List<Widget> _redisNodes(ConnectionConfig config) {
    final databases = ref.watch(redisDatabasesProvider(config.id));
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return databases.when(
      loading: () => [const _Loading(depth: 1)],
      error: (e, _) => [_ErrorRow(depth: 1, error: e)],
      data: (list) => [
        for (final (db, keys) in list)
          _TreeRow(
            depth: 1,
            leading: Icon(
              Icons.storage_rounded,
              size: 16,
              color: keys == 0 ? muted.withValues(alpha: 0.5) : null,
            ),
            label: 'db$db',
            detail: keys == 0 ? null : '$keys keys',
            onTap: () => ref
                .read(workspaceTabsProvider.notifier)
                .openRedis(config.id, db),
          ),
      ],
    );
  }

  /// MongoDB: databases, then their collections and views.
  List<Widget> _documentNodes(ConnectionConfig config) {
    final databases = ref.watch(documentDatabasesProvider(config.id));
    return databases.when(
      loading: () => [const _Loading(depth: 1)],
      error: (e, _) => [_ErrorRow(depth: 1, error: e)],
      data: (list) => [
        for (final database in list)
          if (_filter.isEmpty ||
              database.toLowerCase().contains(_filter) ||
              _isSchemaExpanded(config, database)) ...[
            _TreeRow(
              depth: 1,
              expanded: _isSchemaExpanded(config, database),
              leading: const Icon(Icons.storage_rounded, size: 16),
              label: database,
              onTap: () => _toggle('s:${config.id}:$database'),
              onContextMenu: _menuFor([
                (
                  'Create collection…',
                  () => _createCollection(config, database),
                ),
              ]),
            ),
            if (_isSchemaExpanded(config, database))
              ..._collectionNodes(config, database),
          ],
      ],
    );
  }

  List<Widget> _collectionNodes(ConnectionConfig config, String database) {
    final collections = ref.watch(collectionsProvider((config.id, database)));
    return collections.when(
      loading: () => [const _Loading(depth: 2)],
      error: (e, _) => [_ErrorRow(depth: 2, error: e)],
      data: (list) {
        final visible = [
          for (final c in list)
            if (_filter.isEmpty || c.name.toLowerCase().contains(_filter)) c,
        ];
        if (visible.isEmpty) {
          return [
            _Message(list.isEmpty ? 'No collections' : 'No matches', depth: 2),
          ];
        }
        void open(CollectionInfo info) => ref
            .read(workspaceTabsProvider.notifier)
            .openCollection(config.id, database, info);
        return [
          for (final info in visible)
            _TreeRow(
              depth: 2,
              leading: Icon(
                info.kind == CollectionKind.view
                    ? Icons.visibility_rounded
                    : Icons.folder_copy_outlined,
                size: 16,
                color: const Color(0xFF10B981),
              ),
              label: info.name,
              detail: info.kind == CollectionKind.collection
                  ? null
                  : info.kind.label.toLowerCase(),
              onTap: () => open(info),
              onContextMenu: (position) async {
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
                    PopupMenuItem(value: 'copy', child: Text('Copy name')),
                  ],
                );
                switch (action) {
                  case 'open':
                    open(info);
                  case 'copy':
                    await Clipboard.setData(ClipboardData(text: info.name));
                }
              },
            ),
        ];
      },
    );
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
            onContextMenu: _menuFor(_schemaActions(config, schema)),
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
    final features = _features(config);
    return objects.when(
      loading: () => [const _Loading(depth: 2)],
      error: (e, _) => [_ErrorRow(depth: 2, error: e)],
      data: (list) {
        final widgets = <Widget>[];
        for (final folder in _relationFolders) {
          if (folder.feature case final f? when !features.contains(f)) continue;
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
              onContextMenu: _menuFor(
                _schemaActions(config, schema, folder.label),
              ),
            ),
          );
          if (open) {
            for (final object in visible) {
              widgets.addAll(_objectNode(config, object, depth: 3));
            }
          }
        }
        if (_filter.isEmpty && features.contains(SqlFeature.routines)) {
          widgets.addAll(_routinesFolder(config, schema));
        }
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
    final features = _features(config);
    final folders = [
      for (final folder in _foldersFor(object.kind))
        if (folder.feature == null || features.contains(folder.feature)) folder,
    ];
    final open = folders.isNotEmpty && _expanded.contains(key);
    return [
      _TreeRow(
        depth: depth,
        expanded: folders.isEmpty ? null : open,
        leading: Icon(
          _objectIcon(object.kind),
          size: 16,
          color: _objectColor(object.kind),
        ),
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
        onContextMenu: _menuFor(_objectFolderActions(config, object, folder)),
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
                      'ALTER TABLE ${_qualified(config, object)}\n'
                      '  ADD CONSTRAINT ${_dialect(config).quoteIdent(c.name)} ${c.definition};',
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
        onContextMenu: _menuFor(_schemaActions(config, schema, 'Functions')),
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
    final driver = ref.read(sqlDriverProvider(config.id));
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

  SqlDialect _dialect(ConnectionConfig config) =>
      ref.read(sqlDriverProvider(config.id))?.dialect ?? postgresDialect;

  String _qualified(ConnectionConfig config, DbObject object) =>
      _dialect(config).qualifiedName(object.schema, object.name);

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
          initialText: 'SELECT * FROM ${_qualified(config, object)} LIMIT 100;',
        );
      case 'copy':
        await Clipboard.setData(
          ClipboardData(text: _qualified(config, object)),
        );
    }
  }

  /// What the connected engine supports; empty while not connected.
  Set<SqlFeature> _features(ConnectionConfig config) =>
      ref.watch(sqlDriverProvider(config.id))?.features ?? const {};

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
    DbObjectKind.table => Icons.table_chart_rounded,
    DbObjectKind.partitionedTable => Icons.view_module_rounded,
    DbObjectKind.view => Icons.visibility_rounded,
    DbObjectKind.materializedView => Icons.auto_awesome_motion_rounded,
    DbObjectKind.foreignTable => Icons.link_rounded,
    DbObjectKind.sequence => Icons.pin_rounded,
  };

  Color _objectColor(DbObjectKind kind) => switch (kind) {
    DbObjectKind.table => const Color(0xFF0EA5E9),
    DbObjectKind.partitionedTable => const Color(0xFF3B82F6),
    DbObjectKind.view => const Color(0xFFA855F7),
    DbObjectKind.materializedView => const Color(0xFF8B5CF6),
    DbObjectKind.foreignTable => const Color(0xFF10B981),
    DbObjectKind.sequence => const Color(0xFFF59E0B),
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
  const _RelationFolder(
    this.label,
    this.kinds, {
    this.hideWhenEmpty = false,
    this.feature,
  });

  final String label;
  final Set<DbObjectKind> kinds;
  final bool hideWhenEmpty;

  /// Shown only for engines with this feature; null means always.
  final SqlFeature? feature;
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
  _RelationFolder('Sequences', {
    DbObjectKind.sequence,
  }, feature: SqlFeature.sequences),
];

/// Folders under a table-like object.
enum _ObjectFolder {
  columns('Columns'),
  constraints('Constraints', SqlFeature.constraints),
  foreignKeys('Foreign Keys', SqlFeature.foreignKeys),
  indexes('Indexes', SqlFeature.indexes),
  triggers('Triggers', SqlFeature.triggers),
  partitions('Partitions', SqlFeature.partitions);

  const _ObjectFolder(this.label, [this.feature]);

  final String label;

  /// Shown only for engines with this feature; null means always.
  final SqlFeature? feature;
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.depth,
    required this.label,
    required this.expanded,
    required this.onTap,
    this.count,
    this.onContextMenu,
  });

  final int depth;
  final String label;
  final bool expanded;
  final VoidCallback onTap;

  /// Item count, when known.
  final int? count;

  /// Create actions for the folder's kind of item; see [_TreeRow].
  final void Function(Offset position)? onContextMenu;

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
      onContextMenu: onContextMenu,
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
      borderRadius: BorderRadius.circular(6),
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
        padding: EdgeInsets.only(left: 4.0 + depth * 12, right: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxDetailWidth = constraints.maxWidth * 0.45;
            return SizedBox(
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
                        Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: const TextStyle(fontSize: 13),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (detail != null)
                    // Badges (types, partition bounds) can be long; capped so a
                    // narrow sidebar truncates them instead of overflowing.
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxDetailWidth),
                      child: Tooltip(
                        message: detail!,
                        waitDuration: const Duration(milliseconds: 600),
                        child: Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                          child: Text(
                            detail!,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.ellipsis,
                            style: monoBadgeStyle.copyWith(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ?trailing,
                ],
              ),
            );
          },
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
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: connected ? color : Colors.transparent,
          border: Border.all(color: color, width: 2),
          boxShadow: connected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.5),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ]
              : null,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.dns_rounded, size: 32, color: scheme.primary),
            ),
            const SizedBox(height: 14),
            Text(
              'No connections yet',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Connect to PostgreSQL to browse schemas, tables, and run queries.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Connection'),
            ),
          ],
        ),
      ),
    );
  }
}
