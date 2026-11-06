import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../drivers/key_value.dart';
import '../../drivers/redis/redis_driver.dart';
import '../../drivers/redis/resp.dart';
import '../../state/providers.dart';
import '../../state/workspace_tabs.dart';
import '../connections/connection_dialog.dart';

/// Accent per Redis type, for the key list badges.
Color redisTypeColor(String type) => switch (type) {
  'string' => const Color(0xFF3B82F6),
  'hash' => const Color(0xFF8B5CF6),
  'list' => const Color(0xFF10B981),
  'set' => const Color(0xFFF59E0B),
  'zset' => const Color(0xFFEC4899),
  'stream' => const Color(0xFF06B6D4),
  _ => const Color(0xFF64748B),
};

/// Characters of a value shown in one text widget; laying out much more is
/// slow.
const _maxDisplayChars = 100000;

final _displayCache = Expando<(String, bool)>();

/// [data]'s text as shown, JSON pretty-printed, and whether it was cut at
/// [_maxDisplayChars]. Computed once per loaded value.
(String, bool) _displayText(KeyData data) => _displayCache[data] ??=
    redisDisplayText(data.text ?? '', tryJson: !data.textTruncated);

/// [text] pretty-printed if it is JSON, cut at [maxChars]; with whether it
/// was cut.
@visibleForTesting
(String, bool) redisDisplayText(
  String text, {
  bool tryJson = true,
  int maxChars = _maxDisplayChars,
}) {
  var display = text;
  final start = text.trimLeft();
  if (tryJson && (start.startsWith('{') || start.startsWith('['))) {
    try {
      display = const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
    } on FormatException {
      // Not JSON after all: shown as is.
    }
  }
  return display.length > maxChars
      ? (display.substring(0, maxChars), true)
      : (display, false);
}

/// Console replies formatted once each, capped at [_maxReplyChars].
final _replyCache = Expando<String>();
const _maxReplyChars = 100000;

String _formatReply(Object? reply) => switch (reply) {
  // Expando can't key these; they format cheaply anyway.
  null ||
  int() ||
  String() => formatRedisReply(reply, maxChars: _maxReplyChars),
  _ => _replyCache[reply] ??= formatRedisReply(reply, maxChars: _maxReplyChars),
};

String formatTtl(int ttl) {
  if (ttl < 0) return 'no expiry';
  if (ttl < 60) return '${ttl}s';
  if (ttl < 3600) return '${ttl ~/ 60}m ${ttl % 60}s';
  if (ttl < 86400) return '${ttl ~/ 3600}h ${ttl % 3600 ~/ 60}m';
  return '${ttl ~/ 86400}d ${ttl % 86400 ~/ 3600}h';
}

/// A Redis database: key browser with a value pane, or a console.
class RedisView extends ConsumerStatefulWidget {
  const RedisView({super.key, required this.tab});

  final RedisTab tab;

  @override
  ConsumerState<RedisView> createState() => _RedisViewState();
}

class _RedisViewState extends ConsumerState<RedisView> {
  RedisTab get tab => widget.tab;

