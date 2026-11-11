import '../../../../core/crypto/crypto_engine.dart';
import '../conversation_models.dart';

/// Applies a fresh server conversation list on top of the local previews.
///
/// The server never knows session state and only knows the peer's user id,
/// so its previews arrive with no session and an empty bundle. Taking them
/// wholesale made the next send re-bootstrap the 1:1 session and fork the
/// ratchet; the local session, bundle and identity flag are kept instead.
/// Everything else (membership, last message, timers, epoch) follows the
/// server, and conversations missing from the server list are dropped.
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
  final keepBundle = _isEmptyBundle(incoming.recipientBundle) &&
      local.recipientBundle.userId == incoming.recipientBundle.userId;
  return incoming.copyWith(
    sessionState: incoming.sessionState ?? local.sessionState,
    recipientBundle: keepBundle ? local.recipientBundle : incoming.recipientBundle,
    identityMismatchPending:
        incoming.identityMismatchPending || local.identityMismatchPending,
  );
}

bool _isEmptyBundle(KeyBundle bundle) =>
    bundle.deviceId.isEmpty &&
    bundle.identityPublicKey.isEmpty &&
    bundle.signedPrekeyBundle.isEmpty;
