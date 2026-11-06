import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/engine_style.dart';
import '../../app/theme.dart';
import '../../drivers/connection_uri.dart';
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
  final _urlController = TextEditingController();

  late DatabaseEngine _engine =
      widget.existing?.engine ?? DatabaseEngine.postgres;

  // MongoDB-only settings, stored in [ConnectionConfig.options].
  late bool _srv = widget.existing?.options['srv'] == 'true';
  late final _authSource = TextEditingController(
    text: widget.existing?.options['authSource'],
  );
  late final _params = TextEditingController(
    text: widget.existing?.options['params'],
  );

  late TlsMode _tlsMode = widget.existing?.tlsMode ?? TlsMode.disable;
  late int _color = widget.existing?.color ?? connectionColors.first;
  late bool _savePassword = widget.existing?.savePassword ?? true;
  bool _passwordTouched = false;
  bool _showPassword = false;
  bool _showUrlInput = false;
  String? _urlError;

  bool _busy = false;
  String? _testMessage;
  int? _testLatency;
  bool _testOk = false;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    for (final c in [
      _name,
      _host,
      _port,
      _database,
      _username,
      _password,
      _urlController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _parseConnectionUrl(String url) {
    if (url.trim().isEmpty) return;
    final ParsedConnectionUri parsed;
    try {
      parsed = parseConnectionUri(url);
    } on FormatException catch (e) {
      setState(() => _urlError = e.message);
      return;
    }
    if (_isEdit && parsed.engine != _engine) {
      setState(
        () => _urlError =
            'This connection is ${_engine.label}; the URI is for '
            '${parsed.engine.label}',
      );
      return;
    }

    setState(() {
      _selectEngine(parsed.engine);
      _host.text = parsed.host;
      if (parsed.tlsMode case final tls?) _tlsMode = tls;
      _port.text =
          '${parsed.port ?? _engine.portFor(tls: _tlsMode != TlsMode.disable)}';
      _database.text = parsed.database ?? _engine.defaultDatabase;
      if (parsed.username case final user?) _username.text = user;
      if (parsed.password case final password?) {
        _password.text = password;
        _passwordTouched = true;
      }
      _srv = parsed.options['srv'] == 'true';
      _authSource.text = parsed.options['authSource'] ?? '';
      _params.text = parsed.options['params'] ?? '';
      if (_name.text.isEmpty) _name.text = '${parsed.host}/${_database.text}';
      _showUrlInput = false;
      _urlError = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${parsed.engine.label} settings filled from URI'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Switches engine, replacing port, database and username only where they
  /// still hold the previous engine's defaults, so typed values survive.
  void _selectEngine(DatabaseEngine engine) {
    final old = _engine;
    if (engine == old) return;
    final tls = _tlsMode != TlsMode.disable;
    _engine = engine;
    if (_port.text.isEmpty || _port.text == '${old.portFor(tls: tls)}') {
      _port.text = '${engine.portFor(tls: tls)}';
    }
    if (_database.text.isEmpty || _database.text == old.defaultDatabase) {
      _database.text = engine.defaultDatabase;
    }
    if (_username.text == old.defaultUsername) {
      _username.text = engine.defaultUsername;
    }
  }

  void _setTlsMode(TlsMode mode) {
    final wasTls = _tlsMode != TlsMode.disable;
    final isTls = mode != TlsMode.disable;
    setState(() {
      // ClickHouse serves HTTPS on another port.
      if (wasTls != isTls && _port.text == '${_engine.portFor(tls: wasTls)}') {
        _port.text = '${_engine.portFor(tls: isTls)}';
      }
      _tlsMode = mode;
    });
  }

  bool get _usesPort => !(_engine == DatabaseEngine.mongodb && _srv);

  ConnectionConfig _buildConfig() {
    final host = _host.text.trim();
    final database = _database.text.trim();
    return ConnectionConfig(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _name.text.trim().isEmpty ? '$host/$database' : _name.text.trim(),
      engine: _engine,
      host: host,
      port: int.tryParse(_port.text.trim()) ?? _engine.defaultPort,
      database: database,
      username: _username.text.trim(),
      tlsMode: _tlsMode,
      color: _color,
      savePassword: _savePassword,
      options: {
        if (_engine == DatabaseEngine.mongodb) ...{
          if (_srv) 'srv': 'true',
          if (_authSource.text.trim().isNotEmpty)
            'authSource': _authSource.text.trim(),
          if (_params.text.trim().isNotEmpty) 'params': _params.text.trim(),
        },
      },
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
      _testLatency = null;
    });
    final driver = createDriver(_buildConfig());
    try {
      await driver.connect(await _effectivePassword());
      final latency = await driver.ping();
      _testOk = true;
      _testLatency = latency.inMilliseconds;
      _testMessage =
          'Connected to ${_host.text.trim()}:${_port.text.trim()}/${_database.text.trim()} successfully.';
    } catch (e) {
      _testOk = false;
      _testLatency = null;
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

    return Dialog(
      backgroundColor: scheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.sizeOf(context).height * 0.90,
        ),
        child: DefaultTabController(
          length: 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.dns_rounded,
                        size: 22,
                        color: Color(0xFF38BDF8),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _isEdit
                                    ? 'Edit Connection'
                                    : 'New Connection',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: const Color(0xFF0284C7)
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Text(
                                  _engine.label,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF38BDF8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isEdit
                                ? (widget.existing?.displayAddress ?? '')
                                : 'Configure database credentials and host',
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                      icon: const Icon(Icons.link_rounded, size: 15),
                      label: Text(
                        _showUrlInput ? 'Hide URL' : 'Paste URL',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () =>
                          setState(() => _showUrlInput = !_showUrlInput),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Quick URL import drawer
              if (_showUrlInput)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.link_rounded,
                              size: 15, color: scheme.primary),
                          const SizedBox(width: 6),
                          const Text(
                            'Quick Import from Connection URI',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _urlController,
                              style: monoStyle.copyWith(fontSize: 11.5),
                              decoration: InputDecoration(
                                hintText:
                                    'postgresql://…  mongodb+srv://…  redis://…  clickhouse://…',
                                hintStyle: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                border: const OutlineInputBorder(),
                                errorText: _urlError,
                              ),
                              onSubmitted: _parseConnectionUrl,
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () =>
                                _parseConnectionUrl(_urlController.text),
                            child: const Text('Parse'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              // Tabs Header
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: theme.dividerColor),
                  ),
                ),
                child: const TabBar(
                  tabAlignment: TabAlignment.start,
                  isScrollable: true,
                  tabs: [
                    Tab(
                      icon: Icon(Icons.tune_rounded, size: 16),
                      text: 'General',
                      height: 38,
                    ),
                    Tab(
                      icon: Icon(Icons.shield_outlined, size: 16),
                      text: 'Security & SSL',
                      height: 38,
                    ),
                  ],
                ),
              ),

              // Form tabs
              Flexible(
                child: Form(
                  key: _formKey,
                  child: TabBarView(
                    children: [
                      // TAB 1: General Settings
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!_isEdit) ...[
                              _EnginePicker(
                                selected: _engine,
                                onSelected: (engine) =>
                                    setState(() => _selectEngine(engine)),
                              ),
                              const SizedBox(height: 16),
                            ],
                            TextFormField(
                              controller: _name,
                              decoration: const InputDecoration(
                                labelText: 'Connection Name',
                                hintText:
                                    'e.g. Analytics Prod (defaults to host/database)',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 14),

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: _host,
                                    decoration: InputDecoration(
                                      labelText: 'Host / IP Address *',
                                      hintText: switch (_engine) {
                                        DatabaseEngine.mongodb when _srv =>
                                          'e.g. cluster0.abc.mongodb.net',
                                        DatabaseEngine.mongodb =>
                                          'e.g. localhost, or h1:27017,h2:27017',
                                        _ =>
                                          'e.g. localhost, 127.0.0.1, rds.aws.com',
                                      },
                                      isDense: true,
                                      border: const OutlineInputBorder(),
                                    ),
                                    validator: _required,
                                  ),
                                ),
                                if (_usesPort) ...[
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 1,
                                  child: TextFormField(
                                    controller: _port,
                                    decoration: InputDecoration(
                                      labelText: 'Port *',
                                      hintText: '${_engine.defaultPort}',
                                      isDense: true,
                                      border: const OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    validator: (v) {
                                      final port = int.tryParse(v ?? '');
                                      return port == null ||
                                              port < 1 ||
                                              port > 65535
                                          ? '1–65535'
                                          : null;
                                    },
                                  ),
                                ),
                                ],
                              ],
                            ),
                            if (_engine == DatabaseEngine.mongodb) ...[
                              const SizedBox(height: 6),
                              SwitchListTile(
                                value: _srv,
                                onChanged: (v) => setState(() => _srv = v),
                                title: const Text(
                                  'DNS seed list (mongodb+srv)',
                                  style: TextStyle(fontSize: 12.5),
                                ),
                                subtitle: const Text(
                                  'Atlas and other clusters published via DNS; '
                                  'no port needed',
                                  style: TextStyle(fontSize: 11),
                                ),
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                              ),
                            ],
                            const SizedBox(height: 14),

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _database,
                                    decoration: InputDecoration(
                                      labelText:
                                          _engine == DatabaseEngine.redis
                                          ? 'Database index *'
                                          : 'Database Name *',
                                      hintText:
                                          'e.g. ${_engine.defaultDatabase}',
                                      isDense: true,
                                      border: const OutlineInputBorder(),
                                    ),
                                    keyboardType:
                                        _engine == DatabaseEngine.redis
                                        ? TextInputType.number
                                        : null,
                                    validator: _engine == DatabaseEngine.redis
                                        ? (v) => int.tryParse(v ?? '') == null
                                              ? 'A number, e.g. 0'
                                              : null
                                        : _required,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: _username,
                                    decoration: InputDecoration(
                                      labelText: _engine.usernameOptional
                                          ? 'Username'
                                          : 'Username *',
                                      hintText: _engine.usernameOptional
                                          ? 'Leave empty if not required'
                                          : 'e.g. ${_engine.defaultUsername}',
                                      isDense: true,
                                      border: const OutlineInputBorder(),
                                    ),
                                    validator: _engine.usernameOptional
                                        ? null
                                        : _required,
                                  ),
                                ),
                              ],
                            ),
                            if (_engine == DatabaseEngine.mongodb) ...[
                              const SizedBox(height: 14),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _authSource,
                                      decoration: const InputDecoration(
                                        labelText: 'Auth database',
                                        hintText: 'admin',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: _params,
                                      style: monoStyle.copyWith(fontSize: 12),
                                      decoration: const InputDecoration(
                                        labelText: 'Extra options',
                                        hintText: 'replicaSet=rs0&w=majority',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 14),

                            TextFormField(
                              controller: _password,
                              obscureText: !_showPassword,
                              onChanged: (_) => _passwordTouched = true,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                hintText: _isEdit && widget.existing!.savePassword
                                    ? 'Saved in secure store (leave empty to keep)'
                                    : 'Enter database password',
                                isDense: true,
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _showPassword
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    size: 18,
                                  ),
                                  tooltip: _showPassword
                                      ? 'Hide password'
                                      : 'Show password',
                                  onPressed: () => setState(
                                    () => _showPassword = !_showPassword,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            CheckboxListTile(
                              value: _savePassword,
                              onChanged: (v) =>
                                  setState(() => _savePassword = v ?? true),
                              title: const Text(
                                'Save password in OS keychain',
                                style: TextStyle(fontSize: 12.5),
                              ),
                              subtitle: const Text(
                                'Credentials stored encrypted in platform secure vault',
                                style: TextStyle(fontSize: 11),
                              ),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              dense: true,
                            ),
                            const SizedBox(height: 10),

                            // Environment Tag
                            Row(
                              children: [
                                Text(
                                  'Environment Tag:',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Color(_color).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Color(_color).withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        width: 7,
                                        height: 7,
                                        decoration: BoxDecoration(
                                          color: Color(_color),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        envLabel,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(_color),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final color in connectionColors)
                                  InkWell(
                                    onTap: () => setState(() => _color = color),
                                    borderRadius: BorderRadius.circular(20),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _color == color
                                            ? Color(color).withValues(alpha: 0.18)
                                            : scheme.surfaceContainerLowest,
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: _color == color
                                              ? Color(color)
                                              : scheme.outlineVariant
                                                  .withValues(alpha: 0.6),
                                          width: _color == color ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircleAvatar(
                                            radius: 4.5,
                                            backgroundColor: Color(color),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            connectionColorLabels[color] ?? '',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: _color == color
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                              color: _color == color
                                                  ? Color(color)
                                                  : scheme.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // TAB 2: SSL & Security
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DropdownButtonFormField<TlsMode>(
                              // Rebuilt when a pasted URI changes the mode.
                              key: ValueKey(_tlsMode),
                              initialValue: _tlsMode,
                              decoration: const InputDecoration(
                                labelText: 'TLS / SSL Mode',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: [
                                for (final mode in TlsMode.values)
                                  DropdownMenuItem(
                                    value: mode,
                                    child: Row(
                                      children: [
                                        Icon(
                                          mode == TlsMode.disable
                                              ? Icons.lock_open_rounded
                                              : (mode == TlsMode.require
                                                  ? Icons.lock_outline_rounded
                                                  : Icons.verified_user_rounded),
                                          size: 16,
                                          color: mode == TlsMode.disable
                                              ? Colors.amber.shade700
                                              : (mode == TlsMode.require
                                                  ? const Color(0xFF0284C7)
                                                  : const Color(0xFF10B981)),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(mode.label),
                                      ],
                                    ),
                                  ),
                              ],
                              onChanged: (v) => _setTlsMode(v!),
                            ),
                            const SizedBox(height: 12),

                            // Explanatory card based on chosen TLS mode
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: scheme.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline_rounded,
                                        size: 15,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        switch (_tlsMode) {
                                          TlsMode.disable => 'Unencrypted (Plaintext)',
                                          TlsMode.require =>
                                            'Encrypted (No Verification)',
                                          TlsMode.verifyFull =>
                                            'Full TLS Verification',
                                        },
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    switch (_tlsMode) {
                                      TlsMode.disable =>
                                        'Data is sent unencrypted over the wire. Best for local development and private internal Docker networks.',
                                      TlsMode.require =>
                                        'Connection is encrypted using TLS/SSL, but the server certificate is not verified. Common for hosted providers (e.g. AWS RDS, Heroku, Supabase).',
                                      TlsMode.verifyFull =>
                                        'Connection is strictly verified against standard trusted Root Certificate Authorities. Fails if the server certificate is self-signed or invalid.',
                                    },
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: scheme.onSurfaceVariant,
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),

                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: 0.25),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(
                                    Icons.lock_rounded,
                                    size: 16,
                                    color: Color(0xFF10B981),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Security & Credentials Protection',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF10B981),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Passwords are encrypted and stored in your operating system keychain (Windows Credential Locker, macOS Keychain, or Linux Secret Service). Passwords never leave this computer.',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: scheme.onSurfaceVariant,
                                            height: 1.35,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Test Result Banner
              if (_testMessage != null) ...[
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _testOk
                        ? const Color(0xFF10B981).withValues(alpha: 0.12)
                        : scheme.errorContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _testOk
                          ? const Color(0xFF10B981).withValues(alpha: 0.4)
                          : scheme.error.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _testOk
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        size: 17,
                        color: _testOk ? const Color(0xFF10B981) : scheme.error,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _testOk
                                      ? 'Connection Succeeded'
                                      : 'Connection Failed',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _testOk
                                        ? const Color(0xFF10B981)
                                        : scheme.error,
                                  ),
                                ),
                                if (_testLatency != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'Ping: $_testLatency ms',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF10B981),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 2),
                            SelectableText(
                              _testMessage!,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: _testOk
                                    ? const Color(0xFF10B981)
                                    : scheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!_testOk)
                        IconButton(
                          icon: const Icon(Icons.copy, size: 14),
                          tooltip: 'Copy error message',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: _testMessage!),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Error copied to clipboard'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],

              const Divider(height: 1),

              // Actions Footer
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: _busy
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_rounded, size: 15),
                      label: const Text('Test Connection'),
                      onPressed: _busy ? null : _test,
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _save,
                      child: Text(
                        _isEdit ? 'Save Changes' : 'Create Connection',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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

/// [connectWithPrompt] for SQL work: null unless the engine is relational.
Future<SqlDriver?> connectSqlWithPrompt(
  BuildContext context,
  WidgetRef ref,
  ConnectionConfig config,
) async {
  final driver = await connectWithPrompt(context, ref, config);
  return driver is SqlDriver ? driver : null;
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

/// Grid of engine cards for a new connection. All drivers are built in.
class _EnginePicker extends StatelessWidget {
  const _EnginePicker({required this.selected, required this.onSelected});

  final DatabaseEngine selected;
  final ValueChanged<DatabaseEngine> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Database',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            // Two columns on narrow dialogs, four on wide ones.
            final columns = constraints.maxWidth < 440 ? 2 : 4;
            const gap = 8.0;
            final width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final engine in supportedEngines)
                  SizedBox(
                    width: width,
                    child: _EngineCard(
                      engine: engine,
                      selected: engine == selected,
                      onTap: () => onSelected(engine),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EngineCard extends StatelessWidget {
  const _EngineCard({
    required this.engine,
    required this.selected,
    required this.onTap,
  });

  final DatabaseEngine engine;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = engine.accent;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.12)
            : scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: selected ? accent : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(engine.icon, size: 20, color: accent),
                const SizedBox(height: 6),
                Text(
                  engine.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  engine.blurb,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
