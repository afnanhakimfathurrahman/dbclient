import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/repositories.dart';
import '../../state/providers.dart';

/// Query history for a connection. Returns the SQL the user picked to
/// re-open, or null.
Future<String?> showHistoryDialog(
  BuildContext context, {
  required String connectionId,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _HistoryDialog(connectionId: connectionId),
  );
}

class _HistoryDialog extends ConsumerStatefulWidget {
  const _HistoryDialog({required this.connectionId});

  final String connectionId;

  @override
  ConsumerState<_HistoryDialog> createState() => _HistoryDialogState();
}

class _HistoryDialogState extends ConsumerState<_HistoryDialog> {
  String _filter = '';
  late Stream<List<HistoryEntry>> _entries = _watch();

  Stream<List<HistoryEntry>> _watch() => ref
      .read(historyRepositoryProvider)
      .watch(widget.connectionId, filter: _filter);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Query history'),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 720,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Search',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() {
                _filter = v.trim();
                _entries = _watch();
              }),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<HistoryEntry>>(
                stream: _entries,
                builder: (context, snapshot) {
                  final entries = snapshot.data;
                  if (entries == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (entries.isEmpty) {
                    return const Center(child: Text('No queries yet.'));
                  }
                  return ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(),
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      return ListTile(
                        dense: true,
                        onTap: () => Navigator.of(context).pop(e.sql),
                        leading: Icon(
                          e.error == null
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          color: e.error == null
                              ? Colors.green.shade600
                              : theme.colorScheme.error,
                          size: 18,
                        ),
                        title: Text(
                          e.sql,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: monoStyle,
                        ),
                        subtitle: Text(
                          [
                            _formatTime(e.executedAt),
                            '${e.duration.inMilliseconds} ms',
                            if (e.rowCount != null) '${e.rowCount} rows',
                            if (e.error != null) e.error!,
                          ].join('  ·  '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await ref
                .read(historyRepositoryProvider)
                .clear(widget.connectionId);
          },
          child: const Text('Clear history'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  String _formatTime(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }
}
