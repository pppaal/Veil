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

/// Whether a send has to resolve the peer's key bundle first. Steady-state
/// sends on an established session never touch the key directory.
bool sendNeedsPeerBundle({
  required bool engineHasSession,
  required bool rekeyArmed,
  required ConversationPreview conversation,
}) {
  if (!engineHasSession || rekeyArmed) {
    return true;
  }
  final session = conversation.sessionState;
  final knownDeviceId = conversation.recipientBundle.deviceId;
  return session != null &&
      knownDeviceId.isNotEmpty &&
      session.remoteDeviceId != knownDeviceId;
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
