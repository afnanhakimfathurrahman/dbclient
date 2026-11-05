import 'package:flutter/material.dart';

import '../editor/workspace.dart';
import '../navigator/navigator_pane.dart';

/// App shell: navigator beside the workspace on wide screens, navigator in a
/// drawer on narrow ones (phones, small windows).
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _wideBreakpoint = 800.0;
  double _navigatorWidth = 300;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _wideBreakpoint) {
          return Scaffold(
            appBar: AppBar(title: const Text('DB Client')),
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

        final maxNavigator = constraints.maxWidth * 0.5;
        final width = _navigatorWidth.clamp(200.0, maxNavigator);
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                SizedBox(width: width, child: const NavigatorPane()),
                MouseRegion(
                  cursor: SystemMouseCursors.resizeColumn,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragUpdate: (d) => setState(
                      () => _navigatorWidth = (width + d.delta.dx).clamp(
                        200.0,
                        maxNavigator,
                      ),
                    ),
                    child: const SizedBox(
                      width: 5,
                      child: VerticalDivider(width: 5),
                    ),
                  ),
                ),
                const Expanded(child: Workspace()),
              ],
            ),
          ),
        );
      },
    );
  }
}
