import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../state/editor_tabs.dart';
import '../../state/providers.dart';
import '../connections/connection_dialog.dart';

/// Connection list with a lazily loaded schema → object → column tree.
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
        .read(editorTabsProvider.notifier)
        .open(config.id, initialText: initialText);
    widget.onEditorOpened?.call();
  }

  Future<void> _disconnect(ConnectionConfig config) async {
    setState(() => _expanded.removeWhere((k) => k.contains(config.id)));
    await ref.read(sessionsProvider.notifier).disconnect(config.id);
  }

  void _refresh(ConnectionConfig config) {
    ref.invalidate(schemasProvider(config.id));
    ref.invalidate(objectsProvider);
    ref.invalidate(columnsProvider);
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
    ref.read(editorTabsProvider.notifier).closeForConnection(config.id);
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
                hintText: 'Filter tables',
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
            leading: const Icon(Icons.folder_outlined, size: 16),
            label: schema,
            onTap: () => _toggle('s:${config.id}:$schema'),
          ),
          if (_isSchemaExpanded(config, schema))
            ..._objectNodes(config, schema),
        ],
      ],
    );
  }

  /// Schemas auto-expand while filtering so matches are visible.
  bool _isSchemaExpanded(ConnectionConfig config, String schema) =>
      _filter.isNotEmpty || _expanded.contains('s:${config.id}:$schema');

  List<Widget> _objectNodes(ConnectionConfig config, String schema) {
    final objects = ref.watch(objectsProvider((config.id, schema)));
    return objects.when(
      loading: () => [const _Loading(depth: 2)],
      error: (e, _) => [_ErrorRow(depth: 2, error: e)],
      data: (list) {
        final visible = _filter.isEmpty
            ? list
            : list
                  .where((o) => o.name.toLowerCase().contains(_filter))
                  .toList();
        if (visible.isEmpty) {
          return _filter.isEmpty ? [const _Message('No tables', depth: 2)] : [];
        }
        return [
          for (final object in visible) ...[
            _TreeRow(
              depth: 2,
              expanded: _expanded.contains(_objectKey(config, object)),
              leading: Icon(_objectIcon(object.kind), size: 16),
              label: object.name,
              tooltip: object.kind.label,
              onTap: () => _toggle(_objectKey(config, object)),
              onDoubleTap: () => _openEditor(
                config,
                initialText:
                    'SELECT * FROM ${quoteIdent(object.schema)}.${quoteIdent(object.name)} LIMIT 100;',
              ),
            ),
            if (_expanded.contains(_objectKey(config, object)))
              ..._columnNodes(config, object),
          ],
        ];
      },
    );
  }

  String _objectKey(ConnectionConfig config, DbObject object) =>
      'o:${config.id}:${object.schema}:${object.name}';

  List<Widget> _columnNodes(ConnectionConfig config, DbObject object) {
    final columns = ref.watch(
      columnsProvider((config.id, object.schema, object.name)),
    );
    return columns.when(
      loading: () => [const _Loading(depth: 3)],
      error: (e, _) => [_ErrorRow(depth: 3, error: e)],
      data: (list) => [
        for (final column in list)
          _TreeRow(
            depth: 3,
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
    );
  }

  IconData _objectIcon(DbObjectKind kind) => switch (kind) {
    DbObjectKind.table => Icons.table_chart_outlined,
    DbObjectKind.partitionedTable => Icons.view_module_outlined,
    DbObjectKind.view => Icons.visibility_outlined,
    DbObjectKind.materializedView => Icons.auto_awesome_motion_outlined,
    DbObjectKind.foreignTable => Icons.link,
  };
}

/// Quotes a Postgres identifier when it isn't a plain lowercase name.
String quoteIdent(String name) {
  if (RegExp(r'^[a-z_][a-z0-9_$]*$').hasMatch(name)) return name;
  return '"${name.replaceAll('"', '""')}"';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = InkWell(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      child: Padding(
        padding: EdgeInsets.only(left: 4.0 + depth * 16, right: 4),
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
      padding: EdgeInsets.only(left: 26.0 + depth * 16, top: 6, bottom: 6),
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
        left: 26.0 + depth * 16,
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
        left: 26.0 + depth * 16,
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
