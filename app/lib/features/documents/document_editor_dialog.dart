import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../drivers/mongodb/mongo_json.dart';

/// Edits a document as mongosh-style text. [onSave] receives the parsed
/// document; its errors (and parse errors) show inline and keep the dialog
/// open. Returns true once saved.
Future<bool?> showDocumentEditor(
  BuildContext context, {
  required String title,
  required String initialText,
  required String actionLabel,
  required Future<void> Function(Map<String, dynamic> document) onSave,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _DocumentEditorDialog(
      title: title,
      initialText: initialText,
      actionLabel: actionLabel,
      onSave: onSave,
    ),
  );
}

class _DocumentEditorDialog extends StatefulWidget {
  const _DocumentEditorDialog({
    required this.title,
    required this.initialText,
    required this.actionLabel,
    required this.onSave,
  });

  final String title;
  final String initialText;
  final String actionLabel;
  final Future<void> Function(Map<String, dynamic> document) onSave;

  @override
  State<_DocumentEditorDialog> createState() => _DocumentEditorDialogState();
}

class _DocumentEditorDialogState extends State<_DocumentEditorDialog> {
  late final _controller = TextEditingController(text: widget.initialText);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final Map<String, dynamic> document;
    try {
      document = parseMongoDocument(_controller.text, what: 'document');
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(document);
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
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
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 680,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: scheme.error.withValues(alpha: 0.4),
                  ),
                ),
                child: SelectableText(
                  _error!,
                  style: TextStyle(fontSize: 12, color: scheme.error),
                ),
              ),
              const SizedBox(height: 10),
            ],
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_busy,
                autofocus: true,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: monoStyle.copyWith(fontSize: 12.5, height: 1.4),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "mongosh syntax: ObjectId('…'), ISODate('…'), Long('…'), "
              "Decimal128('…'). Extended JSON works too.",
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.actionLabel),
        ),
      ],
    );
  }
}
