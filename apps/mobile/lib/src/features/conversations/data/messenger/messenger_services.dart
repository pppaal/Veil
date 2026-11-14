import 'dart:async';

import '../../../../app/app_session_state.dart';
import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/network/keys_api.dart';
import '../../../../core/network/veil_api_client.dart';
import '../../../../core/notifications/local_notification_service.dart';
import '../../../../core/realtime/realtime_service.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import '../../../attachments/data/attachment_temp_file_store.dart';
import '../conversation_models.dart';
import '../group_sender_key_coordinator.dart';
import 'attachment_transfer_service.dart';
import 'conversation_crypto_router.dart';
import 'conversation_peer_bindings.dart';
import 'conversation_sync_service.dart';
import 'decrypted_message_cache.dart';
import 'disappearing_messages_service.dart';
import 'envelope_version_policy.dart';
import 'identity_change_service.dart';
import 'identity_trust.dart';
import 'local_notice_writer.dart';
import 'message_content_service.dart';
import 'message_merge.dart';
import 'message_search_service.dart';
import 'messenger_api_mapper.dart';
import 'messenger_operation_runner.dart';
import 'messenger_persistence.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';
import 'outbox_service.dart';
import 'peer_session_resolver.dart';
import 'pending_messages.dart';
import 'prekey_maintenance.dart';
import 'presence_typing_service.dart';
import 'reaction_service.dart';
import 'realtime_event_router.dart';
import 'receipt_service.dart';
import 'session_change.dart';

