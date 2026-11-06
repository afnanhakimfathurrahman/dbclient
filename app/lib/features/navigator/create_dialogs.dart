import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../drivers/create_sql.dart';
import '../../drivers/sql_dialect.dart';
import '../inspector/dialogs/schema_dialog_scaffold.dart';

/// Asks for one name and runs the statement [buildSql] makes from it
/// (CREATE DATABASE, CREATE SCHEMA). Errors from [onExecute] show inline and
/// keep the dialog open. Returns true once created.
Future<bool?> showCreateNamedDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  required IconData icon,
  required String fieldLabel,
  required String Function(String name) buildSql,
  required Future<void> Function(String sql) onExecute,
  required void Function(String sql) onOpenInSql,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _CreateNamedDialog(
      title: title,
      subtitle: subtitle,
      icon: icon,
      fieldLabel: fieldLabel,
      buildSql: buildSql,
      onExecute: onExecute,
      onOpenInSql: onOpenInSql,
    ),
  );
}

class _CreateNamedDialog extends StatefulWidget {
  const _CreateNamedDialog({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.fieldLabel,
    required this.buildSql,
    required this.onExecute,
    required this.onOpenInSql,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final String fieldLabel;
  final String Function(String name) buildSql;
  final Future<void> Function(String sql) onExecute;
  final void Function(String sql) onOpenInSql;

  @override
  State<_CreateNamedDialog> createState() => _CreateNamedDialogState();
}

class _CreateNamedDialogState extends State<_CreateNamedDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _sql {
    final name = _nameController.text.trim();
    return name.isEmpty ? '' : widget.buildSql(name);
  }

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onExecute(_sql);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SchemaDialogScaffold(
      title: widget.title,
      subtitle: widget.subtitle,
      icon: widget.icon,
      actionLabel: 'Create',
      sql: _sql,
      busy: _busy,
      error: _error,
      maxWidth: 480,
      onApply: _apply,
      onOpenInSql: () {
        final sql = _sql;
        Navigator.of(context).pop(false);
        if (sql.isNotEmpty) widget.onOpenInSql(sql);
      },
      body: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '${widget.fieldLabel} *',
            isDense: true,
            border: const OutlineInputBorder(),
          ),
          validator: (v) => v == null || v.trim().isEmpty
              ? '${widget.fieldLabel} is required'
              : null,
          onFieldSubmitted: (_) => _apply(),
        ),
      ),
    );
  }
}

/// Creates a table: name, editable column list and a live SQL preview in
/// the engine's [dialect]. Returns true once created.
Future<bool?> showCreateTableDialog(
  BuildContext context, {
  required SqlDialect dialect,
  required String schema,
  required Future<void> Function(String sql) onExecute,
  required void Function(String sql) onOpenInSql,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _CreateTableDialog(
      dialect: dialect,
      schema: schema,
      onExecute: onExecute,
      onOpenInSql: onOpenInSql,
    ),
  );
}

/// Editing state of one column row.
class _ColumnRow {
  _ColumnRow({
    String name = '',
    String type = '',
    this.nullable = true,
    this.primaryKey = false,
  }) : name = TextEditingController(text: name),
       type = TextEditingController(text: type);

  final TextEditingController name;
  final TextEditingController type;
  final defaultValue = TextEditingController();
  final typeFocus = FocusNode();
  bool nullable;
  bool primaryKey;

  NewColumn get column => NewColumn(
    name: name.text,
    type: type.text,
    nullable: nullable,
    primaryKey: primaryKey,
    defaultValue: defaultValue.text,
  );

  void dispose() {
    name.dispose();
    type.dispose();
    defaultValue.dispose();
    typeFocus.dispose();
  }
}

class _CreateTableDialog extends StatefulWidget {
  const _CreateTableDialog({
    required this.dialect,
    required this.schema,
    required this.onExecute,
    required this.onOpenInSql,
  });

  final SqlDialect dialect;
  final String schema;
  final Future<void> Function(String sql) onExecute;
  final void Function(String sql) onOpenInSql;

  @override
  State<_CreateTableDialog> createState() => _CreateTableDialogState();
}

