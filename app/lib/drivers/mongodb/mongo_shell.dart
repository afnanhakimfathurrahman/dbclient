/// A mongosh-style query language for the MongoDB editor:
/// `db.users.find({ age: { $gt: 18 } }).sort({ name: 1 }).limit(10)`.
///
/// [splitMongoScript] cuts a script into statements, [parseMongoStatement]
/// reads one into a [MongoStatement], and [runMongoStatement] translates it
/// into database commands (`find`, `aggregate`, `insert`…) run through
/// [DocumentDriver.runCommand]. Values use [parseMongo]'s syntax.
library;

import 'package:mongo_dart/mongo_dart.dart' show ObjectId;

import '../document.dart';
import '../driver.dart';
import 'mongo_json.dart';

/// One statement of a script and where it is in the text.
class MongoScriptStatement {
  const MongoScriptStatement(this.text, this.start, this.end);

  final String text;
  final int start;
  final int end;
}

/// A call or property in a `db.…` chain: `find({…})` has [args] text,
/// `users` (a property) has null.
class MongoCall {
  const MongoCall(this.name, [this.args]);

  final String name;

  /// The text between the parentheses; null for a property.
  final String? args;

  bool get isCall => args != null;
}

/// A parsed statement: `show …`, `use …`, or a `db.…` chain.
sealed class MongoStatement {
  const MongoStatement();
}

/// `show collections`, `show dbs`…
class MongoShow extends MongoStatement {
  const MongoShow(this.what);

  final String what;
}

/// `use otherdb`.
class MongoUse extends MongoStatement {
  const MongoUse(this.database);

  final String database;
}

/// `db.<method>(…)` with no collection, e.g. `db.runCommand({…})`.
class MongoDbCall extends MongoStatement {
  const MongoDbCall(this.method, this.args);

  final String method;
  final List<Object?> args;
}

/// `db.<collection>.<method>(…)` and chained cursor calls:
/// `.sort(…).skip(…).limit(…)`.
class MongoCollectionCall extends MongoStatement {
  const MongoCollectionCall(
    this.collection,
    this.method,
    this.args, [
    this.chain = const [],
  ]);

  final String collection;
  final String method;
  final List<Object?> args;
  final List<(String method, List<Object?> args)> chain;
}

/// Splits [script] into statements at `;` and at line breaks between
/// statements (a line starting with `.` continues the previous one).
/// Comment-only parts are dropped.
List<MongoScriptStatement> splitMongoScript(String script) {
  final out = <MongoScriptStatement>[];
  final scanner = _Scanner(script);
  var start = 0;

  void add(int end) {
    final text = script.substring(start, end);
    // Comments are blanked to spaces, so offsets match [text].
    final code = _stripComments(text);
    if (code.trim().isEmpty) return;
    // Blank lines and comments around the statement are not part of it.
    final lead = _leadingIgnorable(text);
    final tail = code.trimRight().length;
    out.add(
      MongoScriptStatement(
        text.substring(lead, tail),
        start + lead,
        start + tail,
      ),
    );
  }

  while (!scanner.atEnd) {
    final c = scanner.char;
    if (scanner.skipStringOrComment()) continue;
    if ('([{'.contains(c)) {
      scanner.depth++;
    } else if (')]}'.contains(c)) {
      if (scanner.depth > 0) scanner.depth--;
    } else if (scanner.depth == 0 && c == ';') {
      add(scanner.pos);
      start = scanner.pos + 1;
    } else if (scanner.depth == 0 && c == '\n') {
      final next = _nextCode(script, scanner.pos + 1);
      final before = _stripComments(script.substring(start, scanner.pos));
      if (before.trim().isNotEmpty &&
          next < script.length &&
          script[next] != '.' &&
          !_endsWithContinuation(before)) {
        add(scanner.pos);
        start = scanner.pos + 1;
      }
    }
    scanner.pos++;
  }
  add(script.length);
  return out;
}

