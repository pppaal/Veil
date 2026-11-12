import 'dart:async';
import 'dart:convert';

import '../../../../core/identity/identity_key_value_backend.dart';
import '../../../../core/identity/identity_verdict.dart';
import '../../../../core/identity/trusted_identity.dart';
import '../../../../core/identity/trusted_identity_resolver.dart';
import '../../../../core/util/base64url.dart';
import 'identity_change.dart';

export 'identity_change.dart';

typedef _DeclinedIdentity = ({String userId, String deviceId, String identityKey});

/// Applies the pin policy to every identity a conversation is about to use:
/// a session bootstrap, an inbound handshake, or a group member's device.
///
/// First use and a matching pin pass. A new device of an unverified contact
/// is admitted and announced. Anything else is refused until the user
/// accepts it with [approve] or keeps the current identity with [decline];
/// a key change is never accepted automatically, and for a verified contact
/// not even by a plain approval.
class IdentityTrust {
  /// [prepare] fills the pin table with what earlier builds knew (see
  /// migrateLegacyTrust); it starts at once and runs once. [decisions] keeps
  /// pending and declined changes across restarts, in the keystore beside
  /// the pins; without it they last for the process. Only [forgetDecisions]
  /// (sign-out) and the device wipe remove the stored record.
  IdentityTrust(this.resolver, {Future<void> Function()? prepare, IdentityKeyValueBackend? decisions})
      : _prepare = prepare,
        _decisions = decisions {
    // Its error reaches every decision that awaits it; it is not unhandled.
    ready.ignore();
  }

  /// Where [decisions] keeps its record.
  static const String decisionsKey = 'decisions.v1';

  final TrustedIdentityResolver resolver;
  final Future<void> Function()? _prepare;
  final IdentityKeyValueBackend? _decisions;
  // The pin table preparation, shared by every generation: the pins stay
  // with the device whoever signs in. Forgotten only when it failed.
  Future<void>? _pinsPrepared;
  // This generation's preparation: the pins, then the record read back.
  Future<void>? _preparing;
  // Advanced by [reset]: a record an earlier generation is still reading is
  // not applied over what this one holds.
  int _generation = 0;
  // Whether this generation read the record back, so that memory holds what
  // is stored and writing it out keeps every decision.
  bool _loaded = false;
  // The delete [forgetDecisions] started; nothing reads the record before
  // it landed, since the keystore does not order a read after a delete.
  Future<void>? _forgetting;
  final Map<String, PendingIdentityChange> _pending = {};
  // Identities the user declined, by userId/deviceId/key: refused from then
  // on without asking again.
  final Map<String, _DeclinedIdentity> _declined = {};
  // Set when a decision changed what is pending, so it is written out.
  bool _decisionsChanged = false;
  final StreamController<IdentityTrustEvent> _events = StreamController<IdentityTrustEvent>.broadcast(sync: true);

  /// Completes once the pin table is prepared and the pending and declined
  /// changes are read back. Every decision waits for it and fails while it
  /// fails: deciding without what earlier builds knew would pin whatever key
  /// arrives first. A failed preparation is tried again by the next caller,
  /// so a cache that opens late holds decisions back only until it does.
  /// After a [reset] it completes only once the record was read again.
  Future<void> get ready async {
    while (true) {
      final generation = _generation;
      await (_preparing ??= _attemptPreparation(generation));
      if (generation == _generation) return;
    }
  }

  Stream<IdentityTrustEvent> get events => _events.stream;

  PendingIdentityChange? pendingFor(String conversationId) => _pending[conversationId];

  /// Whether [conversationId] may use [identityKey] for the device. Refusals
  /// are recorded as the conversation's pending change.
  Future<bool> admit(String conversationId, String userId, String deviceId, String identityKey) async {
    await ready;
    final verdict = await resolver.evaluate(userId, deviceId, identityKey, admitNewDeviceOfUnverifiedUser: true);
    // A directory or handshake that presents the pinned key again withdrew
    // any change pending for the device.
    if (verdict is FirstUse || verdict is PinMatch) _resolveIfAbout(conversationId, userId, deviceId);
    final admitted = _decide(conversationId, userId, deviceId, identityKey, verdict);
    await _saveDecisionsIfChanged();
    return admitted;
  }

