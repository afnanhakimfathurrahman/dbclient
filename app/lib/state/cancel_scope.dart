import 'dart:async';

import '../drivers/driver.dart';

/// Makes one user operation (a query, a script, a page of documents)
/// cancellable, and guarantees cancel never leaves it hanging.
///
/// [cancel] asks the server to stop through [stop]. Work wrapped in [guard]
/// then fails with a [DriverException] coded [cancelledCode]. If it hasn't
/// ended after [grace] (the cancel failed or the network is gone), it is
/// abandoned: [guard] stops waiting and [onAbandon] resets the connection
/// the work still holds. Without a [stop] there is nothing to wait for and
/// the work is abandoned at once.
class CancelScope {
  CancelScope({this.stop, this.onAbandon});

  final Future<void> Function()? stop;
  final Future<void> Function()? onAbandon;

  static const cancelledCode = 'CANCELLED';

  /// How long cancelled work gets to stop before it is abandoned.
  static Duration grace = const Duration(seconds: 5);

  /// Completed (with a value, so it is never an unhandled error) when the
  /// work is abandoned.
  final _abandoned = Completer<DriverException>();
  final _ended = Completer<void>();

  bool _cancelled = false;
  bool get cancelled => _cancelled;

  bool get ended => _ended.isCompleted;

  /// Waits for [work]. After [cancel], its failure (or abandonment) is
  /// reported as a cancellation.
  Future<T> guard<T>(Future<T> work) async {
    try {
      return await Future.any([
        work,
        _abandoned.future.then<T>((e) => throw e),
      ]);
    } catch (e) {
      if (!_cancelled) rethrow;
      if (e is DriverException && e.code == cancelledCode) rethrow;
      throw DriverException(
        'Query cancelled',
        code: cancelledCode,
        detail: e is DriverException ? e.message : '$e',
      );
    }
  }

  /// Marks the operation finished; a later [cancel] does nothing.
  void end() {
    if (!_ended.isCompleted) _ended.complete();
  }

  Future<void> cancel() async {
    if (_cancelled || ended) return;
    _cancelled = true;
    final stop = this.stop;
    if (stop != null) {
      final deadline = Stopwatch()..start();
      try {
        await stop().timeout(grace);
      } catch (_) {
        // Falls back to abandoning below.
      }
      final left = grace - deadline.elapsed;
      try {
        await _ended.future.timeout(left.isNegative ? Duration.zero : left);
        return;
      } on TimeoutException {
        // Still running: give up on it.
      }
    }
    if (ended || _abandoned.isCompleted) return;
    _abandoned.complete(
      DriverException(
        stop == null
            ? 'Query cancelled'
            : 'Query cancelled. The server did not stop it in time, so the '
                  'connection was reset.',
        code: cancelledCode,
      ),
    );
    try {
      await onAbandon?.call();
    } catch (_) {
      // Already broken; the next query reconnects.
    }
  }
}
