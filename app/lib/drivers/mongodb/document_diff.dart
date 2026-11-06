import 'mongo_json.dart';

/// The update that turns [before] into [after], touching only top-level
/// fields that changed: `{$set: {…}, $unset: {…}}`. Empty when nothing
/// changed. Unchanged fields are left alone, so their exact stored BSON
/// types are kept and concurrent edits to other fields aren't overwritten.
///
/// Throws [FormatException] if `_id` was changed or removed: MongoDB can't
/// update it (insert a copy instead).
Map<String, dynamic> documentUpdate(
  Map<String, dynamic> before,
  Map<String, dynamic> after,
) {
  if (before.containsKey('_id') &&
      (!after.containsKey('_id') ||
          formatMongoInline(after['_id']) !=
              formatMongoInline(before['_id']))) {
    throw const FormatException(
      "_id can't be changed; use Clone to insert a copy with a new _id",
    );
  }
  final set = <String, dynamic>{
    for (final MapEntry(:key, :value) in after.entries)
      if (key != '_id' &&
          (!before.containsKey(key) ||
              formatMongoInline(before[key]) != formatMongoInline(value)))
        key: value,
  };
  final unset = <String, dynamic>{
    for (final key in before.keys)
      if (!after.containsKey(key)) key: '',
  };
  return {
    if (set.isNotEmpty) r'$set': set,
    if (unset.isNotEmpty) r'$unset': unset,
  };
}
