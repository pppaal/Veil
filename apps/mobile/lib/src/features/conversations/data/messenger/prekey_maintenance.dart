import 'dart:async';

import '../../../../app/app_session_state.dart';
import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/network/keys_api.dart';
import '../../../../core/network/veil_api_exception.dart';

/// Keeps this device reachable through the key directory: enough one-time
/// prekeys for initiators to claim, a published signed prekey younger than a
/// week, and superseded signed prekeys dropped once their grace period is
/// over.
///
/// What the directory serves is what it last accepted, which the keyring
/// records; a run publishes until the newest signed prekey is that one, so a
/// publish that failed is retried by the next run. Pruning keeps the
/// published signed prekey and everything newer, so the one the directory
/// still serves is never deleted locally.
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
  // One-time prekeys generated for a device whose upload did not complete.
  // Their private halves are stored, so the next run uploads these instead
  // of generating more (the directory skips any it already holds).
  ({String deviceId, List<OneTimePrekey> prekeys})? _unpublished;

  /// Runs maintenance for [session]'s device unless a run completed within
  /// [resumeInterval]; [force] skips that check (sign-in, a completed device
  /// transfer). Concurrent calls share one run. Best effort: a failed run is
  /// retried by the next call and never throws.
  Future<void> run(AppSessionState session, {bool force = false}) {
    final running = _running;
    if (running != null) return running;
    final accessToken = session.accessToken;
    final handle = session.handle;
    final deviceId = session.deviceId;
    final last = _lastCompletedAt;
    if (accessToken == null || handle == null || deviceId == null) return Future<void>.value();
    if (!force && last != null && _clock().difference(last) < resumeInterval) {
      return Future<void>.value();
    }
    final device = (accessToken: accessToken, handle: handle, deviceId: deviceId);
    return _running = _runOnce(device).whenComplete(() => _running = null);
  }

  Future<void> _runOnce(_Device device) async {
    final startedAt = _clock();
    try {
      await _refillOneTimePrekeys(device);
      await _publishSignedPrekeyIfDue(device, startedAt);
      await _prekeys.pruneSignedPrekeys(grace: signedPrekeyGrace);
      _lastCompletedAt = startedAt;
    } catch (_) {
      // Offline or refused: the directory keeps serving what it has, and the
      // next run starts over.
    }
  }

  Future<void> _refillOneTimePrekeys(_Device device) async {
    final unpublished = _unpublished;
    if (unpublished != null && unpublished.deviceId == device.deviceId) {
      await _keys.uploadOneTimePrekeys(unpublished.prekeys, accessToken: device.accessToken);
    }
    _unpublished = null;
    final available = await _keys.oneTimePrekeyCount(accessToken: device.accessToken);
    if (available >= minimumOneTimePrekeys) return;
    final fresh = await _prekeys.generateOneTimePrekeys(count: oneTimePrekeyPoolSize - available);
    _unpublished = (deviceId: device.deviceId, prekeys: fresh);
    await _keys.uploadOneTimePrekeys(fresh, accessToken: device.accessToken);
    _unpublished = null;
  }

  // A fresh signed prekey the directory never accepted (its publish failed)
  // is published as it is; one older than a week is replaced first. A v1
  // identity has no signed prekey of its own, so it reports none and is
  // rotated at once. Either way a v1 identity ref is upgraded to v2, and the
  // new ref is stored before the bundle that needs it is published.
  Future<void> _publishSignedPrekeyIfDue(_Device device, DateTime now) async {
    final current = await _prekeys.currentSignedPrekey();
    final fresh = current != null && now.difference(current.createdAt) <= signedPrekeyMaxAge;
    if (fresh && current.spkId == await _prekeys.publishedSignedPrekeyId()) return;
    final next = fresh ? current : await _prekeys.rotateSignedPrekey();
    final upgradedRef = next.upgradedIdentityPrivateRef;
    if (upgradedRef != null) await _persistIdentityRef(upgradedRef);
    try {
      await _keys.rotateSignedPrekey(next.signedPrekeyBundle, accessToken: device.accessToken);
    } on VeilApiException catch (error) {
      // A publish whose answer was lost left the directory holding this very
      // bundle, and it refuses the same spkId twice; that refusal must not
      // keep every later run from recording the publish.
      if ((error.statusCode ?? 0) ~/ 100 != 4 || !await _directoryServes(device, next.signedPrekeyBundle)) rethrow;
    }
    await _prekeys.markSignedPrekeyPublished(next.spkId);
  }

  Future<bool> _directoryServes(_Device device, String signedPrekeyBundle) async {
    final entry = await _keys.lookup(device.handle, accessToken: device.accessToken, claim: KeyClaim.none);
    return entry.device(device.deviceId)?.bundle.signedPrekeyBundle == signedPrekeyBundle;
  }
}

typedef _Device = ({String accessToken, String handle, String deviceId});
