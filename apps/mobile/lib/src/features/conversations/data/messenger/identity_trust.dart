import 'dart:async';
import 'dart:convert';

import '../../../../core/identity/identity_key_value_backend.dart';
import '../../../../core/identity/identity_verdict.dart';
import '../../../../core/identity/trusted_identity.dart';
import '../../../../core/identity/trusted_identity_resolver.dart';
import '../../../../core/util/base64url.dart';

/// A contact identity this device will not use until the user accepts it:
/// a different key for a pinned device, or a new device of a contact whose
/// other device the user verified.
class PendingIdentityChange {
  const PendingIdentityChange({
    required this.conversationId,
    required this.userId,
    required this.deviceId,
    required this.presentedKey,
    required this.previousKey,
    required this.requiresReverification,
  });

  final String conversationId;
  final String userId;
  final String deviceId;

  /// The key the directory or the handshake presented, base64url.
  final String presentedKey;

  /// The pinned key it would replace; null for a new device.
  final String? previousKey;

  /// The user had verified this contact, so accepting the change takes a
  /// fresh out-of-band verification, never a single tap.
  final bool requiresReverification;

  /// Whether this change is about [identityKey] for the very same device.
  bool presents(String userId, String deviceId, String identityKey) =>
      this.userId == userId && this.deviceId == deviceId && presentedKey == identityKey;

  Map<String, dynamic> toJson() => {
        'conversationId': conversationId,
        'userId': userId,
        'deviceId': deviceId,
        'presentedKey': presentedKey,
        if (previousKey != null) 'previousKey': previousKey,
        'requiresReverification': requiresReverification,
      };

  /// Throws on a record of the wrong shape.
  factory PendingIdentityChange.fromJson(Map<String, dynamic> json) => PendingIdentityChange(
        conversationId: json['conversationId'] as String,
        userId: json['userId'] as String,
        deviceId: json['deviceId'] as String,
        presentedKey: json['presentedKey'] as String,
        previousKey: json['previousKey'] as String?,
        requiresReverification: json['requiresReverification'] as bool,
      );
}

typedef _DeclinedIdentity = ({String userId, String deviceId, String identityKey});

/// Thrown when an operation needs an identity the user has not accepted.
/// Scoped to one conversation: the chat shows it, not a global error.
class IdentityChangedException implements Exception {
  const IdentityChangedException(this.change);

  final PendingIdentityChange change;

  @override
  String toString() => 'The safety number for this conversation changed. Review it before sending.';
}

/// What the trust layer tells the messenger as it decides.
sealed class IdentityTrustEvent {
  const IdentityTrustEvent(this.conversationId);

  final String conversationId;
}

/// A change became pending; the conversation gets the 'identity.changed'
/// notice once.
final class IdentityChangePending extends IdentityTrustEvent {
  IdentityChangePending(this.change) : super(change.conversationId);

  final PendingIdentityChange change;
}

/// A new device of an unverified contact was admitted; the conversation
/// gets the 'identity.new_device' notice once.
final class NewDeviceAdmitted extends IdentityTrustEvent {
  const NewDeviceAdmitted(super.conversationId, {required this.userId, required this.deviceId});

  final String userId;
  final String deviceId;
}

/// A pending change was accepted, declined, or no longer applies.
final class IdentityChangeResolved extends IdentityTrustEvent {
  const IdentityChangeResolved(super.conversationId);
}

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
  /// migrateLegacyTrust); it starts at once. [decisions] keeps pending and
  /// declined changes across restarts, in the keystore beside the pins;
  /// without it they last for the process.
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
  Future<void>? _preparing;
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
  Future<void> get ready => _preparing ??= _attemptPreparation();

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

  /// Forgets pending and declined changes, kept ones included (sign-out);
  /// pins stay with the device.
  Future<void> clearPending() async {
    _pending.clear();
    _declined.clear();
    _decisionsChanged = false;
    await _decisions?.delete(decisionsKey);
  }

  Future<void> dispose() => _events.close();

  Future<void> _attemptPreparation() async {
    try {
      // Through a future, so that even a preparation that throws at once is
      // forgotten only after [ready] has recorded this attempt.
      await Future<void>.sync(() => _prepare?.call());
      await _loadDecisions();
    } catch (_) {
      _preparing = null;
      rethrow;
    }
  }

  // A record that does not read is dropped rather than holding every
  // decision back: a change still pending is raised again by the next
  // refusal, and a forgotten decline only asks again.
  Future<void> _loadDecisions() async {
    final raw = await _decisions?.read(decisionsKey);
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