/// The statement at [cursor]: the one containing it, else the closest one
/// before it (e.g. the cursor is in a comment below), else the first.
MongoScriptStatement? mongoStatementAt(String script, int cursor) {
  final statements = splitMongoScript(script);
  MongoScriptStatement? found;
  for (final s in statements) {
    if (s.start <= cursor) found = s;
  }
  return found ?? statements.firstOrNull;
}

/// Parses one statement. Throws [FormatException] for anything that isn't
/// `show …`, `use …` or a `db.…` chain, or for bad arguments.
MongoStatement parseMongoStatement(String statement) {
  final text = _stripComments(
    statement,
  ).trim().replaceFirst(RegExp(r';+$'), '').trim();
  if (text.isEmpty) throw const FormatException('Nothing to run');

  final show = RegExp(r'^show\s+(\w+)$').firstMatch(text);
  if (show != null) return MongoShow(show.group(1)!);
  final use = RegExp(r'^use\s+(\S+)$').firstMatch(text);
  if (use != null) return MongoUse(use.group(1)!);

  final calls = _readChain(text);
  final first = calls.first;
  if (first.isCall) {
    if (first.name == 'getCollection' || first.name == 'getSiblingDB') {
      final args = _args(first);
      if (args.isEmpty || args.first is! String) {
        throw FormatException('${first.name}(…) needs a name');
      }
      if (first.name == 'getSiblingDB') {
        throw const FormatException(
          'getSiblingDB is not supported here; pick the database in the '
          'toolbar or run "use <database>"',
        );
      }
      return _collectionCall(args.first as String, calls.sublist(1));
    }
    if (calls.length > 1) {
      throw FormatException('Unexpected .${calls[1].name} after ${first.name}(…)');
    }
    return MongoDbCall(first.name, _args(first));
  }
  // db.a.b.find(…): collection names can contain dots.
  final methodAt = calls.indexWhere((c) => c.isCall);
  if (methodAt == -1) {
    throw FormatException(
      'Call a method on the collection, e.g. '
      'db.${calls.map((c) => c.name).join('.')}.find({})',
    );
  }
  final collection = calls.take(methodAt).map((c) => c.name).join('.');
  return _collectionCall(collection, calls.sublist(methodAt));
}

MongoCollectionCall _collectionCall(String collection, List<MongoCall> calls) {
  if (calls.isEmpty || !calls.first.isCall) {
    throw FormatException('Call a method on $collection, e.g. .find({})');
  }
  final rest = calls.sublist(1);
  for (final c in rest) {
    if (!c.isCall) throw FormatException('Unexpected .${c.name}');
  }
  return MongoCollectionCall(
    collection,
    calls.first.name,
    _args(calls.first),
    [for (final c in rest) (c.name, _args(c))],
  );
}

List<Object?> _args(MongoCall call) {
  try {
    return parseMongo('[${call.args}]')! as List<Object?>;
  } on FormatException catch (e) {
    throw FormatException('In ${call.name}(…): ${e.message}');
  }
}

/// Reads `db.a.find(…).limit(…)` into calls after `db`.
List<MongoCall> _readChain(String text) {
  final scanner = _Scanner(text);
  final ident = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

  String identifier() {
    scanner.skipSpace();
    final match = ident.matchAsPrefix(text, scanner.pos);
    if (match == null) scanner.fail('Expected a name');
    scanner.pos = match.end;
    return match.group(0)!;
  }

  if (identifier() != 'db') {
    throw const FormatException(
      'Statements start with db., show or use, e.g. db.users.find({})',
    );
  }
  final calls = <MongoCall>[];
  while (true) {
    scanner.skipSpace();
    if (scanner.atEnd) break;
    final String name;
    if (scanner.char == '.') {
      scanner.pos++;
      name = identifier();
    } else if (scanner.char == '[') {
      // db['my-collection']
      scanner.pos++;
      scanner.skipSpace();
      final quote = scanner.atEnd ? '' : scanner.char;
      if (quote != '"' && quote != "'") scanner.fail('Expected a quoted name');
      final end = text.indexOf(quote, scanner.pos + 1);
      if (end < 0) scanner.fail('Unclosed string');
      name = text.substring(scanner.pos + 1, end);
      scanner.pos = end + 1;
      scanner.skipSpace();
      if (scanner.atEnd || scanner.char != ']') scanner.fail('Expected "]"');
      scanner.pos++;
    } else {
      scanner.fail('Unexpected "${scanner.char}"');
    }
    scanner.skipSpace();
    if (!scanner.atEnd && scanner.char == '(') {
      final open = scanner.pos;
      final close = scanner.matching(open);
      calls.add(MongoCall(name, text.substring(open + 1, close)));
      scanner.pos = close + 1;
    } else {
      calls.add(MongoCall(name));
    }
  }
  if (calls.isEmpty) {
    throw const FormatException('Expected db.<collection>.<method>(…)');
  }
  return calls;
}

