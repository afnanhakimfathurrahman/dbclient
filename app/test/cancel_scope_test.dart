import 'dart:async';

import 'package:db_client/drivers/driver.dart';
import 'package:db_client/state/cancel_scope.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher get isCancelled => throwsA(
  isA<DriverException>().having(
    (e) => e.code,
    'code',
    CancelScope.cancelledCode,
  ),
);

void main() {
  setUp(() => CancelScope.grace = const Duration(milliseconds: 50));

  test('passes results and errors through when not cancelled', () async {
    final scope = CancelScope();
    expect(await scope.guard(Future.value(1)), 1);
    await expectLater(
      scope.guard(Future<int>.error(const DriverException('boom'))),
      throwsA(isA<DriverException>().having((e) => e.message, 'm', 'boom')),
    );
  });

  test('reports the work stopped by the server as cancelled', () async {
    final work = Completer<int>();
    var stopped = false;
    final scope = CancelScope(
      stop: () async {
        stopped = true;
        work.completeError(const DriverException('interrupted'));
      },
    );
    final result = expectLater(
      scope.guard(work.future).whenComplete(scope.end),
      isCancelled,
    );
    await scope.cancel();
    expect(stopped, isTrue);
    await result;
  });

  test('abandons at once without a way to stop the server', () async {
    final scope = CancelScope();
    final result = expectLater(
      scope.guard(Completer<int>().future),
      isCancelled,
    );
    final watch = Stopwatch()..start();
    await scope.cancel();
    await result;
    expect(watch.elapsed, lessThan(CancelScope.grace));
  });

  test('abandons and resets after the grace period', () async {
    var reset = false;
    final scope = CancelScope(
      stop: () => Completer<void>().future, // A cancel that never returns.
      onAbandon: () async => reset = true,
    );
    final result = expectLater(
      scope.guard(Completer<int>().future),
      isCancelled,
    );
    await scope.cancel();
    await result;
    expect(reset, isTrue);
  });

  test('cancel after the work ended does nothing', () async {
    var stopped = false;
    final scope = CancelScope(stop: () async => stopped = true);
    await scope.guard(Future.value(1));
    scope.end();
    await scope.cancel();
    expect(stopped, isFalse);
    expect(scope.cancelled, isFalse);
  });
}
