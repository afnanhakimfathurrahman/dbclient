import 'package:db_client/features/documents/mongo_completion.dart';
import 'package:db_client/features/editor/sql_completion.dart';
import 'package:flutter_test/flutter_test.dart';

class _Catalog implements MongoCatalog {
  @override
  List<String>? collections() => ['users', 'orders'];

  @override
  List<String>? fields(String collection) => collection == 'users'
      ? ['_id', 'name', 'address', 'address.city', 'age']
      : null;
}

SqlCompletion? _complete(String textWithCursor) {
  final cursor = textWithCursor.indexOf('|');
  final text = textWithCursor.replaceFirst('|', '');
  return completeMongo(text: text, cursor: cursor, catalog: _Catalog());
}

List<String> _labels(String textWithCursor) => [
  for (final s in _complete(textWithCursor)?.suggestions ?? const [])
    s.label,
];

void main() {
  test('collections and db methods after db.', () {
    final labels = _labels('db.|');
    expect(labels, containsAll(['users', 'orders', 'getCollection']));
    expect(_labels('db.us|'), ['users']);
    expect(_complete('db.us|')!.input, 'us');
  });

  test('collection methods, with call templates', () {
    final completion = _complete('db.users.fi|')!;
    expect(completion.suggestions.first.label, 'find');
    expect(completion.suggestions.first.insert, 'find({ })');
    expect(_labels("db.getCollection('users').agg|"), ['aggregate']);
  });

  test('cursor methods after a call, also on the next line', () {
    expect(_labels('db.users.find({}).so|'), ['sort']);
    expect(_labels('db.users.find({})\n  .li|'), ['limit']);
  });

  test('field names at document keys, nested with a dot', () {
    expect(_labels('db.users.find({ na|'), ['name']);
    expect(_labels('db.users.find({ address.c|'), ['city']);
    // At a value, not a key.
    expect(_labels('db.users.find({ name: na|'), isEmpty);
  });

  test('operators and \$field references', () {
    expect(
      _labels(r'db.users.find({ age: { $g|'),
      containsAllInOrder([r'$gt', r'$gte', r'$group']),
    );
    expect(
      _labels(r"db.users.aggregate([{ $group: { _id: '$na|"),
      isEmpty, // Inside a string.
    );
    expect(
      _labels(r'db.users.aggregate([{ $group: { _id: $na|'),
      contains(r'$name'),
    );
  });

  test('collection names inside getCollection quotes', () {
    expect(_labels("db.getCollection('or|"), ['orders']);
  });

  test('nothing in comments or without a word', () {
    expect(_complete('// db.us|'), isNull);
    expect(_complete('db.users.find({ |'), isNull);
  });
}
