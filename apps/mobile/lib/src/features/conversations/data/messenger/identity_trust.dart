import 'dart:async';

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
}

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
  /// migrateLegacyTrust); it starts at once.
  IdentityTrust(this.resolver, {Future<void> Function()? prepare}) : _prepare = prepare {
    // Its error reaches every decision that awaits it; it is not unhandled.
    ready.ignore();
  }

  final TrustedIdentityResolver resolver;
  final Future<void> Function()? _prepare;
  Future<void>? _preparing;
  final Map<String, PendingIdentityChange> _pending = {};
  // Identities the user declined, as userId/deviceId/key: refused from then
  // on without asking again.
  final Set<String> _declined = {};
  final StreamController<IdentityTrustEvent> _events = StreamController<IdentityTrustEvent>.broadcast(sync: true);

  /// Completes once the pin table is prepared. Every decision waits for it
  /// and fails while it fails: deciding without what earlier builds knew
  /// would pin whatever key arrives first. A failed preparation is tried
  /// again by the next caller, so a cache that opens late holds decisions
  /// back only until it does.
  Future<void> get ready => _preparing ??= _attemptPreparation();

  Stream<IdentityTrustEvent> get events => _events.stream;

  PendingIdentityChange? pendingFor(String conversationId) => _pending[conversationId];

  /// Whether [conversationId] may use [identityKey] for the device. Refusals
  /// are recorded as the conversation's pending change.
  Future<bool> admit(String conversationId, String userId, String deviceId, String identityKey) async {
    await ready;
    final verdict = await resolver.evaluate(userId, deviceId, identityKey, admitNewDeviceOfUnverifiedUser: true);
    switch (verdict) {
      case FirstUse() || PinMatch():
        _resolveIfAbout(conversationId, userId, deviceId);
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
    if (_declined.contains(_declinedId(userId, deviceId, identityKey))) {
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
      _events.add(IdentityChangeResolved(conversationId));
    }
    return accepted;
  }

  /// Keeps what the pins hold instead of the conversation's pending change,
  /// [reviewed] being the change the user was shown. Its key is refused from
  /// then on, in every conversation, without asking again (until sign-out or
  /// a restart: declines are kept in memory, like pending changes); pending
  /// changes elsewhere that present it are dropped too. Returns the
  /// conversations whose pending change it dropped.
  ///
  /// Throws [StateError], changing nothing, without a pending change or when
  /// the pending change is no longer [reviewed].
  List<String> decline(String conversationId, {required PendingIdentityChange reviewed}) {
    final change = _pending[conversationId];
    if (change == null) throw StateError('No identity change is pending for this conversation.');
    if (!change.presents(reviewed.userId, reviewed.deviceId, reviewed.presentedKey)) {
      throw StateError('The identity change was replaced by a newer one. Review it before declining.');
    }
    _declined.add(_declinedId(change.userId, change.deviceId, change.presentedKey));
    final settled = [
      for (final entry in _pending.entries)
        if (entry.value.presents(change.userId, change.deviceId, change.presentedKey)) entry.key,
    ];
    for (final id in settled) {
      _pending.remove(id);
      _events.add(IdentityChangeResolved(id));
    }
    return settled;
  }

  /// Forgets pending and declined changes (sign-out); pins stay with the
  /// device.
  void clearPending() {
    _pending.clear();
    _declined.clear();
  }

  Future<void> dispose() => _events.close();

  Future<void> _attemptPreparation() async {
    try {
      // Through a future, so that even a preparation that throws at once is
      // forgotten only after [ready] has recorded this attempt.
      await Future<void>.sync(() => _prepare?.call());
    } catch (_) {
      _preparing = null;
      rethrow;
    }
  }

  void _hold(
    String conversationId,
    String userId,
    String deviceId,
    String identityKey, {
    required TrustedIdentity? previous,
    required bool verified,
  }) {
    if (_declined.contains(_declinedId(userId, deviceId, identityKey))) return;
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
    _events.add(IdentityChangePending(change));
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
    _events.add(IdentityChangeResolved(conversationId));
  }
}