/// The messenger's services, wired to each other, and the session
/// lifecycle that spans all of them. VeilMessengerController is the facade
/// in front of it.
class MessengerServices {
  MessengerServices({
    required VeilApiClient apiClient,
    required MessageCryptoEngine cryptoEngine,
    required KeysApi keys,
    required CryptoEnvelopeCodec envelopeCodec,
    required ConversationSessionBootstrapper sessionBootstrapper,
    required RealtimeService realtimeService,
    required ConversationCacheService? cache,
    required AttachmentTempFileStore? attachmentTempFileStore,
    required LocalNotificationService? notificationService,
    required Future<void> Function(Object error)? onSecurityException,
    required Future<void> Function()? sessionSnapshotRestorer,
    required GroupSenderKeyCoordinator? groupCrypto,
    required bool Function() readReceiptsEnabled,
    required bool Function() typingIndicatorsEnabled,
    required this.trust,
    required EnvelopeVersionPolicy envelopeVersions,
    required ConversationPeerBindings peerBindings,
    required PrekeyMaintenance? prekeyMaintenance,
    required void Function() onChanged,
    required void Function() onSignedOut,
  })  : _envelopeVersions = envelopeVersions,
        _onSignedOut = onSignedOut,
        _peerBindings = peerBindings,
        _groupCrypto = groupCrypto,
        _sessionSnapshotRestorer = sessionSnapshotRestorer,
        _prekeys = prekeyMaintenance {
    store = MessengerStateStore(
      onChanged: onChanged,
      decorate: (conversationId, messages) => receipts.applyBacklog(reactions.decorate(conversationId, messages)),
      onLatestMessageChanged: (conversationId) => unawaited(latest.refresh(conversationId)),
    );
    ops = MessengerOperationRunner(onChanged: store.changed, onSecurityException: onSecurityException);
    final mapper = MessengerApiMapper(envelopeCodec);
    // Disappearing expiries are stamped and checked on the relay's clock,
    // corrected by at most an hour (see ServerClock.boundedNow).
    final expiryClock = expiryNow = apiClient.serverClock.boundedNow;
    persistence = MessengerPersistence(cache: cache, store: store, now: expiryClock);
    contents = MessageContentService(
      cache: cache,
      decrypt: (envelope, {beforeCommit}) => crypto.decrypt(envelope, beforeCommit: beforeCommit),
      onContentStored: _onContentStored,
      now: expiryClock,
    );
    latest = DecryptedMessageCache(contents: contents, store: store);
    final notices = LocalNoticeWriter(store: store, contents: contents, session: session, flush: persistence.flush);
    peers = PeerSessionResolver(
      store: store,
      session: session,
      sessions: sessionBootstrapper,
      keys: keys,
      trust: trust,
      bindings: peerBindings,
      flush: persistence.flush,
    );
    crypto = ConversationCryptoRouter(
      store: store,
      session: session,
      engine: cryptoEngine,
      peers: peers,
      trust: trust,
      bindings: peerBindings,
      envelopeVersions: envelopeVersions,
      groupCrypto: groupCrypto,
      refreshConversations: () => sync.refreshConversations(),
      onSessionOpened: (conversationId) =>
          unawaited(contents.retryPending(conversationId, store.messagesOf(conversationId))),
      flush: persistence.flush,
    );
    receipts = ReceiptService(
      store: store,
      session: session,
      apiClient: apiClient,
      readReceiptsEnabled: readReceiptsEnabled,
    );
    final pending = PendingMessages(persistence);
    attachments = AttachmentTransferService(
      store: store,
      session: session,
      apiClient: apiClient,
      mapper: mapper,
      crypto: crypto,
      contents: contents,
      pending: pending,
      tempStore: attachmentTempFileStore,
      ops: ops,
    );
    outbox = OutboxService(
      store: store,
      session: session,
      apiClient: apiClient,
      mapper: mapper,
      crypto: crypto,
      contents: contents,
      pending: pending,
      attachments: attachments,
      ops: ops,
      expiryClock: expiryClock,
    );
    reactions = ReactionService(store: store, session: session, send: outbox.send);
    identity = IdentityChangeService(
      store: store,
      session: session,
      trust: trust,
      peers: peers,
      bindings: peerBindings,
      contents: contents,
      notices: notices,
      retryPendingMessages: outbox.retry,
    );
    disappearing = DisappearingMessagesService(
      store: store,
      contents: contents,
      persistence: persistence,
      session: session,
      apiClient: apiClient,
      mapper: mapper,
      ops: ops,
      now: expiryClock,
    );
    sync = ConversationSyncService(
      store: store,
      session: session,
      apiClient: apiClient,
      mapper: mapper,
      contents: contents,
      persistence: persistence,
      crypto: crypto,
      peerBindings: peerBindings,
      notices: notices,
      disappearing: disappearing,
      outbox: outbox,
      attachments: attachments,
      reactions: reactions,
      latest: latest,
      tempStore: attachmentTempFileStore,
      ops: ops,
    );
    presence = PresenceTypingService(
      realtime: realtimeService,
      isConnected: () => realtime.connected,
      typingIndicatorsEnabled: typingIndicatorsEnabled,
    );
    realtime = RealtimeEventRouter(
      realtime: realtimeService,
      session: session,
      store: store,
      mapper: mapper,
      contents: contents,
      ops: ops,
      receipts: receipts,
      presence: presence,
      sync: sync,
      disappearing: disappearing,
      crypto: crypto,
      outbox: outbox,
      notifications: notificationService,
      refreshAccessToken: apiClient.refreshAccessToken,
    );
    search = MessageSearchService(store: store, contents: contents, cache: cache, session: session);
    store
      ..addObserver(persistence)
      ..addObserver(disappearing);
  }

  final IdentityTrust trust;
  final EnvelopeVersionPolicy _envelopeVersions;
  final ConversationPeerBindings _peerBindings;
  final GroupSenderKeyCoordinator? _groupCrypto;
  final Future<void> Function()? _sessionSnapshotRestorer;
  final PrekeyMaintenance? _prekeys;
  final void Function() _onSignedOut;
  final MessengerSessionContext session = MessengerSessionContext();
  late final MessengerStateStore store;
  late final MessengerOperationRunner ops;
  late final MessengerPersistence persistence;
  late final MessageContentService contents;
  late final DecryptedMessageCache latest;
  late final PeerSessionResolver peers;
  late final ConversationCryptoRouter crypto;
  late final ReceiptService receipts;
  late final AttachmentTransferService attachments;
  late final OutboxService outbox;
  late final ReactionService reactions;
  late final IdentityChangeService identity;
  late final DisappearingMessagesService disappearing;
  late final ConversationSyncService sync;
  late final PresenceTypingService presence;
  late final RealtimeEventRouter realtime;
  late final MessageSearchService search;

  /// The clock disappearing-message expiries are stamped and checked on:
  /// the relay's, corrected by at most an hour (ServerClock.boundedNow).
  late final DateTime Function() expiryNow;
  bool _sessionsRestored = false;

