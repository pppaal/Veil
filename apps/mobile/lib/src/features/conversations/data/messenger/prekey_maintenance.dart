import 'dart:async';

import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/network/keys_api.dart';

/// Keeps this device reachable through the key directory: enough one-time
/// prekeys for initiators to claim, a signed prekey younger than a week, and
/// superseded signed prekeys dropped once their grace period is over.
///
/// A run publishes before it prunes and stops at the first failure, so a
/// signed prekey the directory still serves is never deleted locally.
class PrekeyMaintenance {
  PrekeyMaintenance({
    required PrekeyManager prekeys,
    required KeysApi keys,
    required Future<void> Function(String identityPrivateRef) persistIdentityRef,
    DateTime Function()? clock,
  })  : _prekeys = prekeys,
        _keys = keys,
        _persistIdentityRef = persistIdentityRef,
        _clock = clock ?? DateTime.now;

  /// Below this many unclaimed one-time prekeys the pool is refilled.
  static const int minimumOneTimePrekeys = 20;

  /// The pool is refilled up to this size, the most one upload may carry.
  static const int oneTimePrekeyPoolSize = 100;

  static const Duration signedPrekeyMaxAge = Duration(days: 7);
  static const Duration signedPrekeyGrace = Duration(days: 14);

  /// Resuming the app runs maintenance at most this often.
  static const Duration resumeInterval = Duration(hours: 6);

  final PrekeyManager _prekeys;
  final KeysApi _keys;
  final Future<void> Function(String identityPrivateRef) _persistIdentityRef;
  final DateTime Function() _clock;
  DateTime? _lastCompletedAt;
  Future<void>? _running;

  /// Runs maintenance unless a run completed within [resumeInterval];
  /// [force] skips that check (sign-in, a completed device transfer).
  /// Concurrent calls share one run. Best effort: a failed run is retried by
  /// the next call and never throws.
  Future<void> run({required String accessToken, bool force = false}) {
    final running = _running;
    if (running != null) return running;
    final last = _lastCompletedAt;
    if (!force && last != null && _clock().difference(last) < resumeInterval) {
      return Future<void>.value();
    }
    return _running = _runOnce(accessToken).whenComplete(() => _running = null);
  }

  Future<void> _runOnce(String accessToken) async {
    final startedAt = _clock();
    try {
      await _refillOneTimePrekeys(accessToken);
      await _rotateSignedPrekeyIfDue(accessToken, startedAt);
      await _prekeys.pruneSignedPrekeys(grace: signedPrekeyGrace);
      _lastCompletedAt = startedAt;
    } catch (_) {
      // Offline or refused: the directory keeps serving what it has, and the
      // next run starts over.
    }
  }

  Future<void> _refillOneTimePrekeys(String accessToken) async {
    final available = await _keys.oneTimePrekeyCount(accessToken: accessToken);
    if (available >= minimumOneTimePrekeys) return;
    final fresh = await _prekeys.generateOneTimePrekeys(count: oneTimePrekeyPoolSize - available);
    await _keys.uploadOneTimePrekeys(fresh, accessToken: accessToken);
  }

  // A v1 identity has no signed prekey of its own, so it reports none and is
  // rotated at once; that rotation also yields the v2 identity ref, which is
  // stored before the new bundle is published.
  Future<void> _rotateSignedPrekeyIfDue(String accessToken, DateTime now) async {
    final createdAt = await _prekeys.currentSignedPrekeyCreatedAt();
    if (createdAt != null && now.difference(createdAt) <= signedPrekeyMaxAge) return;
    final rotation = await _prekeys.rotateSignedPrekey();
    final upgradedRef = rotation.upgradedIdentityPrivateRef;
    if (upgradedRef != null) await _persistIdentityRef(upgradedRef);
    await _keys.rotateSignedPrekey(rotation.signedPrekeyBundle, accessToken: accessToken);
  }
}
