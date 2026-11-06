import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart' hide XFile;
import 'package:share_plus/share_plus.dart' as share show XFile;

import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../drivers/export.dart';
import '../../drivers/sql_dialect.dart';
import '../../state/providers.dart';

/// Shows an export dialog with format selection, live preview, copy and
/// save to file (share sheet on mobile).
///
/// [defaultTableName] is the INSERT target for SQL export, already quoted;
/// [fileName] is the suggested file name without extension.
Future<void> showExportDialog(
  BuildContext context, {
  required QueryResult result,
  String? defaultTableName,
  String? connectionId,
  String fileName = 'export',
}) {
  // SQL INSERTs are written in the connection's dialect.
  final dialect = connectionId == null
      ? postgresDialect
      : ProviderScope.containerOf(
              context,
              listen: false,
            ).read(sqlDriverProvider(connectionId))?.dialect ??
            postgresDialect;
  return showDialog<void>(
    context: context,
    builder: (_) => _ExportDialog(
      result: result,
      dialect: dialect,
      tableName: defaultTableName ?? 'exported_data',
      fileName: fileName,
    ),
  );
}

/// Saves the output of [bytes] to a file the user picks (desktop) or hands it
/// to the share sheet (mobile). On desktop [bytes] runs only once a location
/// is picked. Returns a message to show, or null if the user cancelled.
Future<String?> saveExport(
  BuildContext context, {
  required Future<Uint8List> Function() bytes,
  required ExportFormat format,
  required String fileName,
}) async {
  final name = '$fileName.${format.extension}';
  if (Platform.isAndroid || Platform.isIOS) {
    final box = context.findRenderObject() as RenderBox?;
    final data = await bytes();
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [share.XFile.fromData(data, mimeType: format.mimeType)],
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
  await File(path).writeAsBytes(await bytes());
  return 'Saved to $path';
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({
    required this.result,
    required this.dialect,
    required this.tableName,
    required this.fileName,
  });

  final QueryResult result;
  final String tableName;
  final SqlDialect dialect;
  final String fileName;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  /// Lines shown in the preview; the full text can be megabytes, which a
  /// SelectableText can't lay out quickly.
  static const _previewLines = 200;

  /// Only this many rows are exported for the preview; copy and save
  /// export everything on a background isolate.
  static const _previewRows = 200;

  /// Longer preview lines (huge values) are cut.
  static const _previewLineChars = 1000;

  late final _tableName = TextEditingController(text: widget.tableName);
  ExportFormat _selectedFormat = ExportFormat.csv;
  bool _copied = false;
  bool _copying = false;
  bool _saving = false;

  /// The target table the preview uses; follows the field after a pause in
  /// typing, so each keystroke doesn't re-export.
  late String _previewTable = _tableName.text;
  Timer? _previewTableTimer;

  (ExportFormat, String)? _previewKey;
  String _preview = '';
  bool _previewTruncated = false;

  String _target(String text) =>
      text.trim().isEmpty ? widget.tableName : text.trim();

  void _updatePreview() {
    final key = (_selectedFormat, _target(_previewTable));
    if (key == _previewKey) return;
    _previewKey = key;
    final result = widget.result;
    final moreRows = result.rows.length > _previewRows;
    final text = ResultExporter.export(
      moreRows
          ? QueryResult(
              columns: result.columns,
              rows: result.rows.take(_previewRows).toList(),
              affectedRows: result.affectedRows,
              elapsed: result.elapsed,
              truncated: result.truncated,
            )
          : result,
      key.$1,
      tableName: key.$2,
      dialect: widget.dialect,
    );
    final lines = const LineSplitter().convert(text);
    final longLines = lines.any((l) => l.length > _previewLineChars);
    _previewTruncated = moreRows || lines.length > _previewLines;
    _preview = _previewTruncated || longLines
        ? [
            for (final line in lines.take(_previewLines))
              line.length > _previewLineChars
                  ? '${line.substring(0, _previewLineChars)}…'
                  : line,
          ].join('\n')
        : text;
  }

  void _onTableNameChanged(String _) {
    _previewTableTimer?.cancel();
    _previewTableTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _previewTable = _tableName.text);
    });
  }

  Future<String> _exportAll() => ResultExporter.exportInBackground(
    widget.result,
    _selectedFormat,
    tableName: _target(_tableName.text),
    dialect: widget.dialect,
  );

  @override
  void dispose() {
    _previewTableTimer?.cancel();
    _tableName.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard() async {
    setState(() => _copying = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Clipboard.setData(ClipboardData(text: await _exportAll()));
      if (!mounted) return;
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  Future<void> _save(BuildContext buttonContext) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final format = _selectedFormat;
    final tableName = _target(_tableName.text);
    try {
      final message = await saveExport(
        buttonContext,
        bytes: () => ResultExporter.exportBytesInBackground(
          widget.result,
          format,
          tableName: tableName,
          dialect: widget.dialect,
        ),
        format: format,
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
    _updatePreview();
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
            child: Icon(
              Icons.file_download_outlined,
              size: 18,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text(
              'Export Query Results',
              overflow: TextOverflow.ellipsis,
            ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: Colors.amber.shade700.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 15,
                      color: Colors.amber.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Only the $rowCount fetched rows are exported; the '
                        'query returned more.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: scheme.onSurface,
                        ),
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
                onChanged: _onTableNameChanged,
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
                      ? 'first lines · all $rowCount rows are exported'
                      : '${_preview.length} characters',
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
                      _previewTruncated ? '$_preview\n…' : _preview,
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
          onPressed: _copying ? null : _copyToClipboard,
          icon: _copying
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
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
