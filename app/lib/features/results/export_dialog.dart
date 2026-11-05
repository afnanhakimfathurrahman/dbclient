import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' hide XFile;
import 'package:share_plus/share_plus.dart' as share show XFile;

import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../drivers/export.dart';

/// Shows an export dialog with format selection, live preview, copy and
/// save to file (share sheet on mobile).
///
/// [defaultTableName] is the INSERT target for SQL export, already quoted;
/// [fileName] is the suggested file name without extension.
Future<void> showExportDialog(
  BuildContext context, {
  required QueryResult result,
  String? defaultTableName,
  String fileName = 'export',
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _ExportDialog(
      result: result,
      tableName: defaultTableName ?? 'exported_data',
      fileName: fileName,
    ),
  );
}

/// Saves [text] to a file the user picks (desktop) or hands it to the share
/// sheet (mobile). Returns a message to show, or null if the user cancelled.
Future<String?> saveExport(
  BuildContext context, {
  required String text,
  required ExportFormat format,
  required String fileName,
}) async {
  final name = '$fileName.${format.extension}';
  if (Platform.isAndroid || Platform.isIOS) {
    final box = context.findRenderObject() as RenderBox?;
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [
          share.XFile.fromData(utf8.encode(text), mimeType: format.mimeType),
        ],
        fileNameOverrides: [name],
        // Required on iPad to anchor the share popover.
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
    return result.status == ShareResultStatus.dismissed ? null : 'Shared $name';
  }

  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: [
      XTypeGroup(label: format.label, extensions: [format.extension]),
    ],
  );
  if (location == null) return null;
  var path = location.path;
  if (!path.toLowerCase().endsWith('.${format.extension}')) {
    path = '$path.${format.extension}';
  }
  await File(path).writeAsString(text);
  return 'Saved to $path';
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({
    required this.result,
    required this.tableName,
    required this.fileName,
  });

  final QueryResult result;
  final String tableName;
  final String fileName;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  /// Lines shown in the preview; the full text can be megabytes, which a
  /// SelectableText can't lay out quickly.
  static const _previewLines = 200;

  late final _tableName = TextEditingController(text: widget.tableName);
  ExportFormat _selectedFormat = ExportFormat.csv;
  bool _copied = false;
  bool _saving = false;

  // Exporting thousands of rows is not free; cache per format and target.
  (ExportFormat, String)? _cacheKey;
  String _cachedText = '';
  String _cachedPreview = '';
  bool _previewTruncated = false;

  String get _exportedText {
    final key = (_selectedFormat, _tableName.text.trim());
    if (key != _cacheKey) {
      _cacheKey = key;
      _cachedText = ResultExporter.export(
        widget.result,
        _selectedFormat,
        tableName: key.$2.isEmpty ? widget.tableName : key.$2,
      );
      final lines = const LineSplitter().convert(_cachedText);
      _previewTruncated = lines.length > _previewLines;
      _cachedPreview = _previewTruncated
          ? lines.take(_previewLines).join('\n')
          : _cachedText;
    }
    return _cachedText;
  }

  @override
  void dispose() {
    _tableName.dispose();
    super.dispose();
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _exportedText));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _save(BuildContext buttonContext) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final message = await saveExport(
        buttonContext,
        text: _exportedText,
        format: _selectedFormat,
        fileName: widget.fileName,
      );
      if (message == null || !mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rowCount = widget.result.rows.length;
    final text = _exportedText;
    final isMobile = Platform.isAndroid || Platform.isIOS;

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.file_download_outlined,
                size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text('Export Query Results', overflow: TextOverflow.ellipsis),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Text(
              '$rowCount rows',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: 680,
        height: 460,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.result.truncated) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.amber.shade700.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 15, color: Colors.amber.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Only the $rowCount fetched rows are exported; the '
                        'query returned more.',
                        style: TextStyle(fontSize: 11.5, color: scheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Format Selector Chips
            Text('Format:', style: theme.textTheme.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final format in ExportFormat.values)
                  ChoiceChip(
                    selected: _selectedFormat == format,
                    avatar: Icon(
                      _formatIcon(format),
                      size: 15,
                      color: _selectedFormat == format
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    label: Text(format.label),
                    onSelected: (_) => setState(() => _selectedFormat = format),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _selectedFormat.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            if (_selectedFormat == ExportFormat.sql) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _tableName,
                style: monoStyle.copyWith(fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Target table',
                  helperText: 'Inserted as written: quote names if needed',
                  isDense: true,
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            const SizedBox(height: 14),

            // Live Preview Header
            Row(
              children: [
                Text('Preview:', style: theme.textTheme.labelMedium),
                const Spacer(),
                Text(
                  _previewTruncated
                      ? 'first $_previewLines lines · ${text.length} characters'
                      : '${text.length} characters',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // Code Preview Box
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SelectableText(
                      _previewTruncated ? '$_cachedPreview\n…' : _cachedPreview,
                      style: monoStyle.copyWith(fontSize: 12),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        OutlinedButton.icon(
          onPressed: _copyToClipboard,
          icon: Icon(
            _copied ? Icons.check_rounded : Icons.copy_rounded,
            size: 16,
          ),
          label: Text(_copied ? 'Copied!' : 'Copy'),
        ),
        Builder(
          builder: (buttonContext) => FilledButton.icon(
            onPressed: _saving ? null : () => _save(buttonContext),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    isMobile ? Icons.share_rounded : Icons.save_alt_rounded,
                    size: 16,
                  ),
            label: Text(isMobile ? 'Share…' : 'Save to file…'),
          ),
        ),
      ],
    );
  }

  IconData _formatIcon(ExportFormat format) => switch (format) {
        ExportFormat.csv => Icons.table_chart_outlined,
        ExportFormat.json => Icons.data_object_rounded,
        ExportFormat.markdown => Icons.text_snippet_outlined,
        ExportFormat.tsv => Icons.border_all_rounded,
        ExportFormat.sql => Icons.code_rounded,
      };
}
