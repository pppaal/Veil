import 'dart:async';

/// Per-key async serial lock. Every operation that reads and then replaces a
/// conversation's ratchet state runs inside it, so an encrypt can never
/// interleave with a decrypt (or a second encrypt) and reuse a counter.
///
/// Not re-entrant: an action must not wait on the same key again.
class SessionLock {
  final Map<String, Future<void>> _tails = {};

  Future<T> synchronized<T>(String key, Future<T> Function() action) {
    final previous = _tails[key] ?? Future<void>.value();
    final done = Completer<void>();
    final tail = done.future;
    _tails[key] = tail;
    return previous.then((_) => action()).whenComplete(() {
      done.complete();
      if (identical(_tails[key], tail)) _tails.remove(key);
    });
  }
}
