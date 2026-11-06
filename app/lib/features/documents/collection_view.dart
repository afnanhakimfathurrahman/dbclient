import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../drivers/document.dart';
import '../../drivers/driver.dart';
import '../../drivers/mongodb/document_diff.dart';
import '../../drivers/mongodb/mongo_json.dart';
import '../../state/providers.dart';
import '../../state/workspace_tabs.dart';
import '../connections/connection_dialog.dart';
import '../results/results_view.dart';
import 'document_editor_dialog.dart';
import 'json_tree.dart';

enum _DocView {
  documents('Documents', Icons.view_agenda_outlined),
  table('Table', Icons.table_chart_outlined),
  json('JSON', Icons.data_object_rounded);

  const _DocView(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// A MongoDB collection, Compass-style: a query bar, then the matching
/// documents as expandable trees, a table, or raw JSON.
class CollectionView extends ConsumerStatefulWidget {
  const CollectionView({super.key, required this.tab});

  final CollectionTab tab;

  @override
  ConsumerState<CollectionView> createState() => _CollectionViewState();
}

class _CollectionViewState extends ConsumerState<CollectionView> {
  static const _pageSizes = [10, 20, 50, 100, 500];

  _DocView _view = _DocView.documents;

  CollectionTab get tab => widget.tab;
  bool get _writable => tab.info.kind == CollectionKind.collection;

  @override
  void initState() {
    super.initState();
    if (!tab.loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run();
      });
    }
  }

  Future<DocumentDriver?> _driver() async {
    final config = (ref.read(connectionsProvider).value ?? const [])
        .where((c) => c.id == tab.connectionId)
        .firstOrNull;
    if (config == null) return null;
    final driver = await connectWithPrompt(context, ref, config);
    return driver is DocumentDriver ? driver : null;
  }

