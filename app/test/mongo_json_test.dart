import 'package:db_client/drivers/mongodb/mongo_json.dart';
import 'package:decimal/decimal.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mongo_dart/mongo_dart.dart' show ObjectId, Timestamp;
import 'package:uuid/uuid.dart';

void main() {
  final id = ObjectId.fromHexString('65f1c0ffee0000000000abcd');
  final doc = <String, dynamic>{
    '_id': id,
    'name': 'Ana "A" \n',
    'small': 5,
    'long': Int64(5),
    'big': 1 << 40,
    'ratio': 2.0,
    'price': Decimal.parse('19.990'),
    'at': DateTime.utc(2026, 1, 2, 3, 4, 5, 6),
    'uuid': UuidValue.fromString('0f8fad5b-d9cb-469f-a165-70867728950e'),
    'ts': Timestamp(1700000000, 3),
    'nothing': null,
    'tags': ['a', 1, true],
    'nested': {'x': <String, dynamic>{}, 'y': <Object?>[]},
    'weird key': 1,
  };

  test('format then parse keeps every value and BSON type', () {
    for (final indent in ['  ', null]) {
      final text = formatMongo(doc, indent: indent);
      final back = parseMongo(text) as Map<String, dynamic>;
      expect(back.keys, doc.keys);
      expect(back['_id'], isA<ObjectId>());
      expect((back['_id'] as ObjectId).oid, id.oid);
      expect(back['name'], doc['name']);
      expect(back['small'], isA<int>());
      expect(back['long'], Int64(5));
      expect(back['big'], 1 << 40);
      expect(back['ratio'], isA<double>());
      expect(back['price'], Decimal.parse('19.990'));
      expect(back['at'], doc['at']);
      expect(back['uuid'], doc['uuid']);
      expect((back['ts'] as Timestamp).seconds, 1700000000);
      expect((back['ts'] as Timestamp).increment, 3);
      expect(back['nothing'], isNull);
      expect(back['tags'], ['a', 1, true]);
      expect(back['nested'], {'x': {}, 'y': []});
      expect(back['weird key'], 1);
      // Formatting the parsed value gives identical text.
      expect(formatMongo(back, indent: indent), text);
    }
  });

  test('mongosh output style', () {
    expect(
      formatMongoInline({'_id': id, 'n': Int64(7), 'd': 1.0}),
      "{ _id: ObjectId('65f1c0ffee0000000000abcd'), n: Long('7'), d: 1.0 }",
    );
  });

  test('reads shell-style filters', () {
    final filter = parseMongoDocument('''
      // comments are fine
      {
        status: 'A',
        qty: { \$gt: 20, \$lte: NumberLong(100) },
        created: { \$gte: ISODate("2024-01-01") },
        name: /^ann?a\\/x/i,
        "a.b": [1, 2,],
      }
    ''');
    expect(filter['status'], 'A');
    expect((filter['qty'] as Map)[r'$gt'], 20);
    expect((filter['qty'] as Map)[r'$lte'], Int64(100));
    expect((filter['created'] as Map)[r'$gte'], DateTime.utc(2024));
    final regex = filter['name'] as RegExp;
    expect(regex.pattern, r'^ann?a/x');
    expect(regex.isCaseSensitive, isFalse);
    expect(filter['a.b'], [1, 2]);
  });

  test('reads Extended JSON', () {
    final value = parseMongoDocument(
      '{"_id": {"\$oid": "65f1c0ffee0000000000abcd"}, '
      '"n": {"\$numberLong": "9"}, "at": {"\$date": "2024-05-06T00:00:00Z"}}',
    );
    expect(value['_id'], isA<ObjectId>());
    expect(value['n'], Int64(9));
    expect(value['at'], DateTime.utc(2024, 5, 6));
  });

  test('empty filter is an empty document; errors say where', () {
    expect(parseMongoDocument('  '), isEmpty);
    expect(
      () => parseMongoDocument('{ a: 1,\n  b: }'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('line 2'),
        ),
      ),
    );
    expect(() => parseMongoDocument('[1]'), throwsFormatException);
    expect(() => parseMongo('Foo(1)'), throwsFormatException);
  });

  test('type names', () {
    expect(mongoTypeName(Int64(1)), 'Int64');
    expect(mongoTypeName(1), 'Int32');
    expect(mongoTypeName(id), 'ObjectId');
    expect(mongoTypeName({'a': 1}), 'Object');
  });
}
