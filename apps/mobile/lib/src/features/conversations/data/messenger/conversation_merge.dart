import '../../../../core/crypto/crypto_engine.dart';
import '../conversation_models.dart';
import 'conversation_peer_bindings.dart';

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
/// keeps that session under the conversation id, so a server preview that
/// names another user, or turns the conversation into a group, would show
/// one contact while every message goes to another. The peer is [bound]
/// (see ConversationPeerBindings), or else the one the local preview's
/// session was opened with. Such a preview only updates the last message,
/// the updated time and the timer, also when the conversation was left out
/// of an earlier list and has no local preview any more.
List<ConversationPreview> mergeConversationPreviews(
  List<ConversationPreview> local,
  List<ConversationPreview> server, {
  Map<String, ConversationPeer> bound = const {},
}) {
  final localById = {for (final preview in local) preview.id: preview};
  return [
    for (final incoming in server) _mergePreview(localById[incoming.id], incoming, bound[incoming.id]),
  ];
}

ConversationPreview _mergePreview(ConversationPreview? local, ConversationPreview incoming, ConversationPeer? bound) {
  final peer = bound ?? _sessionPeerOf(local);
  if (peer != null && (incoming.type != ConversationType.direct || incoming.recipientBundle.userId != peer.userId)) {
    final kept = local != null && local.recipientBundle.userId == peer.userId ? local : _boundPreview(incoming, peer);
    return kept.copyWith(
      lastEnvelope: incoming.lastEnvelope,
      updatedAt: incoming.updatedAt,
      disappearingTimerSeconds: incoming.disappearingTimerSeconds,
    );
  }
  if (local == null) {
    return incoming;
  }
  final keepBundle = _isEmptyBundle(incoming.recipientBundle) &&
      local.recipientBundle.userId == incoming.recipientBundle.userId;
  return incoming.copyWith(
    sessionState: incoming.sessionState ?? local.sessionState,
    recipientBundle: keepBundle ? local.recipientBundle : incoming.recipientBundle,
  );
}

ConversationPeer? _sessionPeerOf(ConversationPreview? local) =>
    local != null && local.type == ConversationType.direct && local.sessionState != null
        ? ConversationPeer(userId: local.recipientBundle.userId, handle: local.peerHandle)
        : null;

// The bound 1:1 as this device knows it when it has no local preview left:
// its peer and nothing else; the next send asks the directory for that peer.
ConversationPreview _boundPreview(ConversationPreview incoming, ConversationPeer peer) => ConversationPreview(
      id: incoming.id,
      peerHandle: peer.handle,
      peerDisplayName: null,
      recipientBundle: KeyBundle(
        userId: peer.userId,
        deviceId: '',
        handle: peer.handle,
        identityPublicKey: '',
        signedPrekeyBundle: '',
      ),
      lastEnvelope: incoming.lastEnvelope,
      updatedAt: incoming.updatedAt,
    );

bool _isEmptyBundle(KeyBundle bundle) =>
    bundle.deviceId.isEmpty &&
    bundle.identityPublicKey.isEmpty &&
    bundle.signedPrekeyBundle.isEmpty;
