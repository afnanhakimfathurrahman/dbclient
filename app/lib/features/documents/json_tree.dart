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
  /// Paths of expanded objects/arrays, e.g. `address` or `items.0`.
  final _expanded = <String>{};

  void _toggle(String path) => setState(
    () =>
        _expanded.contains(path) ? _expanded.remove(path) : _expanded.add(path),
  );

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    void add(String key, Object? value, String path, int depth) {
      final children = switch (value) {
        Map() => value.entries.map((e) => (e.key.toString(), e.value)),
        List() => value.indexed.map((e) => (e.$1.toString(), e.$2)),
        _ => null,
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
        for (final (childKey, childValue) in children) {
          add(childKey, childValue, '$path.$childKey', depth + 1);
        }
      }
    }

    for (final MapEntry(:key, :value) in widget.document.entries) {
      add(key, value, key, 0);
    }
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
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
