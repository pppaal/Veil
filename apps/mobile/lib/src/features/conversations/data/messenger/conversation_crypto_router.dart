import 'dart:async';

import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/realtime/realtime_events.dart';
import '../../../../core/util/uuid_v4.dart';
import '../conversation_models.dart';
import '../group_sender_key_coordinator.dart';
import 'conversation_peer_bindings.dart';
import 'envelope_version_policy.dart';
import 'identity_trust.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';
import 'peer_session_resolver.dart';
import 'session_policy.dart';

/// The single routing point for every encrypt and decrypt: Sender Keys
/// groups through the group engine, everything else through the pairwise
/// engine under the identity pins, with the version policy refusing
/// downgrades in both directions.
class ConversationCryptoRouter {
  ConversationCryptoRouter({
    required MessengerStateStore store,
    required MessengerSessionContext session,
    required MessageCryptoEngine engine,
    required PeerSessionResolver peers,
    required IdentityTrust trust,
    required ConversationPeerBindings bindings,
    required EnvelopeVersionPolicy envelopeVersions,
    required GroupSenderKeyCoordinator? groupCrypto,
    required Future<void> Function() refreshConversations,
    required void Function(String conversationId) onSessionOpened,
  })  : _store = store,
        _session = session,
        _engine = engine,
        _peers = peers,
        _trust = trust,
        _bindings = bindings,
        _envelopeVersions = envelopeVersions,
        _groupCrypto = groupCrypto,
        _refreshConversations = refreshConversations,
        _onSessionOpened = onSessionOpened;

  final MessengerStateStore _store;
  final MessengerSessionContext _session;
  final MessageCryptoEngine _engine;
  final PeerSessionResolver _peers;
  final IdentityTrust _trust;
  final ConversationPeerBindings _bindings;
  final EnvelopeVersionPolicy _envelopeVersions;
  final GroupSenderKeyCoordinator? _groupCrypto;
  final Future<void> Function() _refreshConversations;
  final void Function(String conversationId) _onSessionOpened;
  // Devices and identity keys inbound handshakes proved, by conversation,
  // from the verifier until the session they opened is recorded.
  final Map<String, ({String deviceId, String key})> _handshakeIdentities = {};
  // Inbound sessions opened before their conversation was listed (the peer
  // created it and wrote straight away), recorded once the list has it.
  final Map<String, ConversationSessionState> _unlistedInboundSessions = {};

  /// Groups that opted into Sender Keys get one ciphertext for everyone,
  /// stamped with the membership epoch; everything else is pairwise.
  Future<CryptoEnvelope> encrypt({
    required ConversationPreview conversation,
    required String senderDeviceId,
    required String body,
    required MessageKind messageKind,
    DateTime? expiresAt,
    AttachmentReference? attachment,
  }) async {
    final groupCrypto = _groupCrypto;
    if (groupCrypto != null && _usesSenderKeys(conversation)) {
      await groupCrypto.prepareSend(
        conversation: conversation,
        accessToken: _session.requireAuthed().accessToken,
        localUserId: _session.userId ?? '',
        localDeviceId: senderDeviceId,
      );
      return groupCrypto.encryptMessage(
        conversation: conversation,
        senderDeviceId: senderDeviceId,
        body: body,
        messageKind: messageKind,
        expiresAt: expiresAt,
        attachment: attachment,
      );
    }

    // A group once seen with Sender Keys never falls back to the pairwise
    // engine, whatever its preview says now.
    if (await _envelopeVersions.isSenderKeysPinned(conversation.id)) {
      throw StateError('This group uses Sender Keys, which this device cannot send with.');
    }
    final isGroup = conversation.type == ConversationType.group;
    Future<CryptoEnvelope> sealFor(KeyBundle bundle) => _engine.encryptMessage(
          conversationId: conversation.id,
          senderDeviceId: senderDeviceId,
          recipientUserId: isGroup ? '' : bundle.userId,
          body: body,
          messageKind: messageKind,
          recipientBundle: bundle,
          expiresAt: expiresAt,
          attachment: attachment,
        );
    if (isGroup) return sealFor(conversation.recipientBundle);
    try {
      return await sealFor(await _peers.bundleForSend(conversation));
    } on SessionRecipientChanged {
      // A peer's handshake moved the session after the recipient was chosen.
      return sealFor(await _peers.bundleForSend(conversation, sessionMoved: true));
    }
  }

