/// Driver interface for document stores (MongoDB).
library;

import 'driver.dart';

enum CollectionKind {
  collection('Collection'),
  view('View'),
  timeseries('Time series');

  const CollectionKind(this.label);

  final String label;
}

class CollectionInfo {
  const CollectionInfo({required this.name, required this.kind});

  final String name;
  final CollectionKind kind;
}

/// One page of a find, in the server's order.
class DocumentPage {
  const DocumentPage({
    required this.documents,
    required this.elapsed,
    required this.hasMore,
  });

  /// Decoded BSON documents (ObjectId, DateTime, Int64, Decimal…).
  final List<Map<String, dynamic>> documents;
  final Duration elapsed;

  /// More documents match beyond this page.
  final bool hasMore;
}

abstract class DocumentDriver extends DatabaseDriver {
  Future<List<String>> listDatabases();
  Future<List<CollectionInfo>> listCollections(String database);

  Future<DocumentPage> find(
    String database,
    String collection, {
    Map<String, dynamic> filter = const {},
    Map<String, dynamic>? projection,
    Map<String, dynamic>? sort,
    int skip = 0,
    int limit = 20,
  });

  /// Runs an aggregation pipeline, returning at most [limit] documents.
  Future<DocumentPage> aggregate(
    String database,
    String collection,
    List<Map<String, dynamic>> pipeline, {
    int limit = 20,
  });

  Future<int> count(
    String database,
    String collection, [
    Map<String, dynamic> filter = const {},
  ]);

  /// Index specs as returned by the server (`name`, `key`, `unique`…).
  Future<List<Map<String, dynamic>>> listIndexes(
    String database,
    String collection,
  );

  /// Inserts [document] and returns its `_id`.
  Future<Object?> insertOne(
    String database,
    String collection,
    Map<String, dynamic> document,
  );

  /// Applies [update] (`$set`, `$unset`…) to the one document matching
  /// [filter]. Throws if nothing matched.
  Future<void> updateOne(
    String database,
    String collection,
    Map<String, dynamic> filter,
    Map<String, dynamic> update,
  );

  /// Deletes the one document matching [filter]. Throws if nothing matched.
  Future<void> deleteOne(
    String database,
    String collection,
    Map<String, dynamic> filter,
  );
}
