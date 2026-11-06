import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show TextEditingController;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:re_editor/re_editor.dart';
import 'package:uuid/uuid.dart';

import '../data/repositories.dart';
import '../drivers/document.dart';
import '../drivers/driver.dart';
import '../drivers/key_value.dart';
import '../drivers/mongodb/mongo_json.dart';
import '../drivers/redis/resp.dart';
import '../drivers/sql_splitter.dart';
import 'data_editor.dart';
import 'providers.dart';

/// Outcome of one statement in a run.
class StatementOutcome {
  const StatementOutcome(this.sql, {this.result, this.error});

  final String sql;
  final QueryResult? result;
  final DriverException? error;
}

/// A tab in the workspace: a SQL editor or an object inspector.
sealed class WorkspaceTab extends ChangeNotifier {
  final String id = const Uuid().v4();

  String get title;
  String get connectionId;

  /// Shows a spinner on the tab while true.
  bool get busy;

  Future<void> cancel() async {}

  bool _disposed = false;

  // Async work can finish after its tab was closed; drop those updates.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Inspector for one table, view, materialized view or sequence. Caches the
/// data preview so switching tabs doesn't re-query.
class InspectorTab extends WorkspaceTab {
  InspectorTab({
    required this.connectionId,
    required this.object,
    this.rowLimit = defaultRowLimit,
  });

  @override
  final String connectionId;
  final DbObject object;

  static const defaultRowLimit = 20;
  static const maxRowLimit = 10000;

  /// How many rows the Data tab loads.
  int rowLimit;

  @override
  String get title =>
      (_editor?.hasChanges ?? false) ? '${object.name} •' : object.name;

  QueryResult? _preview;
  QueryResult? get preview => _preview;

  /// Staged row edits for the preview; null when the data is read-only
  /// (see [readOnlyReason]).
  DataEditController? _editor;
  DataEditController? get editor => _editor;

  /// Why the preview can't be edited, shown in the Data tab.
  String? _readOnlyReason;
  String? get readOnlyReason => _readOnlyReason;

  bool get hasUnsavedChanges => _editor?.hasChanges ?? false;

  void _setEditor(DataEditController? editor) {
    _editor?.removeListener(notifyListeners);
    _editor?.dispose();
    _editor = editor;
    // Re-notify so the tab title shows the unsaved marker.
    editor?.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _setEditor(null);
    super.dispose();
  }

  DriverException? _previewError;
  DriverException? get previewError => _previewError;

  bool _loading = false;
  @override
  bool get busy => _loading;

  bool get previewLoaded => _preview != null || _previewError != null;

