import 'dart:async';

import 'package:db_client/data/repositories.dart';
import 'package:db_client/drivers/driver.dart';
import 'package:db_client/state/cancel_scope.dart';
import 'package:db_client/state/workspace_tabs.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHistory implements HistoryRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

/// Statements hang until [cancel]; with [honorsCancel] false the cancel
/// itself hangs too, like a dead network.
class FakeDriver implements SqlDriver {
  FakeDriver({this.honorsCancel = true});

  final bool honorsCancel;
  final executed = <String>[];
  Completer<QueryResult>? _running;

  @override
  Future<QueryResult> execute(String sql, {int maxRows = 10000}) {
    executed.add(sql);
    return (_running = Completer<QueryResult>()).future;
  }

  @override
  Future<void> cancel() {
    if (!honorsCancel) return Completer<void>().future;
    _running?.completeError(
      const DriverException(
        'canceling statement due to user request',
        code: '57014',
      ),
    );
    return Future.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late EditorTab tab;

  setUp(() {
    tab = EditorTab(title: 't', connectionId: 'c');
    CancelScope.grace = const Duration(milliseconds: 50);
  });

  tearDown(() => tab.dispose());

  test('cancel stops the statement and skips the rest of the script', () async {
    final driver = FakeDriver();
    var abandoned = false;
    final run = tab.run(
      ['select pg_sleep(60)', 'select 2'],
      driver,
      FakeHistory(),
      onAbandon: () async => abandoned = true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(tab.running, isTrue);

    await tab.cancel();
    await run;

    expect(tab.running, isFalse);
    expect(tab.cancelling, isFalse);
    expect(driver.executed, ['select pg_sleep(60)']);
    final error = tab.outcomes.single.error!;
    expect(error.code, CancelScope.cancelledCode);
    expect(error.detail, 'canceling statement due to user request');
    expect(abandoned, isFalse);
  });

  test('a statement the server does not stop is abandoned', () async {
    final driver = FakeDriver(honorsCancel: false);
    var abandoned = false;
    final run = tab.run(
      ['select pg_sleep(60)'],
      driver,
      FakeHistory(),
      onAbandon: () async => abandoned = true,
    );
    await Future<void>.delayed(Duration.zero);

    final cancel = tab.cancel();
    expect(tab.cancelling, isTrue);
    await cancel;
    await run;

    expect(tab.running, isFalse);
    expect(tab.outcomes.single.error?.code, CancelScope.cancelledCode);
    expect(abandoned, isTrue);
  });

  test('cancel while idle does nothing', () async {
    await tab.cancel();
    expect(tab.cancelling, isFalse);
  });
}
