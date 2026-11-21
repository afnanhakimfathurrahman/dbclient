import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_client.dart';
import '../../ai/ai_settings.dart';

/// Picks the AI provider, model and API key. Returns true if saved.
Future<bool> showAiSettingsDialog(BuildContext context) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (_) => const _AiSettingsDialog(),
  );
  return saved ?? false;
}

class _AiSettingsDialog extends ConsumerStatefulWidget {
  const _AiSettingsDialog();

  @override
  ConsumerState<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends ConsumerState<_AiSettingsDialog> {
  final _baseUrl = TextEditingController();
  final _model = TextEditingController();
  final _apiKey = TextEditingController();

  late AiProviderPreset _preset;
  bool _showKey = false;
  bool _busy = false;

  /// Result of the last test or model fetch.
  String? _status;
  bool _statusIsError = false;

  /// Guards against a slow key read landing after the user switched.
  int _loadGeneration = 0;

  AiSettingsNotifier get _notifier => ref.read(aiSettingsProvider.notifier);

  @override
  void initState() {
    super.initState();
    _fill(ref.read(aiSettingsProvider)?.preset ?? AiProviderPreset.openAi);
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _select(AiProviderPreset preset) => setState(() {
    _status = null;
    _fill(preset);
  });

  /// Shows [preset]'s saved settings, then its key once read.
  Future<void> _fill(AiProviderPreset preset) async {
    final generation = ++_loadGeneration;
    final settings = _notifier.settingsFor(preset);
    _preset = preset;
    _baseUrl.text = settings.baseUrl;
    _model.text = settings.model;
    _apiKey.text = '';
    final key = await _notifier.apiKey(preset);
    if (!mounted || generation != _loadGeneration) return;
    _apiKey.text = key;
  }

  AiClient _client() => AiClient(
    AiEndpoint(
      preset: _preset,
      baseUrl: _baseUrl.text,
      model: _model.text,
      apiKey: _apiKey.text,
    ),
  );

  Future<void> _withClient(Future<void> Function(AiClient client) action) async {
    final client = _client();
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await action(client);
    } on AiException catch (e) {
      if (mounted) {
        setState(() {
          _status = e.message;
          _statusIsError = true;
        });
      }
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() => _withClient((client) async {
    final reply = await client.complete(
      system: 'You are a connectivity check.',
      user: 'Reply with the single word OK.',
    );
    if (!mounted) return;
    setState(() {
      final text = reply.trim();
      _status =
          'Connected. The model replied: '
          '${text.length > 60 ? '${text.substring(0, 60)}…' : text}';
      _statusIsError = false;
    });
  });

  Future<void> _pickModel() => _withClient((client) async {
    final models = await client.listModels();
    if (!mounted) return;
    if (models.isEmpty) {
      setState(() {
        _status = 'The provider listed no models.';
        _statusIsError = true;
      });
      return;
    }
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => _ModelPicker(models: models, current: _model.text),
    );
    if (picked != null) _model.text = picked;
  });

  Future<void> _save() async {
    if (_baseUrl.text.trim().isEmpty || _model.text.trim().isEmpty) {
      setState(() {
        _status = 'Base URL and model are required.';
        _statusIsError = true;
      });
      return;
    }
    if (_preset.requiresApiKey && _apiKey.text.trim().isEmpty) {
      setState(() {
        _status = '${_preset.label} needs an API key.';
        _statusIsError = true;
      });
      return;
    }
    await _notifier.save(
      AiSettings(preset: _preset, baseUrl: _baseUrl.text, model: _model.text),
      apiKey: _apiKey.text,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _turnOff() async {
    await _notifier.disable();
    if (mounted) Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = ref.watch(aiSettingsProvider) != null;

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
          const Text('AI Assistant'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'The assistant sends your request, the current query and '
                'your schema (table and column names and types) to the '
                'provider. It never sends row data. Use Ollama or another '
                'local server to keep everything on your machine.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AiProviderPreset>(
                initialValue: _preset,
                isDense: true,
                decoration: const InputDecoration(labelText: 'Provider'),
                items: [
                  for (final p in AiProviderPreset.values)
                    DropdownMenuItem(value: p, child: Text(p.label)),
                ],
                onChanged: _busy ? null : (p) => _select(p!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrl,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  hintText: _preset.protocol == AiProtocol.openAi
                      ? 'https://host/v1'
                      : null,
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKey,
                enabled: !_busy,
                obscureText: !_showKey,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: _preset.requiresApiKey
                      ? 'API key'
                      : 'API key (optional)',
                  helperText: 'Stored in the system keychain.',
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: _showKey ? 'Hide key' : 'Show key',
                    icon: Icon(
                      _showKey
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _showKey = !_showKey),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _model,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Model',
                  isDense: true,
                  suffixIcon: IconButton(
                    tooltip: 'Choose from the provider\'s models',
                    icon: const Icon(Icons.list_rounded, size: 18),
                    onPressed: _busy ? null : _pickModel,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check_rounded, size: 16),
                    label: const Text('Test'),
                    onPressed: _busy ? null : _test,
                  ),
                  const SizedBox(width: 12),
                  if (_status case final status?)
                    Expanded(
                      child: SelectableText(
                        status,
                        style: TextStyle(
                          fontSize: 12,
                          color: _statusIsError ? scheme.error : scheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (enabled)
          TextButton(
            onPressed: _busy ? null : _turnOff,
            child: const Text('Turn off'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ModelPicker extends StatefulWidget {
  const _ModelPicker({required this.models, required this.current});

  final List<String> models;
  final String current;

  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final filter = _filter.toLowerCase();
    final models = [
      for (final m in widget.models)
        if (m.toLowerCase().contains(filter)) m,
    ];
    return AlertDialog(
      title: const Text('Choose a model'),
      contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search, size: 18),
                hintText: 'Filter models...',
              ),
              onChanged: (v) => setState(() => _filter = v.trim()),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: models.length,
                itemBuilder: (context, i) => ListTile(
                  dense: true,
                  title: Text(models[i], style: const TextStyle(fontSize: 13)),
                  selected: models[i] == widget.current,
                  onTap: () => Navigator.of(context).pop(models[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
