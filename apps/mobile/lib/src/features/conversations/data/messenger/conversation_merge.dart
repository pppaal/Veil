import '../../../../core/crypto/crypto_engine.dart';
import '../conversation_models.dart';

/// Applies a fresh server conversation list on top of the local previews.
///
/// The server never knows session state and only knows the peer's user id,
/// so its previews arrive with no session and an empty bundle. Taking them
/// wholesale made the next send re-bootstrap the 1:1 session and fork the
/// ratchet; the local session and bundle are kept instead.
/// Everything else (membership, last message, timers, epoch) follows the
/// server, and conversations missing from the server list are dropped.
///
/// Except who a 1:1 conversation is with, once it has a session: the engine
/// keeps encrypting to the peer that session was opened with, so a server
/// preview that names another user, or turns the conversation into a group,
/// would show one contact while every message goes to another. Such a
/// preview only updates the last message and the timer.
List<ConversationPreview> mergeConversationPreviews(
  List<ConversationPreview> local,
  List<ConversationPreview> server,
) {
  final localById = {for (final preview in local) preview.id: preview};
  return [
    for (final incoming in server) _mergePreview(localById[incoming.id], incoming),
  ];
}

ConversationPreview _mergePreview(ConversationPreview? local, ConversationPreview incoming) {
  if (local == null) {
    return incoming;
  }
  if (_rebindsSessionPeer(local, incoming)) {
    return local.copyWith(
      lastEnvelope: incoming.lastEnvelope,
      updatedAt: incoming.updatedAt,
      disappearingTimerSeconds: incoming.disappearingTimerSeconds,
    );
  }
  final keepBundle = _isEmptyBundle(incoming.recipientBundle) &&
      local.recipientBundle.userId == incoming.recipientBundle.userId;
  return incoming.copyWith(
    sessionState: incoming.sessionState ?? local.sessionState,
    recipientBundle: keepBundle ? local.recipientBundle : incoming.recipientBundle,
  );
}

bool _rebindsSessionPeer(ConversationPreview local, ConversationPreview incoming) =>
    local.type == ConversationType.direct &&
    local.sessionState != null &&
    (incoming.type != ConversationType.direct || incoming.recipientBundle.userId != local.recipientBundle.userId);

bool _isEmptyBundle(KeyBundle bundle) =>
    bundle.deviceId.isEmpty &&
    bundle.identityPublicKey.isEmpty &&
    bundle.signedPrekeyBundle.isEmpty;
