/// Driver interface for key-value stores (Redis).
library;

import 'driver.dart';

/// A key from a scan, with what's needed to list it.
class KeyInfo {
  const KeyInfo({required this.name, required this.type, required this.ttl});

  final String name;

  /// Redis type: string, hash, list, set, zset, stream, ReJSON-RL…
  final String type;

  /// Seconds to live; -1 without expiry.
  final int ttl;
}

class KeyPage {
  const KeyPage({required this.keys, required this.cursor});

  final List<KeyInfo> keys;

  /// Where the next scan continues; '0' when the scan is complete.
  final String cursor;

  bool get done => cursor == '0';
}

/// A key's value, read up to a limit. Which field is filled depends on
/// [type].
class KeyData {
  const KeyData({
    required this.key,
    required this.type,
    required this.ttl,
    required this.length,
    this.memoryBytes,
    this.text,
    this.pairs = const [],
    this.items = const [],
    this.entries = const [],
  });

  final String key;
  final String type;
  final int ttl;

  /// Elements in the value (string: bytes).
  final int length;
  final int? memoryBytes;

  /// string and JSON values.
  final String? text;

  /// hash (field, value) and zset (member, score).
  final List<(String, String)> pairs;

  /// list and set members.
  final List<String> items;

  /// stream entries: (id, [field, value, …]).
  final List<(String, List<String>)> entries;

  int get shown => switch (type) {
    'hash' || 'zset' => pairs.length,
    'list' || 'set' => items.length,
    'stream' => entries.length,
    _ => length,
  };

  bool get truncated => shown < length;
}

abstract class KeyValueDriver extends DatabaseDriver {
  /// Number of logical databases (`databases` config; 16 by default).
  Future<int> databaseCount();

  /// Keys per non-empty database, from `INFO keyspace`.
  Future<Map<int, int>> keyCounts();

  /// One step of a SCAN over [db], continuing from [cursor].
  Future<KeyPage> scan(
    int db, {
    String pattern = '*',
    String cursor = '0',
    int count = 200,
  });

  /// Reads [key]'s value, at most [limit] elements of a collection.
  Future<KeyData> read(int db, String key, {int limit = 500});

  /// Runs a command on [db] for the browser; error replies throw
  /// [DriverException].
  Future<Object?> run(int db, List<String> args);

  /// Runs a console command on a separate connection, so a blocking command
  /// doesn't stall browsing. Error replies are returned, not thrown.
  /// [cancel] aborts it.
  Future<Object?> console(int db, List<String> args);
}
