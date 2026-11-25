import 'dart:async';

/// Polls [condition] until it holds, failing after [timeout]. Keeps the
/// real-time suites fast without fixed sleeps sized for the slowest path.
Future<void> waitFor(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 3),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(reason ?? 'condition not met', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Lets queued microtasks, debounced sync hints and outbox drains finish.
Future<void> settle([Duration duration = const Duration(milliseconds: 260)]) =>
    Future<void>.delayed(duration);
