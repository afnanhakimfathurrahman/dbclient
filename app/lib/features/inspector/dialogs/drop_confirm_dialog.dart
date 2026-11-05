import 'package:flutter/material.dart';

import 'schema_dialog_scaffold.dart';

Future<bool?> showDropConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String objectName,
  required String objectType,
  bool hasCascade = true,
  required String Function(bool cascade) buildSql,
  required Future<void> Function(String sql) onExecute,
  required void Function(String sql) onOpenInSql,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => DropConfirmDialog(
      title: title,
      message: message,
      objectName: objectName,
      objectType: objectType,
      hasCascade: hasCascade,
      buildSql: buildSql,
      onExecute: onExecute,
      onOpenInSql: onOpenInSql,
    ),
  );
}

class DropConfirmDialog extends StatefulWidget {
  const DropConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.objectName,
    required this.objectType,
    this.hasCascade = true,
    required this.buildSql,
    required this.onExecute,
    required this.onOpenInSql,
  });

  final String title;
  final String message;
  final String objectName;
  final String objectType;
  final bool hasCascade;
  final String Function(bool cascade) buildSql;
  final Future<void> Function(String sql) onExecute;
  final void Function(String sql) onOpenInSql;

  @override
  State<DropConfirmDialog> createState() => _DropConfirmDialogState();
}

class _DropConfirmDialogState extends State<DropConfirmDialog> {
  bool _cascade = false;
  bool _busy = false;
  String? _error;

  String get _sql => widget.buildSql(_cascade);

  Future<void> _apply() async {
    final sql = _sql;
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
      title: widget.title,
      icon: Icons.delete_forever_rounded,
      isDestructive: true,
      actionLabel: 'Drop ${widget.objectType}',
      sql: _sql,
      busy: _busy,
      error: _error,
      onApply: _apply,
      onOpenInSql: () {
        final sql = _sql;
        Navigator.of(context).pop(false);
        widget.onOpenInSql(sql);
      },
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.message,
            style: const TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          if (widget.hasCascade) ...[
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _cascade,
              title: const Text(
                'CASCADE (automatically drop dependent objects)',
                style: TextStyle(fontSize: 12.5),
              ),
              subtitle: const Text(
                'Use with caution if views, foreign keys or other objects depend on this',
                style: TextStyle(fontSize: 11),
              ),
              onChanged: (val) => setState(() => _cascade = val ?? false),
            ),
          ],
        ],
      ),
    );
  }
}
