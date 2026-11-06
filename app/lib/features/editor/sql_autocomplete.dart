import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';

import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../drivers/sql_dialect.dart';
import '../../state/providers.dart';
import 'sql_completion.dart';

/// Metadata for completion from the same cached providers the navigator
/// uses. A lookup that isn't loaded yet starts loading and returns null, so
/// its names show up on a later keystroke.
class ProviderSqlCatalog implements SqlCatalog {
  ProviderSqlCatalog(this._ref, this._connectionId);

  final WidgetRef _ref;
  final String _connectionId;

  ConnectionConfig? get _config =>
      (_ref.read(connectionsProvider).value ?? const <ConnectionConfig>[])
          .where((c) => c.id == _connectionId)
          .firstOrNull;

  @override
  String? get defaultSchema {
    final config = _config;
    if (config == null) return null;
    return switch (config.engine) {
      DatabaseEngine.postgres => 'public',
      _ => config.database.isEmpty ? null : config.database,
    };
  }

  @override
  List<String>? schemas() => _ref.read(schemasProvider(_connectionId)).value;

  @override
  List<DbObject>? objects(String schema) {
    // Same for half-typed schema names. The default schema is always
    // asked for, as the schema list may not have loaded yet.
    if (schema != defaultSchema && !(schemas()?.contains(schema) ?? false)) {
      return null;
    }
    return _ref.read(objectsProvider((_connectionId, schema))).value;
  }

  /// Loads columns only for tables the schema has, so half-typed names
  /// ("u", "us", "use"…) don't each start a query and a cache entry.
  @override
  List<ColumnInfo>? columns(String schema, String table) {
    final known = objects(schema)?.any((o) => o.name == table) ?? false;
    if (!known) return null;
    return _ref.read(columnsProvider((_connectionId, schema, table))).value;
  }
}

class _SqlPrompt extends CodePrompt {
  _SqlPrompt(this.suggestion) : super(word: suggestion.label);

  final SqlSuggestion suggestion;

  @override
  CodeAutocompleteResult get autocomplete =>
      CodeAutocompleteResult.fromWord(suggestion.insert);

  /// Already filtered by [completeSql].
  @override
  bool match(String input) => true;
}

/// Runs [completeSql] over the whole editor text, not just the current line,
/// so tables in a FROM clause on another line are known.
class SqlPromptsBuilder implements CodeAutocompletePromptsBuilder {
  SqlPromptsBuilder({
    required this.controller,
    required this.catalog,
    required this.dialect,
  });

  final CodeLineEditingController controller;
  final SqlCatalog Function() catalog;
  final SqlDialect Function() dialect;

  @override
  CodeAutocompleteEditingValue? build(
    BuildContext context,
    CodeLine codeLine,
    CodeLineSelection selection,
  ) {
    final lines = controller.codeLines;
    final text = StringBuffer();
    var cursor = 0;
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) text.write('\n');
      if (i == selection.extentIndex) {
        cursor = text.length + selection.extentOffset;
      }
      text.write(lines[i].text);
    }
    final completion = completeSql(
      text: text.toString(),
      cursor: cursor,
      catalog: catalog(),
      dialect: dialect(),
    );
    if (completion == null) return null;
    return CodeAutocompleteEditingValue(
      input: completion.input,
      prompts: [for (final s in completion.suggestions) _SqlPrompt(s)],
      index: 0,
    );
  }
}

/// The suggestion popup: icon, name and detail per row; follows the
/// keyboard selection (Up/Down, Enter) and accepts clicks.
class SqlCompletionList extends StatefulWidget implements PreferredSizeWidget {
  const SqlCompletionList({
    super.key,
    required this.notifier,
    required this.onSelected,
  });

  static const _rowHeight = 26.0;
  static const _maxRows = 10;
  static const _width = 380.0;

  final ValueNotifier<CodeAutocompleteEditingValue> notifier;
  final ValueChanged<CodeAutocompleteResult> onSelected;

  @override
  Size get preferredSize => Size(
    _width,
    // +2 for the border.
    (notifier.value.prompts.length.clamp(1, _maxRows)) * _rowHeight + 2,
  );

  @override
  State<SqlCompletionList> createState() => _SqlCompletionListState();
}

class _SqlCompletionListState extends State<SqlCompletionList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_follow);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the selected row visible while moving with the arrow keys.
  void _follow() {
    if (!_scroll.hasClients) return;
    const row = SqlCompletionList._rowHeight;
    final top = widget.notifier.value.index * row;
    final view = _scroll.position.viewportDimension;
    if (top < _scroll.offset) {
      _scroll.jumpTo(top);
    } else if (top + row > _scroll.offset + view) {
      _scroll.jumpTo(top + row - view);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: widget.preferredSize.width,
      height: widget.preferredSize.height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: scheme.outline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: ValueListenableBuilder(
        valueListenable: widget.notifier,
        builder: (context, value, _) => ListView.builder(
          controller: _scroll,
          itemExtent: SqlCompletionList._rowHeight,
          itemCount: value.prompts.length,
          itemBuilder: (context, i) {
            final suggestion = (value.prompts[i] as _SqlPrompt).suggestion;
            final selected = i == value.index;
            return InkWell(
              onTap: () =>
                  widget.onSelected(value.copyWith(index: i).autocomplete),
              child: Container(
                color: selected ? scheme.primary.withValues(alpha: 0.18) : null,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    Icon(
                      _icon(suggestion.kind),
                      size: 14,
                      color: _color(suggestion.kind, scheme),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        suggestion.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: monoStyle.copyWith(
                          fontSize: 12.5,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                    if (suggestion.detail case final detail?) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static IconData _icon(SqlSuggestionKind kind) => switch (kind) {
    SqlSuggestionKind.column => Icons.view_column_outlined,
    SqlSuggestionKind.table => Icons.table_chart_outlined,
    SqlSuggestionKind.view => Icons.visibility_outlined,
    SqlSuggestionKind.schema => Icons.account_tree_outlined,
    SqlSuggestionKind.keyword => Icons.text_fields_rounded,
    SqlSuggestionKind.function => Icons.functions_rounded,
  };

  static Color _color(SqlSuggestionKind kind, ColorScheme scheme) =>
      switch (kind) {
        SqlSuggestionKind.column => const Color(0xFF0EA5E9),
        SqlSuggestionKind.table => const Color(0xFF10B981),
        SqlSuggestionKind.view => const Color(0xFFA855F7),
        SqlSuggestionKind.schema => const Color(0xFFF59E0B),
        SqlSuggestionKind.keyword => scheme.primary,
        SqlSuggestionKind.function => const Color(0xFFEC4899),
      };
}
