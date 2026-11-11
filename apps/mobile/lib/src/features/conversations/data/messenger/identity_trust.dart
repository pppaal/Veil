import 'dart:async';

import '../../../../core/identity/identity_verdict.dart';
import '../../../../core/identity/trusted_identity.dart';
import '../../../../core/identity/trusted_identity_resolver.dart';

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

  bool get isNewDevice => previousKey == null;
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

/// A pending change was accepted or no longer applies.
final class IdentityChangeResolved extends IdentityTrustEvent {
  const IdentityChangeResolved(super.conversationId);
}

/// Applies the pin policy to every identity a conversation is about to use:
/// a session bootstrap, an inbound handshake, or a group member's device.
///
/// First use and a matching pin pass. A new device of an unverified contact
/// is admitted and announced. Anything else is refused until the user
/// accepts it with [approve]; a key change is never accepted automatically,
/// and for a verified contact not even by a plain approval.
class IdentityTrust {
  IdentityTrust(this.resolver);

  final TrustedIdentityResolver resolver;
  final Map<String, PendingIdentityChange> _pending = {};
  final StreamController<IdentityTrustEvent> _events = StreamController<IdentityTrustEvent>.broadcast(sync: true);

  Stream<IdentityTrustEvent> get events => _events.stream;

  PendingIdentityChange? pendingFor(String conversationId) => _pending[conversationId];

  /// Whether [conversationId] may use [identityKey] for the device. Refusals
  /// are recorded as the conversation's pending change.
  Future<bool> admit(String conversationId, String userId, String deviceId, String identityKey) async {
    final verdict = await resolver.evaluate(userId, deviceId, identityKey);
    switch (verdict) {
      case FirstUse() || PinMatch():
        _resolveIfAbout(conversationId, userId, deviceId);
        return true;
      case NewDeviceForKnownUser(knownUserVerified: false):
        await resolver.approve(userId, deviceId, identityKey);
        _events.add(NewDeviceAdmitted(conversationId, userId: userId, deviceId: deviceId));
        return true;
      case NewDeviceForKnownUser(knownUserVerified: true):
        _hold(conversationId, userId, deviceId, identityKey, previous: null, verified: true);
      case KeyChanged(:final pinned, :final presentedKey):
        _hold(conversationId, userId, deviceId, presentedKey, previous: pinned, verified: false);
      case KeyChangedVerified(:final pinned, :final presentedKey):
        _hold(conversationId, userId, deviceId, presentedKey, previous: pinned, verified: true);
    }
    return false;
  }

  /// Like [admit], but throws [IdentityChangedException] instead of
  /// returning false, for callers that must not proceed.
  Future<void> require(String conversationId, String userId, String deviceId, String identityKey) async {
    if (!await admit(conversationId, userId, deviceId, identityKey)) {
      throw IdentityChangedException(_pending[conversationId]!);
    }
  }

  /// Accepts the conversation's pending change. A contact the user had
  /// verified needs [reverified]: the caller attests that the user just
  /// compared the new safety number out of band, and the new key is pinned
  /// as verified. Throws [StateError] without a pending change, or when the
  /// change needs a re-verification that was not given.
  Future<TrustedIdentity> approve(String conversationId, {bool reverified = false}) async {
    final change = _pending[conversationId];
    if (change == null) throw StateError('No identity change is pending for this conversation.');
    if (change.requiresReverification && !reverified) {
      throw StateError('This contact was verified. Compare the new safety number before accepting it.');
    }
    await resolver.approve(change.userId, change.deviceId, change.presentedKey);
    final accepted = reverified
        ? await resolver.markVerified(change.userId, change.deviceId, change.presentedKey)
        : (await resolver.pinFor(change.userId, change.deviceId))!;
    _pending.remove(conversationId);
    _events.add(IdentityChangeResolved(conversationId));
    return accepted;
  }

  /// Forgets pending changes (sign-out); pins stay with the device.
  void clearPending() => _pending.clear();

  Future<void> dispose() => _events.close();

  void _hold(
    String conversationId,
    String userId,
    String deviceId,
    String identityKey, {
    required TrustedIdentity? previous,
    required bool verified,
  }) {
    final existing = _pending[conversationId];
    if (existing != null &&
        existing.userId == userId &&
        existing.deviceId == deviceId &&
        existing.presentedKey == identityKey) {
      return;
    }
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

  // A directory that serves the pinned key again withdrew its change.
  void _resolveIfAbout(String conversationId, String userId, String deviceId) {
    final existing = _pending[conversationId];
    if (existing == null || existing.userId != userId || existing.deviceId != deviceId) return;
    _pending.remove(conversationId);
    _events.add(IdentityChangeResolved(conversationId));
  }
}
