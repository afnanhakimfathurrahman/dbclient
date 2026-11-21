import 'package:db_client/drivers/document.dart';
import 'package:db_client/drivers/driver.dart';
import 'package:db_client/drivers/mongodb/mongo_shell.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records commands and answers with canned replies.
class _FakeDriver implements DocumentDriver {
  _FakeDriver(this.reply);

  final Map<String, dynamic> Function(Map<String, dynamic> command) reply;
  final commands = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> runCommand(
    String database,
    Map<String, dynamic> command,
  ) async {
    commands.add((database, command));
    return {'ok': 1, ...reply(command)};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _batch(List<Map<String, dynamic>> docs) => {
  'cursor': {'id': 0, 'ns': 'shop.users', 'firstBatch': docs},
};

void main() {
  group('splitMongoScript', () {
    test('splits at ; and new statements, keeps chained lines', () {
      const script = '''
// A comment
db.users.find({ a: 1 })
  .sort({ b: -1 })
  .limit(5)
db.users.countDocuments({}); show collections
''';
      final statements = [for (final s in splitMongoScript(script)) s.text];
      expect(statements, [
        'db.users.find({ a: 1 })\n  .sort({ b: -1 })\n  .limit(5)',
        'db.users.countDocuments({})',
        'show collections',
      ]);
    });

    test('ignores ; and newlines inside strings, comments and objects', () {
      final statements = splitMongoScript(
        "db.a.find({\n  s: 'x;y', // c;\n  r: /a;b/\n})",
      );
      expect(statements, hasLength(1));
    });

    test('the template runs one find; the examples are comments', () {
      final template = mongoQueryTemplate('users');
      final statements = splitMongoScript(template);
      expect(statements, hasLength(1));
      final parsed = parseMongoStatement(statements.single.text);
      expect(parsed, isA<MongoCollectionCall>());
      final call = parsed as MongoCollectionCall;
      expect(call.collection, 'users');
      expect(call.method, 'find');
      expect(call.args, [<String, dynamic>{}, <String, dynamic>{}]);
      expect([for (final (m, _) in call.chain) m], ['sort', 'skip', 'limit']);
    });

    test('statement at the cursor', () {
      const script = 'db.a.find()\n\ndb.b.find()\n// note';
      expect(mongoStatementAt(script, 0)!.text, 'db.a.find()');
      expect(mongoStatementAt(script, 14)!.text, 'db.b.find()');
      // Below the last statement, in a comment.
      expect(mongoStatementAt(script, script.length)!.text, 'db.b.find()');
    });
  });

  group('parseMongoStatement', () {
    test('collection forms', () {
      for (final text in [
        'db.users.find()',
        "db.getCollection('users').find()",
        "db['users'].find()",
      ]) {
        final call = parseMongoStatement(text) as MongoCollectionCall;
        expect(call.collection, 'users', reason: text);
      }
      final dotted =
          parseMongoStatement('db.system.profile.find()') as MongoCollectionCall;
      expect(dotted.collection, 'system.profile');
    });

    test('db calls, show and use', () {
      final command =
          parseMongoStatement('db.runCommand({ ping: 1 })') as MongoDbCall;
      expect(command.method, 'runCommand');
      expect(command.args, [
        {'ping': 1},
      ]);
      expect((parseMongoStatement('show dbs;') as MongoShow).what, 'dbs');
      expect((parseMongoStatement('use shop') as MongoUse).database, 'shop');
    });

    test('errors are FormatExceptions', () {
      expect(() => parseMongoStatement('users.find()'), throwsFormatException);
      expect(() => parseMongoStatement('db.users'), throwsFormatException);
      expect(
        () => parseMongoStatement('db.users.find({ a: })'),
        throwsFormatException,
      );
      expect(
        () => parseMongoStatement('db.users.find({ a: 1 }'),
        throwsFormatException,
      );
    });
  });

  group('runMongoStatement', () {
    test('find becomes a find command with the chain applied', () async {
      final driver = _FakeDriver(
        (_) => _batch([
          {'_id': 1},
          {'_id': 2},
          {'_id': 3},
        ]),
      );
      final result = await runMongoStatement(
        driver,
        'shop',
        "db.users.find({ age: { \$gt: 18 } }, { name: 1 }).sort({ name: 1 }).skip(10)",
        limit: 2,
      );
      final (database, command) = driver.commands.single;
      expect(database, 'shop');
      expect(command['find'], 'users');
      expect(command['filter'], {
        'age': {r'$gt': 18},
      });
      expect(command['projection'], {'name': 1});
      expect(command['sort'], {'name': 1});
      expect(command['skip'], 10);
      // One more than shown, to tell whether there are more.
      expect(command['limit'], 3);
      expect(result.page.documents, hasLength(2));
      expect(result.page.hasMore, isTrue);
    });

    test('an explicit limit below the cap is used as is', () async {
      final driver = _FakeDriver((_) => _batch([{'_id': 1}]));
      final result = await runMongoStatement(
        driver,
        'shop',
        'db.users.find().limit(5)',
        limit: 50,
      );
      expect(driver.commands.single.$2['limit'], 5);
      expect(result.page.hasMore, isFalse);
    });

    test('aggregate appends a \$limit unless the pipeline writes', () async {
      final driver = _FakeDriver((_) => _batch(const []));
      await runMongoStatement(
        driver,
        'shop',
        'db.users.aggregate([{ \$match: { a: 1 } }])',
        limit: 20,
      );
      await runMongoStatement(
        driver,
        'shop',
        "db.users.aggregate([{ \$out: 'copy' }])",
        limit: 20,
      );
      expect(driver.commands[0].$2['pipeline'], [
        {
          r'$match': {'a': 1},
        },
        {r'$limit': 21},
      ]);
      expect(driver.commands[1].$2['pipeline'], [
        {r'$out': 'copy'},
      ]);
    });

    test('writes report mongosh-style results', () async {
      final driver = _FakeDriver(
        (command) => switch (command.keys.first) {
          'insert' => {'n': 1},
          'update' => {'n': 2, 'nModified': 1},
          'delete' => {'n': 3},
          _ => {},
        },
      );
      final insert = await runMongoStatement(
        driver,
        'shop',
        "db.users.insertOne({ name: 'Ann' })",
      );
      final inserted = driver.commands.last.$2['documents'] as List;
      expect((inserted.single as Map)['name'], 'Ann');
      expect((inserted.single as Map)['_id'], isNotNull);
      expect(insert.page.documents.single['insertedId'], isNotNull);

      final update = await runMongoStatement(
        driver,
        'shop',
        "db.users.updateMany({ a: 1 }, { \$set: { b: 2 } }, { upsert: true })",
      );
      final spec = (driver.commands.last.$2['updates'] as List).single as Map;
      expect(spec['multi'], isTrue);
      expect(spec['upsert'], isTrue);
      expect(update.page.documents.single['matchedCount'], 2);
      expect(update.page.documents.single['modifiedCount'], 1);

      final delete = await runMongoStatement(
        driver,
        'shop',
        'db.users.deleteOne({ a: 1 })',
      );
      final deletes = (driver.commands.last.$2['deletes'] as List).single;
      expect((deletes as Map)['limit'], 1);
      expect(delete.page.documents.single['deletedCount'], 3);
    });

    test('write errors throw', () async {
      final driver = _FakeDriver(
        (_) => {
          'n': 0,
          'writeErrors': [
            {'index': 0, 'code': 11000, 'errmsg': 'E11000 duplicate key'},
          ],
        },
      );
      expect(
        runMongoStatement(driver, 'shop', 'db.users.insertOne({ _id: 1 })'),
        throwsA(
          isA<DriverException>().having((e) => e.code, 'code', '11000'),
        ),
      );
    });

    test('countDocuments, distinct and use', () async {
      final driver = _FakeDriver(
        (command) => command.containsKey('distinct')
            ? {
                'values': ['a', 'b'],
              }
            : _batch([
                {'_id': 1, 'n': 7},
              ]),
      );
      final count = await runMongoStatement(
        driver,
        'shop',
        'db.users.countDocuments({ a: 1 })',
      );
      expect(count.page.documents.single['count'], 7);
      final distinct = await runMongoStatement(
        driver,
        'shop',
        "db.users.distinct('status')",
      );
      expect(distinct.page.documents, [
        {'status': 'a'},
        {'status': 'b'},
      ]);
      final use = await runMongoStatement(driver, 'shop', 'use other');
      expect(use.database, 'other');
    });
  });

  test('fieldPaths walks nested documents and arrays of documents', () {
    expect(
      fieldPaths([
        {
          '_id': 1,
          'address': {'city': 'X'},
          'tags': ['a'],
          'items': [
            {'sku': 'p1'},
          ],
        },
        {'extra': true},
      ]),
      ['_id', 'address', 'address.city', 'tags', 'items', 'items.sku', 'extra'],
    );
  });
}
