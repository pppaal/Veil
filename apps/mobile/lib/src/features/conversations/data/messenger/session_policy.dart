import '../../../../core/crypto/crypto_engine.dart';
import '../conversation_models.dart';

// Re-bootstrapping a live 1:1 session silently forks it: the peer keeps the
// old ratchet and every later message fails to decrypt. These rules keep
// bootstraps to the cases where no usable session can exist. They only ever
// see a directory answer the identity pins already accepted.

enum SessionAction { reuse, bootstrap }

SessionAction decideSession({
  required bool engineHasSession,
  required ConversationSessionState? session,
  required String localDeviceId,
  required KeyBundle bundle,
}) {
  // Nothing to reuse, e.g. a ratchet snapshot that failed to restore.
  if (!engineHasSession) {
    return SessionAction.bootstrap;
  }
  // The engine holds a session the preview never recorded, e.g. one
  // established from an inbound message.
  if (session == null) {
    return SessionAction.reuse;
  }
  if (!session.belongsToLocalDevice(localDeviceId) || !session.matchesBundle(bundle)) {
    return SessionAction.bootstrap;
  }
  // The same device under a key the user has since accepted in place of the
  // one this session was opened to: that identity is gone, and so is the
  // session it had.
  final sessionKey = session.remoteIdentityPublicKey;
  if (sessionKey.isNotEmpty && bundle.identityPublicKey.isNotEmpty && sessionKey != bundle.identityPublicKey) {
    return SessionAction.bootstrap;
  }
  return SessionAction.reuse;
}

/// The conversation after a directory answer for a session it keeps. A
/// session that has not recorded its peer's identity key yet (opened by the
/// peer's first legacy frame, or created before keys were recorded) adopts
/// the accepted key served for the same device.
ConversationPreview keepSession(ConversationPreview conversation, KeyBundle served) {
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

/// What this device knows about a session its engine opened by itself while
/// decrypting a peer's first frame (protocol v2 and libsignal run the
/// responder half of the handshake inside decrypt): the frame's
/// authenticated sender device and, when the engine showed it to the
/// identity verifier, the identity key the handshake proved.
ConversationSessionState observedInboundSession(
  CryptoEnvelope envelope, {
  required String localDeviceId,
  String remoteIdentityPublicKey = '',
}) {
  return ConversationSessionState(
    sessionLocator: '',
    sessionEnvelopeVersion: envelope.version,
    requiresLocalPersistence: false,
    sessionSchemaVersion: 0,
    localDeviceId: localDeviceId,
    remoteDeviceId: envelope.senderDeviceId,
    remoteIdentityFingerprint: '',
    bootstrappedAt: DateTime.now(),
    remoteIdentityPublicKey: remoteIdentityPublicKey,
  );
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
