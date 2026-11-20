import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_client.dart';
import '../../ai/ai_settings.dart';
import '../../ai/sql_assistant.dart';
import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../state/providers.dart';
import 'ai_settings_dialog.dart';

/// How to put generated SQL into the editor.
enum AiInsertMode { atCursor, replaceAll }

/// Asks the configured AI provider for SQL. Returns the SQL to insert and
/// where, or null. The SQL is never run from here.
Future<(String sql, AiInsertMode mode)?> showAskAiDialog(
  BuildContext context, {
  required String connectionId,
  required DatabaseEngine engine,
  String? defaultSchema,
  String? currentSql,
  String? lastError,
}) {
  return showDialog<(String, AiInsertMode)>(
    context: context,
    builder: (_) => _AskAiDialog(
      connectionId: connectionId,
      engine: engine,
      defaultSchema: defaultSchema,
      currentSql: currentSql,
      lastError: lastError,
    ),
  );
}

/// Schema metadata through the cached providers the navigator and
/// autocomplete share.
class _ProviderSchemaSource implements SchemaSource {
  _ProviderSchemaSource(this._ref, this._connectionId);

  final WidgetRef _ref;
  final String _connectionId;

  @override
  Future<List<String>> schemas() =>
      _ref.read(schemasProvider(_connectionId).future);

  @override
  Future<List<DbObject>> objects(String schema) =>
      _ref.read(objectsProvider((_connectionId, schema)).future);

  @override
  Future<List<ColumnInfo>> columns(String schema, String object) =>
      _ref.read(columnsProvider((_connectionId, schema, object)).future);
}

class _AskAiDialog extends ConsumerStatefulWidget {
  const _AskAiDialog({
    required this.connectionId,
    required this.engine,
    this.defaultSchema,
    this.currentSql,
    this.lastError,
  });

  final String connectionId;
  final DatabaseEngine engine;
  final String? defaultSchema;
  final String? currentSql;
  final String? lastError;

  @override
  ConsumerState<_AskAiDialog> createState() => _AskAiDialogState();
}

class _AskAiDialogState extends ConsumerState<_AskAiDialog> {
  final _instruction = TextEditingController();
  late bool _useCurrentSql = _hasCurrentSql;
  late bool _useLastError = _hasLastError;

  bool _busy = false;
  SqlSuggestion? _suggestion;
  String? _error;

  /// Ignores replies to a request the user has since replaced.
  int _generation = 0;

  bool get _hasCurrentSql => widget.currentSql?.trim().isNotEmpty ?? false;
  bool get _hasLastError => widget.lastError?.trim().isNotEmpty ?? false;

  @override
  void dispose() {
    _generation++;
    _instruction.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    var instruction = _instruction.text.trim();
    final fixing = _useLastError && _hasLastError;
    if (instruction.isEmpty && fixing) instruction = 'Fix the query.';
    if (instruction.isEmpty || _busy) return;

    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    final client = await ref.read(aiSettingsProvider.notifier).client();
    if (client == null || !mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      final suggestion = await SqlAssistant(
        client,
        _ProviderSchemaSource(ref, widget.connectionId),
      ).suggest(
        SqlRequest(
          instruction: instruction,
          engine: widget.engine,
          defaultSchema: widget.defaultSchema,
          currentSql: _useCurrentSql || fixing ? widget.currentSql : null,
          lastError: fixing ? widget.lastError : null,
        ),
      );
      if (!mounted || generation != _generation) return;
      setState(() => _suggestion = suggestion);
    } on AiException catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.message);
      }
    } on DriverException catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Could not read the schema: ${e.message}');
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = '$e');
      }
    } finally {
      client.close();
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  void _finish(AiInsertMode mode) {
    final sql = _suggestion?.sql;
    if (sql == null || sql.isEmpty) return;
    Navigator.of(context).pop((sql, mode));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(aiSettingsProvider);
    final suggestion = _suggestion;

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
              Icons.auto_awesome_outlined,
              size: 18,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Text('Ask AI')),
          if (settings != null)
            Flexible(
              child: Text(
                settings.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          IconButton(
            tooltip: 'AI settings',
            icon: const Icon(Icons.settings_outlined, size: 18),
            onPressed: _busy ? null : () => showAiSettingsDialog(context),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      content: SizedBox(
        width: 680,
        child: settings == null
            ? _SetupPrompt(onSetup: () => showAiSettingsDialog(context))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _instruction,
                      autofocus: true,
                      enabled: !_busy,
                      minLines: 1,
                      maxLines: 4,
                      keyboardType: TextInputType.text,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _generate(),
                      decoration: InputDecoration(
                        hintText: _useLastError && _hasLastError
                            ? 'Describe the fix, or leave empty to fix the error'
                            : 'e.g. top 10 customers by order total this year',
                        isDense: true,
                        suffixIcon: IconButton(
                          tooltip: 'Generate (Enter)',
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded, size: 18),
                          onPressed: _busy ? null : _generate,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (_hasCurrentSql)
                          FilterChip(
                            label: const Text(
                              'Use current query',
                              style: TextStyle(fontSize: 12),
                            ),
                            selected: _useCurrentSql,
                            onSelected: _busy
                                ? null
                                : (v) => setState(() => _useCurrentSql = v),
                          ),
                        if (_hasLastError)
                          FilterChip(
                            label: const Text(
                              'Fix last error',
                              style: TextStyle(fontSize: 12),
                            ),
                            selected: _useLastError,
                            onSelected: _busy
                                ? null
                                : (v) => setState(() => _useLastError = v),
                          ),
                      ],
                    ),
                    if (_error case final error?) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        error,
                        style: TextStyle(fontSize: 12, color: scheme.error),
                      ),
                    ],
                    if (suggestion != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 320),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            suggestion.sql,
                            style: const TextStyle(
                              fontFamily: monoFontFamily,
                              fontFamilyFallback: monoFontFallback,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      if (suggestion.explanation.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          suggestion.explanation,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Sends your request and schema names to '
                      '${settings.preset.label}; no row data. Review '
                      'generated SQL before running it.',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (suggestion != null) ...[
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy'),
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: suggestion.sql)),
          ),
          OutlinedButton(
            onPressed: () => _finish(AiInsertMode.replaceAll),
            child: const Text('Replace editor'),
          ),
          FilledButton(
            onPressed: () => _finish(AiInsertMode.atCursor),
            child: const Text('Insert'),
          ),
        ],
      ],
    );
  }
}

class _SetupPrompt extends StatelessWidget {
  const _SetupPrompt({required this.onSetup});

  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Describe the query you need in plain words and get SQL for '
            'this connection. Choose a provider first: OpenAI, Anthropic, '
            'Gemini, OpenRouter, Groq, DeepSeek, or a local model with '
            'Ollama.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.settings_outlined, size: 16),
            label: const Text('Set up AI'),
            onPressed: onSetup,
          ),
        ],
      ),
    );
  }
}
