import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/pgsql.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../state/workspace_tabs.dart';
import '../../state/providers.dart';
import '../connections/connection_dialog.dart';
import '../history/history_dialog.dart';
import '../documents/collection_view.dart';
import '../inspector/inspector_view.dart';
import '../keyvalue/redis_view.dart';
import '../results/results_view.dart';

/// Editor tabs plus the active tab's editor and results.
class Workspace extends ConsumerWidget {
  const Workspace({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workspaceTabsProvider);
    final active = state.active;
    if (active == null) return const _EmptyWorkspace();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabStrip(state: state),
        const Divider(),
        Expanded(
          child: switch (active) {
            EditorTab() => EditorView(key: ValueKey(active.id), tab: active),
            InspectorTab() => InspectorView(
              key: ValueKey(active.id),
              tab: active,
            ),
            CollectionTab() => CollectionView(
              key: ValueKey(active.id),
              tab: active,
            ),
            RedisTab() => RedisView(key: ValueKey(active.id), tab: active),
          },
        ),
      ],
    );
  }
}

class _TabStrip extends ConsumerWidget {
  const _TabStrip({required this.state});

  final WorkspaceTabsState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(connectionsProvider).value ?? const [];
    final notifier = ref.read(workspaceTabsProvider.notifier);
    final theme = Theme.of(context);

