import 'package:flutter/material.dart';

import '../../state/workspace_tabs.dart';

/// Spinner with a Cancel button, for a tab whose operation has nothing to
/// show yet.
class RunningIndicator extends StatelessWidget {
  const RunningIndicator({super.key, required this.tab, this.label = 'Loading…'});

  final WorkspaceTab tab;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(
          dimension: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Text(tab.cancelling ? 'Cancelling…' : label),
        const SizedBox(width: 12),
        TextButton.icon(
          icon: const Icon(Icons.stop_rounded, size: 16),
          label: const Text('Cancel'),
          onPressed: tab.cancelling ? null : tab.cancel,
        ),
      ],
    );
  }
}

/// Progress bar with a Cancel button, above content that stays visible
/// while it reloads.
class RunningBar extends StatelessWidget {
  const RunningBar({super.key, required this.tab});

  final WorkspaceTab tab;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          const Expanded(child: LinearProgressIndicator(minHeight: 2)),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: const TextStyle(fontSize: 11),
            ),
            icon: const Icon(Icons.stop_rounded, size: 14),
            label: Text(tab.cancelling ? 'Cancelling…' : 'Cancel'),
            onPressed: tab.cancelling ? null : tab.cancel,
          ),
        ],
      ),
    );
  }
}
