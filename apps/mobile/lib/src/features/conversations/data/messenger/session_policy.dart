import '../../../../core/crypto/crypto_engine.dart';
import '../conversation_models.dart';

// Re-bootstrapping a live 1:1 session silently forks it: the peer keeps the
// old ratchet and every later message fails to decrypt. These rules keep
// bootstraps to the cases where no usable session can exist.

enum SessionAction { reuse, bootstrap }

class SessionDecision {
  const SessionDecision(this.action, {this.identityMismatch = false});

  final SessionAction action;

  /// The directory now serves a different identity key for the very device
  /// the session is bound to. Never a reason to re-bootstrap on its own.
  final bool identityMismatch;
}

SessionDecision decideSession({
  required bool engineHasSession,
  required ConversationSessionState? session,
  required String localDeviceId,
  required KeyBundle bundle,
}) {
  if (!engineHasSession) {
    return const SessionDecision(SessionAction.bootstrap);
  }
  // The engine holds a session the preview never recorded, e.g. one
  // established from an inbound message.
  if (session == null) {
    return const SessionDecision(SessionAction.reuse);
  }
  if (!session.belongsToLocalDevice(localDeviceId) || !session.matchesBundle(bundle)) {
    return const SessionDecision(SessionAction.bootstrap);
  }
  final recordedKey = session.remoteIdentityPublicKey;
  return SessionDecision(
    SessionAction.reuse,
    identityMismatch: recordedKey.isNotEmpty &&
        bundle.identityPublicKey.isNotEmpty &&
        recordedKey != bundle.identityPublicKey,
  );
}

/// The conversation after a directory answer for a session it keeps.
///
/// A session that has not recorded its peer's identity key yet (opened by
/// the peer's first frame, or created before keys were recorded) adopts the
/// key served for the same device: trust on first use, from the same
/// directory the initiator trusted. A different key for the bound device is
/// only flagged and the pinned bundle stays, because that is who the live
/// session actually encrypts to, and so what safety numbers must show.
ConversationPreview keepSession(
  ConversationPreview conversation,
  KeyBundle served,
  SessionDecision decision,
) {
  assert(decision.action == SessionAction.reuse);
  if (decision.identityMismatch) {
    return conversation.copyWith(identityMismatchPending: true);
  }
  final session = conversation.sessionState;
  final pinsIdentity = session != null &&
      session.remoteIdentityPublicKey.isEmpty &&
      session.matchesBundle(served);
  return conversation.copyWith(
    recipientBundle: served,
    sessionState: pinsIdentity ? session.withRemoteIdentity(served.identityPublicKey) : session,
  );
}

/// Whether an inbound 1:1 frame was sent by a device other than the one the
/// conversation's session is bound to. Server previews carry no device ids,
/// so this is how a device learns that its peer moved to a new one; without
/// it every later send keeps sealing to a device that is gone.
bool comesFromNewPeerDevice(
  ConversationPreview conversation,
  CryptoEnvelope envelope, {
  required String localDeviceId,
}) {
  final session = conversation.sessionState;
  final sender = envelope.senderDeviceId;
  return conversation.type == ConversationType.direct &&
      session != null &&
      sender.isNotEmpty &&
      sender != localDeviceId &&
      sender != session.remoteDeviceId;
}

ConversationSessionState sessionStateFromMaterial(
  SessionBootstrapMaterial material, {
  required String remoteIdentityPublicKey,
}) {
  return ConversationSessionState(
    sessionLocator: material.sessionLocator,
    sessionEnvelopeVersion: material.sessionEnvelopeVersion,
    requiresLocalPersistence: material.requiresLocalPersistence,
    sessionSchemaVersion: material.sessionSchemaVersion,
    localDeviceId: material.localDeviceId,
    remoteDeviceId: material.remoteDeviceId,
    remoteIdentityFingerprint: material.remoteIdentityFingerprint,
    bootstrappedAt: DateTime.now(),
    auditHint: material.auditHint,
    remoteIdentityPublicKey: remoteIdentityPublicKey,
  );
}
