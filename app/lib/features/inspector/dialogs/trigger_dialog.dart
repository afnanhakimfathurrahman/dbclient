import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../drivers/driver.dart';
import '../../../drivers/postgres/postgres_sql.dart';
import 'schema_dialog_scaffold.dart';

Future<bool?> showTriggerDialog(
  BuildContext context, {
  required String schema,
  required String table,
  TriggerInfo? existing,
  bool isView = false,
  required Future<void> Function(String sql) onExecute,
  required void Function(String sql) onOpenInSql,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => TriggerDialog(
      schema: schema,
      table: table,
      isView: isView,
      existing: existing,
      onExecute: onExecute,
      onOpenInSql: onOpenInSql,
    ),
  );
}

class TriggerDialog extends StatefulWidget {
  const TriggerDialog({
    super.key,
    required this.schema,
    required this.table,
    this.existing,
    this.isView = false,
    required this.onExecute,
    required this.onOpenInSql,
  });

  final String schema;
  final String table;
  final TriggerInfo? existing;

  /// Views only support INSTEAD OF … FOR EACH ROW triggers.
  final bool isView;
  final Future<void> Function(String sql) onExecute;
  final void Function(String sql) onOpenInSql;

  bool get isEdit => existing != null;

  @override
  State<TriggerDialog> createState() => _TriggerDialogState();
}

class _TriggerDialogState extends State<TriggerDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  final TextEditingController _functionController = TextEditingController();
  final TextEditingController _conditionController = TextEditingController();
  final TextEditingController _customSqlController = TextEditingController();

  late String _timing = widget.isView ? 'INSTEAD OF' : 'BEFORE';
  late final Set<String> _events = {widget.isView ? 'INSERT' : 'UPDATE'};
  String _forEach = 'ROW';
  late bool _enabled = widget.existing?.enabled ?? true;
  bool _customSqlMode = false;

  bool _busy = false;
  String? _error;

  List<String> get _timings =>
      widget.isView ? const ['INSTEAD OF'] : const ['BEFORE', 'AFTER'];
  List<String> get _allEvents => widget.isView
      ? const ['INSERT', 'UPDATE', 'DELETE']
      : const ['INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'];

  /// Postgres's rules for trigger definitions, checked before sending.
  String? get _ruleError {
    if (_events.contains('TRUNCATE') && _forEach == 'ROW') {
      return 'TRUNCATE triggers must be FOR EACH STATEMENT.';
    }
    if (_timing == 'INSTEAD OF' && _forEach != 'ROW') {
      return 'INSTEAD OF triggers must be FOR EACH ROW.';
    }
    if (_timing == 'INSTEAD OF' &&
        _conditionController.text.trim().isNotEmpty) {
      return 'INSTEAD OF triggers cannot have a WHEN condition.';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _nameController.addListener(() => setState(() {}));
    _functionController.addListener(() => setState(() {}));
    _conditionController.addListener(() => setState(() {}));
    _customSqlController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _functionController.dispose();
    _conditionController.dispose();
    _customSqlController.dispose();
    super.dispose();
  }

  String get _sql {
    if (widget.isEdit) {
      final existing = widget.existing!;
      final newName = _nameController.text.trim();
      return buildAlterTriggerSql(
        schema: widget.schema,
        table: widget.table,
        oldName: existing.name,
        newName: newName != existing.name ? newName : null,
        enabled: _enabled != existing.enabled ? _enabled : null,
      );
    } else {
      if (_customSqlMode) {
        return _customSqlController.text.trim();
      }

      final name = _nameController.text.trim();
      final func = _functionController.text.trim();
      if (name.isEmpty || func.isEmpty || _events.isEmpty) return '';

      return buildCreateTriggerSql(
        schema: widget.schema,
        table: widget.table,
        name: name,
        timing: _timing,
        events: _events.toList(),
        forEach: _forEach,
        functionName: func,
        condition: _conditionController.text.trim().isNotEmpty
            ? _conditionController.text.trim()
            : null,
      );
    }
  }

  Future<void> _apply() async {
    if (!_formKey.currentState!.validate()) return;
    if (!widget.isEdit && !_customSqlMode) {
      if (_events.isEmpty) {
        setState(() => _error = 'Please select at least one trigger event.');
        return;
      }
      if (_functionController.text.trim().isEmpty) {
        setState(() => _error = 'Function name is required.');
        return;
      }
      if (_ruleError case final message?) {
        setState(() => _error = message);
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
          ? 'Edit Trigger "${widget.existing!.name}"'
          : 'Add Trigger',
      subtitle: '${widget.schema}.${widget.table}',
      icon: Icons.bolt_rounded,
      actionLabel: widget.isEdit ? 'Apply Changes' : 'Create Trigger',
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
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'Custom SQL Mode',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch.adaptive(
                    value: _customSqlMode,
                    onChanged: (val) {
                      // Seed from the form; read _sql before switching modes,
                      // since in custom mode it returns the custom text.
                      final generated = _sql;
                      setState(() {
                        _customSqlMode = val;
                        if (val && _customSqlController.text.isEmpty) {
                          _customSqlController.text = generated;
                        }
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],

            if (!widget.isEdit && _customSqlMode) ...[
              TextFormField(
                controller: _customSqlController,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'Custom CREATE TRIGGER Statement *',
                  hintText: 'CREATE TRIGGER ...',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Statement cannot be empty'
                    : null,
              ),
            ] else ...[
              TextFormField(
                controller: _nameController,
                autofocus: !widget.isEdit,
                decoration: const InputDecoration(
                  labelText: 'Trigger Name *',
                  hintText: 'e.g. trg_update_modified_at',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Trigger name is required'
                    : null,
              ),
              const SizedBox(height: 14),

              if (widget.isEdit) ...[
                SwitchListTile.adaptive(
                  title: const Text('Trigger Enabled', style: TextStyle(fontSize: 13)),
                  subtitle: Text(
                    _enabled
                        ? 'Trigger is active on events'
                        : 'Trigger is currently disabled',
                    style: const TextStyle(fontSize: 11),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: _enabled,
                  onChanged: (val) => setState(() => _enabled = val),
                ),
                if (widget.existing?.definition case final def?) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Trigger Definition:',
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
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _timing,
                        decoration: const InputDecoration(
                          labelText: 'Timing',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final t in _timings)
                            DropdownMenuItem(value: t, child: Text(t)),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _timing = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _forEach,
                        decoration: const InputDecoration(
                          labelText: 'Granularity',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'ROW', child: Text('EACH ROW')),
                          DropdownMenuItem(
                            value: 'STATEMENT',
                            child: Text('EACH STATEMENT'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _forEach = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                const Text(
                  'Events *:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final ev in _allEvents)
                      FilterChip(
                        label: Text(ev, style: const TextStyle(fontSize: 12)),
                        selected: _events.contains(ev),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _events.add(ev);
                            } else {
                              _events.remove(ev);
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _functionController,
                  decoration: const InputDecoration(
                    labelText: 'Trigger Function *',
                    hintText: 'e.g. update_timestamp or trigger_audit()',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Function is required'
                      : null,
                ),
                const SizedBox(height: 14),

                TextFormField(
                  controller: _conditionController,
                  decoration: const InputDecoration(
                    labelText: 'WHEN Condition (Optional)',
                    hintText: 'e.g. OLD.balance IS DISTINCT FROM NEW.balance',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
