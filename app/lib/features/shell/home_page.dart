import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../state/workspace_tabs.dart';
import '../connections/connection_dialog.dart';
import '../editor/workspace.dart';
import '../navigator/navigator_pane.dart';

/// App shell: unified top bar, resizable navigator pane, and workspace.
/// Adapts gracefully to desktop, tablet, and mobile form factors.
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  static const _wideBreakpoint = 800.0;
  double _navigatorWidth = 280;
  bool _isDraggingSplitter = false;

  Future<void> _handleNewQuery() => openNewSqlEditor(context, ref);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    // Ctrl/Cmd+N anywhere in the window, including inside the SQL editor.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyN, control: true):
            _handleNewQuery,
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true):
            _handleNewQuery,
      },
      child: Focus(autofocus: true, child: _buildLayout(theme, scheme)),
    );
  }

  Widget _buildLayout(ThemeData theme, ColorScheme scheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _wideBreakpoint) {
          return Scaffold(
            appBar: AppBar(
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(Icons.dns_rounded, size: 18, color: scheme.primary),
                  ),
                  const SizedBox(width: 8),
                  const Text('DB Client'),
                ],
              ),
              actions: [
                IconButton(
                  tooltip: 'New SQL editor',
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  onPressed: _handleNewQuery,
                ),
                IconButton(
                  tooltip: 'Toggle theme',
                  icon: Icon(
                    theme.brightness == Brightness.dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                  ),
                  onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
                ),
                const SizedBox(width: 4),
              ],
            ),
            drawer: Drawer(
              width: constraints.maxWidth * 0.85,
              child: SafeArea(
                child: NavigatorPane(
                  onEditorOpened: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
            body: const SafeArea(child: Workspace()),
          );
        }

        final maxNavigator = (constraints.maxWidth * 0.45).clamp(240.0, 500.0);
        final width = _navigatorWidth.clamp(220.0, maxNavigator);

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                _DesktopTopBar(onNewQuery: _handleNewQuery),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(width: width, child: const NavigatorPane()),
                      _Splitter(
                        isDragging: _isDraggingSplitter,
                        onDragStart: () => setState(() => _isDraggingSplitter = true),
                        onDragEnd: () => setState(() => _isDraggingSplitter = false),
                        onDragUpdate: (delta) {
                          setState(() {
                            _navigatorWidth = (width + delta).clamp(
                              220.0,
                              maxNavigator,
                            );
                          });
                        },
                      ),
                      const Expanded(child: Workspace()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DesktopTopBar extends ConsumerWidget {
  const _DesktopTopBar({required this.onNewQuery});

  final VoidCallback onNewQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final connections = ref.watch(connectionsProvider).value ?? const [];
    final activeTab = ref.watch(workspaceTabsProvider).active;
    final activeConfig = connections
        .where((c) => c.id == activeTab?.connectionId)
        .firstOrNull;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
      ),
      child: Row(
        children: [
          // Brand Logo & Title
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primary,
                  scheme.primary.withValues(alpha: 0.8),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: const Icon(
              Icons.dns_rounded,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'DB Client',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: -0.3,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              'v0.1.0',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),

          const SizedBox(width: 16),
          SizedBox(
            height: 18,
            child: VerticalDivider(color: scheme.outlineVariant),
          ),
          const SizedBox(width: 16),

          // Active Connection Badge
          if (activeConfig != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Color(activeConfig.color).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Color(activeConfig.color).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: Color(activeConfig.color),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    activeConfig.name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(activeConfig.color),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '(${activeConfig.database})',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              'No connection selected',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],

          const Spacer(),

          // Quick Action CTAs
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: const Icon(Icons.add, size: 15),
            label: const Text('New Query', style: TextStyle(fontSize: 12)),
            onPressed: onNewQuery,
          ),
          const SizedBox(width: 6),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: const Icon(Icons.cable_rounded, size: 15),
            label: const Text('Connection', style: TextStyle(fontSize: 12)),
            onPressed: () => showConnectionDialog(context),
          ),
          const SizedBox(width: 10),

          // Theme Switcher Toggle
          IconButton(
            tooltip: isDark ? 'Switch to Light Theme' : 'Switch to Dark Theme',
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 18,
            ),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
        ],
      ),
    );
  }
}

/// An ergonomic vertical splitter with generous hit zone and visual hover/drag feedback.
class _Splitter extends StatefulWidget {
  const _Splitter({
    required this.isDragging,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onDragUpdate,
  });

  final bool isDragging;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final ValueChanged<double> onDragUpdate;

  @override
  State<_Splitter> createState() => _SplitterState();
}

class _SplitterState extends State<_Splitter> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = _isHovered || widget.isDragging;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => widget.onDragStart(),
        onHorizontalDragEnd: (_) => widget.onDragEnd(),
        onHorizontalDragCancel: () => widget.onDragEnd(),
        onHorizontalDragUpdate: (d) => widget.onDragUpdate(d.delta.dx),
        child: SizedBox(
          width: 9,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: highlighted ? 2 : 1,
                color: highlighted ? scheme.primary : scheme.outlineVariant,
              ),
              if (highlighted)
                Container(
                  width: 5,
                  height: 32,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
