import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/pgsql.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../state/editor_tabs.dart';
import '../../state/providers.dart';
import '../connections/connection_dialog.dart';
import '../history/history_dialog.dart';
import '../results/results_view.dart';

/// Editor tabs plus the active tab's editor and results.
class Workspace extends ConsumerWidget {
  const Workspace({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editorTabsProvider);
    final active = state.active;
    if (active == null) return const _EmptyWorkspace();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabStrip(state: state),
        const Divider(),
        Expanded(
          child: EditorView(key: ValueKey(active.id), tab: active),
        ),
      ],
    );
  }
}

class _TabStrip extends ConsumerWidget {
  const _TabStrip({required this.state});

  final EditorTabsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(connectionsProvider).value ?? const [];
    final notifier = ref.read(editorTabsProvider.notifier);

    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final tab in state.tabs)
                  _TabChip(
                    tab: tab,
                    active: tab.id == state.activeId,
                    color: _connectionColor(connections, tab.connectionId),
                    onTap: () => notifier.activate(tab.id),
                    onClose: () => notifier.close(tab.id),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'New SQL editor',
            icon: const Icon(Icons.add, size: 18),
            onPressed: () => notifier.open(state.active!.connectionId),
          ),
        ],
      ),
    );
  }

  Color? _connectionColor(List<ConnectionConfig> list, String id) {
    for (final c in list) {
      if (c.id == id) return Color(c.color);
    }
    return null;
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.tab,
    required this.active,
    required this.color,
    required this.onTap,
    required this.onClose,
  });

  final EditorTab tab;
  final bool active;
  final Color? color;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? scheme.surface : scheme.surfaceContainerHigh,
      child: GestureDetector(
        // Middle-click closes, like browser tabs.
        onTertiaryTapUp: (_) => onClose(),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.only(left: 12, right: 2),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: active
                      ? (color ?? scheme.primary)
                      : Colors.transparent,
                  width: 2,
                ),
                right: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                ListenableBuilder(
                  listenable: tab,
                  builder: (_, _) => tab.running
                      ? const SizedBox.square(
                          dimension: 10,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(Icons.code, size: 14, color: color),
                ),
                const SizedBox(width: 6),
                Text(tab.title),
                IconButton(
                  tooltip: 'Close',
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyWorkspace extends StatelessWidget {
  const _EmptyWorkspace();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('No editor open', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Open a connection and choose "New SQL editor",\n'
              'or double-click a table.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _RunIntent extends Intent {
  const _RunIntent({required this.script});

  final bool script;
}

/// Toolbar, SQL editor and results for one tab.
class EditorView extends ConsumerStatefulWidget {
  const EditorView({super.key, required this.tab});

  final EditorTab tab;

  @override
  ConsumerState<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends ConsumerState<EditorView> {
  double _editorFraction = 0.45;

  EditorTab get tab => widget.tab;

  Future<void> _run({required bool script}) async {
    final connections = ref.read(connectionsProvider).value ?? const [];
    final config = connections
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
    if (driver == null) return;
    await tab.run(statements, driver, ref.read(historyRepositoryProvider));
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showHistory() async {
    final sql = await showHistoryDialog(
      context,
      connectionId: tab.connectionId,
    );
    if (sql != null) {
      ref
          .read(editorTabsProvider.notifier)
          .open(tab.connectionId, initialText: sql);
    }
  }

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
          SingleActivator(LogicalKeyboardKey.keyX, alt: true): _RunIntent(
            script: true,
          ),
        },
        child: ListenableBuilder(
          listenable: tab,
          builder: (context, _) => LayoutBuilder(
            builder: (context, constraints) {
              const toolbarHeight = 40.0;
              const dividerHeight = 6.0;
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
                    child: _Toolbar(
                      tab: tab,
                      runTooltip: 'Run statement ($runKey)',
                      scriptTooltip: 'Run script ($scriptKey)',
                      onRun: () => _run(script: false),
                      onRunScript: () => _run(script: true),
                      onHistory: _showHistory,
                    ),
                  ),
                  SizedBox(
                    height: editorHeight,
                    child: _SqlEditor(tab: tab),
                  ),
                  MouseRegion(
                    cursor: SystemMouseCursors.resizeRow,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: (d) => setState(() {
                        _editorFraction =
                            ((editorHeight + d.delta.dy) / available).clamp(
                              0.1,
                              0.9,
                            );
                      }),
                      child: const SizedBox(
                        height: dividerHeight,
                        child: Center(child: Divider()),
                      ),
                    ),
                  ),
                  Expanded(child: ResultsView(tab: tab)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends ConsumerWidget {
  const _Toolbar({
    required this.tab,
    required this.runTooltip,
    required this.scriptTooltip,
    required this.onRun,
    required this.onRunScript,
    required this.onHistory,
  });

  final EditorTab tab;
  final String runTooltip;
  final String scriptTooltip;
  final VoidCallback onRun;
  final VoidCallback onRunScript;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(connectionsProvider).value ?? const [];
    final hasConnection = connections.any((c) => c.id == tab.connectionId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: runTooltip,
            icon: const Icon(Icons.play_arrow),
            color: Colors.green.shade600,
            onPressed: tab.running ? null : onRun,
          ),
          IconButton(
            tooltip: scriptTooltip,
            icon: const Icon(Icons.playlist_play),
            onPressed: tab.running ? null : onRunScript,
          ),
          IconButton(
            tooltip: 'Cancel',
            icon: const Icon(Icons.stop),
            color: Theme.of(context).colorScheme.error,
            onPressed: tab.running ? tab.cancel : null,
          ),
          const VerticalDivider(indent: 8, endIndent: 8),
          IconButton(
            tooltip: 'Query history',
            icon: const Icon(Icons.history),
            onPressed: onHistory,
          ),
          const Spacer(),
          Flexible(
            flex: 3,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: hasConnection ? tab.connectionId : null,
                hint: const Text('No connection'),
                items: [
                  for (final c in connections)
                    DropdownMenuItem(
                      value: c.id,
                      child: Row(
                        children: [
                          Icon(Icons.circle, size: 10, color: Color(c.color)),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              c.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                onChanged: tab.running ? null : (id) => tab.connectionId = id!,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// re_editor binds Ctrl/Cmd+Enter to "new line"; free those keys for running
/// queries.
class _SqlEditorShortcuts extends DefaultCodeShortcutsActivatorsBuilder {
  const _SqlEditorShortcuts();

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    if (type == CodeShortcutType.newLine) {
      return const [
        SingleActivator(LogicalKeyboardKey.enter),
        SingleActivator(LogicalKeyboardKey.enter, shift: true),
        SingleActivator(LogicalKeyboardKey.numpadEnter),
        SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true),
      ];
    }
    return super.build(type);
  }
}

class _SqlEditor extends StatelessWidget {
  const _SqlEditor({required this.tab});

  final EditorTab tab;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return CodeEditor(
      controller: tab.controller,
      autofocus: true,
      wordWrap: false,
      shortcutsActivatorsBuilder: const _SqlEditorShortcuts(),
      style: CodeEditorStyle(
        fontSize: 14,
        fontFamily: monoFontFamily,
        fontFamilyFallback: monoFontFallback,
        backgroundColor: theme.colorScheme.surface,
        codeTheme: CodeHighlightTheme(
          languages: {'pgsql': CodeHighlightThemeMode(mode: langPgsql)},
          theme: dark ? atomOneDarkTheme : atomOneLightTheme,
        ),
      ),
      indicatorBuilder:
          (context, editingController, chunkController, notifier) {
            return Row(
              children: [
                DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                ),
                DefaultCodeChunkIndicator(
                  width: 16,
                  controller: chunkController,
                  notifier: notifier,
                ),
              ],
            );
          },
    );
  }
}