/// What a statement returned: documents to show, and a one-line summary.
class MongoShellResult {
  const MongoShellResult({
    required this.page,
    required this.summary,
    this.database,
  });

  final DocumentPage page;
  final String summary;

  /// Set by `use`: the database later statements run in.
  final String? database;
}

/// Runs [statement] in [database]. Cursor results stop at [limit]
/// documents unless the statement asks for fewer, and never pass
/// [maxDocuments].
Future<MongoShellResult> runMongoStatement(
  DocumentDriver driver,
  String database,
  String statement, {
  int limit = 50,
  int maxDocuments = 10000,
}) async {
  final watch = Stopwatch()..start();
  final parsed = parseMongoStatement(statement);
  MongoShellResult done(
    List<Map<String, dynamic>> docs,
    String summary, {
    bool hasMore = false,
    String? database,
  }) => MongoShellResult(
    page: DocumentPage(
      documents: docs,
      elapsed: watch.elapsed,
      hasMore: hasMore,
    ),
    summary: summary,
    database: database,
  );

  switch (parsed) {
    case MongoUse(:final database):
      return done(const [], 'Switched to $database', database: database);
    case MongoShow(what: 'dbs' || 'databases'):
      final reply = await driver.runCommand('admin', {'listDatabases': 1});
      final dbs = _docs(reply['databases']);
      return done(dbs, '${dbs.length} database(s)');
    case MongoShow(what: 'collections' || 'tables'):
      final cursor = await _cursor(driver, database, {
        'listCollections': 1,
        'nameOnly': true,
      }, maxDocuments);
      return done(cursor.docs, '${cursor.docs.length} collection(s)');
    case MongoShow(:final what):
      throw FormatException('show $what is not supported; try show collections');
    case MongoDbCall(:final method, :final args):
      return _dbCall(driver, database, method, args, maxDocuments, done);
    case final MongoCollectionCall call:
      return _collectionMethod(
        driver,
        database,
        call,
        limit.clamp(1, maxDocuments),
        maxDocuments,
        done,
      );
  }
}

typedef _Done =
    MongoShellResult Function(
      List<Map<String, dynamic>> docs,
      String summary, {
      bool hasMore,
      String? database,
    });

Future<MongoShellResult> _dbCall(
  DocumentDriver driver,
  String database,
  String method,
  List<Object?> args,
  int maxDocuments,
  _Done done,
) async {
  Map<String, dynamic> command() => _doc(args.firstOrNull, 'the command');
  switch (method) {
    case 'runCommand':
      return done([await driver.runCommand(database, command())], 'ok');
    case 'adminCommand':
      return done([await driver.runCommand('admin', command())], 'ok');
    case 'getCollectionNames':
      final cursor = await _cursor(driver, database, {
        'listCollections': 1,
        'nameOnly': true,
      }, maxDocuments);
      return done(cursor.docs, '${cursor.docs.length} collection(s)');
    case 'createCollection':
      final name = args.firstOrNull;
      if (name is! String) {
        throw const FormatException('createCollection(…) needs a name');
      }
      await driver.runCommand(database, {
        'create': name,
        ..._doc(args.elementAtOrNull(1), 'the options'),
      });
      return done(const [], 'Collection $name created');
    case 'stats':
      return done([await driver.runCommand(database, {'dbStats': 1})], 'ok');
    case 'dropDatabase':
      await driver.runCommand(database, {'dropDatabase': 1});
      return done(const [], 'Database $database dropped');
    default:
      throw FormatException('db.$method(…) is not supported');
  }
}