  /// Seals an attachment under a random id: protocol v2 binds the id into
  /// the blob's AAD, so it must exist before the relay tickets the upload.
  /// Its storage key stays empty: recipients download by attachment id.
  Future<AttachmentCipher> sealAttachment({
    required ConversationPreview conversation,
    required String contentType,
    required List<int> plaintext,
  }) async {
    final recipientBundle = conversation.type == ConversationType.group
        ? conversation.recipientBundle
        : await _peers.bundleForSend(conversation);
    return _engine.encryptAttachment(
      attachmentId: randomUuidV4(),
      storageKey: '',
      contentType: contentType,
      plaintext: plaintext,
      recipientBundle: recipientBundle,
    );
  }

  /// Opens [envelope]; [beforeCommit] stores its content before the engine
  /// commits (see [BeforeCommit]).
  Future<DecryptedMessage> decrypt(CryptoEnvelope envelope, {BeforeCommit? beforeCommit}) async {
    final groupCrypto = _groupCrypto;
    if (groupCrypto != null && GroupSenderKeyCoordinator.isGroupEnvelope(envelope)) {
      final opened = await groupCrypto.decryptMessage(
        envelope,
        accessToken: _session.current.accessToken ?? '',
        localUserId: _session.userId ?? '',
        beforeCommit: beforeCommit,
      );
      if (opened.isOk) await _envelopeVersions.pinSenderKeys(envelope.conversationId);
      return opened;
    }
    // This device's own messages are shown from the content it stored before
    // sealing them, never by opening a frame: it cannot open what it sealed.
    // A pairwise frame under its own device id was made by someone else, the
    // relay included, and opening it would show their words as the user's.
    if (_isOwnDevice(envelope.senderDeviceId)) {
      return const DecryptedMessage(
        body: '',
        messageKind: MessageKind.text,
        status: DecryptStatus.failed,
        failureReason: 'own_device_frame',
      );
    }
    if (await _refusesPairwise(envelope)) {
      return DecryptedMessage(
        body: '',
        messageKind: MessageKind.text,
        status: DecryptStatus.failed,
        failureReason: 'downgrade_rejected',
      );
    }
    _notePeerDevice(envelope);
    // A legacy v1 frame never opens a session here. This device publishes
    // only a v2 bundle, so no honest peer can start a v1 session with it,
    // and the v1 responder handshake authenticates nobody: its root comes
    // from our identity key and an ephemeral the sender chose, so a frame
    // with no session to open on can only come from whoever chose that
    // ephemeral, the relay included. It ends as sessionMissing.
    final decrypted = await _engine.decryptMessage(envelope, beforeCommit: beforeCommit);
    if (decrypted.isOk) {
      await _envelopeVersions.noteAuthenticated(envelope.conversationId, envelope.version);
    }
    _noteOpenedSession(envelope, decrypted);
    return decrypted;
  }