  /// Whether this device can run Sender Keys groups.
  bool get canUseSenderKeys => _groupCrypto != null;

  /// Moves the messenger to [next]: a new token reaches the socket only,
  /// a sign-out forgets everything the identity held, and a new identity
  /// starts from the cache, then the relay.
  Future<void> applySession(AppSessionState next) async {
    // Session updates can still arrive while the owning provider tears the
    // messenger down.
    if (session.isClosed) return;
    switch (session.diff(next)) {
      case SessionChange.none:
        return;
      case SessionChange.tokenOnly:
        // Only an authenticated session can change just its token.
        if (session.signedIn case final signedIn?) await realtime.applyToken(signedIn.accessToken);
        return;
      case SessionChange.signedOut:
        await _signOut();
        return;
      case SessionChange.identityChanged:
        realtime.disconnect();
        _forgetIdentity();
        // Only a new identity starts the writer over: after a sign-out it
        // stays wiped, so nothing still in flight for the identity that
        // left can write into the cache the next one opens.
        persistence.reset();
        unawaited(identity.readBackDecisions());
    }

    // Rehydrate persisted Double Ratchet state before any encrypt/decrypt
    // happens. Only runs once per authenticated session.
    if (!_sessionsRestored) {
      _sessionsRestored = true;
      try {
        await _sessionSnapshotRestorer?.call();
      } catch (_) {
        // Corrupt snapshots are ignored; sessions will be re-bootstrapped
        // lazily on inbound envelope.
      }
    }

    await sync.hydrate();
    await sync.refreshConversations();
    await realtime.connect();
    unawaited(outbox.drain());
    unawaited(_prekeys?.run(next, force: true));
  }

  Future<void> handleAppResumed() async {
    // The expiry timer runs on the monotonic clock, which stops while the
    // device sleeps: what came due meanwhile goes now, relay or not.
    unawaited(disappearing.reconcile());
    if (session.authed == null) return;
    await realtime.reconnect(refreshConversations: true);
    sync.scheduleSyncHint(conversationId: store.activeConversationId);
    await outbox.drain(ignoreRetrySchedule: true);
    // Reads the session now: it may have signed out while this synced.
    unawaited(_prekeys?.run(session.current));
  }

  void dispose() {
    session.close();
    outbox.dispose();
    sync.dispose();
    disappearing.dispose();
    presence.dispose();
    attachments.cancelUploads();
    realtime.disconnect();
    persistence.dispose();
  }

  Future<void> _signOut() async {
    realtime.disconnect();
    _forgetIdentity();
    // Signing out forgets the identity changes the user has not decided
    // and the ones declined, the stored record included. Nothing else
    // deletes it: a sign-in only reads it back.
    final forgettingDecisions = trust.forgetDecisions();
    attachments
      ..cancelUploads()
      ..clear();
    store.clear();
    outbox.clear();
    receipts.clear();
    sync.clearQueuedHints();
    _onSignedOut();
    _sessionsRestored = false;
    _groupCrypto?.clearInMemory();
    await forgettingDecisions;
  }

  // Everything held for the previous identity in memory; the stored
  // records stay.
  void _forgetIdentity() {
    contents.reset();
    reactions.clear();
    trust.reset();
    _envelopeVersions.reset();
    _peerBindings.reset();
    crypto.clear();
    peers.clear();
    latest.clear();
    sync.forgetHistoryMarks();
  }

  // Runs whenever content becomes bound to a relayed message (the ack path
  // applies the same clamp itself). Local expiry is the earlier of the
  // server's outer expiresAt and the authenticated inner one, so a server
  // that strips or extends the timer cannot keep the message around.
  void _onContentStored(ChatMessage message, MessageContentRecord record) {
    if (record.kind == MessageKind.reaction && record.status == MessageContentStatus.ok) {
      reactions.applyOpened(message, record);
    }
    final conversationId = record.conversationId;
    store.updateMessagesWhere(
      (candidate) => candidate.id == message.id,
      (candidate) => withInnerExpiry(candidate, record.innerExpiresAt),
      inConversation: conversationId,
    );
    if (store.messagesOf(conversationId).lastOrNull?.id == message.id) {
      unawaited(latest.refresh(conversationId));
    }
    store.changed();
  }
}
