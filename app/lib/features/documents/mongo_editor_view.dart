import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_highlight/languages/javascript.dart';

import '../../app/theme.dart';
import '../../drivers/document.dart';
import '../../drivers/driver.dart';
import '../../drivers/mongodb/mongo_json.dart';
import '../../state/providers.dart';
import '../../state/workspace_tabs.dart';
import '../common/running_indicator.dart';
import '../connections/connection_dialog.dart';
import '../editor/sql_autocomplete.dart';
import '../editor/workspace.dart';
import '../results/results_view.dart';
import 'collection_view.dart';
import 'mongo_completion.dart';

/// Collections and sampled field names from the cached providers. A lookup
/// that isn't loaded yet starts loading and returns null, so its names show
/// up on a later keystroke.
class ProviderMongoCatalog implements MongoCatalog {
  ProviderMongoCatalog(this._ref, this._connectionId, this._database);

  final WidgetRef _ref;
  final String _connectionId;
  final String _database;

  @override
  List<String>? collections() => _ref
      .read(collectionsProvider((_connectionId, _database)))
      .value
      ?.map((c) => c.name)
      .toList();

  /// Samples only collections that exist, so half-typed names don't each
  /// start a query.
  @override
  List<String>? fields(String collection) {
    if (!(collections()?.contains(collection) ?? false)) return null;
    return _ref
        .read(collectionFieldsProvider((_connectionId, _database, collection)))
        .value;
  }
}

class _RunIntent extends Intent {
  const _RunIntent({required this.script});

  final bool script;
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}

/// MongoDB query editor: mongosh-style statements above, the documents
/// they return below.
class MongoEditorView extends ConsumerStatefulWidget {
  const MongoEditorView({super.key, required this.tab});

  final MongoEditorTab tab;

  @override
  ConsumerState<MongoEditorView> createState() => _MongoEditorViewState();
}

class _MongoEditorViewState extends ConsumerState<MongoEditorView> {
  static const _limits = [10, 20, 50, 100, 500, 1000];

  /// Reads the tab's current database each time, since `use` and the
  /// toolbar can switch it.
  late final _completion = SqlPromptsBuilder.custom(
    controller: tab.controller,
    complete: (text, cursor) => completeMongo(
      text: text,
      cursor: cursor,
      catalog: ProviderMongoCatalog(ref, tab.connectionId, tab.database),
    ),
  );

  double _editorFraction = 0.45;

  MongoEditorTab get tab => widget.tab;