Future<MongoShellResult> _collectionMethod(
  DocumentDriver driver,
  String database,
  MongoCollectionCall call,
  int limit,
  int maxDocuments,
  _Done done,
) async {
  final c = call.collection;
  final args = call.args;
  Map<String, dynamic> arg(int i, String what) =>
      _doc(args.elementAtOrNull(i), what);

  switch (call.method) {
    case 'find' || 'findOne':
      final options = arg(2, 'the options');
      final find = <String, dynamic>{
        'find': c,
        'filter': arg(0, 'the filter'),
        if (args.length > 1) 'projection': arg(1, 'the projection'),
        for (final key in const [
          'projection',
          'sort',
          'skip',
          'limit',
          'hint',
          'collation',
          'maxTimeMS',
          'comment',
        ])
          if (options.containsKey(key)) key: options[key],
      };
      var count = false;
      var explain = false;
      for (final (method, chainArgs) in call.chain) {
        final value = chainArgs.firstOrNull;
        switch (method) {
          case 'sort' || 'projection' || 'project' || 'collation':
            find[method == 'project' ? 'projection' : method] = _doc(
              value,
              'the $method',
            );
          case 'hint':
            find['hint'] = value;
          case 'skip' || 'limit' || 'maxTimeMS' || 'batchSize':
            if (value is! int) {
              throw FormatException('$method(…) needs a number');
            }
            if (method != 'batchSize') find[method] = value;
          case 'comment':
            find['comment'] = value;
          case 'count' || 'size' || 'itcount':
            count = true;
          case 'explain':
            explain = true;
          case 'toArray' || 'pretty':
            break;
          default:
            throw FormatException('.$method(…) is not supported after find');
        }
      }
      if (call.method == 'findOne') find['limit'] = 1;
      if (count) {
        final n = await _countDocuments(
          driver,
          database,
          c,
          find['filter'] as Map<String, dynamic>,
          skip: find['skip'] as int?,
          limit: find['limit'] as int?,
        );
        return done([
          {'count': n},
        ], '$n document(s)');
      }
      if (explain) {
        return done([
          await driver.runCommand(database, {'explain': find}),
        ], 'Query plan');
      }
      final requested = find['limit'] as int?;
      final shown = requested == null || requested <= 0
          ? limit
          : requested.clamp(1, maxDocuments);
      // One extra document tells whether there are more.
      final fetch = requested != null && requested > 0 && requested <= shown
          ? shown
          : shown + 1;
      find['limit'] = fetch;
      find['batchSize'] = fetch;
      find['singleBatch'] = true;
      final reply = await driver.runCommand(database, find);
      final docs = _docs((reply['cursor'] as Map?)?['firstBatch']);
      final more = docs.length > shown;
      final page = more ? docs.sublist(0, shown) : docs;
      if (call.method == 'findOne') {
        return done(page, page.isEmpty ? 'null' : '1 document');
      }
      return done(
        page,
        '${page.length}${more ? '+' : ''} document(s)',
        hasMore: more,
      );

    case 'aggregate':
      final pipeline = args.firstOrNull ?? const [];
      if (pipeline is! List || pipeline.any((s) => s is! Map)) {
        throw const FormatException(
          'aggregate(…) needs an array of stages: [ { \$match: … } ]',
        );
      }
      final stages = [for (final s in pipeline) _doc(s, 'a stage')];
      var explain = false;
      for (final (method, _) in call.chain) {
        switch (method) {
          case 'explain':
            explain = true;
          case 'toArray' || 'pretty':
            break;
          default:
            throw FormatException(
              '.$method(…) is not supported after aggregate',
            );
        }
      }
      final writes =
          stages.isNotEmpty &&
          (stages.last.containsKey(r'$out') ||
              stages.last.containsKey(r'$merge'));
      final command = <String, dynamic>{
        'aggregate': c,
        'pipeline': [
          ...stages,
          // One extra document tells whether there are more.
          if (!writes && !explain) {r'$limit': limit + 1},
        ],
        'cursor': explain ? <String, dynamic>{} : {'batchSize': limit + 1},
        ...arg(1, 'the options'),
      };
      if (explain) {
        return done([
          await driver.runCommand(database, {'explain': command}),
        ], 'Query plan');
      }
      final cursor = await _cursor(driver, database, command, limit + 1);
      final more = cursor.docs.length > limit;
      final page = more ? cursor.docs.sublist(0, limit) : cursor.docs;
      return done(
        page,
        writes
            ? 'Pipeline written to '
                  '${stages.last[r'$out'] ?? stages.last[r'$merge']}'
            : '${page.length}${more ? '+' : ''} document(s)',
        hasMore: more,
      );

    case 'countDocuments':
      final options = arg(1, 'the options');
      final n = await _countDocuments(
        driver,
        database,
        c,
        arg(0, 'the filter'),
        skip: options['skip'] as int?,
        limit: options['limit'] as int?,
      );
      return done([
        {'count': n},
      ], '$n document(s)');

    case 'estimatedDocumentCount' || 'count':
      final reply = await driver.runCommand(database, {
        'count': c,
        if (call.method == 'count') 'query': arg(0, 'the filter'),
      });
      final n = reply['n'];
      return done([
        {'count': n},
      ], '$n document(s)');

    case 'distinct':
      final field = args.firstOrNull;
      if (field is! String) {
        throw const FormatException('distinct(…) needs a field name');
      }
      final reply = await driver.runCommand(database, {
        'distinct': c,
        'key': field,
        'query': arg(1, 'the filter'),
      });
      final values = (reply['values'] as List?) ?? const [];
      return done([
        for (final v in values) {field: v},
      ], '${values.length} distinct value(s)');

    case 'insertOne' || 'insert' || 'insertMany':
      final value = args.firstOrNull;
      final many = call.method == 'insertMany' || value is List;
      final docs = [
        for (final d in many ? (value is List ? value : const []) : [value])
          // Like mongosh, _id is made here so it can be shown.
          {'_id': ObjectId(), ..._doc(d, 'a document')},
      ];
      if (docs.isEmpty) {
        throw FormatException('${call.method}(…) needs a document');
      }
      final reply = await driver.runCommand(database, {
        'insert': c,
        'documents': docs,
        ...arg(1, 'the options'),
      });
      _checkWriteReply(reply);
      return done([
        many
            ? {
                'acknowledged': true,
                'insertedIds': [for (final d in docs) d['_id']],
              }
            : {'acknowledged': true, 'insertedId': docs.first['_id']},
      ], 'Inserted ${reply['n']} document(s)');

    case 'updateOne' || 'updateMany' || 'replaceOne':
      final options = arg(2, 'the options');
      final update = args.elementAtOrNull(1);
      if (update is! Map && update is! List) {
        throw FormatException(
          '${call.method}(…) needs a filter and '
          '${call.method == 'replaceOne' ? 'a document' : 'an update'}',
        );
      }
      final reply = await driver.runCommand(database, {
        'update': c,
        'updates': [
          {
            'q': arg(0, 'the filter'),
            'u': update,
            'multi': call.method == 'updateMany',
            for (final key in const [
              'upsert',
              'arrayFilters',
              'hint',
              'collation',
            ])
              if (options.containsKey(key)) key: options[key],
          },
        ],
      });
      _checkWriteReply(reply);
      final upserted = _docs(reply['upserted']);
      final matched = (reply['n'] as num? ?? 0) - upserted.length;
      return done([
        {
          'acknowledged': true,
          'matchedCount': matched,
          'modifiedCount': reply['nModified'] ?? 0,
          'upsertedCount': upserted.length,
          if (upserted.isNotEmpty) 'upsertedId': upserted.first['_id'],
        },
      ], 'Matched $matched, modified ${reply['nModified'] ?? 0}');

    case 'deleteOne' || 'deleteMany' || 'remove':
      final reply = await driver.runCommand(database, {
        'delete': c,
        'deletes': [
          {'q': arg(0, 'the filter'), 'limit': call.method == 'deleteOne' ? 1 : 0},
        ],
      });
      _checkWriteReply(reply);
      return done([
        {'acknowledged': true, 'deletedCount': reply['n']},
      ], 'Deleted ${reply['n']} document(s)');

    case 'findOneAndUpdate' || 'findOneAndReplace' || 'findOneAndDelete':
      final delete = call.method == 'findOneAndDelete';
      final options = arg(delete ? 1 : 2, 'the options');
      final reply = await driver.runCommand(database, {
        'findAndModify': c,
        'query': arg(0, 'the filter'),
        if (delete) 'remove': true else 'update': args.elementAtOrNull(1),
        if (!delete) 'new': options['returnDocument'] == 'after' ||
            options['returnNewDocument'] == true,
        for (final key in const ['sort', 'upsert', 'collation', 'hint'])
          if (options.containsKey(key)) key: options[key],
        'fields': ?options['projection'],
      });
      final value = reply['value'];
      return done(
        value is Map<String, dynamic> ? [value] : const [],
        value == null ? 'null' : '1 document',
      );

    case 'getIndexes':
      final cursor = await _cursor(driver, database, {
        'listIndexes': c,
      }, maxDocuments);
      return done(cursor.docs, '${cursor.docs.length} index(es)');

    case 'createIndex':
      final keys = arg(0, 'the index keys');
      if (keys.isEmpty) {
        throw const FormatException('createIndex(…) needs keys: { field: 1 }');
      }
      final options = arg(1, 'the options');
      final name =
          options['name'] ??
          [for (final e in keys.entries) '${e.key}_${e.value}'].join('_');
      final reply = await driver.runCommand(database, {
        'createIndexes': c,
        'indexes': [
          {...options, 'key': keys, 'name': name},
        ],
      });
      return done([reply], 'Index $name created');

    case 'dropIndex':
      final index = args.firstOrNull;
      if (index is! String && index is! Map) {
        throw const FormatException('dropIndex(…) needs a name or keys');
      }
      final reply = await driver.runCommand(database, {
        'dropIndexes': c,
        'index': index,
      });
      return done([reply], 'Index dropped');

    case 'drop':
      await driver.runCommand(database, {'drop': c});
      return done(const [], 'Collection $c dropped');

    case 'stats':
      return done([
        await driver.runCommand(database, {'collStats': c}),
      ], 'ok');

    default:
      throw FormatException('db.$c.${call.method}(…) is not supported');
  }
}

