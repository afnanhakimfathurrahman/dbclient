import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../drivers/driver.dart';
import '../../../drivers/postgres/postgres_sql.dart';
import 'schema_dialog_scaffold.dart';

Future<bool?> showIndexDialog(
  BuildContext context, {
  required String schema,
  required String table,
  IndexInfo? existing,
  List<ColumnInfo> columns = const [],
  required Future<void> Function(String sql) onExecute,
  required void Function(String sql) onOpenInSql,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => IndexDialog(
      schema: schema,
      table: table,
      existing: existing,
      columns: columns,
      onExecute: onExecute,
      onOpenInSql: onOpenInSql,
    ),
  );
}

class IndexDialog extends StatefulWidget {
  const IndexDialog({
    super.key,
    required this.schema,
    required this.table,
    this.existing,
    this.columns = const [],
    required this.onExecute,
    required this.onOpenInSql,
  });

  final String schema;
  final String table;
  final IndexInfo? existing;
  final List<ColumnInfo> columns;
  final Future<void> Function(String sql) onExecute;
  final void Function(String sql) onOpenInSql;

  bool get isEdit => existing != null;

  @override
  State<IndexDialog> createState() => _IndexDialogState();
}

class _IndexDialogState extends State<IndexDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  final TextEditingController _predicateController = TextEditingController();

  final Set<String> _selectedColumns = {};
  String _method = 'btree';
  bool _isUnique = false;

  bool _busy = false;
  String? _error;

  static const _methods = ['btree', 'hash', 'gin', 'gist', 'brin', 'spgist'];

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
    _predicateController.addListener(() => setState(() {}));

    if (!widget.isEdit && widget.columns.isNotEmpty) {
      _selectedColumns.add(widget.columns.first.name);
      _autoSuggestName();
    }
  }

  /// True once the user types a name; until then it follows the columns.
  bool _nameEdited = false;

  void _autoSuggestName() {
    if (!_nameEdited && _selectedColumns.isNotEmpty) {
      _nameController.text =
          '${widget.table}_${_selectedColumns.join('_')}_idx';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _predicateController.dispose();
    super.dispose();
  }

  String get _sql {
    final name = _nameController.text.trim();
    if (name.isEmpty) return '';

    if (widget.isEdit) {
      return buildAlterIndexSql(
        schema: widget.schema,
        oldName: widget.existing!.name,
        newName: name,
      );
    } else {
      if (_selectedColumns.isEmpty) return '';
      return buildCreateIndexSql(
        schema: widget.schema,
        table: widget.table,
        name: name,
        columns: _selectedColumns.toList(),
        method: _method,
        isUnique: _isUnique,
        predicate: _predicateController.text.trim().isNotEmpty
            ? _predicateController.text.trim()
            : null,
      );
    }
  }

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate()) return;
    if (!widget.isEdit && _selectedColumns.isEmpty) {
      setState(() => _error = 'Please select at least one column to index.');
      return;
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
      title: widget.isEdit ? 'Edit Index "${widget.existing!.name}"' : 'Add Index',
      subtitle: '${widget.schema}.${widget.table}',
      icon: Icons.key_rounded,
      actionLabel: widget.isEdit ? 'Rename Index' : 'Create Index',
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
              onChanged: (_) => _nameEdited = true,
              decoration: const InputDecoration(
                labelText: 'Index Name *',
                hintText: 'e.g. users_email_idx',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Index name is required' : null,
            ),
            const SizedBox(height: 14),

            if (!widget.isEdit) ...[
              const Text(
                'Indexed Columns *:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              if (widget.columns.isEmpty)
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Columns (comma separated)',
                    hintText: 'e.g. email, created_at',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    _selectedColumns.clear();
                    _selectedColumns.addAll(
                      v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
                    );
                    _autoSuggestName();
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
                            _autoSuggestName();
                          });
                        },
                      ),
                  ],
                ),
              const SizedBox(height: 14),

              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(
                  labelText: 'Index Method',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final m in _methods)
                    DropdownMenuItem(
                      value: m,
                      child: Text(m.toUpperCase()),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _method = val);
                },
              ),
              const SizedBox(height: 14),

              SwitchListTile.adaptive(
                title: const Text('Unique Index', style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                  'Enforce uniqueness of indexed values',
                  style: TextStyle(fontSize: 11),
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: _isUnique,
                onChanged: (val) => setState(() => _isUnique = val),
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _predicateController,
                decoration: const InputDecoration(
                  labelText: 'WHERE Condition (Partial Index)',
                  hintText: 'e.g. deleted_at IS NULL, status = 1',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ] else ...[
              if (widget.existing?.definition case final def?) ...[
                const SizedBox(height: 8),
                Text(
                  'Current Definition:',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  def,
                  style: monoStyle.copyWith(fontSize: 11.5),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