  /// Whether [conversationId] may still seal to, or open frames on, a
  /// session installed for [identityKey]. Asked for every frame, because
  /// what the pins admitted when the session was installed may no longer
  /// pass: a device pinned before the user verified another of the
  /// contact's devices is held for review, as [admit] holds it. A key the
  /// pins hold a successor for is refused without asking again: the user
  /// already accepted that successor, so a late frame from the session it
  /// replaced is no new change to review. A frame on the session in use
  /// says nothing about what the directory now presents, so it settles no
  /// pending change.
  Future<bool> admitSession(String conversationId, String userId, String deviceId, String identityKey) async {
    await ready;
    final verdict = await resolver.evaluate(userId, deviceId, identityKey, admitNewDeviceOfUnverifiedUser: true);
    if (verdict is KeyChanged || verdict is KeyChangedVerified) return false;
    final admitted = _decide(conversationId, userId, deviceId, identityKey, verdict);
    await _saveDecisionsIfChanged();
    return admitted;
  }

  bool _decide(String conversationId, String userId, String deviceId, String identityKey, IdentityVerdict verdict) {
    switch (verdict) {
      case FirstUse() || PinMatch():
        return true;
      case NewDeviceForKnownUser(knownUserVerified: false):
        _events.add(NewDeviceAdmitted(conversationId, userId: userId, deviceId: deviceId));
        return true;
      case NewDeviceForKnownUser(knownUserVerified: true):
        _hold(conversationId, userId, deviceId, identityKey, previous: null, verified: true);
      case KeyChanged(:final pinned, :final presentedKey):
        _hold(conversationId, userId, deviceId, presentedKey, previous: pinned, verified: false);
      case KeyChangedVerified(:final pinned, :final presentedKey):
        _hold(conversationId, userId, deviceId, presentedKey, previous: pinned, verified: true);
      case DeviceOfAnotherUser():
        // Refused outright: there is nothing the user could approve.
        return false;
    }
    return false;
  }

  /// Like [admit], but throws instead of returning false, for callers that
  /// must not proceed: [IdentityChangedException] for a change the user can
  /// review, [StateError] for one the user declined or a device the
  /// directory misattributes.
  Future<void> require(String conversationId, String userId, String deviceId, String identityKey) async {
    if (await admit(conversationId, userId, deviceId, identityKey)) return;
    final change = _pending[conversationId];
    if (change != null) throw IdentityChangedException(change);
    if (_declined.containsKey(_declinedId(userId, deviceId, identityKey))) {
      throw StateError('The key server lists a safety number you chose not to accept for this contact.');
    }
    throw StateError('The key directory lists this device under another user.');
  }

  /// Whether [identityKey] passes the pins for the device as they stand, the
  /// way [admit] would let it through, without pinning or holding anything.
  Future<bool> trusts(String userId, String deviceId, String identityKey) async {
    await ready;
    if (userId.isEmpty || deviceId.isEmpty || identityKey.isEmpty) return false;
    return resolver.isTrusted(userId, deviceId, identityKey);
  }

  /// Accepts the conversation's pending change.
  ///
  /// [reviewed] is the change the user was shown. A newer refusal replaces
  /// the pending change at any time, so an approval that names what was
  /// reviewed fails instead of accepting an identity nobody looked at.
  ///
  /// A contact the user had verified needs [reverified]: the caller attests
  /// that the user just compared the safety number of [reviewed] out of
  /// band, which is why it must be given too, and the key is pinned as
  /// verified.
  ///
  /// Throws [StateError], changing nothing, without a pending change, when
  /// the pending change is no longer [reviewed], or when it needs a
  /// re-verification that was not given.
  Future<TrustedIdentity> approve(
    String conversationId, {
    bool reverified = false,
    PendingIdentityChange? reviewed,
  }) async {
    await ready;
    final change = _pending[conversationId];
    if (change == null) throw StateError('No identity change is pending for this conversation.');
    if (reviewed != null && !change.presents(reviewed.userId, reviewed.deviceId, reviewed.presentedKey)) {
      throw StateError('The identity change was replaced by a newer one. Review it before accepting.');
    }
    if (change.requiresReverification && !reverified) {
      throw StateError('This contact was verified. Compare the new safety number before accepting it.');
    }
    if (reverified && reviewed == null) {
      throw StateError('A re-verification must name the identity whose safety number was compared.');
    }
    await resolver.approve(change.userId, change.deviceId, change.presentedKey);
    final accepted = reverified
        ? await resolver.markVerified(change.userId, change.deviceId, change.presentedKey)
        : (await resolver.pinFor(change.userId, change.deviceId))!;
    // A change held while the pins were written is still pending.
    if (identical(_pending[conversationId], change)) {
      _pending.remove(conversationId);
      _decisionsChanged = true;
      _events.add(IdentityChangeResolved(conversationId));
    }
    _forgetDecline(change.userId, change.deviceId, change.presentedKey);
    await _saveDecisionsIfChanged();
    return accepted;
  }

