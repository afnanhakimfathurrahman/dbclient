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
  final _urlController = TextEditingController();

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
    final text = url.trim();
    if (text.isEmpty) return;

    try {
      final uri = Uri.parse(text);
      if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
        setState(() => _urlError = 'Scheme must be postgres:// or postgresql://');
        return;
      }

      if (uri.host.isNotEmpty) {
        _host.text = uri.host;
      }
      if (uri.hasPort && uri.port > 0) {
        _port.text = uri.port.toString();
      } else {
        _port.text = '5432';
      }
      if (uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty) {
        _database.text = uri.pathSegments.first;
      }
      if (uri.userInfo.isNotEmpty) {
        final parts = uri.userInfo.split(':');
        _username.text = Uri.decodeComponent(parts.first);
        if (parts.length > 1) {
          _password.text = Uri.decodeComponent(parts.sublist(1).join(':'));
          _passwordTouched = true;
        }
      }

      final sslmode = uri.queryParameters['sslmode']?.toLowerCase();
      if (sslmode != null) {
        if (sslmode == 'disable') {
          _tlsMode = TlsMode.disable;
        } else if (sslmode == 'verify-full' || sslmode == 'verify-ca') {
          _tlsMode = TlsMode.verifyFull;
        } else {
          _tlsMode = TlsMode.require;
        }
      }

      if (_name.text.isEmpty && _host.text.isNotEmpty && _database.text.isNotEmpty) {
        _name.text = '${_host.text}/${_database.text}';
      }

      setState(() {
        _showUrlInput = false;
        _urlError = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connection parameters populated from URL'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      setState(() => _urlError = 'Invalid connection URI format');
    }
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
                                child: const Text(
                                  'PostgreSQL',
                                  style: TextStyle(
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
                                    'postgresql://user:password@localhost:5432/dbname?sslmode=disable',
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
                                    decoration: const InputDecoration(
                                      labelText: 'Host / IP Address *',
                                      hintText: 'e.g. localhost, 127.0.0.1, rds.aws.com',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: _required,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  flex: 1,
                                  child: TextFormField(
                                    controller: _port,
                                    decoration: const InputDecoration(
                                      labelText: 'Port *',
                                      hintText: '5432',
                                      isDense: true,
                                      border: OutlineInputBorder(),
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
                            ),
                            const SizedBox(height: 14),

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _database,
                                    decoration: const InputDecoration(
                                      labelText: 'Database Name *',
                                      hintText: 'e.g. postgres',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: _required,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: _username,
                                    decoration: const InputDecoration(
                                      labelText: 'Username *',
                                      hintText: 'e.g. postgres',
                                      isDense: true,
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: _required,
                                  ),
                                ),
                              ],
                            ),
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
                              onChanged: (v) => setState(() => _tlsMode = v!),
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
