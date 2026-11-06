import 'driver.dart';

/// Connection settings read from a pasted URI such as
/// `postgresql://user:pw@host:5432/db?sslmode=require` or
/// `mongodb+srv://user:pw@cluster.example.net/app?authSource=admin`.
class ParsedConnectionUri {
  const ParsedConnectionUri({
    required this.engine,
    required this.host,
    this.port,
    this.database,
    this.username,
    this.password,
    this.tlsMode,
    this.options = const {},
  });

  final DatabaseEngine engine;

  /// One host, or for MongoDB replica sets a `h1:27017,h2:27017` list.
  final String host;
  final int? port;
  final String? database;
  final String? username;
  final String? password;
  final TlsMode? tlsMode;
  final Map<String, String> options;
}

const _schemes = {
  'postgres': DatabaseEngine.postgres,
  'postgresql': DatabaseEngine.postgres,
  'clickhouse': DatabaseEngine.clickhouse,
  'mongodb': DatabaseEngine.mongodb,
  'mongodb+srv': DatabaseEngine.mongodb,
  'redis': DatabaseEngine.redis,
  'rediss': DatabaseEngine.redis,
};

/// Supported schemes, for messages.
String get supportedUriSchemes => _schemes.keys.map((s) => '$s://').join(', ');

/// Parses [text], throwing [FormatException] with a readable message.
///
/// Parsed by hand rather than with [Uri] because MongoDB allows several
/// comma-separated hosts, which [Uri] rejects.
ParsedConnectionUri parseConnectionUri(String text) {
  final match = RegExp(
    r'^([a-z][a-z0-9+]*)://' // scheme
    r'(?:([^:@/?]*)(?::([^@/?]*))?@)?' // user:password@
    r'([^/?#]*)' // host(s)
    r'(?:/([^?#]*))?' // /database
    r'(?:\?([^#]*))?' // ?options
    r'(?:#.*)?$',
    caseSensitive: false,
  ).firstMatch(text.trim());
  if (match == null) {
    throw const FormatException('Not a connection URI');
  }
  final scheme = match.group(1)!.toLowerCase();
  final engine = _schemes[scheme];
  if (engine == null) {
    throw FormatException(
      'Unsupported scheme "$scheme://". Use one of: $supportedUriSchemes',
    );
  }

  String? decode(String? s) =>
      s == null || s.isEmpty ? null : Uri.decodeComponent(s);
  final query = Uri.splitQueryString(match.group(6) ?? '');
  final hosts = match.group(4)!;
  if (hosts.isEmpty) throw const FormatException('The URI has no host');

  // A single host may carry a port; a host list stays as written.
  var host = hosts;
  int? port;
  if (!hosts.contains(',')) {
    final hostPort = RegExp(r'^(\[[^\]]+\]|[^:]+)(?::(\d+))?$')
        .firstMatch(hosts);
    if (hostPort == null) throw FormatException('Invalid host "$hosts"');
    host = hostPort.group(1)!;
    port = int.tryParse(hostPort.group(2) ?? '');
  }

  final path = decode(match.group(5));
  final options = <String, String>{};
  TlsMode? tls;
  String? database = path;

  switch (engine) {
    case DatabaseEngine.postgres:
      tls = switch (query['sslmode']?.toLowerCase()) {
        null => null,
        'disable' || 'allow' || 'prefer' => TlsMode.disable,
        'verify-ca' || 'verify-full' => TlsMode.verifyFull,
        _ => TlsMode.require,
      };
    case DatabaseEngine.clickhouse:
      database = path ?? query['database'];
      if (query['secure'] == 'true') tls = TlsMode.verifyFull;
    case DatabaseEngine.mongodb:
      if (scheme == 'mongodb+srv') {
        options['srv'] = 'true';
        // SRV implies TLS unless explicitly turned off.
        tls = TlsMode.verifyFull;
      }
      final rest = {...query};
      if (rest.remove('authSource') case final source?) {
        options['authSource'] = source;
      }
      for (final key in ['tls', 'ssl']) {
        switch (rest.remove(key)) {
          case 'true':
            tls = TlsMode.verifyFull;
          case 'false':
            tls = TlsMode.disable;
        }
      }
      if (rest.remove('tlsAllowInvalidCertificates') == 'true' ||
          rest.remove('tlsInsecure') == 'true') {
        tls = TlsMode.require;
      }
      if (rest.isNotEmpty) {
        options['params'] = rest.entries
            .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
            .join('&');
      }
    case DatabaseEngine.redis:
      if (scheme == 'rediss') tls = TlsMode.verifyFull;
      if (path != null && int.tryParse(path) == null) {
        throw FormatException('Redis database must be a number, not "$path"');
      }
  }

  return ParsedConnectionUri(
    engine: engine,
    host: host,
    port: port,
    database: database,
    username: decode(match.group(2)),
    password: decode(match.group(3)),
    tlsMode: tls,
    options: options,
  );
}