    return Container(
      height: 38,
      color: theme.colorScheme.surfaceContainerLow,
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
                    onClose: () async {
                      if (tab is InspectorTab &&
                          tab.hasUnsavedChanges &&
                          !await _confirmCloseUnsaved(context, tab)) {
                        return;
                      }
                      notifier.close(tab.id);
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmCloseUnsaved(
    BuildContext context,
    InspectorTab tab,
  ) async {
    final close = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Close ${tab.object.name}?'),
        content: const Text('Unsaved row edits will be lost.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard and close'),
          ),
        ],
      ),
    );
    return close ?? false;
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

  final WorkspaceTab tab;
  final bool active;
  final Color? color;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: active ? scheme.surfaceContainer : Colors.transparent,
      child: GestureDetector(
        // Middle-click closes, like browser tabs.
        onTertiaryTapUp: (_) => onClose(),
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: active
                      ? (color ?? scheme.primary)
                      : Colors.transparent,
                  width: 2.5,
                ),
                right: BorderSide(color: scheme.outlineVariant),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (color != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                ListenableBuilder(
                  listenable: tab,
                  builder: (_, _) => tab.busy
                      ? const SizedBox.square(
                          dimension: 11,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          switch (tab) {
                            InspectorTab() => Icons.table_chart_rounded,
                            CollectionTab() => Icons.data_object_rounded,
                            RedisTab() => Icons.bolt_rounded,
                            EditorTab() => Icons.terminal_rounded,
                          },
                          size: 14,
                          color: active
                              ? (color ?? scheme.primary)
                              : scheme.onSurfaceVariant,
                        ),
                ),
                const SizedBox(width: 6),
                // Rebuilt on tab changes: the title marks unsaved edits.
                ListenableBuilder(
                  listenable: tab,
                  builder: (_, _) => Text(
                    tab.title,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                      color: active
                          ? scheme.onSurface
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Close tab',
                  iconSize: 13,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
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

class _EmptyWorkspace extends ConsumerWidget {
  const _EmptyWorkspace();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 580),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      scheme.primary.withValues(alpha: 0.15),
                      scheme.secondary.withValues(alpha: 0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Icon(
                  Icons.terminal_rounded,
                  size: 38,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Welcome to DB Client',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Direct cross-platform database IDE. Connect directly to real databases without intermediaries.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.code_rounded,
                      iconColor: const Color(0xFF10B981),
                      title: 'New SQL Query',
                      subtitle: 'Write and run SQL with live results',
                      badge: 'Ctrl+N',
                      onTap: () => openNewSqlEditor(context, ref),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickActionCard(
                      icon: Icons.add_circle_outline_rounded,
                      iconColor: scheme.primary,
                      title: 'Add Connection',
                      subtitle: 'Connect to PostgreSQL server or local DB',
                      badge: 'Direct TCP',
                      onTap: () => showConnectionDialog(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.keyboard_rounded,
                          size: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'KEYBOARD SHORTCUTS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ShortcutItem(label: 'Run Statement', keys: 'Ctrl+↵'),
                        _ShortcutItem(
                          label: 'Run Script',
                          keys: 'Ctrl+Shift+↵',
                        ),
                        _ShortcutItem(label: 'Copy Cell', keys: 'Ctrl+C'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: iconColor),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShortcutItem extends StatelessWidget {
  const _ShortcutItem({required this.label, required this.keys});

  final String label;
  final String keys;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Text(
            keys,
            style: monoBadgeStyle.copyWith(
              fontSize: 10,
              color: scheme.onSurface,
            ),
          ),
        ),
      ],
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
    final driver = await connectSqlWithPrompt(context, ref, config);
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
          .read(workspaceTabsProvider.notifier)
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
                      runKeyText: runKey,
                      onRun: () => _run(script: false),
                      onRunScript: () => _run(script: true),
                      onHistory: _showHistory,
                    ),
                  ),
                  SizedBox(
                    height: editorHeight,
                    child: SqlEditor(controller: tab.controller),
                  ),
                  _HorizontalSplitter(
                    onDragUpdate: (dy) => setState(() {
                      _editorFraction = ((editorHeight + dy) / available).clamp(
                        0.1,
                        0.9,
                      );
                    }),
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

class _HorizontalSplitter extends StatefulWidget {
  const _HorizontalSplitter({required this.onDragUpdate});

  final ValueChanged<double> onDragUpdate;

  @override
  State<_HorizontalSplitter> createState() => _HorizontalSplitterState();
}

class _HorizontalSplitterState extends State<_HorizontalSplitter> {
  bool _isHovered = false;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = _isHovered || _isDragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: (_) => setState(() => _isDragging = true),
        onVerticalDragEnd: (_) => setState(() => _isDragging = false),
        onVerticalDragCancel: () => setState(() => _isDragging = false),
        onVerticalDragUpdate: (d) => widget.onDragUpdate(d.delta.dy),
        child: SizedBox(
          height: 8,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                height: highlighted ? 2 : 1,
                color: highlighted ? scheme.primary : scheme.outlineVariant,
              ),
              if (highlighted)
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
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
    required this.runKeyText,
    required this.onRun,
    required this.onRunScript,
    required this.onHistory,
  });

  final EditorTab tab;
  final String runTooltip;
  final String scriptTooltip;
  final String runKeyText;
  final VoidCallback onRun;
  final VoidCallback onRunScript;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final connections = ref.watch(connectionsProvider).value ?? const [];
    final hasConnection = connections.any((c) => c.id == tab.connectionId);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(
        children: [
          // Prominent Run Button
          Tooltip(
            message: runTooltip,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                visualDensity: VisualDensity.compact,
              ),
              icon: tab.running
                  ? const SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_arrow_rounded, size: 16),
              label: Text(
                'Run ($runKeyText)',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              onPressed: tab.running ? null : onRun,
            ),
          ),
          const SizedBox(width: 6),
          Tooltip(
            message: scriptTooltip,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.playlist_play_rounded, size: 16),
              label: const Text('Script', style: TextStyle(fontSize: 12)),
              onPressed: tab.running ? null : onRunScript,
            ),
          ),
          if (tab.running) ...[
            const SizedBox(width: 6),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.errorContainer,
                foregroundColor: scheme.onErrorContainer,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.stop_rounded, size: 16),
              label: const Text('Cancel', style: TextStyle(fontSize: 12)),
              onPressed: tab.cancel,
            ),
          ],
          const SizedBox(width: 8),
          SizedBox(
            height: 18,
            child: VerticalDivider(color: scheme.outlineVariant),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Query history',
            icon: const Icon(Icons.history_rounded, size: 18),
            onPressed: onHistory,
          ),
          const Spacer(),

          // Target Connection Dropdown Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isDense: true,
                value: hasConnection ? tab.connectionId : null,
                hint: Text(
                  'Select connection',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                icon: const Icon(Icons.arrow_drop_down, size: 18),
                items: [
                  for (final c in connections)
                    DropdownMenuItem(
                      value: c.id,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: Color(c.color),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            c.name,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
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
          const SizedBox(width: 4),
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

/// SQL code editor with Postgres highlighting. Also used read-only for DDL.
class SqlEditor extends StatelessWidget {
  const SqlEditor({super.key, required this.controller, this.readOnly = false});

  final CodeLineEditingController controller;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codeTheme =
        theme.extension<SqlCodeTheme>()?.styles ??
        (theme.brightness == Brightness.dark
            ? atomOneDarkTheme
            : atomOneLightTheme);
    return CodeEditor(
      controller: controller,
      autofocus: !readOnly,
      readOnly: readOnly,
      showCursorWhenReadOnly: false,
      wordWrap: false,
      shortcutsActivatorsBuilder: const _SqlEditorShortcuts(),
      style: CodeEditorStyle(
        fontSize: 14,
        fontFamily: monoFontFamily,
        fontFamilyFallback: monoFontFallback,
        backgroundColor: theme.colorScheme.surface,
        codeTheme: CodeHighlightTheme(
          languages: {'pgsql': CodeHighlightThemeMode(mode: langPgsql)},
          theme: codeTheme,
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