  Future<void> loadPreview(SqlDriver driver, String sql) async {
    if (_loading) return;
    _loading = true;
    _previewError = null;
    notifyListeners();
    try {
      // The SQL asks for one extra row, so [QueryResult.truncated] tells
      // whether the table has more than [rowLimit].
      final preview = await driver.execute(sql, maxRows: rowLimit);
      _preview = preview;
      await _prepareEditing(driver, preview);
    } on DriverException catch (e) {
      _previewError = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Rows are edited by primary key, so only tables with one are editable.
  Future<void> _prepareEditing(SqlDriver driver, QueryResult preview) async {
    _setEditor(null);
    if (!object.kind.isTable) {
      _readOnlyReason = '${object.kind.label}s are read-only here';
      return;
    }
    if (!driver.features.contains(SqlFeature.rowEditing)) {
      _readOnlyReason =
          'Read-only: ${driver.config.engine.label} rows are changed with '
          'SQL (e.g. ALTER TABLE … UPDATE)';
      return;
    }
    final List<ColumnInfo> columns;
    try {
      columns = await driver.listColumns(object.schema, object.name);
    } on DriverException catch (e) {
      // The data still shows; only editing is unavailable.
      _readOnlyReason =
          'Read-only: could not read the primary key (${e.message})';
      return;
    }
    final keyNames = {
      for (final c in columns)
        if (c.isPrimaryKey) c.name,
    };
    final keyColumns = [
      for (final (i, c) in preview.columns.indexed)
        if (keyNames.contains(c.name)) i,
    ];
    if (keyNames.isEmpty || keyColumns.length != keyNames.length) {
      _readOnlyReason = 'Read-only: the table has no primary key';
      return;
    }
    _readOnlyReason = null;
    _setEditor(
      DataEditController(
        schema: object.schema,
        table: object.name,
        columns: preview.columns,
        baseRows: preview.rows,
        keyColumns: keyColumns,
        dialect: driver.dialect,
      ),
    );
  }

  bool shows(String connectionId, DbObject other) =>
      this.connectionId == connectionId &&
      object.schema == other.schema &&
      object.name == other.name;
}

enum DocumentQueryMode { find, aggregate }

/// A MongoDB collection: query inputs (kept across tab switches) and the
/// current page of documents.
class CollectionTab extends WorkspaceTab {
  CollectionTab({
    required this.connectionId,
    required this.database,
    required this.info,
    this.limit = InspectorTab.defaultRowLimit,
  });

  @override
  final String connectionId;
  final String database;
  final CollectionInfo info;

  String get collection => info.name;

  @override
  String get title => collection;

  final filter = TextEditingController();
  final projection = TextEditingController();
  final sort = TextEditingController();
  final pipeline = TextEditingController(
    text: '[\n  { \$match: {} },\n  { \$group: { _id: null, count: { \$sum: 1 } } }\n]',
  );

  DocumentQueryMode mode = DocumentQueryMode.find;
  int skip = 0;
  int limit;

  DocumentPage? _page;
  DocumentPage? get page => _page;

  /// Documents matching the filter; null for aggregations or until known.
  int? _total;
  int? get total => _total;

  /// A parse error in the inputs or a server error.
  Object? _error;
  Object? get error => _error;

  bool _loading = false;
  @override
  bool get busy => _loading;

  bool get loaded => _page != null || _error != null;

  /// Runs the current query. [resetSkip] starts again from the first page.
  Future<void> run(DocumentDriver driver, {bool resetSkip = false}) async {
    if (_loading) return;
    if (resetSkip) skip = 0;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (mode == DocumentQueryMode.find) {
        final filterDoc = parseMongoDocument(filter.text, what: 'filter');
        final page = await driver.find(
          database,
          collection,
          filter: filterDoc,
          projection: parseMongoDocument(projection.text, what: 'projection'),
          sort: parseMongoDocument(sort.text, what: 'sort'),
          skip: skip,
          limit: limit,
        );
        _page = page;
        _total = await driver.count(database, collection, filterDoc);
      } else {
        final stages = parseMongo(pipeline.text);
        if (stages is! List || stages.any((s) => s is! Map<String, dynamic>)) {
          throw const FormatException(
            'The pipeline must be an array of stages: [ { \$match: … } ]',
          );
        }
        _page = await driver.aggregate(
          database,
          collection,
          stages.cast<Map<String, dynamic>>(),
          limit: limit,
        );
        _total = null;
      }
    } on FormatException catch (e) {
      _error = e.message;
    } on DriverException catch (e) {
      _error = e;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  bool shows(String connectionId, String database, String collection) =>
      this.connectionId == connectionId &&
      this.database == database &&
      this.collection == collection;

  @override
  void dispose() {
    for (final c in [filter, projection, sort, pipeline]) {
      c.dispose();
    }
    super.dispose();
  }
}

/// One Redis database: a key browser (pattern scan, selected key's value)
/// and a redis-cli style console.
class RedisTab extends WorkspaceTab {
  RedisTab({required this.connectionId, required this.db});

  @override
  final String connectionId;
  final int db;

  @override
  String get title => 'db$db';

  // Key browser.
  final pattern = TextEditingController(text: '*');
  List<KeyInfo> keys = const [];
  String _cursor = '0';
  bool get scanComplete => _cursor == '0';
  bool _scanned = false;
  bool get scanned => _scanned;
  Object? scanError;

  String? selectedKey;
  KeyData? value;
  Object? valueError;

  // Console.
  bool consoleMode = false;
  final consoleInput = TextEditingController();
  final consoleLog = <(String command, Object? reply)>[];
  final history = <String>[];

  KeyValueDriver? _consoleDriver;
  bool _scanning = false;
  bool _reading = false;
  bool _consoleRunning = false;
  bool get consoleRunning => _consoleRunning;

  @override
  bool get busy => _scanning || _reading || _consoleRunning;

  bool get scanning => _scanning;
  bool get reading => _reading;

  /// Scans from the start, or continues with [more].
  Future<void> scan(KeyValueDriver driver, {bool more = false}) async {
    if (_scanning) return;
    _scanning = true;
    scanError = null;
    notifyListeners();
    try {
      final page = await driver.scan(
        db,
        pattern: pattern.text.trim(),
        cursor: more ? _cursor : '0',
      );
      keys = more ? [...keys, ...page.keys] : page.keys;
      _cursor = page.cursor;
      _scanned = true;
    } on DriverException catch (e) {
      scanError = e;
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> open(KeyValueDriver driver, String key) async {
    selectedKey = key;
    value = null;
    await reloadValue(driver);
  }

  Future<void> reloadValue(KeyValueDriver driver) async {
    final key = selectedKey;
    if (key == null) return;
    _reading = true;
    valueError = null;
    notifyListeners();
    try {
      final data = await driver.read(db, key);
      // Ignore a late reply after another key was selected.
      if (selectedKey == key) value = data;
    } on DriverException catch (e) {
      if (selectedKey == key) {
        value = null;
        valueError = e;
      }
    } finally {
      _reading = false;
      notifyListeners();
    }
  }

  /// Drops a key that was deleted or renamed from the list.
  void forgetKey(String key) {
    keys = [
      for (final k in keys)
        if (k.name != key) k,
    ];
    if (selectedKey == key) {
      selectedKey = null;
      value = null;
    }
    notifyListeners();
  }

  Future<void> runConsole(KeyValueDriver driver, String line) async {
    final List<String> args;
    try {
      args = splitRedisCommand(line);
    } on FormatException catch (e) {
      consoleLog.add((line, RespError('ERR ${e.message}')));
      notifyListeners();
      return;
    }
    if (args.isEmpty) return;
    if (history.isEmpty || history.last != line) history.add(line);
    _consoleRunning = true;
    _consoleDriver = driver;
    notifyListeners();
    Object? reply;
    try {
      reply = await driver.console(db, args);
    } on DriverException catch (e) {
      reply = RespError(e.message);
    } finally {
      _consoleRunning = false;
      _consoleDriver = null;
    }
    consoleLog.add((line, reply));
    notifyListeners();
  }

  @override
  Future<void> cancel() async => _consoleDriver?.cancel();

  @override
  void dispose() {
    pattern.dispose();
    consoleInput.dispose();
    super.dispose();
  }
}

/// One SQL editor tab: its text, the connection it targets and the results
/// of the last run.
class EditorTab extends WorkspaceTab {
  EditorTab({
    required this.title,
    required this._connectionId,
    String initialText = '',
  }) : controller = CodeLineEditingController.fromText(initialText);

  @override
  final String title;
  final CodeLineEditingController controller;

  String _connectionId;
  @override
  String get connectionId => _connectionId;
  set connectionId(String value) {
    if (value == _connectionId) return;
    _connectionId = value;
    notifyListeners();
  }

  @override
  bool get busy => _running;

  bool _running = false;
  bool get running => _running;

  List<StatementOutcome> _outcomes = const [];
  List<StatementOutcome> get outcomes => _outcomes;

  int _selectedOutcome = 0;
  int get selectedOutcome => _selectedOutcome;
  set selectedOutcome(int value) {
    _selectedOutcome = value;
    notifyListeners();
  }

  SqlDriver? _runningOn;

  /// Text of the statement under the cursor, or the selection if any.
  String? currentStatement() {
    final selected = controller.selectedText;
    if (selected.trim().isNotEmpty) return selected;
    final text = controller.text;
    final statement = statementAt(text, _cursorOffset(text));
    return statement?.text;
  }

  /// All statements in the selection, or in the whole script.
  List<String> allStatements() {
    final selected = controller.selectedText;
    final source = selected.trim().isNotEmpty ? selected : controller.text;
    return [for (final s in splitSql(source)) s.text];
  }

  Future<void> run(
    List<String> statements,
    SqlDriver driver,
    HistoryRepository history,
  ) async {
    if (_running || statements.isEmpty) return;
    _running = true;
    _runningOn = driver;
    _outcomes = const [];
    _selectedOutcome = 0;
    notifyListeners();

    final outcomes = <StatementOutcome>[];
    try {
      for (final sql in statements) {
        final watch = Stopwatch()..start();
        try {
          final result = await driver.execute(sql);
          outcomes.add(StatementOutcome(sql, result: result));
          await history.add(
            connectionId: connectionId,
            sql: sql,
            duration: result.elapsed,
            rowCount: result.hasResultSet
                ? result.rows.length
                : result.affectedRows,
          );
        } on DriverException catch (e) {
          outcomes.add(StatementOutcome(sql, error: e));
          await history.add(
            connectionId: connectionId,
            sql: sql,
            duration: watch.elapsed,
            error: e.message,
          );
          break; // Stop the script at the first failing statement.
        }
        _outcomes = List.unmodifiable(outcomes);
        notifyListeners();
      }
    } finally {
      _outcomes = List.unmodifiable(outcomes);
      // Show the last statement that produced rows; otherwise the last one.
      final withRows = outcomes.lastIndexWhere(
        (o) => o.result?.hasResultSet ?? false,
      );
      final failed = outcomes.indexWhere((o) => o.error != null);
      _selectedOutcome = failed != -1
          ? failed
          : (withRows != -1 ? withRows : outcomes.length - 1).clamp(
              0,
              outcomes.length,
            );
      _running = false;
      _runningOn = null;
      notifyListeners();
    }
  }

  @override
  Future<void> cancel() async {
    await _runningOn?.cancel();
  }

  int _cursorOffset(String text) {
    final position = controller.selection.extent;
    final lines = text.split('\n');
    var offset = 0;
    for (var i = 0; i < position.index && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    return offset + position.offset;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

class WorkspaceTabsState {
  const WorkspaceTabsState({this.tabs = const [], this.activeId});

  final List<WorkspaceTab> tabs;
  final String? activeId;

  WorkspaceTab? get active {
    for (final tab in tabs) {
      if (tab.id == activeId) return tab;
    }
    return null;
  }
}

class WorkspaceTabsNotifier extends Notifier<WorkspaceTabsState> {
  int _counter = 0;

  @override
  WorkspaceTabsState build() {
    ref.onDispose(() {
      for (final tab in state.tabs) {
        tab.dispose();
      }
    });
    return const WorkspaceTabsState();
  }

  EditorTab open(String connectionId, {String initialText = ''}) {
    _counter++;
    final tab = EditorTab(
      title: 'Script-$_counter',
      connectionId: connectionId,
      initialText: initialText,
    );
    state = WorkspaceTabsState(tabs: [...state.tabs, tab], activeId: tab.id);
    return tab;
  }

  /// Opens an inspector for [object], or switches to it if already open.
  void openInspector(String connectionId, DbObject object) {
    for (final tab in state.tabs) {
      if (tab is InspectorTab && tab.shows(connectionId, object)) {
        activate(tab.id);
        return;
      }
    }
    final tab = InspectorTab(
      connectionId: connectionId,
      object: object,
      rowLimit: ref.read(dataRowLimitProvider),
    );
    state = WorkspaceTabsState(tabs: [...state.tabs, tab], activeId: tab.id);
  }

  /// Opens a Redis database, or switches to it if already open.
  void openRedis(String connectionId, int db) {
    for (final tab in state.tabs) {
      if (tab is RedisTab && tab.connectionId == connectionId && tab.db == db) {
        activate(tab.id);
        return;
      }
    }
    final tab = RedisTab(connectionId: connectionId, db: db);
    state = WorkspaceTabsState(tabs: [...state.tabs, tab], activeId: tab.id);
  }

  /// Opens a collection, or switches to it if already open.
  void openCollection(
    String connectionId,
    String database,
    CollectionInfo info,
  ) {
    for (final tab in state.tabs) {
      if (tab is CollectionTab &&
          tab.shows(connectionId, database, info.name)) {
        activate(tab.id);
        return;
      }
    }
    final tab = CollectionTab(
      connectionId: connectionId,
      database: database,
      info: info,
      limit: ref.read(dataRowLimitProvider),
    );
    state = WorkspaceTabsState(tabs: [...state.tabs, tab], activeId: tab.id);
  }

  void activate(String id) {
    state = WorkspaceTabsState(tabs: state.tabs, activeId: id);
  }

  void close(String id) {
    final index = state.tabs.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final tab = state.tabs[index];
    final remaining = [...state.tabs]..removeAt(index);
    String? activeId = state.activeId;
    if (activeId == id) {
      activeId = remaining.isEmpty
          ? null
          : remaining[(index - 1).clamp(0, remaining.length - 1)].id;
    }
    state = WorkspaceTabsState(tabs: remaining, activeId: activeId);
    tab.cancel();
    tab.dispose();
  }

  /// Closes every tab bound to [connectionId], e.g. after it was deleted.
  void closeForConnection(String connectionId) {
    for (final tab in [...state.tabs]) {
      if (tab.connectionId == connectionId) close(tab.id);
    }
  }
}

final workspaceTabsProvider =
    NotifierProvider<WorkspaceTabsNotifier, WorkspaceTabsState>(
      WorkspaceTabsNotifier.new,
    );