class _CreateTableDialogState extends State<_CreateTableDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _rows = <_ColumnRow>[];
  bool _busy = false;
  String? _error;

  /// ClickHouse columns are rarely Nullable; new rows start NOT NULL there.
  bool get _nullableByDefault => widget.dialect is! ClickHouseDialect;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_changed);
    _track(
      _ColumnRow(
        name: 'id',
        type: defaultKeyType(widget.dialect),
        nullable: false,
        primaryKey: true,
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Adds [row], rebuilding (for the preview) whenever it is edited.
  void _track(_ColumnRow row) {
    row.name.addListener(_changed);
    row.type.addListener(_changed);
    row.defaultValue.addListener(_changed);
    _rows.add(row);
  }

  void _add() =>
      setState(() => _track(_ColumnRow(nullable: _nullableByDefault)));

  void _remove(_ColumnRow row) {
    setState(() => _rows.remove(row));
    // Disposed after the frame that stops using its controllers.
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  String get _sql => buildCreateTableSql(
    widget.dialect,
    schema: widget.schema,
    table: _nameController.text,
    columns: [for (final row in _rows) row.column],
  );

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate()) return;
    if (_rows.isEmpty) {
      setState(() => _error = 'Add at least one column');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onExecute(_sql);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SchemaDialogScaffold(
      title: 'Create Table',
      subtitle: widget.schema,
      icon: Icons.table_chart_rounded,
      actionLabel: 'Create Table',
      sql: _sql,
      busy: _busy,
      error: _error,
      maxWidth: 820,
      onApply: _apply,
      onOpenInSql: () {
        final sql = _sql;
        Navigator.of(context).pop(false);
        if (sql.isNotEmpty) widget.onOpenInSql(sql);
      },
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Table Name *',
                hintText: 'e.g. orders',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Table name is required'
                  : null,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Columns',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add column'),
                  onPressed: _busy ? null : _add,
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final row in _rows)
              Padding(
                key: ObjectKey(row),
                padding: const EdgeInsets.only(bottom: 10),
                child: _columnRow(row),
              ),
          ],
        ),
      ),
    );
  }

  /// One line on wide dialogs; two on phones.
  Widget _columnRow(_ColumnRow row) {
    final name = TextFormField(
      controller: row.name,
      decoration: const InputDecoration(
        labelText: 'Name',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
    );
    final type = _TypeField(
      controller: row.type,
      focusNode: row.typeFocus,
      suggestions: columnTypeSuggestions(widget.dialect),
    );
    final defaultValue = TextFormField(
      controller: row.defaultValue,
      decoration: const InputDecoration(
        labelText: 'Default',
        isDense: true,
        border: OutlineInputBorder(),
      ),
    );
    final flags = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Flag(
          label: 'PK',
          tooltip: 'Primary key',
          value: row.primaryKey,
          onChanged: (v) => setState(() {
            row.primaryKey = v;
            if (v) row.nullable = false;
          }),
        ),
        _Flag(
          label: 'Null',
          tooltip: 'Allow NULL values',
          value: row.nullable && !row.primaryKey,
          onChanged: row.primaryKey
              ? null
              : (v) => setState(() => row.nullable = v),
        ),
        IconButton(
          tooltip: 'Remove column',
          icon: const Icon(Icons.close_rounded, size: 18),
          onPressed: _busy ? null : () => _remove(row),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 600) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: name),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: type),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: defaultValue),
              flags,
            ],
          );
        }
        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: name),
                const SizedBox(width: 8),
                Expanded(child: type),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: defaultValue),
                flags,
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Small labelled checkbox for a column flag.
class _Flag extends StatelessWidget {
  const _Flag({
    required this.label,
    required this.tooltip,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String tooltip;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: value,
            visualDensity: VisualDensity.compact,
            onChanged: onChanged == null ? null : (v) => onChanged!(v!),
          ),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

/// Data type field with the engine's common types as suggestions.
class _TypeField extends StatelessWidget {
  const _TypeField({
    required this.controller,
    required this.focusNode,
    required this.suggestions,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (value) {
        final query = value.text.toLowerCase();
        return suggestions.where(
          (t) => query.isEmpty || t.toLowerCase().contains(query),
        );
      },
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 280),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              children: [
                for (final option in options)
                  InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        option,
                        style: monoStyle.copyWith(fontSize: 12),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
          TextFormField(
            controller: controller,
            focusNode: focusNode,
            style: monoStyle.copyWith(fontSize: 12),
            decoration: const InputDecoration(
              labelText: 'Type',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
          ),
    );
  }
}

/// MongoDB: creates a collection in [database], or with [database] null a
/// new database together with its first collection (MongoDB creates a
/// database when something is first stored in it). Returns true once
/// created.
Future<bool?> showCreateCollectionDialog(
  BuildContext context, {
  String? database,
  required Future<void> Function(String database, String collection) onCreate,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) =>
        _CreateCollectionDialog(database: database, onCreate: onCreate),
  );
}

class _CreateCollectionDialog extends StatefulWidget {
  const _CreateCollectionDialog({
    required this.database,
    required this.onCreate,
  });

  final String? database;
  final Future<void> Function(String database, String collection) onCreate;

  @override
  State<_CreateCollectionDialog> createState() =>
      _CreateCollectionDialogState();
}

class _CreateCollectionDialogState extends State<_CreateCollectionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _databaseController = TextEditingController();
  final _collectionController = TextEditingController();
  bool _busy = false;
  String? _error;

  bool get _newDatabase => widget.database == null;

  @override
  void dispose() {
    _databaseController.dispose();
    _collectionController.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onCreate(
        widget.database ?? _databaseController.text.trim(),
        _collectionController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  String? _required(String? v, String what) =>
      v == null || v.trim().isEmpty ? '$what is required' : null;

  @override
  Widget build(BuildContext context) {
    return SchemaDialogScaffold(
      title: _newDatabase ? 'Create Database' : 'Create Collection',
      subtitle: widget.database,
      icon: _newDatabase ? Icons.storage_rounded : Icons.folder_copy_outlined,
      iconColor: const Color(0xFF10B981),
      actionLabel: 'Create',
      sql: '',
      busy: _busy,
      error: _error,
      maxWidth: 480,
      onApply: _apply,
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_newDatabase) ...[
              TextFormField(
                controller: _databaseController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Database Name *',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => _required(v, 'Database name'),
              ),
              const SizedBox(height: 14),
            ],
            TextFormField(
              controller: _collectionController,
              autofocus: !_newDatabase,
              decoration: InputDecoration(
                labelText: _newDatabase
                    ? 'First Collection *'
                    : 'Collection Name *',
                helperText: _newDatabase
                    ? 'MongoDB stores a database once it has a collection'
                    : null,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              validator: (v) => _required(v, 'Collection name'),
              onFieldSubmitted: (_) => _apply(),
            ),
          ],
        ),
      ),
    );
  }
}
