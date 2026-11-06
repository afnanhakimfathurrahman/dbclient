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
    final scheme = theme.colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.history_rounded,
              size: 18,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          const Text('Query History'),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 720,
        height: 480,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: 'Search queries...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              onChanged: (v) => setState(() {
                _filter = v.trim();
                _entries = _watch();
              }),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: StreamBuilder<List<HistoryEntry>>(
                stream: _entries,
                builder: (context, snapshot) {
                  final entries = snapshot.data;
                  if (entries == null) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (entries.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_toggle_off_rounded, size: 36, color: scheme.outline),
                          const SizedBox(height: 8),
                          Text('No queries found', style: TextStyle(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      final isSuccess = e.error == null;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        onTap: () => Navigator.of(context).pop(e.sql),
                        leading: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isSuccess
                                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                : scheme.error.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isSuccess
                                ? Icons.check_rounded
                                : Icons.close_rounded,
                            color: isSuccess
                                ? const Color(0xFF10B981)
                                : scheme.error,
                            size: 14,
                          ),
                        ),
                        title: Text(
                          e.sql,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: monoStyle.copyWith(fontSize: 12),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Text(
                                _formatTime(e.executedAt),
                                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                              ),
                              const SizedBox(width: 8),
                              Text('·', style: TextStyle(color: scheme.outlineVariant)),
                              const SizedBox(width: 8),
                              Text(
                                '${e.duration.inMilliseconds} ms',
                                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                              ),
                              if (e.rowCount != null) ...[
                                const SizedBox(width: 8),
                                Text('·', style: TextStyle(color: scheme.outlineVariant)),
                                const SizedBox(width: 8),
                                Text(
                                  '${e.rowCount} rows',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.onSurface),
                                ),
                              ],
                              if (e.error != null) ...[
                                const SizedBox(width: 8),
                                Text('·', style: TextStyle(color: scheme.outlineVariant)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    e.error!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11, color: scheme.error),
                                  ),
                                ),
                              ],
                            ],
                          ),
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
