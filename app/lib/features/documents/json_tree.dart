import 'package:flutter/material.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId, Timestamp;
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../drivers/mongodb/mongo_json.dart';

/// A document as an expandable field tree, like MongoDB Compass: scalars
/// inline and colored by type, objects and arrays collapsed to a summary.
class JsonTree extends StatefulWidget {
  const JsonTree({super.key, required this.document});

  final Map<String, dynamic> document;

  @override
  State<JsonTree> createState() => _JsonTreeState();
}

class _JsonTreeState extends State<JsonTree> {
  /// Children of an expanded object/array shown at first, and per "more".
  static const _chunk = 100;

  /// Paths of expanded objects/arrays, e.g. `address` or `items.0`.
  final _expanded = <String>{};

  /// Children shown per expanded path, when more than [_chunk].
  final _shown = <String, int>{};

  /// The rows, rebuilt only when the document or expansion changes.
  List<Widget>? _rows;

  void _toggle(String path) => setState(() {
    _expanded.contains(path) ? _expanded.remove(path) : _expanded.add(path);
    _rows = null;
  });

  void _showMore(String path) => setState(() {
    _shown[path] = (_shown[path] ?? _chunk) + _chunk;
    _rows = null;
  });

  @override
  void didUpdateWidget(JsonTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.document, widget.document)) _rows = null;
  }

  List<Widget> _buildRows() {
    final rows = <Widget>[];
    void add(String key, Object? value, String path, int depth) {
      final (children, count) = switch (value) {
        Map() => (
          value.entries.map((e) => (e.key.toString(), e.value)),
          value.length,
        ),
        List() => (
          value.indexed.map((e) => (e.$1.toString(), e.$2)),
          value.length,
        ),
        _ => (null, 0),
      };
      final open = _expanded.contains(path);
      rows.add(
        _FieldRow(
          name: key,
          value: value,
          depth: depth,
          expanded: children == null ? null : open,
          onToggle: () => _toggle(path),
        ),
      );
      if (children != null && open) {
        final shown = _shown[path] ?? _chunk;
        for (final (childKey, childValue) in children.take(shown)) {
          add(childKey, childValue, '$path.$childKey', depth + 1);
        }
        if (count > shown) {
          final remaining = count - shown;
          rows.add(
            Padding(
              padding: EdgeInsets.only(left: (depth + 1) * 16.0),
              child: TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                onPressed: () => _showMore(path),
                child: Text(
                  'Show ${remaining < _chunk ? remaining : _chunk} more '
                  '($remaining remaining)',
                ),
              ),
            ),
          );
        }
      }
    }

    for (final MapEntry(:key, :value) in widget.document.entries) {
      add(key, value, key, 0);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _rows ??= _buildRows(),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.name,
    required this.value,
    required this.depth,
    required this.expanded,
    required this.onToggle,
  });

  final String name;
  final Object? value;
  final int depth;

  /// Null for scalars.
  final bool? expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final code = theme.extension<SqlCodeTheme>()?.styles ?? const {};
    Color? token(String name) => code[name]?.color;

    const numberTypes = {'Int32', 'Int64', 'Double', 'Decimal128'};
    final (text, color) = switch (value) {
      null => ('null', token('literal')),
      bool() => ('$value', token('literal')),
      _ when numberTypes.contains(mongoTypeName(value)) => (
        formatMongoInline(value),
        token('number'),
      ),
      String() => ('"$value"', token('string')),
      ObjectId() || UuidValue() => (formatMongoInline(value), token('type')),
      DateTime() ||
      Timestamp() => (formatMongoInline(value), token('built_in')),
      Map(:final length) => (
        'Object ($length ${length == 1 ? 'field' : 'fields'})',
        null,
      ),
      List(:final length) => ('Array ($length)', null),
      _ => (formatMongoInline(value), token('symbol')),
    };

    return InkWell(
      onTap: expanded == null ? null : onToggle,
      child: Padding(
        padding: EdgeInsets.only(left: depth * 16.0, top: 2, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 16,
              child: expanded == null
                  ? null
                  : Icon(
                      expanded! ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
            ),
            Text(
              '$name: ',
              style: monoStyle.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            Flexible(
              child: Tooltip(
                message: mongoTypeName(value),
                waitDuration: const Duration(milliseconds: 600),
                child: Text(
                  text,
                  maxLines: expanded == null ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle.copyWith(
                    fontSize: 12.5,
                    color: color ?? scheme.onSurfaceVariant,
                    fontStyle: expanded == null ? null : FontStyle.italic,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
