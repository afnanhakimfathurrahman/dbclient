import 'package:flutter/material.dart';

import '../../../drivers/driver.dart';
import '../../../drivers/postgres/postgres_sql.dart';
import 'schema_dialog_scaffold.dart';

Future<bool?> showConstraintDialog(
  BuildContext context, {
  required String schema,
  required String table,
  ConstraintInfo? existing,
  List<ColumnInfo> columns = const [],
  ConstraintKind? initialKind,
  required Future<void> Function(String sql) onExecute,
  required void Function(String sql) onOpenInSql,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => ConstraintDialog(
      schema: schema,
      table: table,
      existing: existing,
      columns: columns,
      initialKind: initialKind,
      onExecute: onExecute,
      onOpenInSql: onOpenInSql,
    ),
  );
}

class ConstraintDialog extends StatefulWidget {
  const ConstraintDialog({
    super.key,
    required this.schema,
    required this.table,
    this.existing,
    this.columns = const [],
    this.initialKind,
    required this.onExecute,
    required this.onOpenInSql,
  });

  final String schema;
  final String table;
  final ConstraintInfo? existing;
  final List<ColumnInfo> columns;
  final ConstraintKind? initialKind;
  final Future<void> Function(String sql) onExecute;
  final void Function(String sql) onOpenInSql;

  bool get isEdit => existing != null;

  @override
  State<ConstraintDialog> createState() => _ConstraintDialogState();
}

