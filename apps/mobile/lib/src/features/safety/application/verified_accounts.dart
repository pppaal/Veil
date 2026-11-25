import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../conversations/data/messenger/identity_trust.dart';

/// The accounts every pinned device of which the user verified, with
/// nothing about them pending review: held in memory for the checks that
/// must answer at once (ContactTrust). Reloaded with one keystore read at
/// sign-in ([reload]), on every identity trust event and on every
/// verification.
class VerifiedAccounts extends ChangeNotifier {
  VerifiedAccounts(this._trust) {
    _events = _trust.events.listen((_) => unawaited(reload()));
    _verifications = _trust.verifications.listen((_) => unawaited(reload()));
  }

  final IdentityTrust _trust;
  late final StreamSubscription<IdentityTrustEvent> _events;
  late final StreamSubscription<IdentityVerified> _verifications;
  Set<String> _verified = const {};
  int _generation = 0;
  bool _disposed = false;

  /// Whether every pin of [userId] is verified and no change of theirs is
  /// pending now.
  bool isVerified(String userId) => _verified.contains(userId) && !_trust.hasPendingChangeAbout(userId);

  /// The accounts [isVerified] holds for, as last read.
  Iterable<String> get userIds => _verified.where((userId) => !_trust.hasPendingChangeAbout(userId));

  /// Reads the pins again. A keystore that cannot be read leaves the set as
  /// it was.
  Future<void> reload() async {
    final generation = ++_generation;
    final Map<String, bool> everyPinVerified = {};
    try {
      for (final pin in await _trust.resolver.allPins()) {
        everyPinVerified[pin.userId] = (everyPinVerified[pin.userId] ?? true) && pin.isVerified;
      }
    } catch (_) {
      return;
    }
    if (generation != _generation || _disposed) return;
    final next = {
      for (final MapEntry(:key, :value) in everyPinVerified.entries)
        if (value) key,
    };
    if (setEquals(next, _verified)) return;
    _verified = next;
    notifyListeners();
  }

  /// Forgets the set (sign-out).
  void clear() {
    _generation += 1;
    if (_verified.isEmpty) return;
    _verified = const {};
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_events.cancel());
    unawaited(_verifications.cancel());
    super.dispose();
  }
}
