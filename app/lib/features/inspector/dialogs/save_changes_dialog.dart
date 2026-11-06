import 'package:flutter/material.dart';

import 'schema_dialog_scaffold.dart';

/// Confirms staged row edits: shows the SQL and runs it in one transaction.
/// Returns true once saved.
Future<bool?> showSaveChangesDialog(
  BuildContext context, {
  required String table,
  required int changeCount,
  required List<String> statements,
  required Future<void> Function(List<String> statements) onExecute,
  required void Function(String sql) onOpenInSql,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _SaveChangesDialog(
      table: table,
      changeCount: changeCount,
      statements: statements,
      onExecute: onExecute,
      onOpenInSql: onOpenInSql,
    ),
  );
}

class _SaveChangesDialog extends StatefulWidget {
  const _SaveChangesDialog({
    required this.table,
    required this.changeCount,
    required this.statements,
    required this.onExecute,
    required this.onOpenInSql,
  });

  final String table;
  final int changeCount;
  final List<String> statements;
  final Future<void> Function(List<String> statements) onExecute;
  final void Function(String sql) onOpenInSql;

  @override
  State<_SaveChangesDialog> createState() => _SaveChangesDialogState();
}

class _SaveChangesDialogState extends State<_SaveChangesDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _apply() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onExecute(widget.statements);
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
    final rows = widget.changeCount == 1 ? 'row' : 'rows';
    return SchemaDialogScaffold(
      title: 'Save changes to ${widget.changeCount} $rows',
      subtitle: widget.table,
      icon: Icons.save_outlined,
      actionLabel: 'Save',
      sql: widget.statements.join('\n'),
      busy: _busy,
      error: _error,
      onApply: _apply,
      onOpenInSql: () {
        Navigator.of(context).pop(false);
        widget.onOpenInSql(widget.statements.join('\n'));
      },
      maxWidth: 720,
      body: const Text(
        'These statements run in one transaction: if any fails, none are '
        'applied and your edits stay staged.',
        style: TextStyle(fontSize: 13, height: 1.4),
      ),
    );
  }
}
