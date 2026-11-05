// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ConnectionsTable extends Connections
    with TableInfo<$ConnectionsTable, ConnectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ConnectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _engineMeta = const VerificationMeta('engine');
  @override
  late final GeneratedColumn<String> engine = GeneratedColumn<String>(
    'engine',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _databaseMeta = const VerificationMeta(
    'database',
  );
  @override
  late final GeneratedColumn<String> database = GeneratedColumn<String>(
    'database',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tlsModeMeta = const VerificationMeta(
    'tlsMode',
  );
  @override
  late final GeneratedColumn<String> tlsMode = GeneratedColumn<String>(
    'tls_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorMeta = const VerificationMeta('color');
  @override
  late final GeneratedColumn<int> color = GeneratedColumn<int>(
    'color',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savePasswordMeta = const VerificationMeta(
    'savePassword',
  );
  @override
  late final GeneratedColumn<bool> savePassword = GeneratedColumn<bool>(
    'save_password',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("save_password" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    engine,
    host,
    port,
    database,
    username,
    tlsMode,
    color,
    savePassword,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'connections';
  @override
  VerificationContext validateIntegrity(
    Insertable<ConnectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('engine')) {
      context.handle(
        _engineMeta,
        engine.isAcceptableOrUnknown(data['engine']!, _engineMeta),
      );
    } else if (isInserting) {
      context.missing(_engineMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('database')) {
      context.handle(
        _databaseMeta,
        database.isAcceptableOrUnknown(data['database']!, _databaseMeta),
      );
    } else if (isInserting) {
      context.missing(_databaseMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('tls_mode')) {
      context.handle(
        _tlsModeMeta,
        tlsMode.isAcceptableOrUnknown(data['tls_mode']!, _tlsModeMeta),
      );
    } else if (isInserting) {
      context.missing(_tlsModeMeta);
    }
    if (data.containsKey('color')) {
      context.handle(
        _colorMeta,
        color.isAcceptableOrUnknown(data['color']!, _colorMeta),
      );
    } else if (isInserting) {
      context.missing(_colorMeta);
    }
    if (data.containsKey('save_password')) {
      context.handle(
        _savePasswordMeta,
        savePassword.isAcceptableOrUnknown(
          data['save_password']!,
          _savePasswordMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ConnectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ConnectionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      engine: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}engine'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      database: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}database'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      tlsMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tls_mode'],
      )!,
      color: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color'],
      )!,
      savePassword: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}save_password'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $ConnectionsTable createAlias(String alias) {
    return $ConnectionsTable(attachedDatabase, alias);
  }
}

class ConnectionRow extends DataClass implements Insertable<ConnectionRow> {
  final String id;
  final String name;
  final String engine;
  final String host;
  final int port;
  final String database;
  final String username;
  final String tlsMode;
  final int color;
  final bool savePassword;
  final DateTime createdAt;
  const ConnectionRow({
    required this.id,
    required this.name,
    required this.engine,
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.tlsMode,
    required this.color,
    required this.savePassword,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['engine'] = Variable<String>(engine);
    map['host'] = Variable<String>(host);
    map['port'] = Variable<int>(port);
    map['database'] = Variable<String>(database);
    map['username'] = Variable<String>(username);
    map['tls_mode'] = Variable<String>(tlsMode);
    map['color'] = Variable<int>(color);
    map['save_password'] = Variable<bool>(savePassword);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  ConnectionsCompanion toCompanion(bool nullToAbsent) {
    return ConnectionsCompanion(
      id: Value(id),
      name: Value(name),
      engine: Value(engine),
      host: Value(host),
      port: Value(port),
      database: Value(database),
      username: Value(username),
      tlsMode: Value(tlsMode),
      color: Value(color),
      savePassword: Value(savePassword),
      createdAt: Value(createdAt),
    );
  }

  factory ConnectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ConnectionRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      engine: serializer.fromJson<String>(json['engine']),
      host: serializer.fromJson<String>(json['host']),
      port: serializer.fromJson<int>(json['port']),
      database: serializer.fromJson<String>(json['database']),
      username: serializer.fromJson<String>(json['username']),
      tlsMode: serializer.fromJson<String>(json['tlsMode']),
      color: serializer.fromJson<int>(json['color']),
      savePassword: serializer.fromJson<bool>(json['savePassword']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'engine': serializer.toJson<String>(engine),
      'host': serializer.toJson<String>(host),
      'port': serializer.toJson<int>(port),
      'database': serializer.toJson<String>(database),
      'username': serializer.toJson<String>(username),
      'tlsMode': serializer.toJson<String>(tlsMode),
      'color': serializer.toJson<int>(color),
      'savePassword': serializer.toJson<bool>(savePassword),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  ConnectionRow copyWith({
    String? id,
    String? name,
    String? engine,
    String? host,
    int? port,
    String? database,
    String? username,
    String? tlsMode,
    int? color,
    bool? savePassword,
    DateTime? createdAt,
  }) => ConnectionRow(
    id: id ?? this.id,
    name: name ?? this.name,
    engine: engine ?? this.engine,
    host: host ?? this.host,
    port: port ?? this.port,
    database: database ?? this.database,
    username: username ?? this.username,
    tlsMode: tlsMode ?? this.tlsMode,
    color: color ?? this.color,
    savePassword: savePassword ?? this.savePassword,
    createdAt: createdAt ?? this.createdAt,
  );
  ConnectionRow copyWithCompanion(ConnectionsCompanion data) {
    return ConnectionRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      engine: data.engine.present ? data.engine.value : this.engine,
      host: data.host.present ? data.host.value : this.host,
      port: data.port.present ? data.port.value : this.port,
      database: data.database.present ? data.database.value : this.database,
      username: data.username.present ? data.username.value : this.username,
      tlsMode: data.tlsMode.present ? data.tlsMode.value : this.tlsMode,
      color: data.color.present ? data.color.value : this.color,
      savePassword: data.savePassword.present
          ? data.savePassword.value
          : this.savePassword,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ConnectionRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('engine: $engine, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('database: $database, ')
          ..write('username: $username, ')
          ..write('tlsMode: $tlsMode, ')
          ..write('color: $color, ')
          ..write('savePassword: $savePassword, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    engine,
    host,
    port,
    database,
    username,
    tlsMode,
    color,
    savePassword,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ConnectionRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.engine == this.engine &&
          other.host == this.host &&
          other.port == this.port &&
          other.database == this.database &&
          other.username == this.username &&
          other.tlsMode == this.tlsMode &&
          other.color == this.color &&
          other.savePassword == this.savePassword &&
          other.createdAt == this.createdAt);
}

class ConnectionsCompanion extends UpdateCompanion<ConnectionRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> engine;
  final Value<String> host;
  final Value<int> port;
  final Value<String> database;
  final Value<String> username;
  final Value<String> tlsMode;
  final Value<int> color;
  final Value<bool> savePassword;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const ConnectionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.engine = const Value.absent(),
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    this.database = const Value.absent(),
    this.username = const Value.absent(),
    this.tlsMode = const Value.absent(),
    this.color = const Value.absent(),
    this.savePassword = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ConnectionsCompanion.insert({
    required String id,
    required String name,
    required String engine,
    required String host,
    required int port,
    required String database,
    required String username,
    required String tlsMode,
    required int color,
    this.savePassword = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       engine = Value(engine),
       host = Value(host),
       port = Value(port),
       database = Value(database),
       username = Value(username),
       tlsMode = Value(tlsMode),
       color = Value(color);
  static Insertable<ConnectionRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? engine,
    Expression<String>? host,
    Expression<int>? port,
    Expression<String>? database,
    Expression<String>? username,
    Expression<String>? tlsMode,
    Expression<int>? color,
    Expression<bool>? savePassword,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (engine != null) 'engine': engine,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (database != null) 'database': database,
      if (username != null) 'username': username,
      if (tlsMode != null) 'tls_mode': tlsMode,
      if (color != null) 'color': color,
      if (savePassword != null) 'save_password': savePassword,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ConnectionsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? engine,
    Value<String>? host,
    Value<int>? port,
    Value<String>? database,
    Value<String>? username,
    Value<String>? tlsMode,
    Value<int>? color,
    Value<bool>? savePassword,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return ConnectionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      engine: engine ?? this.engine,
      host: host ?? this.host,
      port: port ?? this.port,
      database: database ?? this.database,
      username: username ?? this.username,
      tlsMode: tlsMode ?? this.tlsMode,
      color: color ?? this.color,
      savePassword: savePassword ?? this.savePassword,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (engine.present) {
      map['engine'] = Variable<String>(engine.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (database.present) {
      map['database'] = Variable<String>(database.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (tlsMode.present) {
      map['tls_mode'] = Variable<String>(tlsMode.value);
    }
    if (color.present) {
      map['color'] = Variable<int>(color.value);
    }
    if (savePassword.present) {
      map['save_password'] = Variable<bool>(savePassword.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ConnectionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('engine: $engine, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('database: $database, ')
          ..write('username: $username, ')
          ..write('tlsMode: $tlsMode, ')
          ..write('color: $color, ')
          ..write('savePassword: $savePassword, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QueryHistoryTable extends QueryHistory
    with TableInfo<$QueryHistoryTable, HistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueryHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _connectionIdMeta = const VerificationMeta(
    'connectionId',
  );
  @override
  late final GeneratedColumn<String> connectionId = GeneratedColumn<String>(
    'connection_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES connections (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _sqlMeta = const VerificationMeta('sql');
  @override
  late final GeneratedColumn<String> sql = GeneratedColumn<String>(
    'sql',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _executedAtMeta = const VerificationMeta(
    'executedAt',
  );
  @override
  late final GeneratedColumn<DateTime> executedAt = GeneratedColumn<DateTime>(
    'executed_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _durationMsMeta = const VerificationMeta(
    'durationMs',
  );
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
    'duration_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rowCountMeta = const VerificationMeta(
    'rowCount',
  );
  @override
  late final GeneratedColumn<int> rowCount = GeneratedColumn<int>(
    'row_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorMeta = const VerificationMeta('error');
  @override
  late final GeneratedColumn<String> error = GeneratedColumn<String>(
    'error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    connectionId,
    sql,
    executedAt,
    durationMs,
    rowCount,
    error,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'query_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('connection_id')) {
      context.handle(
        _connectionIdMeta,
        connectionId.isAcceptableOrUnknown(
          data['connection_id']!,
          _connectionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_connectionIdMeta);
    }
    if (data.containsKey('sql')) {
      context.handle(
        _sqlMeta,
        sql.isAcceptableOrUnknown(data['sql']!, _sqlMeta),
      );
    } else if (isInserting) {
      context.missing(_sqlMeta);
    }
    if (data.containsKey('executed_at')) {
      context.handle(
        _executedAtMeta,
        executedAt.isAcceptableOrUnknown(data['executed_at']!, _executedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_executedAtMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
        _durationMsMeta,
        durationMs.isAcceptableOrUnknown(data['duration_ms']!, _durationMsMeta),
      );
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('row_count')) {
      context.handle(
        _rowCountMeta,
        rowCount.isAcceptableOrUnknown(data['row_count']!, _rowCountMeta),
      );
    }
    if (data.containsKey('error')) {
      context.handle(
        _errorMeta,
        error.isAcceptableOrUnknown(data['error']!, _errorMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      connectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}connection_id'],
      )!,
      sql: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sql'],
      )!,
      executedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}executed_at'],
      )!,
      durationMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_ms'],
      )!,
      rowCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}row_count'],
      ),
      error: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error'],
      ),
    );
  }

  @override
  $QueryHistoryTable createAlias(String alias) {
    return $QueryHistoryTable(attachedDatabase, alias);
  }
}

class HistoryRow extends DataClass implements Insertable<HistoryRow> {
  final int id;
  final String connectionId;
  final String sql;
  final DateTime executedAt;
  final int durationMs;
  final int? rowCount;
  final String? error;
  const HistoryRow({
    required this.id,
    required this.connectionId,
    required this.sql,
    required this.executedAt,
    required this.durationMs,
    this.rowCount,
    this.error,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['connection_id'] = Variable<String>(connectionId);
    map['sql'] = Variable<String>(sql);
    map['executed_at'] = Variable<DateTime>(executedAt);
    map['duration_ms'] = Variable<int>(durationMs);
    if (!nullToAbsent || rowCount != null) {
      map['row_count'] = Variable<int>(rowCount);
    }
    if (!nullToAbsent || error != null) {
      map['error'] = Variable<String>(error);
    }
    return map;
  }

  QueryHistoryCompanion toCompanion(bool nullToAbsent) {
    return QueryHistoryCompanion(
      id: Value(id),
      connectionId: Value(connectionId),
      sql: Value(sql),
      executedAt: Value(executedAt),
      durationMs: Value(durationMs),
      rowCount: rowCount == null && nullToAbsent
          ? const Value.absent()
          : Value(rowCount),
      error: error == null && nullToAbsent
          ? const Value.absent()
          : Value(error),
    );
  }

  factory HistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryRow(
      id: serializer.fromJson<int>(json['id']),
      connectionId: serializer.fromJson<String>(json['connectionId']),
      sql: serializer.fromJson<String>(json['sql']),
      executedAt: serializer.fromJson<DateTime>(json['executedAt']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      rowCount: serializer.fromJson<int?>(json['rowCount']),
      error: serializer.fromJson<String?>(json['error']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'connectionId': serializer.toJson<String>(connectionId),
      'sql': serializer.toJson<String>(sql),
      'executedAt': serializer.toJson<DateTime>(executedAt),
      'durationMs': serializer.toJson<int>(durationMs),
      'rowCount': serializer.toJson<int?>(rowCount),
      'error': serializer.toJson<String?>(error),
    };
  }

  HistoryRow copyWith({
    int? id,
    String? connectionId,
    String? sql,
    DateTime? executedAt,
    int? durationMs,
    Value<int?> rowCount = const Value.absent(),
    Value<String?> error = const Value.absent(),
  }) => HistoryRow(
    id: id ?? this.id,
    connectionId: connectionId ?? this.connectionId,
    sql: sql ?? this.sql,
    executedAt: executedAt ?? this.executedAt,
    durationMs: durationMs ?? this.durationMs,
    rowCount: rowCount.present ? rowCount.value : this.rowCount,
    error: error.present ? error.value : this.error,
  );
  HistoryRow copyWithCompanion(QueryHistoryCompanion data) {
    return HistoryRow(
      id: data.id.present ? data.id.value : this.id,
      connectionId: data.connectionId.present
          ? data.connectionId.value
          : this.connectionId,
      sql: data.sql.present ? data.sql.value : this.sql,
      executedAt: data.executedAt.present
          ? data.executedAt.value
          : this.executedAt,
      durationMs: data.durationMs.present
          ? data.durationMs.value
          : this.durationMs,
      rowCount: data.rowCount.present ? data.rowCount.value : this.rowCount,
      error: data.error.present ? data.error.value : this.error,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryRow(')
          ..write('id: $id, ')
          ..write('connectionId: $connectionId, ')
          ..write('sql: $sql, ')
          ..write('executedAt: $executedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('rowCount: $rowCount, ')
          ..write('error: $error')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    connectionId,
    sql,
    executedAt,
    durationMs,
    rowCount,
    error,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryRow &&
          other.id == this.id &&
          other.connectionId == this.connectionId &&
          other.sql == this.sql &&
          other.executedAt == this.executedAt &&
          other.durationMs == this.durationMs &&
          other.rowCount == this.rowCount &&
          other.error == this.error);
}

class QueryHistoryCompanion extends UpdateCompanion<HistoryRow> {
  final Value<int> id;
  final Value<String> connectionId;
  final Value<String> sql;
  final Value<DateTime> executedAt;
  final Value<int> durationMs;
  final Value<int?> rowCount;
  final Value<String?> error;
  const QueryHistoryCompanion({
    this.id = const Value.absent(),
    this.connectionId = const Value.absent(),
    this.sql = const Value.absent(),
    this.executedAt = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.rowCount = const Value.absent(),
    this.error = const Value.absent(),
  });
  QueryHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String connectionId,
    required String sql,
    required DateTime executedAt,
    required int durationMs,
    this.rowCount = const Value.absent(),
    this.error = const Value.absent(),
  }) : connectionId = Value(connectionId),
       sql = Value(sql),
       executedAt = Value(executedAt),
       durationMs = Value(durationMs);
  static Insertable<HistoryRow> custom({
    Expression<int>? id,
    Expression<String>? connectionId,
    Expression<String>? sql,
    Expression<DateTime>? executedAt,
    Expression<int>? durationMs,
    Expression<int>? rowCount,
    Expression<String>? error,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (connectionId != null) 'connection_id': connectionId,
      if (sql != null) 'sql': sql,
      if (executedAt != null) 'executed_at': executedAt,
      if (durationMs != null) 'duration_ms': durationMs,
      if (rowCount != null) 'row_count': rowCount,
      if (error != null) 'error': error,
    });
  }

  QueryHistoryCompanion copyWith({
    Value<int>? id,
    Value<String>? connectionId,
    Value<String>? sql,
    Value<DateTime>? executedAt,
    Value<int>? durationMs,
    Value<int?>? rowCount,
    Value<String?>? error,
  }) {
    return QueryHistoryCompanion(
      id: id ?? this.id,
      connectionId: connectionId ?? this.connectionId,
      sql: sql ?? this.sql,
      executedAt: executedAt ?? this.executedAt,
      durationMs: durationMs ?? this.durationMs,
      rowCount: rowCount ?? this.rowCount,
      error: error ?? this.error,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (connectionId.present) {
      map['connection_id'] = Variable<String>(connectionId.value);
    }
    if (sql.present) {
      map['sql'] = Variable<String>(sql.value);
    }
    if (executedAt.present) {
      map['executed_at'] = Variable<DateTime>(executedAt.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (rowCount.present) {
      map['row_count'] = Variable<int>(rowCount.value);
    }
    if (error.present) {
      map['error'] = Variable<String>(error.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueryHistoryCompanion(')
          ..write('id: $id, ')
          ..write('connectionId: $connectionId, ')
          ..write('sql: $sql, ')
          ..write('executedAt: $executedAt, ')
          ..write('durationMs: $durationMs, ')
          ..write('rowCount: $rowCount, ')
          ..write('error: $error')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ConnectionsTable connections = $ConnectionsTable(this);
  late final $QueryHistoryTable queryHistory = $QueryHistoryTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    connections,
    queryHistory,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'connections',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('query_history', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$ConnectionsTableCreateCompanionBuilder =
    ConnectionsCompanion Function({
      required String id,
      required String name,
      required String engine,
      required String host,
      required int port,
      required String database,
      required String username,
      required String tlsMode,
      required int color,
      Value<bool> savePassword,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$ConnectionsTableUpdateCompanionBuilder =
    ConnectionsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> engine,
      Value<String> host,
      Value<int> port,
      Value<String> database,
      Value<String> username,
      Value<String> tlsMode,
      Value<int> color,
      Value<bool> savePassword,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$ConnectionsTableReferences
    extends BaseReferences<_$AppDatabase, $ConnectionsTable, ConnectionRow> {
  $$ConnectionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$QueryHistoryTable, List<HistoryRow>>
  _queryHistoryRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.queryHistory,
    aliasName: 'connections__id__query_history__connection_id',
  );

  $$QueryHistoryTableProcessedTableManager get queryHistoryRefs {
    final manager = $$QueryHistoryTableTableManager(
      $_db,
      $_db.queryHistory,
    ).filter((f) => f.connectionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_queryHistoryRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ConnectionsTableFilterComposer
    extends Composer<_$AppDatabase, $ConnectionsTable> {
  $$ConnectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get engine => $composableBuilder(
    column: $table.engine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get database => $composableBuilder(
    column: $table.database,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tlsMode => $composableBuilder(
    column: $table.tlsMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get savePassword => $composableBuilder(
    column: $table.savePassword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> queryHistoryRefs(
    Expression<bool> Function($$QueryHistoryTableFilterComposer f) f,
  ) {
    final $$QueryHistoryTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.queryHistory,
      getReferencedColumn: (t) => t.connectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$QueryHistoryTableFilterComposer(
            $db: $db,
            $table: $db.queryHistory,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConnectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $ConnectionsTable> {
  $$ConnectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get engine => $composableBuilder(
    column: $table.engine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get database => $composableBuilder(
    column: $table.database,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tlsMode => $composableBuilder(
    column: $table.tlsMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get color => $composableBuilder(
    column: $table.color,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get savePassword => $composableBuilder(
    column: $table.savePassword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ConnectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ConnectionsTable> {
  $$ConnectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get engine =>
      $composableBuilder(column: $table.engine, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get database =>
      $composableBuilder(column: $table.database, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get tlsMode =>
      $composableBuilder(column: $table.tlsMode, builder: (column) => column);

  GeneratedColumn<int> get color =>
      $composableBuilder(column: $table.color, builder: (column) => column);

  GeneratedColumn<bool> get savePassword => $composableBuilder(
    column: $table.savePassword,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> queryHistoryRefs<T extends Object>(
    Expression<T> Function($$QueryHistoryTableAnnotationComposer a) f,
  ) {
    final $$QueryHistoryTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.queryHistory,
      getReferencedColumn: (t) => t.connectionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$QueryHistoryTableAnnotationComposer(
            $db: $db,
            $table: $db.queryHistory,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ConnectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ConnectionsTable,
          ConnectionRow,
          $$ConnectionsTableFilterComposer,
          $$ConnectionsTableOrderingComposer,
          $$ConnectionsTableAnnotationComposer,
          $$ConnectionsTableCreateCompanionBuilder,
          $$ConnectionsTableUpdateCompanionBuilder,
          (ConnectionRow, $$ConnectionsTableReferences),
          ConnectionRow,
          PrefetchHooks Function({bool queryHistoryRefs})
        > {
  $$ConnectionsTableTableManager(_$AppDatabase db, $ConnectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ConnectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ConnectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ConnectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> engine = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String> database = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> tlsMode = const Value.absent(),
                Value<int> color = const Value.absent(),
                Value<bool> savePassword = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConnectionsCompanion(
                id: id,
                name: name,
                engine: engine,
                host: host,
                port: port,
                database: database,
                username: username,
                tlsMode: tlsMode,
                color: color,
                savePassword: savePassword,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String engine,
                required String host,
                required int port,
                required String database,
                required String username,
                required String tlsMode,
                required int color,
                Value<bool> savePassword = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ConnectionsCompanion.insert(
                id: id,
                name: name,
                engine: engine,
                host: host,
                port: port,
                database: database,
                username: username,
                tlsMode: tlsMode,
                color: color,
                savePassword: savePassword,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ConnectionsTable, ConnectionRow>(table),
                  $$ConnectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({queryHistoryRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (queryHistoryRefs) db.queryHistory],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (queryHistoryRefs)
                    await $_getPrefetchedDataByColumns<
                      ConnectionRow,
                      $ConnectionsTable,
                      HistoryRow,
                      $QueryHistoryTable
                    >(
                      currentTable: table,
                      referencedTable: $$ConnectionsTableReferences
                          ._queryHistoryRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$ConnectionsTableReferences(
                            db,
                            table,
                            p0,
                          ).queryHistoryRefs,
                      currentColumn: 'id',
                      referencedColumn: 'connection_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$ConnectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ConnectionsTable,
      ConnectionRow,
      $$ConnectionsTableFilterComposer,
      $$ConnectionsTableOrderingComposer,
      $$ConnectionsTableAnnotationComposer,
      $$ConnectionsTableCreateCompanionBuilder,
      $$ConnectionsTableUpdateCompanionBuilder,
      (ConnectionRow, $$ConnectionsTableReferences),
      ConnectionRow,
      PrefetchHooks Function({bool queryHistoryRefs})
    >;
typedef $$QueryHistoryTableCreateCompanionBuilder =
    QueryHistoryCompanion Function({
      Value<int> id,
      required String connectionId,
      required String sql,
      required DateTime executedAt,
      required int durationMs,
      Value<int?> rowCount,
      Value<String?> error,
    });
typedef $$QueryHistoryTableUpdateCompanionBuilder =
    QueryHistoryCompanion Function({
      Value<int> id,
      Value<String> connectionId,
      Value<String> sql,
      Value<DateTime> executedAt,
      Value<int> durationMs,
      Value<int?> rowCount,
      Value<String?> error,
    });

final class $$QueryHistoryTableReferences
    extends BaseReferences<_$AppDatabase, $QueryHistoryTable, HistoryRow> {
  $$QueryHistoryTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ConnectionsTable _connectionIdTable(_$AppDatabase db) => db
      .connections
      .createAlias('query_history__connection_id__connections__id');

  $$ConnectionsTableProcessedTableManager get connectionId {
    final $_column = $_itemColumn<String>('connection_id')!;

    final manager = $$ConnectionsTableTableManager(
      $_db,
      $_db.connections,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_connectionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$QueryHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $QueryHistoryTable> {
  $$QueryHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sql => $composableBuilder(
    column: $table.sql,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get executedAt => $composableBuilder(
    column: $table.executedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rowCount => $composableBuilder(
    column: $table.rowCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnFilters(column),
  );

  $$ConnectionsTableFilterComposer get connectionId {
    final $$ConnectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.connectionId,
      referencedTable: $db.connections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConnectionsTableFilterComposer(
            $db: $db,
            $table: $db.connections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QueryHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $QueryHistoryTable> {
  $$QueryHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sql => $composableBuilder(
    column: $table.sql,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get executedAt => $composableBuilder(
    column: $table.executedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rowCount => $composableBuilder(
    column: $table.rowCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get error => $composableBuilder(
    column: $table.error,
    builder: (column) => ColumnOrderings(column),
  );

  $$ConnectionsTableOrderingComposer get connectionId {
    final $$ConnectionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.connectionId,
      referencedTable: $db.connections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConnectionsTableOrderingComposer(
            $db: $db,
            $table: $db.connections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QueryHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $QueryHistoryTable> {
  $$QueryHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get sql =>
      $composableBuilder(column: $table.sql, builder: (column) => column);

  GeneratedColumn<DateTime> get executedAt => $composableBuilder(
    column: $table.executedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get durationMs => $composableBuilder(
    column: $table.durationMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rowCount =>
      $composableBuilder(column: $table.rowCount, builder: (column) => column);

  GeneratedColumn<String> get error =>
      $composableBuilder(column: $table.error, builder: (column) => column);

  $$ConnectionsTableAnnotationComposer get connectionId {
    final $$ConnectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.connectionId,
      referencedTable: $db.connections,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ConnectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.connections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QueryHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $QueryHistoryTable,
          HistoryRow,
          $$QueryHistoryTableFilterComposer,
          $$QueryHistoryTableOrderingComposer,
          $$QueryHistoryTableAnnotationComposer,
          $$QueryHistoryTableCreateCompanionBuilder,
          $$QueryHistoryTableUpdateCompanionBuilder,
          (HistoryRow, $$QueryHistoryTableReferences),
          HistoryRow,
          PrefetchHooks Function({bool connectionId})
        > {
  $$QueryHistoryTableTableManager(_$AppDatabase db, $QueryHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueryHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueryHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueryHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> connectionId = const Value.absent(),
                Value<String> sql = const Value.absent(),
                Value<DateTime> executedAt = const Value.absent(),
                Value<int> durationMs = const Value.absent(),
                Value<int?> rowCount = const Value.absent(),
                Value<String?> error = const Value.absent(),
              }) => QueryHistoryCompanion(
                id: id,
                connectionId: connectionId,
                sql: sql,
                executedAt: executedAt,
                durationMs: durationMs,
                rowCount: rowCount,
                error: error,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String connectionId,
                required String sql,
                required DateTime executedAt,
                required int durationMs,
                Value<int?> rowCount = const Value.absent(),
                Value<String?> error = const Value.absent(),
              }) => QueryHistoryCompanion.insert(
                id: id,
                connectionId: connectionId,
                sql: sql,
                executedAt: executedAt,
                durationMs: durationMs,
                rowCount: rowCount,
                error: error,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$QueryHistoryTable, HistoryRow>(table),
                  $$QueryHistoryTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({connectionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (connectionId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.connectionId,
                        referencedTable: $$QueryHistoryTableReferences
                            ._connectionIdTable(db),
                        referencedColumn: $$QueryHistoryTableReferences
                            ._connectionIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$QueryHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $QueryHistoryTable,
      HistoryRow,
      $$QueryHistoryTableFilterComposer,
      $$QueryHistoryTableOrderingComposer,
      $$QueryHistoryTableAnnotationComposer,
      $$QueryHistoryTableCreateCompanionBuilder,
      $$QueryHistoryTableUpdateCompanionBuilder,
      (HistoryRow, $$QueryHistoryTableReferences),
      HistoryRow,
      PrefetchHooks Function({bool connectionId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ConnectionsTableTableManager get connections =>
      $$ConnectionsTableTableManager(_db, _db.connections);
  $$QueryHistoryTableTableManager get queryHistory =>
      $$QueryHistoryTableTableManager(_db, _db.queryHistory);
}