  /// Decides whether a peer identity may be used in a 1:1 conversation:
  /// before an inbound handshake installs a session, with the same pin
  /// policy as an outbound bootstrap, and before every frame sealed to or
  /// opened on an installed session, so that one the pins stopped admitting
  /// is neither written to nor shown as the conversation's peer.
  Future<bool> verifyRemoteIdentity(RemoteIdentityClaim claim) async {
    // No peer may claim this device's id: admitting it would pin the local
    // device under someone else's account.
    if (_isOwnDevice(claim.senderDeviceId)) return false;
    try {
      if (_store.conversationById(claim.conversationId) == null) await _refreshConversations();
      final conversation = _store.conversationById(claim.conversationId);
      if (conversation == null || conversation.type != ConversationType.direct) return false;
      final peerUserId = conversation.recipientBundle.userId;
      final key = claim.identityKeyEd25519;
      // Held for its listed handle (see ConversationPeerBindings.holdFor):
      // nothing it sent opens, and the pins are not even asked, until the
      // user acknowledges the account. The frames wait and open then.
      final listed = ConversationPeer(userId: peerUserId, handle: conversation.peerHandle);
      if (await _bindings.holdFor(conversation.id, listed) != null) return false;
      if (!claim.installsSession) {
        return await _trust.admitSession(conversation.id, peerUserId, claim.senderDeviceId, key);
      }
      if (!await _trust.admit(conversation.id, peerUserId, claim.senderDeviceId, key)) {
        return false;
      }
      await _bindings.bindAll({conversation.id: listed});
      _handshakeIdentities[conversation.id] = (deviceId: claim.senderDeviceId, key: key);
      return true;
    } catch (_) {
      // Fails closed; the frame is retried once the conversation resolves.
      return false;
    }
  }

  /// Records the inbound sessions held back until their conversation was
  /// listed; call after the list was refreshed.
  void recordUnlistedSessions() {
    final unlisted = Map.of(_unlistedInboundSessions);
    _unlistedInboundSessions.clear();
    unlisted.forEach(_recordInboundSession);
  }

  // Sender Keys mode is pinned the first time a group is listed with it,
  // and a pinned group stays a Sender Keys group whatever a later list
  // says: listed without it, its sends and frames would go through the
  // pairwise engine. Returns the previews and the ids of the groups whose
  // listing tried to turn Sender Keys off.
  Future<(List<ConversationPreview>, List<String>)> keepSenderKeys(List<ConversationPreview> previews) async {
    final kept = <ConversationPreview>[];
    final overruled = <String>[];
    for (final preview in previews) {
      if (preview.type == ConversationType.group && preview.useSenderKeys) {
        await _envelopeVersions.pinSenderKeys(preview.id);
        kept.add(preview);
      } else if (await _envelopeVersions.isSenderKeysPinned(preview.id)) {
        kept.add(preview.copyWith(type: ConversationType.group, useSenderKeys: true));
        overruled.add(preview.id);
      } else {
        kept.add(preview);
      }
    }
    return (kept, overruled);
  }

  void handleKeyDistribution(Map<String, dynamic> payload) {
    final groupCrypto = _groupCrypto;
    if (groupCrypto == null) return;
    unawaited(groupCrypto.handleKeyDistributionEvent(
      payload,
      localUserId: _session.userId ?? '',
      accessToken: _session.current.accessToken ?? '',
    ));
  }

  // Membership changed: remember the new epoch on the preview, refresh the
  // member list, then let the group engine re-key and redistribute.
  Future<void> handleEpochBumped(GroupEpochBumpedEvent event) async {
    _store.updateConversation(event.conversationId, (preview) => preview.copyWith(groupEpoch: event.epoch));
    try {
      await _refreshConversations();
    } catch (_) {
      // Membership refresh is best-effort; the epoch is already recorded.
    }
    final groupCrypto = _groupCrypto;
    final session = _session.signedIn;
    if (groupCrypto == null || session == null) return;
    await groupCrypto.handleEpochBumped(
      conversationId: event.conversationId,
      epoch: event.epoch,
      reason: event.reason.name,
      userId: event.userId,
      accessToken: session.accessToken,
      localUserId: session.userId,
      localDeviceId: session.deviceId,
    );
  }

  void clear() {
    _handshakeIdentities.clear();
    _unlistedInboundSessions.clear();
  }

  bool _isOwnDevice(String deviceId) {
    final localDeviceId = _session.deviceId;
    return localDeviceId != null && localDeviceId.isNotEmpty && deviceId == localDeviceId;
  }

