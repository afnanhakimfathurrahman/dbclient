import 'package:db_client/drivers/mongodb/document_diff.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId;

void main() {
  final id = ObjectId.fromHexString('65f1c0ffee0000000000abcd');
  final before = <String, dynamic>{
    '_id': id,
    'name': 'Ana',
    'count': Int64(5),
    'tags': ['a'],
    'gone': true,
  };

  test('only changed, added and removed fields are sent', () {
    final after = <String, dynamic>{
      '_id': ObjectId.fromHexString(id.oid),
      'name': 'Ana',
      'count': Int64(5),
      'tags': ['a', 'b'],
      'added': 1,
    };
    expect(documentUpdate(before, after), {
      r'$set': {
        'tags': ['a', 'b'],
        'added': 1,
      },
      r'$unset': {'gone': ''},
    });
  });

  test('no change gives an empty update', () {
    expect(documentUpdate(before, {...before}), isEmpty);
  });

  test('a type change counts as a change', () {
    final update = documentUpdate(before, {...before, 'count': 5});
    expect(update, {
      r'$set': {'count': 5},
    });
  });

  test('changing or removing _id is refused', () {
    expect(
      () => documentUpdate(before, {...before, '_id': ObjectId()}),
      throwsFormatException,
    );
    expect(
      () => documentUpdate(before, {...before}..remove('_id')),
      throwsFormatException,
    );
  });
}
