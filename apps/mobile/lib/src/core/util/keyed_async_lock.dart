import 'dart:async';

/// Serializes asynchronous critical sections that share a key while letting
/// different keys run concurrently.
///
/// Crypto state machines (a group's sender-key chains, the identity pin
/// table) mutate across several `await`s; without this, two calls on the same
/// key can both start from the same snapshot and the later commit silently
/// rewinds the earlier one. Not re-entrant: an action must never wait on the
/// same key it already holds.
class KeyedAsyncLock<K> {
  final Map<K, Future<void>> _tails = <K, Future<void>>{};

  /// Runs [action] once every earlier action queued under [key] has settled,
  /// and completes with its result or error.
  Future<T> synchronized<T>(K key, Future<T> Function() action) async {
    final previous = _tails[key];
    final released = Completer<void>();
    final tail = released.future;
    _tails[key] = tail;
    try {
      if (previous != null) await previous;
      return await action();
    } finally {
      released.complete();
      if (identical(_tails[key], tail)) {
        _tails.remove(key);
      }
    }
  }
}