  bool _usesSenderKeys(ConversationPreview conversation) =>
      conversation.type == ConversationType.group && conversation.useSenderKeys && _groupCrypto != null;

  // The envelope version is outer metadata: a Sender Keys group (one the
  // relay lists as such, or ever did) never takes the pairwise path, and a
  // conversation where protocol v2 authenticated never goes back to an
  // older version.
  Future<bool> _refusesPairwise(CryptoEnvelope envelope) async =>
      (_store.conversationById(envelope.conversationId)?.useSenderKeys ?? false) ||
      await _envelopeVersions.rejects(envelope.conversationId, envelope.version);

  // A frame from a device the 1:1 session is not bound to means the peer has
  // most likely moved, so the next send asks the directory and follows.
  void _notePeerDevice(CryptoEnvelope envelope) {
    final conversation = _store.conversationById(envelope.conversationId);
    final localDeviceId = _session.deviceId;
    if (conversation != null &&
        localDeviceId != null &&
        comesFromNewPeerDevice(conversation, envelope, localDeviceId: localDeviceId)) {
      _peers.recheckDirectory([conversation.id]);
    }
  }

  // Engines run the responder half of the handshake inside decrypt. Once a
  // peer frame has opened, record the session it established, so replies,
  // identity pinning and device-move detection have something to compare
  // against. A handshake that moved an established conversation to another
  // device or identity is recorded as well (see sessionNames), and the next
  // send confirms that device with the directory before encrypting to it
  // again.
  void _noteOpenedSession(CryptoEnvelope envelope, DecryptedMessage decrypted) {
    final conversationId = envelope.conversationId;
    // Taken whatever happens next, so a key proved by a handshake that was
    // not kept is never attributed to a later session.
    final proven = _handshakeIdentities.remove(conversationId);
    final provenKey = proven?.deviceId == envelope.senderDeviceId ? proven!.key : '';
    final conversation = _store.conversationById(conversationId);
    final localDeviceId = _session.deviceId;
    if (localDeviceId == null ||
        envelope.senderDeviceId == localDeviceId ||
        (conversation != null && conversation.type != ConversationType.direct) ||
        !decrypted.isOk ||
        !_peers.hasSessionFor(conversationId)) {
      return;
    }
    final recorded = conversation?.sessionState ?? _unlistedInboundSessions[conversationId];
    if (recorded != null) {
      if (provenKey.isEmpty || sessionNames(recorded, envelope.senderDeviceId, provenKey)) return;
      _peers.recheckDirectory([conversationId]);
    }
    _recordInboundSession(
      conversationId,
      observedInboundSession(envelope, localDeviceId: localDeviceId, remoteIdentityPublicKey: provenKey),
    );
    _onSessionOpened(conversationId);
  }

  // Records an inbound session on its conversation, so a reply reuses it
  // instead of bootstrapping a second one the sender would never know about.
  // Only 1:1 conversations carry a pairwise session, and one held back until
  // its conversation was listed may turn out to belong to a group.
  void _recordInboundSession(String conversationId, ConversationSessionState state) {
    final conversation = _store.conversationById(conversationId);
    if (conversation == null) {
      _unlistedInboundSessions[conversationId] = state;
      return;
    }
    if (conversation.type != ConversationType.direct) {
      return;
    }
    final provenKey = state.remoteIdentityPublicKey;
    _store.updateConversation(
      conversationId,
      (preview) => preview.copyWith(
        sessionState: state,
        recipientBundle: provenKey.isEmpty
            ? null
            : KeyBundle(
                userId: preview.recipientBundle.userId,
                deviceId: state.remoteDeviceId,
                handle: preview.peerHandle,
                identityPublicKey: provenKey,
                signedPrekeyBundle: '',
              ),
      ),
    );
    // A session whose handshake this device did not see proved nobody to
    // it; its peer's key is pinned from the directory instead.
    if (provenKey.isEmpty) _peers.learnPeerIdentity(conversation).ignore();
  }
}