class _ConstraintDialogState extends State<ConstraintDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final TextEditingController _definitionController = TextEditingController(
    text: widget.existing?.definition ?? '',
  );
  late final TextEditingController _expressionController = TextEditingController();
  late final TextEditingController _refSchemaController = TextEditingController(
    text: widget.schema,
  );
  final TextEditingController _refTableController = TextEditingController();
  final TextEditingController _refColumnsController = TextEditingController();

  late ConstraintKind _kind = widget.existing?.kind ??
      widget.initialKind ??
      ConstraintKind.primaryKey;

  final Set<String> _selectedColumns = {};
  String _onDelete = 'NO ACTION';
  String _onUpdate = 'NO ACTION';

  bool _busy = false;
  String? _error;

  static const _actions = [
    'NO ACTION',
    'CASCADE',
    'SET NULL',
    'SET DEFAULT',
    'RESTRICT',
  ];

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
    _definitionController.addListener(() => setState(() {}));
    _expressionController.addListener(() => setState(() {}));
    _refSchemaController.addListener(() => setState(() {}));
    _refTableController.addListener(() => setState(() {}));
    _refColumnsController.addListener(() => setState(() {}));

    if (!widget.isEdit && widget.columns.isNotEmpty) {
      // Pick first column by default for convenience
      _selectedColumns.add(widget.columns.first.name);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _definitionController.dispose();
    _expressionController.dispose();
    _refSchemaController.dispose();
    _refTableController.dispose();
    _refColumnsController.dispose();
    super.dispose();
  }

  String get _sql {
    if (widget.isEdit) {
      final existing = widget.existing!;
      final newName = _nameController.text.trim();
      final newDef = _definitionController.text.trim();

      return buildAlterConstraintSql(
        schema: widget.schema,
        table: widget.table,
        oldName: existing.name,
        newName: newName != existing.name ? newName : null,
        newDefinition: newDef != existing.definition ? newDef : null,
      );
    } else {
      final name = _nameController.text.trim();
      return buildAddConstraintSql(
        schema: widget.schema,
        table: widget.table,
        name: name.isNotEmpty ? name : null,
        kind: _kind,
        columns: _selectedColumns.toList(),
        expression: _expressionController.text.trim().isNotEmpty
            ? _expressionController.text.trim()
            : null,
        referencedSchema: _refSchemaController.text.trim().isNotEmpty
            ? _refSchemaController.text.trim()
            : null,
        referencedTable: _refTableController.text.trim().isNotEmpty
            ? _refTableController.text.trim()
            : null,
        referencedColumns: _refColumnsController.text
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
        onDelete: _onDelete,
        onUpdate: _onUpdate,
      );
    }
  }

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate()) return;
    if (!widget.isEdit) {
      if (_kind != ConstraintKind.check && _selectedColumns.isEmpty) {
        setState(() => _error = 'Please select at least one column.');
        return;
      }
      if (_kind == ConstraintKind.check &&
          _expressionController.text.trim().isEmpty) {
        setState(() => _error = 'Check expression cannot be empty.');
        return;
      }
      if (_kind == ConstraintKind.foreignKey &&
          _refTableController.text.trim().isEmpty) {
        setState(() => _error = 'Referenced table is required.');
        return;
      }
    }

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
          ? 'Edit Constraint "${widget.existing!.name}"'
          : (_kind == ConstraintKind.foreignKey
              ? 'Add Foreign Key'
              : 'Add Constraint'),
      subtitle: '${widget.schema}.${widget.table}',
      icon: _kind == ConstraintKind.foreignKey
          ? Icons.link_rounded
          : Icons.shield_outlined,
      actionLabel: widget.isEdit ? 'Apply Changes' : 'Add Constraint',
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
            if (!widget.isEdit) ...[
              DropdownButtonFormField<ConstraintKind>(
                initialValue: _kind,
                decoration: const InputDecoration(
                  labelText: 'Constraint Type',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final k in const [
                    ConstraintKind.primaryKey,
                    ConstraintKind.unique,
                    ConstraintKind.check,
                    ConstraintKind.foreignKey,
                  ])
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _kind = val);
                },
              ),
              const SizedBox(height: 14),
            ],

            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: widget.isEdit ? 'Constraint Name *' : 'Constraint Name (Optional)',
                hintText: 'e.g. ${widget.table}_pkey',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              validator: widget.isEdit
                  ? (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null
                  : null,
            ),
            const SizedBox(height: 14),

            if (widget.isEdit) ...[
              TextFormField(
                controller: _definitionController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Constraint Definition *',
                  hintText: 'e.g. PRIMARY KEY (id) or CHECK (qty >= 0)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Definition is required' : null,
              ),
            ] else ...[
              if (_kind != ConstraintKind.check) ...[
                const Text(
                  'Select Columns:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                if (widget.columns.isEmpty)
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Columns (comma separated)',
                      hintText: 'e.g. id, tenant_id',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      _selectedColumns.clear();
                      _selectedColumns.addAll(
                        v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
                      );
                      setState(() {});
                    },
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final col in widget.columns)
                        FilterChip(
                          label: Text(col.name, style: const TextStyle(fontSize: 12)),
                          selected: _selectedColumns.contains(col.name),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                _selectedColumns.add(col.name);
                              } else {
                                _selectedColumns.remove(col.name);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                const SizedBox(height: 14),
              ],

              if (_kind == ConstraintKind.check) ...[
                TextFormField(
                  controller: _expressionController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Check Condition Expression *',
                    hintText: "e.g. price >= 0, status IN ('draft', 'published')",
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              if (_kind == ConstraintKind.foreignKey) ...[
                Row(
                  children: [
                    Expanded(
                      flex: 1,
                      child: TextFormField(
                        controller: _refSchemaController,
                        decoration: const InputDecoration(
                          labelText: 'Target Schema',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _refTableController,
                        decoration: const InputDecoration(
                          labelText: 'Target Table *',
                          hintText: 'e.g. users',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _refColumnsController,
                  decoration: const InputDecoration(
                    labelText: 'Target Column(s) *',
                    hintText: 'e.g. id',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _onDelete,
                        decoration: const InputDecoration(
                          labelText: 'On Delete',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final a in _actions)
                            DropdownMenuItem(value: a, child: Text(a)),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _onDelete = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _onUpdate,
                        decoration: const InputDecoration(
                          labelText: 'On Update',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final a in _actions)
                            DropdownMenuItem(value: a, child: Text(a)),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _onUpdate = v);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