  Future<void> _run({required bool script}) async {
    if (tab.busy) return;
    final config = (ref.read(connectionsProvider).value ?? const [])
        .where((c) => c.id == tab.connectionId)
        .firstOrNull;
    if (config == null) {
      _snack('This tab\'s connection no longer exists.');
      return;
    }
    final statements = script ? tab.allStatements() : [?tab.currentStatement()];
    if (statements.isEmpty) {
      _snack('Nothing to run.');
      return;
    }
    final driver = await connectWithPrompt(context, ref, config);
    if (driver is! DocumentDriver || !mounted) return;
    final sessions = ref.read(sessionsProvider.notifier);
    await tab.run(
      statements,
      driver,
      // A command that ignored the cancel still holds the connection.
      onAbandon: () => sessions.disconnect(config.id),
    );
    // Writes and drops change what the navigator shows.
    if (!mounted) return;
    ref.invalidate(collectionsProvider((tab.connectionId, tab.database)));
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final isMac = Theme.of(context).platform == TargetPlatform.macOS;
    final runKey = isMac ? '⌘↵' : 'Ctrl+Enter';
    final scriptKey = isMac ? '⌘⇧↵' : 'Ctrl+Shift+Enter';
    return Actions(
      actions: {
        _RunIntent: CallbackAction<_RunIntent>(
          onInvoke: (intent) => _run(script: intent.script),
        ),
        _CancelIntent: CallbackAction<_CancelIntent>(
          onInvoke: (_) => tab.busy ? tab.cancel() : null,
        ),
      },
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter, control: true): _RunIntent(
            script: false,
          ),
          SingleActivator(LogicalKeyboardKey.enter, meta: true): _RunIntent(
            script: false,
          ),
          SingleActivator(LogicalKeyboardKey.enter, control: true, shift: true):
              _RunIntent(script: true),
          SingleActivator(LogicalKeyboardKey.enter, meta: true, shift: true):
              _RunIntent(script: true),
          SingleActivator(LogicalKeyboardKey.escape): _CancelIntent(),
        },
        child: ListenableBuilder(
          listenable: tab,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              const toolbarHeight = 40.0;
              const dividerHeight = 8.0;
              final available =
                  constraints.maxHeight - toolbarHeight - dividerHeight;
              final editorHeight = (available * _editorFraction).clamp(
                60.0,
                (available - 60).clamp(60.0, double.infinity),
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: toolbarHeight,
                    child: _toolbar(runKey, scriptKey),
                  ),
                  SizedBox(
                    height: editorHeight,
                    child: SqlEditor(
                      controller: tab.controller,
                      completion: _completion,
                      languageName: 'javascript',
                      language: langJavascript,
                    ),
                  ),
                  HorizontalSplitter(
                    onDragUpdate: (dy) => setState(() {
                      _editorFraction = ((editorHeight + dy) / available).clamp(
                        0.1,
                        0.9,
                      );
                    }),
                  ),
                  Expanded(child: _MongoResults(tab: tab)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _toolbar(String runKey, String scriptKey) {
    final scheme = Theme.of(context).colorScheme;
    final databases =
        ref.watch(documentDatabasesProvider(tab.connectionId)).value ??
        const <String>[];
    final running = tab.busy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'Run statement ($runKey)',
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              icon: running
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 16),
              label: const Text(
                'Run',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
              onPressed: running ? null : () => _run(script: false),
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: 'Run all statements ($scriptKey)',
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.playlist_play_rounded, size: 16),
              label: const Text('Script', style: TextStyle(fontSize: 12)),
              onPressed: running ? null : () => _run(script: true),
            ),
          ),
          if (running) ...[
            const SizedBox(width: 6),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.errorContainer,
                foregroundColor: scheme.onErrorContainer,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.stop_rounded, size: 16),
              label: Text(
                tab.cancelling ? 'Cancelling…' : 'Cancel',
                style: const TextStyle(fontSize: 12),
              ),
              onPressed: tab.cancelling ? null : tab.cancel,
            ),
          ],
          const Spacer(),
          PopupMenuButton<int>(
            tooltip: 'Documents to show per result',
            initialValue: tab.limit,
            onSelected: (limit) => setState(() => tab.limit = limit),
            itemBuilder: (_) => [
              for (final limit in _limits)
                PopupMenuItem(value: limit, child: Text('$limit documents')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Max ${tab.limit}',
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // The database statements run in; `use <db>` changes it too.
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isDense: true,
                  isExpanded: true,
                  value: tab.database,
                  icon: const Icon(Icons.arrow_drop_down, size: 18),
                  items: [
                    for (final db in {...databases, tab.database})
                      DropdownMenuItem(
                        value: db,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.storage_rounded, size: 14),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                db,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: running ? null : (db) => tab.database = db!,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ResultView {
  documents('Documents', Icons.view_agenda_outlined),
  table('Table', Icons.table_chart_outlined),
  json('JSON', Icons.data_object_rounded);

  const _ResultView(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The selected statement's documents (as trees, a table or JSON) or
/// error, with a strip to switch between the statements of a script.
class _MongoResults extends StatefulWidget {
  const _MongoResults({required this.tab});

  final MongoEditorTab tab;

  @override
  State<_MongoResults> createState() => _MongoResultsState();
}

class _MongoResultsState extends State<_MongoResults> {
  _ResultView _view = _ResultView.documents;

  /// Table and JSON views per page, built once rather than per rebuild.
  static final _tables = Expando<QueryResult>();
  static final _json = Expando<String>();

  MongoEditorTab get tab => widget.tab;

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outcomes = tab.outcomes;
    if (outcomes.isEmpty) {
      if (tab.busy) return Center(child: RunningIndicator(tab: tab));
      return Center(
        child: Text(
          'Run a statement to see its documents here',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    final index = tab.selectedOutcome.clamp(0, outcomes.length - 1);
    final outcome = outcomes[index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (outcomes.length > 1) _statementStrip(outcomes, index),
        _header(outcome),
        const Divider(height: 1),
        if (tab.busy) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _body(outcome)),
      ],
    );
  }

  Widget _statementStrip(List<MongoOutcome> outcomes, int selected) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        itemCount: outcomes.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final failed = outcomes[i].error != null;
          return ChoiceChip(
            visualDensity: VisualDensity.compact,
            label: Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: 11,
                color: failed ? scheme.error : null,
              ),
            ),
            avatar: failed
                ? Icon(Icons.error_outline_rounded, size: 14, color: scheme.error)
                : null,
            selected: i == selected,
            tooltip: outcomes[i].statement,
            onSelected: (_) => tab.selectedOutcome = i,
          );
        },
      ),
    );
  }

  Widget _header(MongoOutcome outcome) {
    final scheme = Theme.of(context).colorScheme;
    final result = outcome.result;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          if (result != null && result.page.documents.isNotEmpty) ...[
            SegmentedButton<_ResultView>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: [
                for (final v in _ResultView.values)
                  ButtonSegment(
                    value: v,
                    icon: Icon(v.icon, size: 15),
                    label: Text(v.label, style: const TextStyle(fontSize: 12)),
                  ),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              result == null
                  ? 'Failed'
                  : '${result.summary} · '
                        '${result.page.elapsed.inMilliseconds} ms'
                        '${result.page.hasMore ? ' · more available, raise '
                                  '"Max" or add .limit()' : ''}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: result == null ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (result != null && result.page.documents.isNotEmpty)
            IconButton(
              tooltip: 'Copy all as JSON',
              icon: const Icon(Icons.copy_all_rounded, size: 18),
              onPressed: () => _copy(formatMongo(result.page.documents)),
            ),
        ],
      ),
    );
  }

  Widget _body(MongoOutcome outcome) {
    final scheme = Theme.of(context).colorScheme;
    final result = outcome.result;
    if (result == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          '${outcome.error}\n\n${outcome.statement}',
          style: monoStyle.copyWith(fontSize: 12.5, color: scheme.error),
        ),
      );
    }
    final page = result.page;
    if (page.documents.isEmpty) {
      return Center(
        child: Text(
          result.summary,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    return switch (_view) {
      _ResultView.documents => ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: page.documents.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final doc = page.documents[i];
          return DocumentCard(
            key: ObjectKey(doc),
            document: doc,
            onCopy: () => _copy(formatMongo(doc)),
          );
        },
      ),
      _ResultView.table => ResultGrid(
        key: ObjectKey(page),
        result: _tables[page] ??= documentsTable(page),
      ),
      _ResultView.json => SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: SelectableText(
          _json[page] ??= formatMongo(page.documents),
          style: monoStyle.copyWith(fontSize: 12.5, height: 1.4),
        ),
      ),
    };
  }
}