Future<int> _countDocuments(
  DocumentDriver driver,
  String database,
  String collection,
  Map<String, dynamic> filter, {
  int? skip,
  int? limit,
}) async {
  final reply = await driver.runCommand(database, {
    'aggregate': collection,
    'pipeline': [
      {r'$match': filter},
      if (skip != null && skip > 0) {r'$skip': skip},
      if (limit != null && limit > 0) {r'$limit': limit},
      {
        r'$group': {
          '_id': 1,
          'n': {r'$sum': 1},
        },
      },
    ],
    'cursor': <String, dynamic>{},
  });
  final batch = _docs((reply['cursor'] as Map?)?['firstBatch']);
  return (batch.firstOrNull?['n'] as num?)?.toInt() ?? 0;
}

/// Runs a cursor command and reads its first batch, up to [max] documents;
/// a cursor left open on the server is closed.
Future<({List<Map<String, dynamic>> docs})> _cursor(
  DocumentDriver driver,
  String database,
  Map<String, dynamic> command,
  int max,
) async {
  final reply = await driver.runCommand(database, command);
  final cursor = reply['cursor'] as Map?;
  final docs = _docs(cursor?['firstBatch']);
  final id = cursor?['id'];
  if (id != null && '$id' != '0') {
    final ns = '${cursor?['ns'] ?? ''}';
    final dot = ns.indexOf('.');
    try {
      await driver.runCommand(database, {
        'killCursors': dot < 0 ? ns : ns.substring(dot + 1),
        'cursors': [id],
      });
    } on DriverException {
      // The server closes idle cursors itself.
    }
  }
  return (docs: docs.length > max ? docs.sublist(0, max) : docs);
}