  /// Records that the user compared [identityKey], the pinned key of the
  /// device, out of band (see TrustedIdentityResolver.markVerified). A
  /// decline of that very key no longer applies.
  Future<TrustedIdentity> markVerified(String userId, String deviceId, String identityKey) async {
    await ready;
    final verified = await resolver.markVerified(userId, deviceId, identityKey);
    _forgetDecline(userId, deviceId, identityKey);
    await _saveDecisionsIfChanged();
    return verified;
  }

  /// Keeps what the pins hold instead of the conversation's pending change,
  /// [reviewed] being the change the user was shown. Its key is refused from
  /// then on, in every conversation, without asking again until the user
  /// accepts or verifies that same key; pending changes elsewhere that
  /// present it are dropped too. The decline is kept across restarts.
  /// Returns the conversations whose pending change it dropped. Which key a
  /// conversation's session uses is not known here: the caller refuses to
  /// decline that one.
  ///
  /// Throws [StateError], changing nothing, without a pending change or when
  /// the pending change is no longer [reviewed].
  Future<List<String>> decline(String conversationId, {required PendingIdentityChange reviewed}) async {
    await ready;
    final change = _pending[conversationId];
    if (change == null) throw StateError('No identity change is pending for this conversation.');
    if (!change.presents(reviewed.userId, reviewed.deviceId, reviewed.presentedKey)) {
      throw StateError('The identity change was replaced by a newer one. Review it before declining.');
    }
    _declined[_declinedId(change.userId, change.deviceId, change.presentedKey)] =
        (userId: change.userId, deviceId: change.deviceId, identityKey: change.presentedKey);
    final settled = [
      for (final entry in _pending.entries)
        if (entry.value.presents(change.userId, change.deviceId, change.presentedKey)) entry.key,
    ];
    for (final id in settled) {
      _pending.remove(id);
      _events.add(IdentityChangeResolved(id));
    }
    _decisionsChanged = true;
    await _saveDecisionsIfChanged();
    return settled;
  }

  /// Forgets what was read for the previous session (a sign-in or another
  /// identity): pending and declined changes leave memory, and the next
  /// [ready] reads them back from the keystore. The stored record stays:
  /// signing in, like a restart, neither drops a pending change nor forgets
  /// a decline.
  void reset() {
    _generation += 1;
    _preparing = null;
    _loaded = false;
    _pending.clear();
    _declined.clear();
    _decisionsChanged = false;
  }

  /// Forgets pending and declined changes, the stored record included
  /// (sign-out); pins stay with the device until it is wiped. Completes once
  /// the record is gone; the next [ready] reads only after that.
  Future<void> forgetDecisions() {
    reset();
    return _forgetting = Future<void>.sync(() => _decisions?.delete(decisionsKey));
  }

  Future<void> dispose() => _events.close();

  Future<void> _attemptPreparation(int generation) async {
    try {
      await _preparePins();
      final forgetting = _forgetting;
      if (forgetting != null) {
        try {
          await forgetting;
        } catch (_) {
          // [forgetDecisions] reported it; a record it could not delete is
          // still what is stored, and is read back as such.
        }
      }
      await _loadDecisions(generation);
    } catch (_) {
      // Only this generation's attempt is forgotten: a newer one may be in
      // flight already.
      if (generation == _generation) _preparing = null;
      rethrow;
    }
  }

