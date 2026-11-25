import '../../../../core/network/keys_api.dart';

/// Short-lived memory of directory answers, per handle. Every directory
/// lookup tells the server "someone is about to message @handle" and claims
/// one of the peer's one-time prekeys, so session setup reuses a recent
/// answer instead of asking again.
class PeerBundleCache {
  PeerBundleCache({
    this.ttl = const Duration(minutes: 10),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _clock;
  final Map<String, (DirectoryDevice, DateTime, int)> _entries = {};

  DirectoryDevice? fresh(String handle) => freshRead(handle)?.device;

  /// A recent answer for [handle], with the identity check mark taken when
  /// it was asked for (IdentityTrust.checkMark).
  ({DirectoryDevice device, int checkMark})? freshRead(String handle) {
    final entry = _entries[handle];
    if (entry == null) {
      return null;
    }
    final (device, fetchedAt, checkMark) = entry;
    if (_clock().difference(fetchedAt) >= ttl) {
      _entries.remove(handle);
      return null;
    }
    return (device: device, checkMark: checkMark);
  }

  void remember(String handle, DirectoryDevice device, {int checkMark = 0}) {
    _entries[handle] = (device, _clock(), checkMark);
  }

  /// A one-time prekey opens one session only; a later bootstrap from the
  /// same answer runs without it.
  void spendOneTimePrekey(String handle) {
    final entry = _entries[handle];
    if (entry == null) return;
    final (device, fetchedAt, checkMark) = entry;
    _entries[handle] = (DirectoryDevice(bundle: device.bundle, isActive: device.isActive), fetchedAt, checkMark);
  }

  void clear() => _entries.clear();
}