void _checkWriteReply(Map<String, dynamic> reply) {
  final errors = reply['writeErrors'];
  if (errors is List && errors.isNotEmpty) {
    final first = errors.first as Map;
    throw DriverException(
      '${first['errmsg'] ?? 'Write failed'}',
      code: first['code']?.toString(),
    );
  }
  if (reply['writeConcernError'] case final Map error) {
    throw DriverException(
      '${error['errmsg'] ?? 'Write concern failed'}',
      code: error['code']?.toString(),
    );
  }
}

Map<String, dynamic> _doc(Object? value, String what) => switch (value) {
  null => <String, dynamic>{},
  final Map<String, dynamic> map => map,
  final Map map => {for (final e in map.entries) '${e.key}': e.value},
  _ => throw FormatException('Expected a document for $what: { … }'),
};

List<Map<String, dynamic>> _docs(Object? value) => [
  if (value is List)
    for (final v in value)
      if (v is Map) _doc(v, 'a document'),
];

/// Walks text, skipping strings, comments and regex literals.
class _Scanner {
  _Scanner(this.text);

  final String text;
  int pos = 0;
  int depth = 0;

  bool get atEnd => pos >= text.length;
  String get char => text[pos];

  Never fail(String message) {
    final before = text.substring(0, pos.clamp(0, text.length));
    final line = '\n'.allMatches(before).length + 1;
    final column = pos - (before.lastIndexOf('\n') + 1) + 1;
    throw FormatException('$message (line $line, column $column)');
  }