  Future<void> _preparePins() async {
    // Through a future, so that even a preparation that throws at once is
    // forgotten only after it was recorded as this attempt.
    final preparing = _pinsPrepared ??= Future<void>.sync(() => _prepare?.call());
    try {
      await preparing;
    } catch (_) {
      if (identical(_pinsPrepared, preparing)) _pinsPrepared = null;
      rethrow;
    }
  }

  // A record that does not read is dropped rather than holding every
  // decision back: a change still pending is raised again by the next
  // refusal, and a forgotten decline only asks again. A decision made while
  // the record was being read (one that straddled a [reset]) is kept over
  // the stored change for its conversation.
  Future<void> _loadDecisions(int generation) async {
    final raw = await _decisions?.read(decisionsKey);
    if (generation != _generation) return;
    _loaded = true;
    if (raw == null) return;
    final List<PendingIdentityChange> pending;
    final List<_DeclinedIdentity> declined;
    try {
      final document = json.decode(raw) as Map<String, dynamic>;
      pending = [
        for (final change in document['pending'] as List) PendingIdentityChange.fromJson(change as Map<String, dynamic>),
      ];
      declined = [
        for (final key in (document['declined'] as List).cast<Map<String, dynamic>>())
          (userId: key['userId'] as String, deviceId: key['deviceId'] as String, identityKey: key['identityKey'] as String),
      ];
    } on Object {
      return;
    }
    for (final change in pending) {
      _pending.putIfAbsent(change.conversationId, () => change);
    }
    for (final key in declined) {
      _declined[_declinedId(key.userId, key.deviceId, key.identityKey)] = key;
    }
  }

  Future<void> _saveDecisionsIfChanged() async {
    if (!_decisionsChanged) return;
    // A decision that straddled a [reset] was made before this generation
    // read the record back: writing memory out now would overwrite every
    // decision stored. It is merged with the record first.
    if (!_loaded) {
      await ready;
      if (!_decisionsChanged) return;
    }
    _decisionsChanged = false;
    await _decisions?.write(
      decisionsKey,
      json.encode({
        'pending': [for (final change in _pending.values) change.toJson()],
        'declined': [
          for (final key in _declined.values)
            {'userId': key.userId, 'deviceId': key.deviceId, 'identityKey': key.identityKey},
        ],
      }),
    );
  }

  void _hold(
    String conversationId,
    String userId,
    String deviceId,
    String identityKey, {
    required TrustedIdentity? previous,
    required bool verified,
  }) {
    if (_declined.containsKey(_declinedId(userId, deviceId, identityKey))) return;
    if (_pending[conversationId]?.presents(userId, deviceId, identityKey) ?? false) return;
    final change = PendingIdentityChange(
      conversationId: conversationId,
      userId: userId,
      deviceId: deviceId,
      presentedKey: identityKey,
      previousKey: previous?.identityKey,
      requiresReverification: verified,
    );
    _pending[conversationId] = change;
    _decisionsChanged = true;
    _events.add(IdentityChangePending(change));
  }

  void _forgetDecline(String userId, String deviceId, String identityKey) {
    if (_declined.remove(_declinedId(userId, deviceId, identityKey)) != null) _decisionsChanged = true;
  }

  // Keys arrive in more than one base64url spelling; the resolver's verdicts
  // carry the canonical one, which is what declines are recorded under.
  static String _declinedId(String userId, String deviceId, String identityKey) =>
      '$userId/$deviceId/${_canonical(identityKey)}';

  static String _canonical(String identityKey) {
    try {
      return base64UrlNoPadEncode(base64UrlNoPadDecode(identityKey));
    } on FormatException {
      return identityKey;
    }
  }

  // A directory that serves the pinned key again withdrew its change.
  void _resolveIfAbout(String conversationId, String userId, String deviceId) {
    final existing = _pending[conversationId];
    if (existing == null || existing.userId != userId || existing.deviceId != deviceId) return;
    _pending.remove(conversationId);
    _decisionsChanged = true;
    _events.add(IdentityChangeResolved(conversationId));
  }
}
