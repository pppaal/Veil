import '../../../../core/crypto/crypto_engine.dart';

/// Short-lived memory of directory answers, per handle. Every directory
/// fetch tells the server "someone is about to message @handle", so session
/// setup reuses a recent answer instead of asking again.
class PeerBundleCache {
  PeerBundleCache({
    this.ttl = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _clock;
  final Map<String, (KeyBundle, DateTime)> _entries = {};

  KeyBundle? fresh(String handle) {
    final entry = _entries[handle];
    if (entry == null) {
      return null;
    }
    final (bundle, fetchedAt) = entry;
    if (_clock().difference(fetchedAt) >= ttl) {
      _entries.remove(handle);
      return null;
    }
    return bundle;
  }

  void remember(String handle, KeyBundle bundle) {
    _entries[handle] = (bundle, _clock());
  }

  void clear() => _entries.clear();
}
