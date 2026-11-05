import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/theme.dart';
import '../../drivers/driver.dart';
import '../../drivers/registry.dart';
import '../../state/providers.dart';
import '../../state/workspace_tabs.dart';

/// Create or edit a connection. Returns the saved config, or null if
/// cancelled.
Future<ConnectionConfig?> showConnectionDialog(
  BuildContext context, {
  ConnectionConfig? existing,
}) {
  return showDialog<ConnectionConfig>(
    context: context,
    builder: (_) => _ConnectionDialog(existing: existing),
  );
}

class _ConnectionDialog extends ConsumerStatefulWidget {
  const _ConnectionDialog({this.existing});

  final ConnectionConfig? existing;

  @override
  ConsumerState<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends ConsumerState<_ConnectionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _host = TextEditingController(
    text: widget.existing?.host ?? 'localhost',
  );
  late final _port = TextEditingController(
    text: '${widget.existing?.port ?? DatabaseEngine.postgres.defaultPort}',
  );
  late final _database = TextEditingController(
    text: widget.existing?.database ?? 'postgres',
  );
  late final _username = TextEditingController(
    text: widget.existing?.username ?? 'postgres',
  );
  final _password = TextEditingController();
  late TlsMode _tlsMode = widget.existing?.tlsMode ?? TlsMode.disable;
  late int _color = widget.existing?.color ?? connectionColors.first;
  late bool _savePassword = widget.existing?.savePassword ?? true;
  bool _passwordTouched = false;

  bool _busy = false;
  String? _testMessage;
  bool _testOk = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_name, _host, _port, _database, _username, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  ConnectionConfig _buildConfig() {
    final host = _host.text.trim();
    final database = _database.text.trim();
    return ConnectionConfig(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _name.text.trim().isEmpty ? '$host/$database' : _name.text.trim(),
      engine: DatabaseEngine.postgres,
      host: host,
      port: int.parse(_port.text.trim()),
      database: database,
      username: _username.text.trim(),
      tlsMode: _tlsMode,
      color: _color,
      savePassword: _savePassword,
    );
  }

  /// Password to connect with: the typed one, or the stored one when editing
  /// and the field was left untouched.
  Future<String?> _effectivePassword() async {
    if (_passwordTouched || !_isEdit) return _password.text;
    return ref
        .read(connectionRepositoryProvider)
        .readPassword(widget.existing!.id);
  }

