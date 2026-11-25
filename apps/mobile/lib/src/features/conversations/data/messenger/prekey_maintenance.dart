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
///
/// The directory accepts a signed prekey only while its timestamp is at
/// most an hour old and at most ten minutes ahead of the directory's clock
/// (error `signed_prekey_timestamp_out_of_window`). Timestamps are therefore
/// taken from the directory's clock as its responses report it
/// (ServerClock), and a signed prekey whose publish failed is sent again
/// unchanged only while it is younger than [signedPrekeyResendWindow];
/// after that, or once the directory refused its timestamp, a successor is
/// drawn under the next id.
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

  /// How long an unpublished signed prekey may be sent again as it is, by
  /// the directory's clock: well inside the hour the directory accepts.
  static const Duration signedPrekeyResendWindow = Duration(minutes: 30);

  /// How far ahead of the directory's clock it accepts a timestamp.
  static const Duration _directoryLead = Duration(minutes: 10);

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
  // Set when the directory refused the timestamp of the signed prekey this
  // device sent: the next attempt draws a successor, whatever its age says.
  bool _drawSignedPrekey = false;

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

  // One-time prekeys come first, and neither step stops the other: a
  // directory that refuses the signed prekey must not also leave this device
  // without one-time prekeys. Only an unreachable directory ends the run
  // early, since a publish would fail as well, after drawing a signed prekey
  // nobody can receive. Offline or refused, the directory keeps serving what
  // it has, and the next run tries again.
  Future<void> _runOnce(_Device device) async {
    final startedAt = _clock();
    final refill = await _failureOf(() => _refillOneTimePrekeys(device));
    if (refill is VeilApiException && refill.statusCode == null) return;
    final publish = await _failureOf(() => _publishSignedPrekeyIfDue(device));
    if (refill != null || publish != null) return;
    if (await _failureOf(() => _prekeys.pruneSignedPrekeys(grace: signedPrekeyGrace)) == null) {
      _lastCompletedAt = startedAt;
    }
  }

  static Future<Object?> _failureOf(Future<void> Function() step) async {
    try {
      await step();
      return null;
    } catch (error) {
      return error;
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

  // A signed prekey the directory never accepted (its publish failed) is
  // sent again as it is while the directory still takes its timestamp; one
  // older than that, or than a week, is replaced first. A v1 identity has no
  // signed prekey of its own, so it reports none and is rotated at once.
  // Either way a v1 identity ref is upgraded to v2, and the new ref is
  // stored before the bundle that needs it is published.
  Future<void> _publishSignedPrekeyIfDue(_Device device) async {
    final now = _keys.serverClock.now();
    final current = await _prekeys.currentSignedPrekey();
    final age = current == null ? null : now.difference(current.createdAt);
    final fresh = age != null && age <= signedPrekeyMaxAge;
    if (fresh && current!.spkId == await _prekeys.publishedSignedPrekeyId()) return;
    final resendable = fresh && !_drawSignedPrekey && age < signedPrekeyResendWindow && age > -_directoryLead;
    final next = resendable ? current! : await _prekeys.rotateSignedPrekey(createdAt: now);
    _drawSignedPrekey = false;
    final upgradedRef = next.upgradedIdentityPrivateRef;
    if (upgradedRef != null) await _persistIdentityRef(upgradedRef);
    try {
      await _keys.rotateSignedPrekey(next.signedPrekeyBundle, accessToken: device.accessToken);
    } on VeilApiException catch (error) {
      // The refusal's Date header already corrected the server clock.
      if (error.code == 'signed_prekey_timestamp_out_of_window') {
        _drawSignedPrekey = true;
        rethrow;
      }
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
