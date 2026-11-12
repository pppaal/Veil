import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/app_session_state.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/identity/identity_key_value_backend.dart';
import '../../../core/identity/trusted_identity_resolver.dart';
import '../../../core/identity/trusted_identity_store.dart';
import '../../../core/network/keys_api.dart';
import '../../../core/network/veil_api_client.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../../core/storage/conversation_cache_service.dart';
import '../../attachments/data/attachment_temp_file_store.dart';
import '../../device_transfer/data/device_transfer_controller.dart';
import 'conversation_models.dart';
import 'group_sender_key_coordinator.dart';
import 'messenger/attachment_transfer_service.dart';
import 'messenger/conversation_peer_bindings.dart';
import 'messenger/envelope_version_policy.dart';
import 'messenger/identity_trust.dart';
import 'messenger/messenger_services.dart';
import 'messenger/prekey_maintenance.dart';
import 'messenger/presence_typing_service.dart';

export 'messenger/attachment_transfer_service.dart' show AttachmentTransferPhase, AttachmentTransferSnapshot;

/// The messenger as the app sees it: one notifier in front of the services
/// under messenger/ (see MessengerServices), which do the work.
class VeilMessengerController extends ChangeNotifier {
  static bool _always() => true;

  VeilMessengerController({
    required VeilApiClient apiClient,
    required MessageCryptoEngine cryptoEngine,
    required KeyBundleCodec keyBundleCodec,
    required CryptoEnvelopeCodec envelopeCodec,
    required ConversationSessionBootstrapper sessionBootstrapper,
    required RealtimeService realtimeService,
    required ConversationCacheService? cacheService,
    AttachmentTempFileStore? attachmentTempFileStore,
    LocalNotificationService? notificationService,
    Future<void> Function(Object error)? onSecurityException,
    Future<void> Function()? sessionSnapshotRestorer,
    GroupSenderKeyCoordinator? groupCrypto,
    bool Function()? readReceiptsEnabled,
    bool Function()? typingIndicatorsEnabled,
    KeysApi? keysApi,
    IdentityTrust? identityTrust,
    EnvelopeVersionPolicy? envelopeVersions,
    ConversationPeerBindings? peerBindings,
    PrekeyMaintenance? prekeyMaintenance,
    DeviceTransferController? deviceTransfer,
  }) : _ownsDeviceTransfer = deviceTransfer == null {
    _services = MessengerServices(
      apiClient: apiClient,
      cryptoEngine: cryptoEngine,
      keys: keysApi ?? KeysApi(apiClient, keyBundleCodec),
      envelopeCodec: envelopeCodec,
      sessionBootstrapper: sessionBootstrapper,
      realtimeService: realtimeService,
      cache: cacheService,
      attachmentTempFileStore: attachmentTempFileStore,
      notificationService: notificationService,
      onSecurityException: onSecurityException,
      sessionSnapshotRestorer: sessionSnapshotRestorer,
      groupCrypto: groupCrypto,
      readReceiptsEnabled: readReceiptsEnabled ?? _always,
      typingIndicatorsEnabled: typingIndicatorsEnabled ?? _always,
      // Without a keystore-backed trust layer, pins last for the process.
      trust: identityTrust ??
          IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(InMemoryIdentityKeyValueBackend()))),
      envelopeVersions: envelopeVersions ?? EnvelopeVersionPolicy(),
      peerBindings: peerBindings ?? ConversationPeerBindings(),
      prekeyMaintenance: prekeyMaintenance,
      onChanged: notifyListeners,
      onSignedOut: () => _deviceTransfer.clearTransferState(),
    );
    _deviceTransfer = deviceTransfer ??
        DeviceTransferController(
          apiClient: apiClient,
          session: () => _services.session.current,
          onSecurityException: onSecurityException,
        );
    _deviceTransfer.addListener(notifyListeners);
    _trustEvents = _services.trust.events.listen((event) => unawaited(_services.identity.onTrustEvent(event)));
  }

  late final MessengerServices _services;
  late final DeviceTransferController _deviceTransfer;
  final bool _ownsDeviceTransfer;
  late final StreamSubscription<IdentityTrustEvent> _trustEvents;
  bool _disposed = false;

  List<ConversationPreview> get conversations => _services.store.conversations;
  bool get isBusy => _services.ops.isBusy;
  bool get realtimeConnected => _services.realtime.connected;
  String? get errorMessage => _services.ops.errorMessage;
  bool get hasPendingWork => _services.outbox.hasPendingWork;
  String? get activeConversationId => _services.store.activeConversationId;

  bool isResolvingAttachment(String attachmentId) => _services.attachments.isResolving(attachmentId);
  String? attachmentDownloadError(String attachmentId) => _services.attachments.downloadError(attachmentId);
  AttachmentTransferSnapshot? attachmentTransferForMessage(String clientMessageId) =>
      _services.attachments.transferFor(clientMessageId);

  /// Who is typing and who is online. A notifier of its own, so widgets
  /// that show these signals rebuild without the rest of the messenger.
  PresenceTypingService get presenceTyping => _services.presence;
  String? typingHandleFor(String conversationId) => _services.presence.typingHandleFor(conversationId);
  bool isUserOnline(String userId) => _services.presence.isUserOnline(userId);

  /// Decrypted body of the conversation's latest message when that message
  /// is text that opened successfully; null otherwise.
  String? lastMessagePreviewFor(String conversationId) => _services.latest.previewFor(conversationId);

  /// Decrypted kind of the conversation's latest message, or null until it
  /// has opened. Never the envelope's unauthenticated kind.
  MessageKind? lastMessageKindFor(String conversationId) => _services.latest.kindFor(conversationId);

  List<ChatMessage> messagesFor(String conversationId) => List.unmodifiable(_services.store.messagesOf(conversationId));
  bool hasMoreHistoryFor(String conversationId) => _services.store.pagingFor(conversationId).hasMoreHistory;
  bool isLoadingHistoryFor(String conversationId) => _services.sync.isLoadingHistory(conversationId);
  int pendingCountFor(String conversationId) => _services.store.pendingCountFor(conversationId);
  DateTime? nextRetryAtForConversation(String conversationId) => _services.outbox.nextRetryAt(conversationId);

  /// Now, on the clock disappearing messages expire by: the relay's, as its
  /// responses report it, corrected by at most an hour. Whatever shows or
  /// hides a message by its expiry reads this, never the device clock, so a
  /// device whose clock runs fast does not hide a message the relay still
  /// keeps.
  DateTime expiryNow() => _services.expiryNow();

  /// The conversation with [conversationId] in the current list, if any.
  ConversationPreview? conversationById(String conversationId) => _services.store.conversationById(conversationId);

  Future<void> applySession(AppSessionState session) => _services.applySession(session);

  /// The conversation the user is looking at right now, or null. Incoming
  /// messages there are marked read and raise no notification, so callers
  /// must clear it as soon as the chat is no longer on screen.
  void setActiveConversation(String? conversationId) => _services.store.activeConversationId = conversationId;

  Future<void> handleAppResumed() => _services.handleAppResumed();

  /// Writes every pending state change to the cache now, e.g. before the
  /// app is paused.
  Future<void> flushPendingWrites() => _services.persistence.flush();

  Future<void> refreshConversations() => _services.ops.run(_services.sync.refreshConversations);

  Future<void> loadConversationMessages(String conversationId) =>
      _services.ops.run(() => _services.sync.syncConversation(conversationId));

  Future<void> loadOlderConversationMessages(String conversationId) => _services.sync.loadOlder(conversationId);

  Future<void> retryPendingMessages([String? conversationId]) => _services.outbox.retry(conversationId);

  Future<String?> startConversationByHandle(String handle) => _services.sync.startDirectConversation(handle);

  /// New groups opt into Sender Keys (per-sender chains and authorship)
  /// when this client can run them; the legacy shared-key path stays for
  /// groups created by older clients.
  Future<void> createGroup({
    required String name,
    String? description,
    List<String> memberHandles = const [],
    bool isPublic = false,
    bool? useSenderKeys,
  }) =>
      _services.sync.createGroup(
        name: name,
        description: description,
        memberHandles: memberHandles,
        isPublic: isPublic,
        useSenderKeys: useSenderKeys ?? _services.canUseSenderKeys,
      );

  void notifyTyping(String conversationId) => _services.presence.localTyping(conversationId);

  Future<void> sendText({required String conversationId, required String body, Duration? disappearAfter}) async {
    _services.presence.localTypingEnded(conversationId);
    await _services.outbox.send(
      conversationId: conversationId,
      body: body,
      messageKind: MessageKind.text,
      disappearAfter: disappearAfter,
    );
  }

  Future<void> sendSystemNotice({required String conversationId, required String body, Duration? disappearAfter}) =>
      _services.outbox.send(
        conversationId: conversationId,
        body: body,
        messageKind: MessageKind.system,
        disappearAfter: disappearAfter,
      );

  /// Replaces the session of the 1:1 [conversationId] with a fresh X3DH
  /// handshake that must pass the identity pins (else
  /// IdentityChangedException). The old session is archived, so frames in
  /// flight on it still open; the next message sent carries the handshake.
  /// Returns false when there is no session to replace. A forced ratchet
  /// step on the live session cannot be made safe: if the peer sent since
  /// our last send, neither side could decrypt the other again.
  Future<bool> renewSession(String conversationId) => _services.peers.renewSession(conversationId);

  /// A member's chain key arrived (or the group re-keyed): give this
  /// conversation's "awaiting sender key" rows another pass.
  void onGroupKeysChanged(String conversationId) =>
      unawaited(_services.contents.retryPending(conversationId, _services.store.messagesOf(conversationId)));

  /// The identity change that holds [conversationId] back, if any.
  PendingIdentityChange? pendingIdentityChangeFor(String conversationId) =>
      _services.identity.pendingFor(conversationId);

  /// Every identity change that starts holding a conversation back.
  Stream<PendingIdentityChange> get identityChanges => _services.identity.changes;

  /// Accepts the identity change pending in [conversationId] when it is
  /// still [reviewed]; a contact the user had verified needs [reverified]
  /// (see IdentityTrust.approve). Then reopens what it held back.
  Future<void> approveIdentityChange(String conversationId, {bool reverified = false, PendingIdentityChange? reviewed}) =>
      _services.identity.approve(conversationId, reverified: reverified, reviewed: reviewed);

  /// Whether the user may keep the current identity instead of the change
  /// pending in [conversationId] (see [declineIdentityChange]).
  bool mayDeclineIdentityChange(String conversationId) => _services.identity.mayDecline(conversationId);

  /// Keeps the pinned identity instead of [reviewed], whose key is refused
  /// from then on (see IdentityTrust.decline). Throws [StateError] when
  /// [reviewed] presents the identity the conversation's session sends to.
  Future<void> declineIdentityChange(String conversationId, {required PendingIdentityChange reviewed}) =>
      _services.identity.decline(conversationId, reviewed: reviewed);

  /// Decides whether a peer identity may be used in a 1:1 conversation; see
  /// LibCryptoAdapter.setRemoteIdentityVerifier.
  Future<bool> verifyRemoteIdentity(RemoteIdentityClaim claim) => _services.crypto.verifyRemoteIdentity(claim);

  Future<void> sendAttachmentPlaceholder(String conversationId, {String filename = 'dossier.enc'}) =>
      _services.outbox.sendAttachmentPlaceholder(conversationId, filename: filename);

  Future<void> markRead(String messageId) => _services.receipts.markRead(messageId);

  Future<void> setDisappearingTimer(String conversationId, int? seconds) =>
      _services.disappearing.setTimer(conversationId, seconds);

  Future<String?> getAttachmentDownloadUrl(String attachmentId) => _services.attachments.downloadUrl(attachmentId);

  Future<void> cancelPendingAttachment(String clientMessageId) => _services.outbox.cancelAttachment(clientMessageId);

  @Deprecated('Use deviceTransferControllerProvider.')
  String? get transferSessionId => _deviceTransfer.transferSessionId;
  @Deprecated('Use deviceTransferControllerProvider.')
  String? get transferToken => _deviceTransfer.transferToken;
  @Deprecated('Use deviceTransferControllerProvider.')
  String? get transferStatus => _deviceTransfer.transferStatus;
  @Deprecated('Use deviceTransferControllerProvider.')
  DateTime? get transferExpiresAt => _deviceTransfer.transferExpiresAt;
  @Deprecated('Use deviceTransferControllerProvider.')
  String? get transferPayload => _deviceTransfer.transferPayload;
  @Deprecated('Use deviceTransferControllerProvider.')
  Future<void> initTransfer() => _deviceTransfer.initTransfer();
  @Deprecated('Use deviceTransferControllerProvider.')
  Future<void> approveTransfer(String claimId) => _deviceTransfer.approveTransfer(claimId);
  @Deprecated('Use deviceTransferControllerProvider.')
  void clearTransferState() => _deviceTransfer.clearTransferState();

  Future<DecryptedMessage> decryptEnvelope(CryptoEnvelope envelope) => _services.crypto.decrypt(envelope);

  /// Content of [message] for display. Reads stored content; the envelope is
  /// decrypted only if this message has never been opened before.
  Future<DecryptedMessage> decryptMessage(ChatMessage message) => _services.contents.read(message);

  /// Ids of loaded messages whose decrypted content matches [query]. Reads
  /// stored content only and never decrypts.
  Future<List<String>> searchLoadedMessageIds(String conversationId, {required String query}) =>
      _services.search.searchLoaded(conversationId, query: query);

  Future<MessageSearchPage> searchMessageArchive({required MessageSearchQuery query}) =>
      _services.search.searchArchive(query);

  /// Adds [emoji] to [message], or withdraws it if it is already this
  /// user's reaction. It travels end to end as a message of kind reaction.
  Future<void> toggleReaction(ChatMessage message, String emoji) => _services.reactions.toggle(message, emoji);

  /// The key [handle]'s active device currently publishes, as the directory
  /// serves it. Read-only: it claims no prekey and changes no session or pin.
  Future<KeyBundle> fetchPeerKeyBundle(String handle) => _services.peers.publishedBundle(handle);

  @override
  void dispose() {
    _services.dispose();
    unawaited(_trustEvents.cancel());
    _deviceTransfer.removeListener(notifyListeners);
    if (_ownsDeviceTransfer) _deviceTransfer.dispose();
    _disposed = true;
    super.dispose();
  }

  // Decrypts, uploads and syncs finish asynchronously and may land after the
  // owning provider has disposed this controller.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
