import 'dart:async';

import '../conversation_models.dart';
import 'conversation_peer_bindings.dart';
import 'identity_trust.dart';
import 'local_notice.dart';
import 'local_notice_writer.dart';
import 'message_content_service.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';
import 'peer_session_resolver.dart';
import 'session_policy.dart';

/// The user's side of identity changes: showing what holds a conversation
/// back, approving or declining it, and the notices the trust layer raises.
class IdentityChangeService {
  IdentityChangeService({
    required MessengerStateStore store,
    required MessengerSessionContext session,
    required IdentityTrust trust,
    required PeerSessionResolver peers,
    required ConversationPeerBindings bindings,
    required MessageContentService contents,
    required LocalNoticeWriter notices,
    required Future<void> Function(String conversationId) retryPendingMessages,
  })  : _store = store,
        _session = session,
        _trust = trust,
        _peers = peers,
        _bindings = bindings,
        _contents = contents,
        _notices = notices,
        _retryPendingMessages = retryPendingMessages;

  final MessengerStateStore _store;
  final MessengerSessionContext _session;
  final IdentityTrust _trust;
  final PeerSessionResolver _peers;
  final ConversationPeerBindings _bindings;
  final MessageContentService _contents;
  final LocalNoticeWriter _notices;
  final Future<void> Function(String conversationId) _retryPendingMessages;

  PendingIdentityChange? pendingFor(String conversationId) => _trust.pendingFor(conversationId);

  /// Every identity change that starts holding a conversation back.
  Stream<PendingIdentityChange> get changes =>
      _trust.events.expand((event) => [if (event is IdentityChangePending) event.change]);

  /// Accepts the change pending in [conversationId], when it is still
  /// [reviewed], then reopens what it held back (see IdentityTrust.approve).
  Future<void> approve(String conversationId, {bool reverified = false, PendingIdentityChange? reviewed}) async {
    final accepted = await _trust.approve(conversationId, reverified: reverified, reviewed: reviewed);
    // Every chat with this contact may still hold a session to the identity
    // the approval replaced.
    _peers.recheckDirectory([
      conversationId,
      for (final other in _store.conversations)
        if (other.type == ConversationType.direct && other.recipientBundle.userId == accepted.userId) other.id,
    ]);
    unawaited(_contents.retryPending(conversationId, _store.messagesOf(conversationId)));
    await _retryPendingMessages(conversationId);
  }

  /// Why the 1:1 [conversationId] admits no identity until the user
  /// acknowledges the account it is listed with, if it is held.
  PeerAccountHold? accountHoldFor(String conversationId) => _bindings.heldNow(conversationId);

  /// The user chose to talk to the account the held 1:1 [conversationId]
  /// is listed with: it is bound to that account, and what it sent and what
  /// waited to be sent go through as a first contact.
  Future<void> acknowledgeAccount(String conversationId) async {
    final conversation = _store.conversationById(conversationId);
    if (conversation == null || conversation.type != ConversationType.direct) return;
    await _bindings.acknowledge(
      conversationId,
      ConversationPeer(userId: conversation.recipientBundle.userId, handle: conversation.peerHandle),
    );
    _store.changed();
    unawaited(_contents.retryPending(conversationId, _store.messagesOf(conversationId)));
    await _retryPendingMessages(conversationId);
  }

  /// Whether the user may keep the current identity instead of the change
  /// pending in [conversationId].
  bool mayDecline(String conversationId) {
    final change = _trust.pendingFor(conversationId);
    return change != null && !_presentsSessionIdentity(conversationId, change);
  }

  /// Keeps the identity the pins hold instead of [reviewed]; its key is
  /// refused from then on without asking again. Throws [StateError] when
  /// [reviewed] presents the identity the session sends to.
  Future<void> decline(String conversationId, {required PendingIdentityChange reviewed}) async {
    if (_presentsSessionIdentity(conversationId, reviewed)) {
      throw StateError('The safety number this conversation sends to cannot be declined. Verify it instead.');
    }
    for (final settled in await _trust.decline(conversationId, reviewed: reviewed)) {
      // The directory may still serve the declined key; asking it again
      // would only refuse every send.
      _peers.skipDirectoryRecheck(settled);
      await _retryPendingMessages(settled);
    }
  }

  // A device is pinned once for every conversation, and a pinned device
  // passes silently from then on. So a new device is announced in each
  // chat with its owner, not only where it first showed up: admitted
  // through a group, it could otherwise take over the 1:1 with that
  // contact without a word there.
  Future<void> onTrustEvent(IdentityTrustEvent event) async {
    final announced = switch (event) {
      NewDeviceAdmitted(:final userId, :final deviceId) => [
          event,
          for (final other in _store.conversations)
            if (other.id != event.conversationId &&
                other.type == ConversationType.direct &&
                other.recipientBundle.userId == userId)
              NewDeviceAdmitted(other.id, userId: userId, deviceId: deviceId),
        ],
      _ => [event],
    };
    for (final each in announced) {
      await _notices.write(
        each.conversationId,
        localNoticeFor(each, conversationMessages: _store.messagesOf(each.conversationId), now: DateTime.now()),
      );
      // The trust layer outlives the messenger and may have announced the
      // change just before it was disposed.
      if (_session.isClosed) return;
    }
    _store.changed();
  }

  // Reads the pending and declined identity changes back for the session
  // just applied, so a chat a restart left with a pending change shows it
  // without waiting for the next refusal. A trust layer that cannot prepare
  // yet (the cache opens late) is read by the next decision instead.
  Future<void> readBackDecisions() async {
    try {
      await _trust.ready;
    } catch (_) {
      return;
    }
    _store.changed();
  }

  // Whether [change] presents the identity the session of the 1:1
  // [conversationId] sends to: the bundle a steady-state send seals to,
  // which the engine binds its sending state to.
  bool _presentsSessionIdentity(String conversationId, PendingIdentityChange change) {
    final conversation = _store.conversationById(conversationId);
    if (conversation == null ||
        conversation.type != ConversationType.direct ||
        !_peers.hasSessionFor(conversationId)) {
      return false;
    }
    final bundle = conversation.recipientBundle;
    return bundle.deviceId == change.deviceId && sameIdentityKey(bundle.identityPublicKey, change.presentedKey);
  }
}