  Future<void> _run({bool reset = false}) async {
    final driver = await _driver();
    if (driver != null) await tab.run(driver, resetSkip: reset);
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  /// Runs a write, then re-runs the query so the list shows the result.
  Future<void> _write(
    Future<void> Function(DocumentDriver driver) action,
  ) async {
    final driver = await _driver();
    if (driver == null) throw const DriverException('Not connected');
    await action(driver);
    await tab.run(driver);
  }

  Future<void> _insert({Map<String, dynamic>? template}) async {
    final saved = await showDocumentEditor(
      context,
      title: template == null
          ? 'Insert into ${tab.collection}'
          : 'Clone into ${tab.collection}',
      initialText: template == null ? '{\n  \n}' : formatMongo(template),
      actionLabel: 'Insert',
      onSave: (doc) =>
          _write((d) => d.insertOne(tab.database, tab.collection, doc)),
    );
    if (saved ?? false) _snack('Document inserted');
  }

  Future<void> _edit(Map<String, dynamic> document) async {
    final saved = await showDocumentEditor(
      context,
      title: 'Edit document',
      initialText: formatMongo(document),
      actionLabel: 'Update',
      onSave: (edited) async {
        final update = documentUpdate(document, edited);
        if (update.isEmpty) return;
        await _write(
          (d) => d.updateOne(tab.database, tab.collection, {
            '_id': document['_id'],
          }, update),
        );
      },
    );
    if (saved ?? false) _snack('Document updated');
  }

  Future<void> _delete(Map<String, dynamic> document) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete document?'),
        content: Text(
          '_id: ${formatMongoInline(document['_id'])}\n\n'
          'This deletes it from ${tab.database}.${tab.collection} now; '
          'it cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;
    try {
      await _write(
        (d) =>
            d.deleteOne(tab.database, tab.collection, {'_id': document['_id']}),
      );
      _snack('Document deleted');
    } catch (e) {
      _snack('$e');
    }
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    _snack('$what copied');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tab,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          _queryBar(),
          const Divider(height: 1),
          _resultsToolbar(),
          const Divider(height: 1),
          if (tab.busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _results()),
        ],
      ),
    );
  }

  Widget _header() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          Icon(
            tab.info.kind == CollectionKind.view
                ? Icons.visibility_rounded
                : Icons.folder_copy_outlined,
            size: 18,
            color: const Color(0xFF10B981),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${tab.database}.${tab.collection}',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            tab.info.kind.label,
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, size: 18),
            onPressed: tab.busy ? null : _run,
          ),
        ],
      ),
    );
  }

  Widget _queryField(
    TextEditingController controller,
    String label,
    String hint, {
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      style: monoStyle.copyWith(fontSize: 12.5),
      minLines: 1,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        floatingLabelBehavior: FloatingLabelBehavior.always,
      ),
      onSubmitted: maxLines == 1 ? (_) => _run(reset: true) : null,
    );
  }

  Widget _queryBar() {
    final find = tab.mode == DocumentQueryMode.find;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () =>
            _run(reset: true),
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () =>
            _run(reset: true),
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<DocumentQueryMode>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: DocumentQueryMode.find,
                      label: Text('Find'),
                    ),
                    ButtonSegment(
                      value: DocumentQueryMode.aggregate,
                      label: Text('Aggregate'),
                    ),
                  ],
                  selected: {tab.mode},
                  onSelectionChanged: (s) => setState(() => tab.mode = s.first),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: find
                      ? _queryField(
                          tab.filter,
                          'Filter',
                          "{ status: 'active' }",
                        )
                      : _queryField(
                          tab.pipeline,
                          'Pipeline',
                          '[ { \$match: { … } } ]',
                          maxLines: 8,
                        ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: Text(find ? 'Find' : 'Run'),
                  onPressed: tab.busy ? null : () => _run(reset: true),
                ),
              ],
            ),
            if (find) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _queryField(
                      tab.projection,
                      'Project',
                      '{ name: 1, _id: 0 }',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _queryField(tab.sort, 'Sort', '{ createdAt: -1 }'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _resultsToolbar() {
    final scheme = Theme.of(context).colorScheme;
    final page = tab.page;
    final shown = page?.documents.length ?? 0;
    final range = shown == 0
        ? 'No documents'
        : '${tab.skip + 1}–${tab.skip + shown}'
              '${tab.total != null ? ' of ${tab.total}' : ''}';
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          SegmentedButton<_DocView>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (final v in _DocView.values)
                ButtonSegment(
                  value: v,
                  icon: Icon(v.icon, size: 15),
                  label: Text(v.label, style: const TextStyle(fontSize: 12)),
                ),
            ],
            selected: {_view},
            onSelectionChanged: (s) => setState(() => _view = s.first),
          ),
          if (_writable) ...[
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Insert', style: TextStyle(fontSize: 12)),
              onPressed: _insert,
            ),
          ],
          const Spacer(),
          Flexible(
            child: Text(
              range,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          if (tab.mode == DocumentQueryMode.find) ...[
            IconButton(
              tooltip: 'Previous page',
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              onPressed: tab.busy || tab.skip == 0
                  ? null
                  : () {
                      tab.skip = (tab.skip - tab.limit).clamp(0, tab.skip);
                      _run();
                    },
            ),
            IconButton(
              tooltip: 'Next page',
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              onPressed: tab.busy || !(page?.hasMore ?? false)
                  ? null
                  : () {
                      tab.skip += tab.limit;
                      _run();
                    },
            ),
          ],
          PopupMenuButton<int>(
            tooltip: 'Documents per page',
            initialValue: tab.limit,
            onSelected: (size) {
              tab.limit = size;
              ref.read(dataRowLimitProvider.notifier).set(size);
              _run(reset: true);
            },
            itemBuilder: (_) => [
              for (final size in _pageSizes)
                PopupMenuItem(value: size, child: Text('$size per page')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '${tab.limit} / page',
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _results() {
    final scheme = Theme.of(context).colorScheme;
    final page = tab.page;
    final error = tab.error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SelectableText(
            '$error',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.error),
          ),
        ),
      );
    }
    if (page == null) {
      return tab.busy
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox.shrink();
    }
    if (page.documents.isEmpty) {
      return Center(
        child: Text(
          'No documents match',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return switch (_view) {
      _DocView.documents => ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: page.documents.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final doc = page.documents[i];
          return _DocumentCard(
            key: ObjectKey(doc),
            document: doc,
            onCopy: () => _copy(formatMongo(doc), 'Document'),
            onEdit: _writable && doc.containsKey('_id')
                ? () => _edit(doc)
                : null,
            onClone: _writable
                ? () => _insert(template: {...doc}..remove('_id'))
                : null,
            onDelete: _writable && doc.containsKey('_id')
                ? () => _delete(doc)
                : null,
          );
        },
      ),
      _DocView.table => ResultGrid(
        key: ObjectKey(page),
        result: _asTable(page),
      ),
      _DocView.json => SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: SelectableText(
          formatMongo(page.documents),
          style: monoStyle.copyWith(fontSize: 12.5, height: 1.4),
        ),
      ),
    };
  }

  /// Top-level fields as columns (in order of first appearance), nested
  /// values as one-line mongosh text.
  static QueryResult _asTable(DocumentPage page) {
    final names = <String>{for (final doc in page.documents) ...doc.keys}
        .take(200)
        .toList();
    return QueryResult(
      columns: [
        for (final name in names)
          ResultColumn(
            name: name,
            dataType: mongoTypeName(
              page.documents
                  .map((d) => d[name])
                  .firstWhere((v) => v != null, orElse: () => null),
            ),
          ),
      ],
      rows: [
        for (final doc in page.documents)
          [
            for (final name in names)
              switch (doc[name]) {
                null => null,
                final String s => s,
                final num n => n,
                final bool b => b,
                final v => formatMongoInline(v),
              },
          ],
      ],
      affectedRows: 0,
      elapsed: page.elapsed,
      truncated: page.hasMore,
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({
    super.key,
    required this.document,
    required this.onCopy,
    this.onEdit,
    this.onClone,
    this.onDelete,
  });

  final Map<String, dynamic> document;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback? onClone;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget action(
      IconData icon,
      String tooltip,
      VoidCallback? onPressed, {
      Color? color,
    }) => IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 16, color: color),
      onPressed: onPressed,
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: JsonTree(document: document)),
          Column(
            children: [
              if (onEdit != null) action(Icons.edit_outlined, 'Edit', onEdit),
              action(Icons.copy_rounded, 'Copy as JSON', onCopy),
              if (onClone != null)
                action(Icons.control_point_duplicate_rounded, 'Clone', onClone),
              if (onDelete != null)
                action(
                  Icons.delete_outline_rounded,
                  'Delete',
                  onDelete,
                  color: scheme.error,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
