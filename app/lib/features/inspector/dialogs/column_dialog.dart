import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../drivers/driver.dart';
import '../../../drivers/postgres/postgres_sql.dart';
import 'schema_dialog_scaffold.dart';

Future<bool?> showColumnDialog(
  BuildContext context, {
  required String schema,
  required String table,
  ColumnInfo? existing,
  required Future<void> Function(String sql) onExecute,
  required void Function(String sql) onOpenInSql,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => ColumnDialog(
      schema: schema,
      table: table,
      existing: existing,
      onExecute: onExecute,
      onOpenInSql: onOpenInSql,
    ),
  );
}

class ColumnDialog extends StatefulWidget {
  const ColumnDialog({
    super.key,
    required this.schema,
    required this.table,
    this.existing,
    required this.onExecute,
    required this.onOpenInSql,
  });

  final String schema;
  final String table;
  final ColumnInfo? existing;
  final Future<void> Function(String sql) onExecute;
  final void Function(String sql) onOpenInSql;

  bool get isEdit => existing != null;

  @override
  State<ColumnDialog> createState() => _ColumnDialogState();
}

class _ColumnDialogState extends State<ColumnDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _typeController = TextEditingController(
    text: widget.existing?.dataType ?? 'text',
  );
  late final TextEditingController _defaultController = TextEditingController(
    text: widget.existing?.defaultValue ?? '',
  );
  late final TextEditingController _commentController = TextEditingController(
    text: widget.existing?.comment ?? '',
  );
  final TextEditingController _usingController = TextEditingController();
  final _typeFocus = FocusNode();

  late bool _notNull = widget.existing != null ? !widget.existing!.nullable : false;
  bool _isPrimaryKey = false;

  bool _busy = false;
  String? _error;

  static const _commonTypes = [
    'integer',
    'bigint',
    'smallint',
    'serial',
    'bigserial',
    'text',
    'varchar(255)',
    'boolean',
    'numeric(10,2)',
    'real',
    'double precision',
    'timestamp with time zone',
    'timestamp',
    'date',
    'time',
    'jsonb',
    'json',
    'uuid',
    'bytea',
  ];

  @override
  void initState() {
    super.initState();
    _isPrimaryKey = widget.existing?.isPrimaryKey ?? false;
    _nameController.addListener(() => setState(() {}));
    _typeController.addListener(() => setState(() {}));
    _defaultController.addListener(() => setState(() {}));
    _commentController.addListener(() => setState(() {}));
    _usingController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _defaultController.dispose();
    _commentController.dispose();
    _usingController.dispose();
    _typeFocus.dispose();
    super.dispose();
  }

  bool get _typeChanged =>
      widget.isEdit &&
      _typeController.text.trim() != widget.existing!.dataType;

  String get _sql {
    final name = _nameController.text.trim();
    final type = _typeController.text.trim();
    if (name.isEmpty || type.isEmpty) return '';

    if (widget.isEdit) {
      final existing = widget.existing!;
      return buildAlterColumnSql(
        schema: widget.schema,
        table: widget.table,
        oldName: existing.name,
        newName: name != existing.name ? name : null,
        oldType: existing.dataType,
        newType: type != existing.dataType ? type : null,
        oldNotNull: !existing.nullable,
        newNotNull: _notNull,
        oldDefault: existing.defaultValue,
        newDefault: _defaultController.text.trim(),
        // Only when changed; an emptied comment is removed.
        comment: _commentController.text.trim() != (existing.comment ?? '')
            ? _commentController.text.trim()
            : null,
        using: _typeChanged ? _usingController.text.trim() : null,
      );
    } else {
      return buildAddColumnSql(
        schema: widget.schema,
        table: widget.table,
        name: name,
        type: type,
        notNull: _notNull,
        defaultExpr: _defaultController.text.trim().isNotEmpty
            ? _defaultController.text.trim()
            : null,
        isPrimaryKey: _isPrimaryKey,
        comment: _commentController.text.trim().isNotEmpty
            ? _commentController.text.trim()
            : null,
      );
    }
  }

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate()) return;
    final sql = _sql;
    if (sql.trim().isEmpty) {
      Navigator.of(context).pop(false);
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.onExecute(sql);
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
      title: widget.isEdit
          ? 'Edit Column "${widget.existing!.name}"'
          : 'Add Column',
      subtitle: '${widget.schema}.${widget.table}',
      icon: Icons.view_column_outlined,
      actionLabel: widget.isEdit ? 'Apply Changes' : 'Add Column',
      sql: _sql,
      busy: _busy,
      error: _error,
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
              autofocus: !widget.isEdit,
              decoration: const InputDecoration(
                labelText: 'Column Name *',
                hintText: 'e.g. user_id, email, created_at',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Column name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),

            // Data type with suggestions
            RawAutocomplete<String>(
              textEditingController: _typeController,
              focusNode: _typeFocus,
              optionsBuilder: (textEditingValue) {
                final query = textEditingValue.text.toLowerCase();
                return _commonTypes.where(
                  (t) => query.isEmpty || t.contains(query),
                );
              },
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(8),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 240,
                      maxWidth: 320,
                    ),
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
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Data Type *',
                    hintText: 'e.g. text, integer, varchar(255)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Data type is required';
                    }
                    return null;
                  },
                );
              },
            ),
            if (_typeChanged) ...[
              const SizedBox(height: 14),
              TextFormField(
                controller: _usingController,
                style: monoStyle.copyWith(fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'USING expression (optional)',
                  hintText:
                      'e.g. ${quoteIdent(widget.existing!.name)}'
                      '::${_typeController.text.trim()}',
                  helperText:
                      'Needed when existing values can\'t be cast '
                      'automatically',
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 14),

            TextFormField(
              controller: _defaultController,
              decoration: const InputDecoration(
                labelText: 'Default Value Expression',
                hintText: "e.g. 'active', 0, now(), gen_random_uuid()",
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),

            SwitchListTile.adaptive(
              title: const Text('Not Null', style: TextStyle(fontSize: 13)),
              subtitle: const Text(
                'Reject NULL values for this column',
                style: TextStyle(fontSize: 11),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _notNull,
              onChanged: (val) => setState(() => _notNull = val),
            ),

            if (!widget.isEdit) ...[
              SwitchListTile.adaptive(
                title: const Text('Primary Key', style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                  'Add PRIMARY KEY constraint on this column',
                  style: TextStyle(fontSize: 11),
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _isPrimaryKey,
                onChanged: (val) => setState(() {
                  _isPrimaryKey = val;
                  if (val) _notNull = true;
                }),
              ),
            ],

            const SizedBox(height: 10),
            TextFormField(
              controller: _commentController,
              decoration: const InputDecoration(
                labelText: 'Comment / Description',
                hintText: 'Optional comment on this column',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
