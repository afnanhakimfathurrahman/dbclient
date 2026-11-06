import 'package:flutter/material.dart';

import '../drivers/driver.dart';

/// Icon and brand-neutral accent for each engine, used by the connection
/// picker and the navigator.
extension EngineStyle on DatabaseEngine {
  IconData get icon => switch (this) {
    DatabaseEngine.postgres => Icons.storage_rounded,
    DatabaseEngine.mysql => Icons.dataset_rounded,
    DatabaseEngine.clickhouse => Icons.view_week_rounded,
    DatabaseEngine.mongodb => Icons.eco_rounded,
    DatabaseEngine.redis => Icons.bolt_rounded,
  };

  Color get accent => switch (this) {
    DatabaseEngine.postgres => const Color(0xFF3B82F6),
    DatabaseEngine.mysql => const Color(0xFF0EA5E9),
    DatabaseEngine.clickhouse => const Color(0xFFEAB308),
    DatabaseEngine.mongodb => const Color(0xFF10B981),
    DatabaseEngine.redis => const Color(0xFFEF4444),
  };

  /// One line for the picker.
  String get blurb => switch (this) {
    DatabaseEngine.postgres => 'Relational · SQL',
    DatabaseEngine.mysql => 'Relational · MySQL & MariaDB',
    DatabaseEngine.clickhouse => 'Analytics · SQL over HTTP',
    DatabaseEngine.mongodb => 'Documents · JSON queries',
    DatabaseEngine.redis => 'Key-value · commands',
  };
}