  @override
  void initState() {
    super.initState();
    if (!tab.scanned) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scan();
      });
    }
  }

  Future<KeyValueDriver?> _driver() async {
    final config = (ref.read(connectionsProvider).value ?? const [])
        .where((c) => c.id == tab.connectionId)
        .firstOrNull;
    if (config == null) return null;
    final driver = await connectWithPrompt(context, ref, config);
    return driver is KeyValueDriver ? driver : null;
  }

  Future<void> _scan({bool more = false}) async {
    final driver = await _driver();
    if (driver != null) await tab.scan(driver, more: more);
  }

  Future<void> _open(String key) async {
    final driver = await _driver();
    if (driver != null) await tab.open(driver, key);
  }

  void _snack(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  /// Runs a write command, reports errors, and reloads the open value.
  Future<bool> _write(List<String> args, {bool reload = true}) async {
    final driver = await _driver();
    if (driver == null) return false;
    try {
      await driver.run(tab.db, args);
    } on DriverException catch (e) {
      _snack(e.message);
      return false;
    }
    if (reload) await tab.reloadValue(driver);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tab,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          const Divider(height: 1),
          Expanded(
            child: tab.consoleMode
                ? _RedisConsole(tab: tab, driver: _driver)
                : _browser(),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          const Icon(Icons.bolt_rounded, size: 18, color: Color(0xFFEF4444)),
          const SizedBox(width: 8),
          Text(
            'Database ${tab.db}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: const [
              ButtonSegment(
                value: false,
                icon: Icon(Icons.key_rounded, size: 15),
                label: Text('Keys'),
              ),
              ButtonSegment(
                value: true,
                icon: Icon(Icons.terminal_rounded, size: 15),
                label: Text('Console'),
              ),
            ],
            selected: {tab.consoleMode},
            onSelectionChanged: (s) =>
                setState(() => tab.consoleMode = s.first),
          ),
        ],
      ),
    );
  }

  Widget _browser() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 720;
        final list = _keyList();
        final value = _valuePane();
        if (narrow) {
          // Phones and narrow windows: list on top, value below.
          return Column(
            children: [
              SizedBox(height: constraints.maxHeight * 0.42, child: list),
              const Divider(height: 1),
              Expanded(child: value),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: 340, child: list),
            const VerticalDivider(width: 1),
            Expanded(child: value),
          ],
        );
      },
    );
  }

  Widget _keyList() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: tab.pattern,
                  style: monoStyle.copyWith(fontSize: 12.5),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 16),
                    hintText: 'Pattern, e.g. user:*',
                  ),
                  onSubmitted: (_) => _scan(),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Scan',
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: tab.scanning ? null : _scan,
              ),
              IconButton(
                tooltip: 'New key',
                icon: const Icon(Icons.add_rounded, size: 18),
                onPressed: _newKey,
              ),
            ],
          ),
        ),
        if (tab.scanning) const LinearProgressIndicator(minHeight: 2),
        if (tab.scanError case final error?)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('$error', style: TextStyle(color: scheme.error)),
          ),
        Expanded(
          child: tab.keys.isEmpty && tab.scanned
              ? Center(
                  child: Text(
                    'No keys match',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: tab.keys.length + (tab.scanComplete ? 0 : 1),
                  itemBuilder: (context, i) {
                    if (i == tab.keys.length) {
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: OutlinedButton(
                          onPressed: tab.scanning
                              ? null
                              : () => _scan(more: true),
                          child: const Text('Load more'),
                        ),
                      );
                    }
                    final key = tab.keys[i];
                    return _KeyRow(
                      info: key,
                      selected: key.name == tab.selectedKey,
                      onTap: () => _open(key.name),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: scheme.surfaceContainerLow,
          child: Text(
            '${tab.keys.length} keys${tab.scanComplete ? '' : ' (more available)'}',
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _valuePane() {
    final scheme = Theme.of(context).colorScheme;
    final key = tab.selectedKey;
    if (key == null) {
      return Center(
        child: Text(
          'Select a key to see its value',
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      );
    }
    if (tab.valueError case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('$error', style: TextStyle(color: scheme.error)),
        ),
      );
    }
    final data = tab.value;
    if (data == null) return const Center(child: CircularProgressIndicator());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _valueHeader(data),
        if (tab.reading) const LinearProgressIndicator(minHeight: 2),
        const Divider(height: 1),
        Expanded(child: _valueBody(data)),
      ],
    );
  }

  Widget _valueHeader(KeyData data) {
    final scheme = Theme.of(context).colorScheme;
    final facts = [
      formatTtl(data.ttl),
      if (data.type == 'string')
        '${data.length} bytes'
      else
        '${data.length} items',
      if (data.memoryBytes case final bytes?) '$bytes B in memory',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _TypeBadge(data.type),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SelectableText(
                        data.key,
                        maxLines: 2,
                        style: monoStyle.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  facts.join('  ·  '),
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded, size: 18),
            onPressed: () async {
              final driver = await _driver();
              if (driver != null) await tab.reloadValue(driver);
            },
          ),
          IconButton(
            tooltip: 'Copy key name',
            icon: const Icon(Icons.copy_rounded, size: 17),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: data.key));
              _snack('Key name copied');
            },
          ),
          PopupMenuButton<String>(
            tooltip: 'Key actions',
            onSelected: (action) => switch (action) {
              'ttl' => _editTtl(data),
              'rename' => _rename(data),
              'delete' => _deleteKey(data),
              _ => null,
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'ttl', child: Text('Set TTL…')),
              const PopupMenuItem(value: 'rename', child: Text('Rename…')),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  'Delete key',
                  style: TextStyle(color: scheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _valueBody(KeyData data) {
    final scheme = Theme.of(context).colorScheme;
    final key = data.key;
    final truncatedNote = data.truncated
        ? 'Showing ${data.shown} of ${data.length}'
        : null;

    switch (data.type) {
      case 'ReJSON-RL' when data.text == null && data.textTruncated:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'This JSON document is too large to show here. Read parts of '
              'it in the console, e.g. JSON.GET $key \$.path',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        );
      case 'string' || 'ReJSON-RL':
        final text = data.text ?? '';
        final (display, cut) = _displayText(data);
        final note = [
          if (data.textTruncated)
            'Showing the first ${RedisDriver.stringPreviewBytes ~/ 1024} KB '
                'of ${data.length} bytes, read-only',
          if (cut) 'Showing the first $_maxDisplayChars characters',
        ].join(' · ');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(14),
                child: SelectableText(
                  display,
                  style: monoStyle.copyWith(fontSize: 12.5, height: 1.4),
                ),
              ),
            ),
            if (data.type == 'string' || note.isNotEmpty)
              _ActionBar(
                children: [
                  if (data.type == 'string')
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Edit value'),
                      // Saving a partial value would cut it short.
                      onPressed: data.textTruncated
                          ? null
                          : () async {
                              final values = await _prompt('Edit $key', [
                                ('Value', text),
                              ], multiline: true);
                              // KEEPTTL keeps the expiry (Redis 6+).
                              if (values != null) {
                                await _write([
                                  'SET',
                                  key,
                                  values[0],
                                  'KEEPTTL',
                                ]);
                              }
                            },
                    ),
                  if (note.isNotEmpty)
                    Text(
                      note,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
          ],
        );
      case 'hash':
        return _MemberTable(
          headers: const ['Field', 'Value'],
          rows: [
            for (final (f, v) in data.pairs) [f, v],
          ],
          note: truncatedNote,
          addLabel: 'Add field',
          onAdd: () async {
            final v = await _prompt('Add field', [
              ('Field', ''),
              ('Value', ''),
            ]);
            if (v != null) await _write(['HSET', key, v[0], v[1]]);
          },
          onEdit: (row) async {
            final v = await _prompt('Edit ${row[0]}', [
              ('Value', row[1]),
            ], multiline: true);
            if (v != null) await _write(['HSET', key, row[0], v[0]]);
          },
          onDelete: (row) => _write(['HDEL', key, row[0]]),
        );
      case 'list':
        return _MemberTable(
          headers: const ['Index', 'Value'],
          rows: [
            for (final (i, v) in data.items.indexed) ['$i', v],
          ],
          note: truncatedNote,
          addLabel: 'Append',
          onAdd: () async {
            final v = await _prompt('Append to $key', [('Value', '')]);
            if (v != null) await _write(['RPUSH', key, v[0]]);
          },
          onEdit: (row) async {
            final v = await _prompt('Edit index ${row[0]}', [
              ('Value', row[1]),
            ], multiline: true);
            if (v != null) await _write(['LSET', key, row[0], v[0]]);
          },
          // Removes by position: mark the element, then remove the mark,
          // so duplicates elsewhere in the list are untouched.
          onDelete: (row) async {
            const marker = '__db_client_deleted__';
            if (await _write(['LSET', key, row[0], marker], reload: false)) {
              await _write(['LREM', key, '1', marker]);
            }
          },
        );
      case 'set':
        return _MemberTable(
          headers: const ['Member'],
          rows: [
            for (final m in data.items) [m],
          ],
          note: truncatedNote,
          addLabel: 'Add member',
          onAdd: () async {
            final v = await _prompt('Add to $key', [('Member', '')]);
            if (v != null) await _write(['SADD', key, v[0]]);
          },
          onDelete: (row) => _write(['SREM', key, row[0]]),
        );
      case 'zset':
        return _MemberTable(
          headers: const ['Member', 'Score'],
          rows: [
            for (final (m, s) in data.pairs) [m, s],
          ],
          note: truncatedNote,
          addLabel: 'Add member',
          onAdd: () async {
            final v = await _prompt('Add to $key', [
              ('Member', ''),
              ('Score', '0'),
            ]);
            if (v != null) await _write(['ZADD', key, v[1], v[0]]);
          },
          onEdit: (row) async {
            final v = await _prompt('Score of ${row[0]}', [('Score', row[1])]);
            if (v != null) await _write(['ZADD', key, v[0], row[0]]);
          },
          onDelete: (row) => _write(['ZREM', key, row[0]]),
        );
      case 'stream':
        return _MemberTable(
          headers: const ['ID', 'Fields'],
          rows: [
            for (final (id, fields) in data.entries)
              [
                id,
                [
                  for (var i = 0; i + 1 < fields.length; i += 2)
                    '${fields[i]}=${fields[i + 1]}',
                ].join('  '),
              ],
          ],
          note: truncatedNote == null
              ? 'Newest first'
              : '$truncatedNote, newest first',
          onDelete: (row) => _write(['XDEL', key, row[0]]),
        );
      default:
        return Center(
          child: Text(
            'Viewing "${data.type}" values isn\'t supported yet; '
            'use the console.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        );
    }
  }

  /// A small form dialog; returns the entered values, or null if cancelled.
  Future<List<String>?> _prompt(
    String title,
    List<(String label, String initial)> fields, {
    bool multiline = false,
  }) {
    return showDialog<List<String>>(
      context: context,
      builder: (_) =>
          _PromptDialog(title: title, fields: fields, multiline: multiline),
    );
  }

  Future<void> _editTtl(KeyData data) async {
    final values = await _prompt('Time to live for ${data.key}', [
      ('Seconds (empty for no expiry)', data.ttl < 0 ? '' : '${data.ttl}'),
    ]);
    if (values == null) return;
    final seconds = int.tryParse(values[0].trim());
    if (values[0].trim().isEmpty || seconds == null || seconds < 0) {
      await _write(['PERSIST', data.key]);
    } else {
      await _write(['EXPIRE', data.key, '$seconds']);
    }
  }

  Future<void> _rename(KeyData data) async {
    final values = await _prompt('Rename ${data.key}', [
      ('New name', data.key),
    ]);
    if (values == null || values[0] == data.key) return;
    final driver = await _driver();
    if (driver == null) return;
    try {
      // RENAMENX refuses to overwrite an existing key.
      final renamed = await driver.run(tab.db, [
        'RENAMENX',
        data.key,
        values[0],
      ]);
      if (renamed == 0) {
        _snack('A key named "${values[0]}" already exists');
        return;
      }
    } on DriverException catch (e) {
      _snack(e.message);
      return;
    }
    tab.forgetKey(data.key);
    await tab.scan(driver);
    await tab.open(driver, values[0]);
  }

  Future<void> _deleteKey(KeyData data) async {
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete key?'),
        content: Text(
          '"${data.key}" (${data.type}, ${data.length} '
          '${data.type == 'string' ? 'bytes' : 'items'}) will be deleted now.',
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
    if (await _write(['DEL', data.key], reload: false)) tab.forgetKey(data.key);
  }

  Future<void> _newKey() async {
    final created = await showDialog<(String key, List<List<String>> commands)>(
      context: context,
      builder: (_) => const _NewKeyDialog(),
    );
    if (created == null) return;
    final driver = await _driver();
    if (driver == null) return;
    final (key, commands) = created;
    try {
      if (await driver.run(tab.db, ['EXISTS', key]) == 1) {
        _snack('"$key" already exists');
        return;
      }
      for (final command in commands) {
        await driver.run(tab.db, command);
      }
    } on DriverException catch (e) {
      _snack(e.message);
      return;
    }
    await tab.scan(driver);
    await tab.open(driver, key);
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge(this.type);

  final String type;

  @override
  Widget build(BuildContext context) {
    final color = redisTypeColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        type == 'ReJSON-RL' ? 'JSON' : type.toUpperCase(),
        style: monoBadgeStyle.copyWith(fontSize: 9.5, color: color),
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({
    required this.info,
    required this.selected,
    required this.onTap,
  });

  final KeyInfo info;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.primary.withValues(alpha: 0.12) : null,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              SizedBox(width: 58, child: _TypeBadge(info.type)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  info.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle.copyWith(fontSize: 12.5),
                ),
              ),
              if (info.ttl >= 0) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Expires in ${formatTtl(info.ttl)}',
                  child: Icon(
                    Icons.timer_outlined,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Row(children: children),
    );
  }
}

/// Rows of a collection value with per-row edit and delete.
class _MemberTable extends StatelessWidget {
  const _MemberTable({
    required this.headers,
    required this.rows,
    this.note,
    this.addLabel,
    this.onAdd,
    this.onEdit,
    this.onDelete,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final String? note;
  final String? addLabel;
  final VoidCallback? onAdd;
  final Future<void> Function(List<String> row)? onEdit;
  final Future<void> Function(List<String> row)? onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final header = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      color: scheme.onSurfaceVariant,
    );
    Widget cells(
      List<String> values, {
      TextStyle? style,
      bool header = false,
    }) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, v) in values.indexed)
          Expanded(
            flex: headers.length > 1 && i == 0 ? 2 : 3,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: header
                  ? Text(v, style: style)
                  : SelectableText(v, maxLines: 4, style: style),
            ),
          ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
          color: scheme.surfaceContainerHigh,
          child: Row(
            children: [
              Expanded(child: cells(headers, style: header, header: true)),
              SizedBox(
                width: (onEdit != null ? 36 : 0) + (onDelete != null ? 36 : 0),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    'Empty',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final row = rows[i];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: cells(
                              row,
                              style: monoStyle.copyWith(fontSize: 12.5),
                            ),
                          ),
                          if (onEdit case final edit?)
                            IconButton(
                              tooltip: 'Edit',
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              onPressed: () => edit(row),
                            ),
                          if (onDelete case final delete?)
                            IconButton(
                              tooltip: 'Remove',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                Icons.delete_outline_rounded,
                                size: 16,
                                color: scheme.error,
                              ),
                              onPressed: () => delete(row),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (onAdd != null || note != null)
          _ActionBar(
            children: [
              if (onAdd != null)
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(addLabel ?? 'Add'),
                  onPressed: onAdd,
                ),
              const Spacer(),
              if (note != null)
                Text(
                  note!,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.fields,
    required this.multiline,
  });

  final String title;
  final List<(String, String)> fields;
  final bool multiline;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final _controllers = [
    for (final (_, initial) in widget.fields)
      TextEditingController(text: initial),
  ];

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context).pop([for (final c in _controllers) c.text]);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (i, (label, _)) in widget.fields.indexed) ...[
              if (i > 0) const SizedBox(height: 12),
              TextField(
                controller: _controllers[i],
                autofocus: i == 0,
                style: monoStyle.copyWith(fontSize: 12.5),
                minLines: widget.multiline ? 3 : 1,
                maxLines: widget.multiline ? 12 : 1,
                decoration: InputDecoration(labelText: label),
                onSubmitted: widget.multiline ? null : (_) => _submit(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

/// Creates a key of any type with its first element. Returns the key and
/// the commands to run.
class _NewKeyDialog extends StatefulWidget {
  const _NewKeyDialog();

  @override
  State<_NewKeyDialog> createState() => _NewKeyDialogState();
}

class _NewKeyDialogState extends State<_NewKeyDialog> {
  static const _types = ['string', 'hash', 'list', 'set', 'zset'];

  String _type = 'string';
  final _key = TextEditingController();
  final _first = TextEditingController();
  final _second = TextEditingController();
  final _ttl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    for (final c in [_key, _first, _second, _ttl]) {
      c.dispose();
    }
    super.dispose();
  }

  (String, String?) get _labels => switch (_type) {
    'hash' => ('Field', 'Value'),
    'zset' => ('Member', 'Score'),
    'set' => ('Member', null),
    _ => ('Value', null),
  };

  void _create() {
    final key = _key.text;
    if (key.isEmpty) {
      setState(() => _error = 'Enter a key name');
      return;
    }
    final ttl = _ttl.text.trim();
    if (ttl.isNotEmpty && (int.tryParse(ttl) ?? -1) <= 0) {
      setState(() => _error = 'TTL must be a positive number of seconds');
      return;
    }
    if (_type == 'zset' && double.tryParse(_second.text.trim()) == null) {
      setState(() => _error = 'Score must be a number');
      return;
    }
    final first = _first.text;
    final second = _second.text;
    Navigator.of(context).pop((
      key,
      [
        switch (_type) {
          'hash' => ['HSET', key, first, second],
          'list' => ['RPUSH', key, first],
          'set' => ['SADD', key, first],
          'zset' => ['ZADD', key, second.trim(), first],
          _ => ['SET', key, first],
        },
        if (ttl.isNotEmpty) ['EXPIRE', key, ttl],
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final (firstLabel, secondLabel) = _labels;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('New key'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Text(_error!, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 6,
              children: [
                for (final type in _types)
                  ChoiceChip(
                    label: Text(type),
                    selected: _type == type,
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _key,
              autofocus: true,
              style: monoStyle.copyWith(fontSize: 12.5),
              decoration: const InputDecoration(labelText: 'Key'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _first,
              style: monoStyle.copyWith(fontSize: 12.5),
              minLines: 1,
              maxLines: _type == 'string' ? 8 : 1,
              decoration: InputDecoration(labelText: firstLabel),
            ),
            if (secondLabel != null) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _second,
                style: monoStyle.copyWith(fontSize: 12.5),
                decoration: InputDecoration(labelText: secondLabel),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _ttl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'TTL in seconds (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _create, child: const Text('Create')),
      ],
    );
  }
}

/// redis-cli style console: a log of commands and replies, an input line
/// with history (Up/Down), and Cancel for blocking commands.
class _RedisConsole extends StatefulWidget {
  const _RedisConsole({required this.tab, required this.driver});

  final RedisTab tab;
  final Future<KeyValueDriver?> Function() driver;

  @override
  State<_RedisConsole> createState() => _RedisConsoleState();
}

class _RedisConsoleState extends State<_RedisConsole> {
  /// Commands that wipe or stop the server ask first.
  static const _dangerous = {'FLUSHALL', 'FLUSHDB', 'SHUTDOWN'};

  final _scroll = ScrollController();
  final _focus = FocusNode();
  int? _historyIndex;

  RedisTab get tab => widget.tab;

  @override
  void dispose() {
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final line = tab.consoleInput.text.trim();
    if (line.isEmpty || tab.consoleRunning) return;
    final command = line.split(RegExp(r'\s+')).first.toUpperCase();
    if (_dangerous.contains(command) && !await _confirm(command)) return;
    final driver = await widget.driver();
    if (driver == null) return;
    tab.consoleInput.clear();
    _historyIndex = null;
    await tab.runConsole(driver, line);
    _focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<bool> _confirm(String command) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Run $command?'),
        content: Text(switch (command) {
          'FLUSHALL' => 'Deletes every key in every database on this server.',
          'FLUSHDB' => 'Deletes every key in database ${tab.db}.',
          _ => 'Stops the Redis server.',
        }),
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
            child: Text(command),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _recall(int direction) {
    final history = tab.history;
    if (history.isEmpty) return;
    final next = ((_historyIndex ?? history.length) + direction).clamp(
      0,
      history.length,
    );
    _historyIndex = next;
    final text = next == history.length ? '' : history[next];
    tab.consoleInput.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code =
        Theme.of(context).extension<SqlCodeTheme>()?.styles ?? const {};
    final prompt = 'db${tab.db}>';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            color: scheme.surface,
            child: tab.consoleLog.isEmpty
                ? Center(
                    child: Text(
                      'Type a command, e.g. INFO server or SCAN 0 MATCH user:*',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  )
                : SelectionArea(
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: tab.consoleLog.length,
                      itemBuilder: (context, i) {
                        final (command, reply) = tab.consoleLog[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$prompt $command',
                                style: monoStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: code['keyword']?.color,
                                ),
                              ),
                              Text(
                                _formatReply(reply),
                                style: monoStyle.copyWith(
                                  color: reply is RespError
                                      ? scheme.error
                                      : code['string']?.color,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            children: [
              Text(prompt, style: monoStyle.copyWith(color: scheme.primary)),
              const SizedBox(width: 8),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                        _recall(-1),
                    const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                        _recall(1),
                  },
                  child: TextField(
                    controller: tab.consoleInput,
                    focusNode: _focus,
                    autofocus: true,
                    style: monoStyle,
                    decoration: const InputDecoration.collapsed(
                      hintText: 'Command',
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ),
              if (tab.consoleRunning)
                TextButton.icon(
                  icon: const Icon(Icons.stop_rounded, size: 16),
                  label: const Text('Cancel'),
                  onPressed: tab.cancel,
                )
              else
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.clear_all_rounded, size: 18),
                  onPressed: tab.consoleLog.isEmpty
                      ? null
                      : () => setState(tab.consoleLog.clear),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