  Future<void> _test() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _testMessage = null;
    });
    final driver = createDriver(_buildConfig());
    try {
      await driver.connect(await _effectivePassword());
      final latency = await driver.ping();
      _testOk = true;
      _testMessage = 'Connected (${latency.inMilliseconds} ms)';
    } catch (e) {
      _testOk = false;
      _testMessage = '$e';
    } finally {
      await driver.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final config = _buildConfig();
    await ref
        .read(connectionRepositoryProvider)
        .save(
          config,
          password: _savePassword && (_passwordTouched || !_isEdit)
              ? _password.text
              : null,
        );
    if (mounted) Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final envLabel = connectionColorLabels[_color] ?? 'Custom';

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(
              Icons.dns_rounded,
              size: 18,
              color: Color(0xFF38BDF8),
            ),
          ),
          const SizedBox(width: 10),
          Text(_isEdit ? 'Edit Connection' : 'New PostgreSQL Connection'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Connection Name',
                    hintText: 'e.g. Analytics Prod (defaults to host/database)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextFormField(
                        controller: _host,
                        decoration: const InputDecoration(labelText: 'Host'),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _port,
                        decoration: const InputDecoration(labelText: 'Port'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (v) {
                          final port = int.tryParse(v ?? '');
                          return port == null || port < 1 || port > 65535
                              ? '1–65535'
                              : null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _database,
                        decoration:
                            const InputDecoration(labelText: 'Database'),
                        validator: _required,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _username,
                        decoration: const InputDecoration(labelText: 'User'),
                        validator: _required,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  onChanged: (_) => _passwordTouched = true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: _isEdit && widget.existing!.savePassword
                        ? 'Unchanged'
                        : 'Database password',
                  ),
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  value: _savePassword,
                  onChanged: (v) => setState(() => _savePassword = v ?? true),
                  title: const Text('Save password in secure store',
                      style: TextStyle(fontSize: 13)),
                  subtitle: const Text(
                      'Credentials stored encrypted in OS keychain',
                      style: TextStyle(fontSize: 11)),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<TlsMode>(
                  initialValue: _tlsMode,
                  decoration:
                      const InputDecoration(labelText: 'TLS / SSL Mode'),
                  items: [
                    for (final mode in TlsMode.values)
                      DropdownMenuItem(value: mode, child: Text(mode.label)),
                  ],
                  onChanged: (v) => setState(() => _tlsMode = v!),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text('Environment Tag:',
                        style: theme.textTheme.labelMedium),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Color(_color).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Color(_color).withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        envLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(_color),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  children: [
                    for (final color in connectionColors)
                      InkWell(
                        onTap: () => setState(() => _color = color),
                        customBorder: const CircleBorder(),
                        child: Tooltip(
                          message: connectionColorLabels[color] ?? '',
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: Color(color),
                            child: _color == color
                                ? const Icon(
                                    Icons.check,
                                    size: 16,
                                    color: Colors.white,
                                  )
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                if (_testMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _testOk
                          ? const Color(0xFF10B981).withValues(alpha: 0.12)
                          : scheme.errorContainer.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _testOk
                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
                            : scheme.error.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _testOk
                              ? Icons.check_circle_rounded
                              : Icons.error_outline_rounded,
                          size: 16,
                          color: _testOk
                              ? const Color(0xFF10B981)
                              : scheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _testMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _testOk
                                  ? const Color(0xFF10B981)
                                  : scheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _test,
          child: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Test connection'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  String? _required(String? value) =>
      (value == null || value.trim().isEmpty) ? 'Required' : null;
}

/// Connects [config], asking for the password if it isn't saved. Shows a
/// snackbar and returns null on failure or cancel.
Future<DatabaseDriver?> connectWithPrompt(
  BuildContext context,
  WidgetRef ref,
  ConnectionConfig config,
) async {
  final sessions = ref.read(sessionsProvider.notifier);
  final existing = sessions.driverFor(config.id);
  if (existing != null) return existing;

  String? password;
  if (config.savePassword) {
    password = await ref
        .read(connectionRepositoryProvider)
        .readPassword(config.id);
  } else {
    if (!context.mounted) return null;
    password = await _promptPassword(context, config);
    if (password == null) return null;
  }

  try {
    return await sessions.connect(config, password);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${config.name}: $e')));
    }
    return null;
  }
}

/// Opens a SQL editor on the most relevant connection: the active tab's, else
/// one that is already connected, else the first saved one. With no saved
/// connections, asks the user to create one first.
Future<void> openNewSqlEditor(BuildContext context, WidgetRef ref) async {
  final connections = ref.read(connectionsProvider).value ?? const [];
  ConnectionConfig? config;
  if (connections.isEmpty) {
    config = await showConnectionDialog(context);
  } else {
    final preferred = [
      ?ref.read(workspaceTabsProvider).active?.connectionId,
      ...ref.read(sessionsProvider).keys,
    ];
    config = [
      for (final id in preferred) ...connections.where((c) => c.id == id),
      connections.first,
    ].first;
  }
  if (config == null || !context.mounted) return;
  final driver = await connectWithPrompt(context, ref, config);
  if (driver != null) {
    ref.read(workspaceTabsProvider.notifier).open(config.id);
  }
}

Future<String?> _promptPassword(BuildContext context, ConnectionConfig config) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PasswordDialog(config: config),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.config});

  final ConnectionConfig config;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Password for ${widget.config.name}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        decoration: InputDecoration(labelText: widget.config.displayAddress),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