  void skipSpace() {
    while (!atEnd) {
      if (char.trim().isEmpty) {
        pos++;
      } else if (!_skipComment()) {
        return;
      }
    }
  }

  bool _skipComment() {
    if (text.startsWith('//', pos)) {
      final end = text.indexOf('\n', pos);
      pos = end < 0 ? text.length : end;
      return true;
    }
    if (text.startsWith('/*', pos)) {
      final end = text.indexOf('*/', pos + 2);
      pos = end < 0 ? text.length : end + 2;
      return true;
    }
    return false;
  }

  /// Skips a string, comment or regex at [pos]; false if there is none.
  bool skipStringOrComment() {
    if (_skipComment()) return true;
    final c = char;
    if (c == '"' || c == "'" || c == '`') {
      pos++;
      while (!atEnd && char != c) {
        if (char == r'\') pos++;
        pos++;
      }
      pos++;
      return true;
    }
    if (c == '/' && _regexAllowed()) {
      pos++;
      while (!atEnd && char != '/' && char != '\n') {
        if (char == r'\') pos++;
        pos++;
      }
      pos++;
      return true;
    }
    return false;
  }

  /// A `/` starts a regex where a value is expected, not after one.
  bool _regexAllowed() {
    var i = pos - 1;
    while (i >= 0 && text[i].trim().isEmpty) {
      i--;
    }
    return i < 0 || '(,:[{=!&|?;'.contains(text[i]);
  }

  /// The index of the bracket closing the one at [open].
  int matching(int open) {
    final saved = depth;
    depth = 0;
    pos = open;
    while (!atEnd) {
      if (skipStringOrComment()) continue;
      final c = char;
      if ('([{'.contains(c)) {
        depth++;
      } else if (')]}'.contains(c)) {
        depth--;
        if (depth == 0) {
          depth = saved;
          return pos;
        }
      }
      pos++;
    }
    pos = open;
    fail('Unclosed "${text[open]}"');
  }
}

/// [text] with comments blanked out (strings and regexes kept).
String _stripComments(String text) {
  final out = StringBuffer();
  final scanner = _Scanner(text);
  while (!scanner.atEnd) {
    final start = scanner.pos;
    if (scanner._skipComment()) {
      // Keep line breaks so positions and statement breaks survive.
      out.write(text.substring(start, scanner.pos).replaceAll(RegExp(r'[^\n]'), ' '));
      continue;
    }
    if (scanner.skipStringOrComment()) {
      out.write(text.substring(start, scanner.pos.clamp(0, text.length)));
      continue;
    }
    out.write(scanner.char);
    scanner.pos++;
  }
  return out.toString();
}

/// Length of the blank lines and comments [text] starts with.
int _leadingIgnorable(String text) {
  final scanner = _Scanner(text)..skipSpace();
  return scanner.pos.clamp(0, text.length);
}

/// Index of the first character at or after [from] that isn't space or
/// part of a comment.
int _nextCode(String text, int from) {
  final scanner = _Scanner(text)..pos = from;
  scanner.skipSpace();
  return scanner.pos;
}

/// A line ending like this continues on the next one: `db.users.` or
/// `find(…) ,`.
bool _endsWithContinuation(String text) {
  final trimmed = text.trimRight();
  return trimmed.isEmpty || '.,([{=+-*&|?:'.contains(trimmed[trimmed.length - 1]);
}

/// What a new MongoDB editor starts with: a complete find on [collection]
/// (filter, projection, sort, skip, limit) ready to run, and commented
/// examples of the other operations.
String mongoQueryTemplate(String? collection) {
  final name = collection ?? 'collection';
  final quoted = "'${name.replaceAll(r'\', r'\\').replaceAll("'", r"\'")}'";
  final coll = 'db.getCollection($quoted)';
  return '''
// MongoDB query — mongosh syntax. Ctrl+Enter runs the statement at the
// cursor, Ctrl+Shift+Enter runs them all. Statements end with ";".

$coll.find(
  {
    // Filter, e.g. status: 'active', age: { \$gte: 18 }
  },
  {
    // Projection, e.g. name: 1, email: 1, _id: 0
  }
)
  .sort({ _id: -1 })
  .skip(0)
  .limit(20);

// More examples (uncomment one and run it):
// $coll.findOne({ _id: ObjectId('...') });
// $coll.countDocuments({ status: 'active' });
// $coll.distinct('status', { });
// $coll.aggregate([
//   { \$match: { status: 'active' } },
//   { \$group: { _id: '\$type', count: { \$sum: 1 } } },
//   { \$sort: { count: -1 } }
// ]);
// $coll.insertOne({ name: 'Ann', createdAt: new Date() });
// $coll.updateOne({ _id: ObjectId('...') }, { \$set: { status: 'done' } });
// $coll.deleteOne({ _id: ObjectId('...') });
// $coll.getIndexes();
// show collections;
''';
}

/// Field paths in [documents], nested ones dotted (`address.city`), in
/// order of first appearance; for completion.
List<String> fieldPaths(List<Map<String, dynamic>> documents, {int depth = 3}) {
  final paths = <String>{};
  void walk(Map<Object?, Object?> doc, String prefix, int level) {
    for (final MapEntry(:key, :value) in doc.entries) {
      final path = '$prefix$key';
      paths.add(path);
      if (level >= depth) continue;
      // Arrays of documents: their fields, as queries address them.
      final nested = value is List
          ? value.whereType<Map<Object?, Object?>>().firstOrNull
          : value;
      if (nested is Map<Object?, Object?>) walk(nested, '$path.', level + 1);
    }
  }

  for (final doc in documents) {
    walk(doc, '', 1);
  }
  return paths.toList();
}
