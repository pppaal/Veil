import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../app/app_state.dart';
import '../../../core/config/veil_config.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/identity/identity_key_value_backend.dart';
import '../../../core/identity/trusted_identity_resolver.dart';
import '../../../core/identity/trusted_identity_store.dart';
import '../../../core/network/keys_api.dart';
import '../../../core/network/veil_api_client.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../../core/storage/conversation_cache_service.dart';
import '../../../core/util/uuid_v4.dart';
import '../../attachments/data/attachment_temp_file_store.dart';
import 'conversation_models.dart';
import 'group_sender_key_coordinator.dart';
import 'messenger/conversation_merge.dart';
import 'messenger/conversation_peer_bindings.dart';
import 'messenger/envelope_version_policy.dart';
import 'messenger/identity_trust.dart';
import 'messenger/local_notice.dart';
import 'messenger/message_content_service.dart';
import 'messenger/message_merge.dart';
import 'messenger/peer_bundle_cache.dart';
import 'messenger/prekey_maintenance.dart';
import 'messenger/reactions.dart';
import 'messenger/retry_policy.dart';
import 'messenger/session_change.dart';
import 'messenger/session_policy.dart';

class VeilMessengerController extends ChangeNotifier {
  static const _retrySweepInterval = Duration(seconds: 3);
  static const _syncHintDebounceDuration = Duration(milliseconds: 180);

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
  })  : _readReceiptsEnabled = readReceiptsEnabled ?? _always,
        _typingIndicatorsEnabled = typingIndicatorsEnabled ?? _always,
        _apiClient = apiClient,
        _cryptoEngine = cryptoEngine,
        _envelopeCodec = envelopeCodec,
        _sessionBootstrapper = sessionBootstrapper,
        _realtimeService = realtimeService,
        _cacheService = cacheService,
        _attachmentTempFileStore = attachmentTempFileStore,
        _notificationService = notificationService,
        _onSecurityException = onSecurityException,
        _sessionSnapshotRestorer = sessionSnapshotRestorer,
        _groupCrypto = groupCrypto,
        _keys = keysApi ?? KeysApi(apiClient, keyBundleCodec),
        // Without a keystore-backed trust layer, pins last for the process.
        _trust = identityTrust ??
            IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(InMemoryIdentityKeyValueBackend()))),
        _envelopeVersions = envelopeVersions ?? EnvelopeVersionPolicy(),
        _peerBindings = peerBindings ?? ConversationPeerBindings(),
        _prekeys = prekeyMaintenance {
    _trustEvents = _trust.events.listen((event) => unawaited(_onTrustEvent(event)));
    _expirationTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_reconcileExpiringState()),
    );
    _retryTicker = Timer.periodic(
      _retrySweepInterval,
      (_) => unawaited(_drainOutbox()),
    );
  }

  final VeilApiClient _apiClient;
  final MessageCryptoEngine _cryptoEngine;
  final CryptoEnvelopeCodec _envelopeCodec;
  final ConversationSessionBootstrapper _sessionBootstrapper;
  final RealtimeService _realtimeService;
  final ConversationCacheService? _cacheService;
  final AttachmentTempFileStore? _attachmentTempFileStore;
  final LocalNotificationService? _notificationService;
  final Future<void> Function(Object error)? _onSecurityException;
  final Future<void> Function()? _sessionSnapshotRestorer;
  final GroupSenderKeyCoordinator? _groupCrypto;
  final KeysApi _keys;
  final IdentityTrust _trust;
  final EnvelopeVersionPolicy _envelopeVersions;
  final ConversationPeerBindings _peerBindings;
  final PrekeyMaintenance? _prekeys;
  late final StreamSubscription<IdentityTrustEvent> _trustEvents;
  final ReactionLedger _reactions = ReactionLedger();
  // Devices and identity keys inbound handshakes proved, by conversation,
  // from the verifier until the session they opened is recorded.
  final Map<String, ({String deviceId, String key})> _handshakeIdentities = {};
  // Privacy switches, read on every use so a settings change applies at once.
  final bool Function() _readReceiptsEnabled;
  final bool Function() _typingIndicatorsEnabled;
  late final MessageContentService _contents = MessageContentService(
    cache: _cacheService,
    decrypt: decryptEnvelope,
    onContentStored: _onContentStored,
  );
  final PeerBundleCache _peerBundles = PeerBundleCache();
  // Conversations whose next send must ask the directory first: a rekey was
  // armed, or a frame arrived from a peer device the session is not bound to.
  final Set<String> _directoryRecheck = <String>{};
  // Inbound sessions opened before their conversation was listed (the peer
  // created it and wrote straight away), recorded once the list has it.
  final Map<String, ConversationSessionState> _unlistedInboundSessions = {};
  // Opened content of each conversation's latest message, for the list.
  final Map<String, MessageContentRecord> _lastContents = {};
  bool _sessionsRestored = false;
  bool _disposed = false;
  final Random _random = Random.secure();

  Timer? _expirationTicker;
  Timer? _retryTicker;
  List<ConversationPreview> _conversations = [];
  final Map<String, List<ChatMessage>> _messagesByConversation = {};
  final Map<String, ConversationPagingState> _pagingStateByConversation = {};
  final Map<String, PendingMessageRecord> _pendingByClientMessageId = {};
  final Map<String, _PendingReceiptUpdate> _receiptBacklogByMessageId = {};
  final Set<String> _historyLoadingConversationIds = {};
  final Set<String> _resolvingAttachmentIds = {};
  final Set<String> _queuedSyncConversationIds = {};
  bool _conversationRefreshQueued = false;
  bool _refreshConversationsOnConnect = true;
  final Map<String, AttachmentTransferSnapshot> _attachmentTransfersByClientMessageId = {};
  final Map<String, String> _attachmentDownloadErrors = {};
  final Map<String, AttachmentUploadCancellationSignal> _activeUploadSignals = {};

  AppSessionState _session = const AppSessionState();
  bool _isBusy = false;
  bool _isDrainingOutbox = false;
  bool _realtimeConnected = false;
  String? _activeConversationId;
  String? _errorMessage;
  String? _transferSessionId;
  String? _transferToken;
  String? _transferStatus;
  DateTime? _transferExpiresAt;
  Timer? _syncHintDebounce;
  bool _syncAfterHintInFlight = false;
  final Map<String, String> _typingByConversation = {};
  Timer? _typingClearTimer;
  Timer? _localTypingDebounce;
  bool _localTypingActive = false;
  final Set<String> _onlineUserIds = {};

  List<ConversationPreview> get conversations => _conversations;
  bool get isBusy => _isBusy;
  bool get realtimeConnected => _realtimeConnected;
  String? get errorMessage => _errorMessage;
  bool isResolvingAttachment(String attachmentId) => _resolvingAttachmentIds.contains(attachmentId);
  String? attachmentDownloadError(String attachmentId) => _attachmentDownloadErrors[attachmentId];
  AttachmentTransferSnapshot? attachmentTransferForMessage(String clientMessageId) =>
      _attachmentTransfersByClientMessageId[clientMessageId];
  String? get transferSessionId => _transferSessionId;
  String? get transferToken => _transferToken;
  String? get transferStatus => _transferStatus;
  DateTime? get transferExpiresAt => _transferExpiresAt;
  bool get hasPendingWork => _pendingByClientMessageId.isNotEmpty;
  String? typingHandleFor(String conversationId) => _typingByConversation[conversationId];
  bool isUserOnline(String userId) => _onlineUserIds.contains(userId);
  String? get activeConversationId => _activeConversationId;

  /// Decrypted body of the conversation's latest message when that message
  /// is text that opened successfully; null otherwise.
  String? lastMessagePreviewFor(String conversationId) {
    final content = _lastContents[conversationId];
    return content?.kind == MessageKind.text ? content!.body : null;
  }

  /// Decrypted kind of the conversation's latest message, or null until it
  /// has opened. Never the envelope's unauthenticated kind.
  MessageKind? lastMessageKindFor(String conversationId) => _lastContents[conversationId]?.kind;
  String? get transferPayload =>
      _transferSessionId == null || _transferToken == null
          ? null
          : 'VEIL_TRANSFER::${_transferSessionId!}::${_transferToken!}';

  List<ChatMessage> messagesFor(String conversationId) =>
      List.unmodifiable(_messagesByConversation[conversationId] ?? const []);

  bool hasMoreHistoryFor(String conversationId) =>
      _pagingStateByConversation[conversationId]?.hasMoreHistory ?? true;

  bool isLoadingHistoryFor(String conversationId) =>
      _historyLoadingConversationIds.contains(conversationId);

  int pendingCountFor(String conversationId) => _messagesByConversation[conversationId]
          ?.where((message) => message.isPending || message.hasFailed)
          .length ??
      0;

  DateTime? nextRetryAtForConversation(String conversationId) {
    DateTime? earliest;
    for (final pending in _pendingByClientMessageId.values) {
      if (pending.conversationId != conversationId || pending.nextRetryAt == null) {
        continue;
      }
      final nextRetryAt = pending.nextRetryAt!;
      if (earliest == null || nextRetryAt.isBefore(earliest)) {
        earliest = nextRetryAt;
      }
    }
    return earliest;
  }

  Future<void> applySession(AppSessionState session) async {
    // Session updates can still arrive while the owning provider tears the
    // controller down.
    if (_disposed) return;
    final change = classifySessionChange(_session, session);
    _session = session;

    switch (change) {
      case SessionChange.none:
        return;
      case SessionChange.tokenOnly:
        // Same identity: every cache and the live ratchet state stay valid.
        // Rehydrating here used to drop decrypted history whose message keys
        // were already spent; only the socket needs the new token.
        _refreshConversationsOnConnect = false;
        if (_realtimeConnected) {
          _realtimeService.updateAuth(session.accessToken!);
        } else {
          await _connectRealtime();
        }
        return;
      case SessionChange.signedOut:
        _realtimeService.disconnect();
        _realtimeConnected = false;
        _forgetIdentityCaches();
        // Signing out forgets the identity changes the user has not decided
        // and the ones declined, the stored record included. Nothing else
        // deletes it: a sign-in only reads it back.
        final forgettingDecisions = _trust.forgetDecisions();
        for (final signal in _activeUploadSignals.values) {
          signal.cancel();
        }
        _activeUploadSignals.clear();
        _conversations = [];
        _messagesByConversation.clear();
        _pagingStateByConversation.clear();
        _pendingByClientMessageId.clear();
        _receiptBacklogByMessageId.clear();
        _resolvingAttachmentIds.clear();
        _attachmentDownloadErrors.clear();
        _attachmentTransfersByClientMessageId.clear();
        _queuedSyncConversationIds.clear();
        _activeConversationId = null;
        _transferSessionId = null;
        _transferToken = null;
        _transferStatus = null;
        _transferExpiresAt = null;
        _sessionsRestored = false;
        _groupCrypto?.clearInMemory();
        notifyListeners();
        await forgettingDecisions;
        return;
      case SessionChange.identityChanged:
        _realtimeService.disconnect();
        _realtimeConnected = false;
        _forgetIdentityCaches();
        unawaited(_readBackIdentityDecisions());
    }

    // Rehydrate persisted Double Ratchet state before any encrypt/decrypt
    // happens. Only runs once per authenticated session.
    if (!_sessionsRestored) {
      _sessionsRestored = true;
      final restorer = _sessionSnapshotRestorer;
      if (restorer != null) {
        try {
          await restorer();
        } catch (_) {
          // Corrupt snapshots are ignored; sessions will be re-bootstrapped
          // lazily on inbound envelope.
        }
      }
    }

    await _hydrateFromCache();
    await _refreshConversationsCore();
    await _connectRealtime();
    unawaited(_drainOutbox());
    unawaited(_prekeys?.run(session, force: true));
  }

  /// The conversation the user is looking at right now, or null. Incoming
  /// messages there are marked read and raise no notification, so callers
  /// must clear it as soon as the chat is no longer on screen.
  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
  }

  void _forgetIdentityCaches() {
    _contents.reset();
    _reactions.clear();
    // What was read for the previous session; the stored record stays.
    _trust.reset();
    _envelopeVersions.reset();
    _peerBindings.reset();
    _handshakeIdentities.clear();
    _peerBundles.clear();
    _directoryRecheck.clear();
    _unlistedInboundSessions.clear();
    _lastContents.clear();
  }

  // Reads the pending and declined identity changes back for the session
  // just applied, so a chat a restart left with a pending change shows it
  // without waiting for the next refusal. A trust layer that cannot prepare
  // yet (the cache opens late) is read by the next decision instead.
  Future<void> _readBackIdentityDecisions() async {
    try {
      await _trust.ready;
    } catch (_) {
      return;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> handleAppResumed() async {
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }

    await _refreshRealtimeAndSync(forceReconnect: true);
    // Reads the session now: it may have signed out while this synced.
    unawaited(_prekeys?.run(_session));
  }

  Future<void> refreshConversations() async {
    await _run(_refreshConversationsCore);
  }

  Future<void> loadConversationMessages(String conversationId) async {
    await _run(() => _syncConversation(conversationId));
  }

  Future<void> loadOlderConversationMessages(String conversationId) async {
    if (_historyLoadingConversationIds.contains(conversationId) || !hasMoreHistoryFor(conversationId)) {
      return;
    }

    _historyLoadingConversationIds.add(conversationId);
    notifyListeners();
    try {
      await _syncConversation(conversationId, loadMore: true);
    } catch (error) {
      _errorMessage = formatUserFacingError(error);
      notifyListeners();
    } finally {
      _historyLoadingConversationIds.remove(conversationId);
      notifyListeners();
    }
  }

  Future<void> retryPendingMessages([String? conversationId]) async {
    await _drainOutbox(
      conversationId: conversationId,
      markFailuresAsRetrying: true,
      ignoreRetrySchedule: true,
    );
  }

  Future<String?> startConversationByHandle(String handle) async {
    String? conversationId;
    await _run(() async {
      if (!_session.isAuthenticated || !VeilConfig.hasApi) {
        throw StateError('Authenticated API session required.');
      }

      final result = await _apiClient.createDirectConversation(_session.accessToken!, handle);
      final conversation = result['conversation'] as Map<String, dynamic>?;
      conversationId = conversation?['id'] as String?;
      await _refreshConversationsCore();
    });
    return conversationId;
  }

  Future<void> createGroup({
    required String name,
    String? description,
    List<String> memberHandles = const [],
    bool isPublic = false,
    // New groups opt into Sender Keys (per-sender chains + authorship) when
    // this client can run them; the legacy shared-key path stays for groups
    // created by older clients.
    bool? useSenderKeys,
  }) async {
    await _run(() async {
      if (!_session.isAuthenticated || !VeilConfig.hasApi) {
        throw StateError('Authenticated API session required.');
      }

      await _apiClient.createGroup(_session.accessToken!, {
        'name': name,
        if (description != null && description.isNotEmpty) 'description': description,
        if (memberHandles.isNotEmpty) 'memberHandles': memberHandles,
        'isPublic': isPublic,
        'useSenderKeys': useSenderKeys ?? (_groupCrypto != null),
      });
      await _refreshConversationsCore();
    });
  }

  void notifyTyping(String conversationId) {
    if (!_realtimeConnected || !_typingIndicatorsEnabled()) return;
    if (!_localTypingActive) {
      _localTypingActive = true;
      _realtimeService.emit('typing.start', {'conversationId': conversationId});
    }
    _localTypingDebounce?.cancel();
    _localTypingDebounce = Timer(const Duration(seconds: 3), () {
      _localTypingActive = false;
      _realtimeService.emit('typing.stop', {'conversationId': conversationId});
    });
  }

  Future<void> sendText({
    required String conversationId,
    required String body,
    Duration? disappearAfter,
  }) async {
    _localTypingDebounce?.cancel();
    if (_localTypingActive) {
      _localTypingActive = false;
      _realtimeService.emit('typing.stop', {'conversationId': conversationId});
    }
    await _sendEnvelope(
      conversationId: conversationId,
      body: body,
      messageKind: MessageKind.text,
      disappearAfter: disappearAfter,
    );
  }

  Future<void> sendSystemNotice({
    required String conversationId,
    required String body,
    Duration? disappearAfter,
  }) async {
    await _sendEnvelope(
      conversationId: conversationId,
      body: body,
      messageKind: MessageKind.system,
      disappearAfter: disappearAfter,
    );
  }

  /// Replaces the session of the 1:1 [conversationId] with a new one: a
  /// fresh X3DH handshake with the peer's current directory entry, which
  /// must pass the identity pins first (else IdentityChangedException and
  /// nothing changes). The old session is archived, never destroyed, so
  /// frames already in flight on it still open; the next message sent here
  /// carries the handshake, and the peer moves to the new session when it
  /// reads it. Returns false when there is no session to replace.
  ///
  /// A forced ratchet step on the live session cannot be made safe: if the
  /// peer sent since our last send, the step is taken from a ratchet key it
  /// already moved past, and neither side can decrypt the other again.
  Future<bool> renewSession(String conversationId) async {
    final conversation = conversationById(conversationId);
    if (conversation == null ||
        conversation.type != ConversationType.direct ||
        !_session.isAuthenticated ||
        !_sessionBootstrapper.hasSessionFor(conversationId)) {
      return false;
    }
    final served = await _fetchPeerBundle(conversation.peerHandle, KeyClaim.active);
    await _applyDirectoryAnswer(conversationId, served, mustBootstrap: true);
    _directoryRecheck.remove(conversationId);
    return true;
  }

  /// Encrypts and queues one message; false when that failed (the failure
  /// is surfaced as usual).
  Future<bool> _sendEnvelope({
    required String conversationId,
    required String body,
    required MessageKind messageKind,
    Duration? disappearAfter,
  }) async {
    var queued = false;
    await _run(() async {
      if (!_session.isAuthenticated || !VeilConfig.hasApi) {
        throw StateError('Authenticated API session required.');
      }

      final conversation =
          _conversations.firstWhere((item) => item.id == conversationId);
      final clientMessageId = _nextClientMessageId();
      final expiresAt = disappearAfter == null ? null : DateTime.now().add(disappearAfter);
      final envelope = await _encryptOutbound(
        conversation: conversation,
        clientMessageId: clientMessageId,
        body: body,
        messageKind: messageKind,
        expiresAt: expiresAt,
      );

      await _enqueuePendingMessage(
        conversation: conversation,
        clientMessageId: clientMessageId,
        envelope: envelope,
      );
      queued = true;
      unawaited(_drainOutbox(conversationId: conversationId));
    });
    return queued;
  }

  bool _usesSenderKeys(ConversationPreview conversation) =>
      conversation.type == ConversationType.group &&
      conversation.useSenderKeys &&
      _groupCrypto != null;

  /// The conversation with [conversationId] in the current list, if any.
  ConversationPreview? conversationById(String conversationId) {
    for (final convo in _conversations) {
      if (convo.id == conversationId) return convo;
    }
    return null;
  }

  /// A member's chain key arrived (or the group re-keyed): give this
  /// conversation's "awaiting sender key" rows another pass. Content that
  /// already opened is final and is not touched.
  void onGroupKeysChanged(String conversationId) {
    unawaited(_contents.retryPending(conversationId, messagesFor(conversationId)));
  }

  /// The identity change that holds [conversationId] back, if any.
  PendingIdentityChange? pendingIdentityChangeFor(String conversationId) => _trust.pendingFor(conversationId);

  /// Every identity change that starts holding a conversation back.
  Stream<PendingIdentityChange> get identityChanges =>
      _trust.events.expand((event) => [if (event is IdentityChangePending) event.change]);

  /// Accepts the identity change pending in [conversationId], then reopens
  /// what it held back. Fails when the pending change is no longer
  /// [reviewed], the one the user was shown. A contact the user had verified
  /// needs [reverified], set only once the user compared the safety number
  /// of [reviewed] out of band (see IdentityTrust.approve).
  Future<void> approveIdentityChange(
    String conversationId, {
    bool reverified = false,
    PendingIdentityChange? reviewed,
  }) async {
    final accepted = await _trust.approve(conversationId, reverified: reverified, reviewed: reviewed);
    // Every chat with this contact may still hold a session to the identity
    // the approval replaced.
    _directoryRecheck.addAll([
      conversationId,
      for (final other in _conversations)
        if (other.type == ConversationType.direct && other.recipientBundle.userId == accepted.userId) other.id,
    ]);
    unawaited(_contents.retryPending(conversationId, messagesFor(conversationId)));
    await retryPendingMessages(conversationId);
  }

  /// Whether the user may keep the current identity instead of the change
  /// pending in [conversationId] (see [declineIdentityChange]).
  bool mayDeclineIdentityChange(String conversationId) {
    final change = _trust.pendingFor(conversationId);
    return change != null && !_presentsSessionIdentity(conversationId, change);
  }

  /// Keeps the identity the pins hold instead of the change pending in
  /// [conversationId], [reviewed] being the change the user was shown; its
  /// key is refused from then on without asking again (see
  /// IdentityTrust.decline). Messages it held back go out on the
  /// conversation's current session. Throws [StateError] when [reviewed]
  /// presents the identity that session sends to: there is no current key
  /// to keep in its place.
  Future<void> declineIdentityChange(String conversationId, {required PendingIdentityChange reviewed}) async {
    if (_presentsSessionIdentity(conversationId, reviewed)) {
      throw StateError('The safety number this conversation sends to cannot be declined. Verify it instead.');
    }
    for (final settled in await _trust.decline(conversationId, reviewed: reviewed)) {
      // The directory may still serve the declined key; asking it again
      // would only refuse every send.
      _directoryRecheck.remove(settled);
      await retryPendingMessages(settled);
    }
  }

  // Whether [change] presents the identity the session of the 1:1
  // [conversationId] sends to: the bundle a steady-state send seals to,
  // which the engine binds its sending state to.
  bool _presentsSessionIdentity(String conversationId, PendingIdentityChange change) {
    final conversation = conversationById(conversationId);
    if (conversation == null ||
        conversation.type != ConversationType.direct ||
        !_sessionBootstrapper.hasSessionFor(conversationId)) {
      return false;
    }
    final bundle = conversation.recipientBundle;
    return bundle.deviceId == change.deviceId && sameIdentityKey(bundle.identityPublicKey, change.presentedKey);
  }

  /// Decides whether a peer identity may be used in a 1:1 conversation
  /// (adapters that authenticate their peers call it, see
  /// LibCryptoAdapter.setRemoteIdentityVerifier): before an inbound
  /// handshake installs a session, with the same pin policy as an outbound
  /// bootstrap, and before every frame sealed to or opened on an installed
  /// session, so that one the pins stopped admitting is neither written to
  /// nor shown as the conversation's peer.
  Future<bool> verifyRemoteIdentity(RemoteIdentityClaim claim) async {
    try {
      if (conversationById(claim.conversationId) == null) await _refreshConversationsCore();
      final conversation = conversationById(claim.conversationId);
      if (conversation == null || conversation.type != ConversationType.direct) return false;
      final peerUserId = conversation.recipientBundle.userId;
      final key = claim.identityKeyEd25519;
      if (!claim.installsSession) {
        return await _trust.admitSession(conversation.id, peerUserId, claim.senderDeviceId, key);
      }
      if (!await _trust.admit(conversation.id, peerUserId, claim.senderDeviceId, key)) {
        return false;
      }
      _handshakeIdentities[conversation.id] = (deviceId: claim.senderDeviceId, key: key);
      return true;
    } catch (_) {
      // Fails closed; the frame is retried once the conversation resolves.
      return false;
    }
  }

  Future<void> _onTrustEvent(IdentityTrustEvent event) async {
    // A device is pinned once for every conversation, and a pinned device
    // passes silently from then on. So a new device is announced in each
    // chat with its owner, not only where it first showed up: admitted
    // through a group, it could otherwise take over the 1:1 with that
    // contact without a word there.
    final announced = switch (event) {
      NewDeviceAdmitted(:final userId, :final deviceId) => [
          event,
          for (final other in _conversations)
            if (other.id != event.conversationId &&
                other.type == ConversationType.direct &&
                other.recipientBundle.userId == userId)
              NewDeviceAdmitted(other.id, userId: userId, deviceId: deviceId),
        ],
      _ => [event],
    };
    for (final each in announced) {
      await _storeNotice(
        each.conversationId,
        localNoticeFor(each, conversationMessages: messagesFor(each.conversationId), now: DateTime.now()),
      );
      // The trust layer outlives this controller and may have announced
      // the change just before it was disposed.
      if (_disposed) return;
    }
    notifyListeners();
  }

  // Inserts [notice] into its conversation unless it is already there.
  Future<void> _storeNotice(String conversationId, LocalNotice? notice) async {
    if (notice == null || messagesFor(conversationId).any((message) => message.id == notice.message.id)) return;
    await _contents.storeLocalNotice(notice.message, notice.code);
    if (_disposed) return;
    _mergeServerMessages(conversationId, [notice.message]);
    await _persistConversationState(conversationId);
  }

  // Stores the plaintext before encrypting so the sender can always show
  // its own message: the sender cannot decrypt what it sealed.
  Future<CryptoEnvelope> _encryptOutbound({
    required ConversationPreview conversation,
    required String clientMessageId,
    required String body,
    required MessageKind messageKind,
    DateTime? expiresAt,
  }) async {
    await _contents.storeOutbound(
      conversationId: conversation.id,
      clientMessageId: clientMessageId,
      body: body,
      kind: messageKind,
      expiresAt: expiresAt,
    );
    try {
      return await _encryptForConversation(
        conversation: conversation,
        senderDeviceId: _session.deviceId!,
        body: body,
        messageKind: messageKind,
        expiresAt: expiresAt,
      );
    } catch (_) {
      // Never queued, so never shown: do not keep its plaintext at rest.
      await _contents.discardOutbound(clientMessageId);
      rethrow;
    }
  }

  // Single routing point for outbound encryption. Groups that opted into
  // Sender Keys go through the group engine (one ciphertext for everyone,
  // stamped with the membership epoch); everything else keeps the 1:1 path.
  Future<CryptoEnvelope> _encryptForConversation({
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
        accessToken: _session.accessToken!,
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
    Future<CryptoEnvelope> sealFor(KeyBundle bundle) => _cryptoEngine.encryptMessage(
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
      return await sealFor(await _bundleForSend(conversation));
    } on SessionRecipientChanged {
      // A peer's handshake moved the session after the recipient was chosen.
      return sealFor(await _bundleForSend(conversation, sessionMoved: true));
    }
  }

  Future<void> sendAttachmentPlaceholder(
    String conversationId, {
    String filename = 'dossier.enc',
  }) async {
    await _run(() async {
      if (!_session.isAuthenticated || !VeilConfig.hasApi) {
        throw StateError('Authenticated API session required.');
      }

      final conversation = _conversations.firstWhere((item) => item.id == conversationId);
      final clientMessageId = _nextClientMessageId();
      final tempBlob = await _stageAttachmentBlob(filename: filename);
      final envelope = await _encryptOutbound(
        conversation: conversation,
        clientMessageId: clientMessageId,
        body: 'Encrypted attachment',
        messageKind: MessageKind.file,
      );

      await _enqueuePendingMessage(
        conversation: conversation,
        clientMessageId: clientMessageId,
        envelope: envelope,
        attachmentUploadDraft: AttachmentUploadDraft(
          filename: filename,
          contentType: _guessContentType(filename),
          sizeBytes: tempBlob.sizeBytes,
          sha256: tempBlob.sha256,
          tempFilePath: tempBlob.path,
          lastUpdatedAt: tempBlob.createdAt,
        ),
      );
      unawaited(_drainOutbox(conversationId: conversationId));
    });
  }

  Future<void> markRead(String messageId) async {
    if (!_session.isAuthenticated ||
        !VeilConfig.hasApi ||
        !_readReceiptsEnabled() ||
        messageId.startsWith(localNoticeIdPrefix)) {
      return;
    }

    try {
      await _apiClient.markRead(_session.accessToken!, messageId);
      _applyReceiptEvent(messageId, readAt: DateTime.now());
    } catch (_) {
      // Server resync reconciles later.
    }
  }

  Future<void> setDisappearingTimer(
    String conversationId,
    int? seconds,
  ) async {
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      _applyTimerChanged(
        conversationId: conversationId,
        disappearingTimerSeconds: seconds,
      );
      return;
    }

    try {
      final response = await _apiClient.setDisappearingTimer(
        _session.accessToken!,
        conversationId,
        seconds,
      );
      final data = response['conversation'] as Map<String, dynamic>?;
      final nextSeconds = data == null
          ? seconds
          : data['disappearingTimerSeconds'] as int?;
      _applyTimerChanged(
        conversationId: conversationId,
        disappearingTimerSeconds: nextSeconds,
      );
    } catch (error) {
      await _handleSecurityException(error);
      _errorMessage = formatUserFacingError(error);
      notifyListeners();
      rethrow;
    }
  }

  void _applyTimerChanged({
    required String conversationId,
    required int? disappearingTimerSeconds,
  }) {
    var changed = false;
    _conversations = _conversations.map((conversation) {
      if (conversation.id != conversationId) {
        return conversation;
      }
      if (conversation.disappearingTimerSeconds == disappearingTimerSeconds) {
        return conversation;
      }
      changed = true;
      return conversation.copyWith(
        disappearingTimerSeconds: disappearingTimerSeconds,
      );
    }).toList(growable: false);
    if (changed) {
      unawaited(_cacheService?.storeConversations(_conversations));
      notifyListeners();
    }
  }

  Future<String?> getAttachmentDownloadUrl(String attachmentId) async {
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      return null;
    }

    _attachmentDownloadErrors.remove(attachmentId);
    _resolvingAttachmentIds.add(attachmentId);
    notifyListeners();
    try {
      final response = await _apiClient.getDownloadTicket(_session.accessToken!, attachmentId);
      return (response['ticket'] as Map<String, dynamic>)['downloadUrl'] as String;
    } catch (error) {
      await _handleSecurityException(error);
      final message = formatUserFacingError(error);
      _attachmentDownloadErrors[attachmentId] = message;
      _errorMessage = message;
      return null;
    } finally {
      _resolvingAttachmentIds.remove(attachmentId);
      notifyListeners();
    }
  }

  Future<void> cancelPendingAttachment(String clientMessageId) async {
    final pending = _pendingByClientMessageId[clientMessageId];
    if (pending == null || pending.attachmentUploadDraft == null) {
      return;
    }

    _activeUploadSignals.remove(clientMessageId)?.cancel();
    final failed = pending.copyWith(
      state: MessageDeliveryState.failed,
      errorMessage: 'Attachment upload was canceled on this device.',
      nextRetryAt: null,
      lastAttemptAt: DateTime.now(),
    );
    _pendingByClientMessageId[clientMessageId] = failed;
    await _cacheService?.upsertPendingMessage(failed);
    _updateLocalMessageState(
      clientMessageId,
      state: MessageDeliveryState.failed,
      errorMessage: failed.errorMessage,
    );
    _updateAttachmentTransfer(
      clientMessageId,
      phase: AttachmentTransferPhase.canceled,
      progress: failed.attachmentUploadDraft?.sizeBytes == null
          ? 0
          : ((failed.attachmentUploadDraft!.bytesUploaded / failed.attachmentUploadDraft!.sizeBytes)
                  .clamp(0, 1))
              .toDouble(),
      errorMessage: failed.errorMessage,
      filename: failed.attachmentUploadDraft?.filename,
      contentType: failed.attachmentUploadDraft?.contentType,
      sizeBytes: failed.attachmentUploadDraft?.sizeBytes,
      canRetry: true,
      canCancel: false,
    );
    notifyListeners();
  }

  Future<void> initTransfer() async {
    await _run(() async {
      if (!_session.isAuthenticated || !VeilConfig.hasApi) {
        _transferStatus = 'Transfer requires API mode.';
        return;
      }

      final response =
          await _apiClient.initTransfer(_session.accessToken!, _session.deviceId!);
      _transferSessionId = response['sessionId'] as String;
      _transferToken = response['transferToken'] as String;
      _transferExpiresAt = DateTime.parse(response['expiresAt'] as String);
      _transferStatus = 'Init complete. Token ready.';
    });
  }

  Future<void> approveTransfer(String claimId) async {
    await _run(() async {
      final trimmedClaimId = claimId.trim();
      if (_transferSessionId == null || !_session.isAuthenticated || !VeilConfig.hasApi) {
        _transferStatus = 'Start transfer first.';
        return;
      }
      if (trimmedClaimId.isEmpty) {
        _transferStatus = 'Enter the new-device claim code first.';
        return;
      }

      await _apiClient.approveTransfer(_session.accessToken!, {
        'sessionId': _transferSessionId,
        'claimId': trimmedClaimId,
      });
      _transferStatus = 'Approved claim $trimmedClaimId on old device.';
    });
  }

  void clearTransferState() {
    _transferSessionId = null;
    _transferToken = null;
    _transferStatus = null;
    _transferExpiresAt = null;
    notifyListeners();
  }

  Future<DecryptedMessage> decryptEnvelope(CryptoEnvelope envelope) async {
    final groupCrypto = _groupCrypto;
    if (groupCrypto != null && GroupSenderKeyCoordinator.isGroupEnvelope(envelope)) {
      final opened = await groupCrypto.decryptMessage(
        envelope,
        accessToken: _session.accessToken ?? '',
        localUserId: _session.userId ?? '',
      );
      if (opened.isOk) await _envelopeVersions.pinSenderKeys(envelope.conversationId);
      return opened;
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
    final decrypted = await _cryptoEngine.decryptMessage(envelope);
    if (decrypted.isOk) {
      await _envelopeVersions.noteAuthenticated(envelope.conversationId, envelope.version);
    }
    _noteOpenedSession(envelope, decrypted);
    return decrypted;
  }

  // The envelope version is outer metadata: a Sender Keys group (one the
  // relay lists as such, or ever did) never takes the pairwise path, and a
  // conversation where protocol v2 authenticated never goes back to an
  // older version.
  Future<bool> _refusesPairwise(CryptoEnvelope envelope) async {
    return (conversationById(envelope.conversationId)?.useSenderKeys ?? false) ||
        await _envelopeVersions.rejects(envelope.conversationId, envelope.version);
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
    final conversation = conversationById(conversationId);
    final localDeviceId = _session.deviceId;
    if (localDeviceId == null ||
        envelope.senderDeviceId == localDeviceId ||
        (conversation != null && conversation.type != ConversationType.direct) ||
        !decrypted.isOk ||
        !_sessionBootstrapper.hasSessionFor(conversationId)) {
      return;
    }
    final recorded = conversation?.sessionState ?? _unlistedInboundSessions[conversationId];
    if (recorded != null) {
      if (provenKey.isEmpty || sessionNames(recorded, envelope.senderDeviceId, provenKey)) return;
      _directoryRecheck.add(conversationId);
    }
    _recordInboundSession(
      conversationId,
      observedInboundSession(
        envelope,
        localDeviceId: localDeviceId,
        remoteIdentityPublicKey: provenKey,
      ),
    );
    unawaited(_contents.retryPending(conversationId, messagesFor(conversationId)));
  }

  // A frame from a device the 1:1 session is not bound to means the peer has
  // most likely moved, so the next send asks the directory and follows.
  void _notePeerDevice(CryptoEnvelope envelope) {
    final conversation = conversationById(envelope.conversationId);
    final localDeviceId = _session.deviceId;
    if (conversation != null &&
        localDeviceId != null &&
        comesFromNewPeerDevice(conversation, envelope, localDeviceId: localDeviceId)) {
      _directoryRecheck.add(conversation.id);
    }
  }

  // Records an inbound session on its conversation, so a reply reuses it
  // instead of bootstrapping a second one the sender would never know about.
  // Only 1:1 conversations carry a pairwise session, and one held back until
  // its conversation was listed may turn out to belong to a group.
  void _recordInboundSession(String conversationId, ConversationSessionState state) {
    final conversation = conversationById(conversationId);
    if (conversation == null) {
      _unlistedInboundSessions[conversationId] = state;
      return;
    }
    if (conversation.type != ConversationType.direct) {
      return;
    }
    final provenKey = state.remoteIdentityPublicKey;
    _updateConversation(
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
    if (provenKey.isEmpty) _learnPeerIdentity(conversation).ignore();
  }

  /// Content of [message] for display. Reads stored content; the envelope is
  /// decrypted only if this message has never been opened before.
  Future<DecryptedMessage> decryptMessage(ChatMessage message) => _contents.read(message);

  /// Ids of loaded messages whose decrypted content matches [query]. Reads
  /// stored content only and never decrypts.
  Future<List<String>> searchLoadedMessageIds(
    String conversationId, {
    required String query,
  }) async {
    final messages = messagesFor(conversationId);
    final normalizedQuery = _normalizeSearchQuery(query);
    if (normalizedQuery.isEmpty) {
      return messages.map((message) => message.id).toList();
    }

    final contents = await _contents.storedFor(messages);
    return [
      for (final message in messages)
        if (contents[message.id] case final content?
            when content.status == MessageContentStatus.ok &&
                searchableContentText(content).toLowerCase().contains(normalizedQuery))
          message.id,
    ];
  }

  Future<MessageSearchPage> searchMessageArchive({
    required MessageSearchQuery query,
  }) async {
    final normalizedQuery = _normalizeSearchQuery(query.query);
    if (normalizedQuery.isEmpty) {
      return const MessageSearchPage(items: <MessageSearchResult>[]);
    }

    final cache = _cacheService;
    if (cache == null || _session.deviceId == null) {
      return const MessageSearchPage(items: <MessageSearchResult>[]);
    }

    return cache.searchMessageArchive(
      query: MessageSearchQuery(
        query: normalizedQuery,
        conversationId: query.conversationId,
        senderFilter: query.senderFilter,
        typeFilter: query.typeFilter,
        dateFilter: query.dateFilter,
        limit: query.limit,
        beforeSentAt: query.beforeSentAt,
        beforeMessageId: query.beforeMessageId,
      ),
      currentDeviceId: _session.deviceId!,
    );
  }

  Future<void> _refreshConversationsCore() async {
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      _conversations = [];
      return;
    }

    final response = await _apiClient.getConversations(_session.accessToken!);
    final items = (response['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    // Recorded before this list can drop a conversation together with the
    // only record of whom its session is with.
    await _peerBindings.bindAll({
      for (final preview in _conversations)
        if (preview.type == ConversationType.direct && preview.sessionState != null)
          preview.id: ConversationPeer(userId: preview.recipientBundle.userId, handle: preview.peerHandle),
    });
    final (listed, keptSenderKeys) = await _keepSenderKeys(mergeConversationPreviews(
      _conversations,
      items.map(_conversationFromApi).toList(),
      bound: await _peerBindings.all(),
    ));
    _conversations = listed..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final unlisted = Map.of(_unlistedInboundSessions);
    _unlistedInboundSessions.clear();
    unlisted.forEach(_recordInboundSession);
    await _cacheService?.storeConversations(_conversations);
    for (final conversationId in keptSenderKeys) {
      await _storeNotice(
        conversationId,
        senderKeysKeptNotice(conversationId, conversationMessages: messagesFor(conversationId), now: DateTime.now()),
      );
    }
    await _reconcileExpiringState();
  }

  // Sender Keys mode is pinned the first time a group is listed with it,
  // and a pinned group stays a Sender Keys group whatever a later list
  // says: listed without it, its sends and frames would go through the
  // pairwise engine. Returns the previews and the ids of the groups whose
  // listing tried to turn Sender Keys off.
  Future<(List<ConversationPreview>, List<String>)> _keepSenderKeys(List<ConversationPreview> previews) async {
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

  // A refresh pages the relay's history from the newest message back to the
  // newest one this device already holds, so a backlog longer than one page
  // is fetched, and decrypted oldest first, rather than skipped: frames past
  // it would otherwise wait on skipped keys, of which a chain keeps only so
  // many. It stops after [_historyPagesPerSync] pages; the paging cursor
  // then points at what is left, which loading older history picks up.
  static const _historyPageSize = 50;
  static const _historyPagesPerSync = 10;

  Future<void> _syncConversation(
    String conversationId, {
    bool loadMore = false,
  }) async {
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      _messagesByConversation[conversationId] = [];
      return;
    }

    final pagingState = _pagingStateByConversation[conversationId] ?? const ConversationPagingState();
    final knownUpTo = loadMore ? null : _newestRelayedOrder(conversationId);
    final fetched = <ChatMessage>[];
    var cursor = loadMore ? pagingState.nextCursor : null;
    String? nextCursor;
    for (var page = 0; page < (loadMore ? 1 : _historyPagesPerSync); page++) {
      final response = await _apiClient.getMessages(
        _session.accessToken!,
        conversationId,
        cursor: cursor,
        limit: _historyPageSize,
      );
      final items = (response['items'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>().map(_messageFromApi);
      fetched.addAll(items);
      nextCursor = response['nextCursor'] as String?;
      final reachedKnown = knownUpTo != null && items.any((message) => (message.conversationOrder ?? 0) <= knownUpTo);
      if (nextCursor == null || reachedKnown || knownUpTo == null) break;
      cursor = nextCursor;
    }
    final items = await _contents.withoutRetired(
      fetched.where((message) => !message.isLocalNotice).toList()..sort(compareMessages),
    );

    _mergeServerMessages(conversationId, items);
    unawaited(_contents.ingestAll(items));

    final newPagingState = ConversationPagingState(
      nextCursor: nextCursor,
      hasMoreHistory: nextCursor != null,
      lastSyncedAt: DateTime.now(),
    );
    _pagingStateByConversation[conversationId] = newPagingState;
    await _cacheService?.storePagingState(
      conversationId,
      nextCursor: newPagingState.nextCursor,
      hasMoreHistory: newPagingState.hasMoreHistory,
      lastSyncedAt: newPagingState.lastSyncedAt,
    );

    _syncConversationPreviewFromMessages(conversationId);
    await _persistConversationState(conversationId);
    notifyListeners();
  }

  // The newest relayed message of [conversationId] this device holds; null
  // when it holds none, and a refresh then reads only the newest page.
  int? _newestRelayedOrder(String conversationId) => (_messagesByConversation[conversationId] ?? const <ChatMessage>[])
      .where((message) => !message.isLocalNotice)
      .map((message) => message.conversationOrder)
      .nonNulls
      .fold<int?>(null, (newest, order) => newest == null || order > newest ? order : newest);

  Future<void> _enqueuePendingMessage({
    required ConversationPreview conversation,
    required String clientMessageId,
    required CryptoEnvelope envelope,
    AttachmentUploadDraft? attachmentUploadDraft,
  }) async {
    final createdAt = DateTime.now();
    final pending = PendingMessageRecord(
      clientMessageId: clientMessageId,
      conversationId: conversation.id,
      senderDeviceId: _session.deviceId!,
      recipientUserId: envelope.recipientUserId,
      envelope: envelope,
      createdAt: createdAt,
      state: attachmentUploadDraft == null
          ? MessageDeliveryState.pending
          : MessageDeliveryState.uploading,
      attachmentUploadDraft: attachmentUploadDraft,
    );

    _pendingByClientMessageId[clientMessageId] = pending;
    final optimisticMessage = ChatMessage(
      id: 'local-$clientMessageId',
      clientMessageId: clientMessageId,
      senderDeviceId: _session.deviceId!,
      sentAt: createdAt,
      envelope: envelope,
      deliveryState: pending.state,
      expiresAt: envelope.expiresAt,
      isMine: true,
    );

    _messagesByConversation.putIfAbsent(conversation.id, () => []);
    _messagesByConversation[conversation.id] = mergeMessageCollections(
      _messagesByConversation[conversation.id] ?? const [],
      <ChatMessage>[optimisticMessage],
    );
    if (attachmentUploadDraft != null) {
      _updateAttachmentTransfer(
        clientMessageId,
        phase: AttachmentTransferPhase.staged,
        progress: 0,
        filename: attachmentUploadDraft.filename,
        contentType: attachmentUploadDraft.contentType,
        sizeBytes: attachmentUploadDraft.sizeBytes,
        canRetry: false,
        canCancel: true,
      );
    }
    _syncConversationPreviewFromMessages(conversation.id);
    await _cacheService?.upsertPendingMessage(pending);
    await _persistConversationState(conversation.id);
    notifyListeners();
  }

  Future<void> _drainOutbox({
    String? conversationId,
    bool markFailuresAsRetrying = false,
    bool ignoreRetrySchedule = false,
  }) async {
    if (_disposed || _isDrainingOutbox || !_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }

    _isDrainingOutbox = true;
    try {
      final now = DateTime.now();
      final pendingItems = _pendingByClientMessageId.values
          .where((item) => conversationId == null || item.conversationId == conversationId)
          .where((item) => markFailuresAsRetrying || item.state != MessageDeliveryState.failed)
          .where(
            (item) =>
                ignoreRetrySchedule ||
                item.nextRetryAt == null ||
                !item.nextRetryAt!.isAfter(now),
          )
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      for (final pending in pendingItems) {
        var marked = pending.copyWith(
          retryCount: pending.retryCount + 1,
          lastAttemptAt: now,
          nextRetryAt: null,
          state: pending.attachmentUploadDraft == null
              ? MessageDeliveryState.pending
              : MessageDeliveryState.uploading,
          errorMessage: null,
        );
        _pendingByClientMessageId[pending.clientMessageId] = marked;
        await _cacheService?.upsertPendingMessage(marked);
        _updateLocalMessageState(
          pending.clientMessageId,
          state: marked.state,
          errorMessage: null,
        );
        if (marked.attachmentUploadDraft != null) {
          _updateAttachmentTransfer(
            marked.clientMessageId,
            phase: AttachmentTransferPhase.preparing,
            progress: _progressForDraft(marked.attachmentUploadDraft),
            filename: marked.attachmentUploadDraft?.filename,
            contentType: marked.attachmentUploadDraft?.contentType,
            sizeBytes: marked.attachmentUploadDraft?.sizeBytes,
            canRetry: false,
            canCancel: true,
          );
        }

        try {
          if (marked.attachmentUploadDraft != null) {
            marked = await _preparePendingAttachment(marked);
            _pendingByClientMessageId[marked.clientMessageId] = marked;
            await _cacheService?.upsertPendingMessage(marked);
            _updateLocalMessageState(
              marked.clientMessageId,
              state: MessageDeliveryState.pending,
            );
            _attachmentTransfersByClientMessageId.remove(marked.clientMessageId);
          }

          final groupEpoch = GroupSenderKeyCoordinator.epochOf(marked.envelope);
          final response = await _apiClient.sendMessage(_session.accessToken!, {
            'conversationId': marked.conversationId,
            'clientMessageId': marked.clientMessageId,
            'envelope': _envelopeToJson(marked.envelope),
            if (groupEpoch != null) 'groupEpoch': groupEpoch,
          });
          final serverMessage =
              _messageFromApi(response['message'] as Map<String, dynamic>);
          if (serverMessage.isLocalNotice) throw const FormatException('The relay acknowledged a local notice id.');
          _pendingByClientMessageId.remove(marked.clientMessageId);
          await _cacheService?.removePendingMessage(marked.clientMessageId);
          final content = await _contents.acknowledge(
            clientMessageId: marked.clientMessageId,
            serverMessageId: serverMessage.id,
          );
          _mergeServerMessages(
            marked.conversationId,
            <ChatMessage>[withInnerExpiry(serverMessage, content?.innerExpiresAt)],
          );
          await _persistConversationState(marked.conversationId);
          _attachmentTransfersByClientMessageId.remove(marked.clientMessageId);
        } catch (error) {
          await _handleSecurityException(error);
          // _preparePendingAttachment stores each step it completes (the
          // sealed draft, its ticket). Building on the copy taken before it
          // ran would drop the sealed reference, and the retry would try to
          // re-seal a staging file that was deleted once sealed.
          final latest = _pendingByClientMessageId[marked.clientMessageId] ?? marked;
          final isTransient = shouldRetryAutomatically(error, latest.retryCount);
          final nextRetryAt = isTransient
              ? now.add(retryDelayForAttempt(latest.retryCount))
              : null;
          final failed = latest.copyWith(
            state: isTransient
                ? (latest.attachmentUploadDraft == null
                    ? MessageDeliveryState.pending
                    : MessageDeliveryState.uploading)
                : MessageDeliveryState.failed,
            nextRetryAt: nextRetryAt,
            errorMessage: formatUserFacingError(error),
          );
          _pendingByClientMessageId[marked.clientMessageId] = failed;
          await _cacheService?.upsertPendingMessage(failed);
          _updateLocalMessageState(
            marked.clientMessageId,
            state: failed.state,
            errorMessage: failed.errorMessage,
          );
          if (failed.attachmentUploadDraft != null) {
            _updateAttachmentTransfer(
              failed.clientMessageId,
              phase: extractVeilApiErrorCode(error) == 'attachment_upload_canceled'
                  ? AttachmentTransferPhase.canceled
                  : AttachmentTransferPhase.failed,
              progress: _progressForDraft(failed.attachmentUploadDraft),
              errorMessage: failed.errorMessage,
              filename: failed.attachmentUploadDraft?.filename,
              contentType: failed.attachmentUploadDraft?.contentType,
              sizeBytes: failed.attachmentUploadDraft?.sizeBytes,
              canRetry: true,
              canCancel: false,
            );
          }
          // An identity change is the conversation's issue, not a global one.
          if (error is! IdentityChangedException) _errorMessage = failed.errorMessage;
        }
      }
    } finally {
      _isDrainingOutbox = false;
      notifyListeners();
    }
  }

  Future<void> _hydrateFromCache() async {
    final cache = _cacheService;
    if (cache == null) {
      return;
    }

    await cache.purgeExpiredMessages();
    final (cached, _) = await _keepSenderKeys(await cache.readConversations());
    _conversations = cached;
    _messagesByConversation.clear();
    _pagingStateByConversation.clear();
    _pendingByClientMessageId.clear();
    _attachmentTransfersByClientMessageId.clear();

    for (final conversation in _conversations) {
      // Content this device already retired stays gone, even when a cached
      // copy of its message survived.
      final cachedMessages = await _contents.withoutRetired(await cache.readMessages(conversation.id));
      // Re-applied in case the app stopped before a clamped copy was saved.
      final innerExpiries = await _contents.innerExpiriesFor(cachedMessages);
      _messagesByConversation[conversation.id] = [
        for (final message in cachedMessages)
          withInnerExpiry(
            message.copyWith(isMine: message.senderDeviceId == _session.deviceId),
            innerExpiries[message.id],
          ),
      ];
      // Reactions live only in their encrypted messages; replay the ones
      // already opened and authenticated, as live delivery applies them.
      final contents = await _contents.storedFor(_messagesByConversation[conversation.id]!);
      for (final message in _messagesByConversation[conversation.id]!) {
        if (contents[message.id] case final content?
            when content.kind == MessageKind.reaction && content.status == MessageContentStatus.ok) {
          _applyReactionMessage(message, content);
        }
      }
      _pagingStateByConversation[conversation.id] = await cache.readPagingState(conversation.id);
    }

    final pendingMessages = await cache.readPendingMessages();
    final keepTempPaths = <String>{};
    for (final pending in pendingMessages) {
      _pendingByClientMessageId[pending.clientMessageId] = pending;
      final draft = pending.attachmentUploadDraft;
      if (draft?.tempFilePath case final path?) {
        keepTempPaths.add(path);
      }
      if (draft != null) {
        _updateAttachmentTransfer(
          pending.clientMessageId,
          phase: pending.state == MessageDeliveryState.failed
              ? AttachmentTransferPhase.failed
              : AttachmentTransferPhase.staged,
          progress: _progressForDraft(draft),
          errorMessage: pending.errorMessage,
          filename: draft.filename,
          contentType: draft.contentType,
          sizeBytes: draft.sizeBytes,
          canRetry: pending.state == MessageDeliveryState.failed,
          canCancel: pending.state != MessageDeliveryState.failed,
        );
      }
      final optimisticMessage = ChatMessage(
        id: 'local-${pending.clientMessageId}',
        clientMessageId: pending.clientMessageId,
        senderDeviceId: pending.senderDeviceId,
        sentAt: pending.createdAt,
        envelope: pending.envelope,
        deliveryState: pending.state,
        expiresAt: pending.envelope.expiresAt,
        isMine: pending.senderDeviceId == _session.deviceId,
      );
      _messagesByConversation.putIfAbsent(pending.conversationId, () => []);
      _messagesByConversation[pending.conversationId] = mergeMessageCollections(
        _messagesByConversation[pending.conversationId] ?? const [],
        <ChatMessage>[optimisticMessage],
      );
    }

    await _attachmentTempFileStore?.cleanupOrphanedFiles(keepPaths: keepTempPaths);
    for (final conversationId in _messagesByConversation.keys) {
      unawaited(_refreshLastContent(conversationId));
    }
    await _reconcileExpiringState();
    notifyListeners();
  }

  Future<void> _connectRealtime() async {
    if (_realtimeConnected || !_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }

    _realtimeService.connect(
      baseUrl: VeilConfig.realtimeUrl,
      accessToken: _session.accessToken!,
      onConnectionChanged: (connected) {
        _realtimeConnected = connected;
        if (connected) {
          _clearTransientRelayError();
        } else {
          _noteTransientRelayInterruption();
        }
        notifyListeners();
        if (connected) {
          _scheduleSyncAfterRealtimeHint(refreshConversations: _refreshConversationsOnConnect);
          _refreshConversationsOnConnect = true;
          unawaited(_drainOutbox(ignoreRetrySchedule: true));
        }
      },
      onEvent: (event, payload) async {
        switch (event) {
          case 'message.delivered':
            final data = payload as Map<String, dynamic>;
            _applyReceiptEvent(
              data['messageId'] as String,
              deliveredAt: DateTime.parse(data['deliveredAt'] as String),
            );
            break;
          case 'message.read':
            final data = payload as Map<String, dynamic>;
            _applyReceiptEvent(
              data['messageId'] as String,
              readAt: DateTime.parse(data['readAt'] as String),
            );
            break;
          case 'message.new':
            final data = payload as Map<String, dynamic>;
            final message = _messageFromApi(data);
            if (message.isLocalNotice || (await _contents.withoutRetired(<ChatMessage>[message])).isEmpty) {
              break;
            }
            final conversationId = message.envelope.conversationId;
            _mergeServerMessages(conversationId, <ChatMessage>[message]);
            unawaited(_contents.ingestAll(<ChatMessage>[message]));
            unawaited(_persistConversationState(conversationId));
            notifyListeners();
            if (!message.isMine && conversationId == _activeConversationId) {
              await markRead(message.id);
            } else if (!message.isMine && message.envelope.messageKind != MessageKind.reaction) {
              // A reaction updates a message already seen. Trusting the
              // relay's label costs nothing: it could withhold the message.
              unawaited(_notificationService?.showMessageNotification(
                conversationId: conversationId,
                title: 'VEIL',
                body: 'New encrypted message',
              ));
            }
            _scheduleSyncAfterRealtimeHint(conversationId: conversationId);
            break;
          case 'message.reaction':
            // Deprecated and never emitted (contract C9). Reactions are
            // authenticated only inside the ratchet; a relay event names
            // whatever reactor the server likes, so it is never applied.
            break;
          case 'typing.start':
            final data = payload as Map<String, dynamic>;
            final convId = data['conversationId'] as String;
            final handle = data['handle'] as String? ?? '';
            _typingByConversation[convId] = handle;
            _typingClearTimer?.cancel();
            _typingClearTimer = Timer(const Duration(seconds: 5), () {
              _typingByConversation.remove(convId);
              notifyListeners();
            });
            notifyListeners();
            break;
          case 'typing.stop':
            final data = payload as Map<String, dynamic>;
            _typingByConversation.remove(data['conversationId'] as String);
            notifyListeners();
            break;
          case 'presence.update':
            final data = payload as Map<String, dynamic>;
            final userId = data['userId'] as String;
            final status = data['status'] as String;
            if (status == 'online') {
              _onlineUserIds.add(userId);
            } else {
              _onlineUserIds.remove(userId);
            }
            notifyListeners();
            break;
          case 'conversation.sync':
            final data = payload as Map<String, dynamic>;
            _scheduleSyncAfterRealtimeHint(conversationId: data['conversationId'] as String?);
            break;
          case 'conversation.timer.changed':
            final data = payload as Map<String, dynamic>;
            _applyTimerChanged(
              conversationId: data['conversationId'] as String,
              disappearingTimerSeconds: data['disappearingTimerSeconds'] as int?,
            );
            break;
          case 'group.key.distribution':
            final groupCrypto = _groupCrypto;
            if (groupCrypto == null) break;
            unawaited(groupCrypto.handleKeyDistributionEvent(
              payload as Map<String, dynamic>,
              localUserId: _session.userId ?? '',
              accessToken: _session.accessToken ?? '',
            ));
            break;
          case 'group.epoch.bumped':
            final data = payload as Map<String, dynamic>;
            unawaited(_handleGroupEpochBumped(data));
            break;
          default:
            break;
        }
      },
    );
  }

  // Membership changed: remember the new epoch on the preview, refresh the
  // member list, then let the group engine re-key and redistribute.
  Future<void> _handleGroupEpochBumped(Map<String, dynamic> data) async {
    final conversationId = data['conversationId'] as String? ?? '';
    final epoch = (data['epoch'] as num?)?.toInt();
    if (conversationId.isEmpty || epoch == null) return;
    _conversations = _conversations
        .map((c) => c.id == conversationId ? c.copyWith(groupEpoch: epoch) : c)
        .toList(growable: false);
    notifyListeners();
    try {
      await _refreshConversationsCore();
    } catch (_) {
      // Membership refresh is best-effort; the epoch is already recorded.
    }
    final groupCrypto = _groupCrypto;
    if (groupCrypto == null || !_session.isAuthenticated) return;
    await groupCrypto.handleEpochBumped(
      conversationId: conversationId,
      epoch: epoch,
      reason: data['reason'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      accessToken: _session.accessToken!,
      localUserId: _session.userId ?? '',
      localDeviceId: _session.deviceId ?? '',
    );
  }

  Future<void> _refreshRealtimeAndSync({bool forceReconnect = false}) async {
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }

    if (forceReconnect || !_realtimeService.isConnected || !_realtimeConnected) {
      await _reconnectRealtime(refreshConversations: true);
    }
    _scheduleSyncAfterRealtimeHint(conversationId: _activeConversationId);
    await _drainOutbox(ignoreRetrySchedule: true);
  }

  // [refreshConversations] false resyncs message history after the reconnect
  // without refetching the conversation list.
  Future<void> _reconnectRealtime({required bool refreshConversations}) async {
    _realtimeService.disconnect();
    _realtimeConnected = false;
    _refreshConversationsOnConnect = refreshConversations;
    notifyListeners();
    await _connectRealtime();
  }

  void _scheduleSyncAfterRealtimeHint({
    String? conversationId,
    bool refreshConversations = true,
  }) {
    if (_disposed) {
      return;
    }
    _conversationRefreshQueued |= refreshConversations;
    if (conversationId != null && conversationId.isNotEmpty) {
      _queuedSyncConversationIds.add(conversationId);
    }
    _syncHintDebounce?.cancel();
    _syncHintDebounce = Timer(
      _syncHintDebounceDuration,
      () => unawaited(_flushQueuedSyncHints()),
    );
  }

  Future<void> _flushQueuedSyncHints() async {
    if (_disposed || !_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }
    if (_syncAfterHintInFlight) {
      return;
    }

    _syncAfterHintInFlight = true;
    try {
      if (_conversationRefreshQueued) {
        _conversationRefreshQueued = false;
        await _refreshConversationsCore();
      }
      final queuedConversationIds = Set<String>.from(_queuedSyncConversationIds);
      _queuedSyncConversationIds.clear();
      final conversationsToSync = <String>{
        ..._messagesByConversation.keys,
        ..._pendingByClientMessageId.values.map((item) => item.conversationId),
        ...queuedConversationIds,
      };
      final activeConversationId = _activeConversationId;
      if (activeConversationId != null) {
        conversationsToSync.add(activeConversationId);
      }

      for (final targetConversationId in conversationsToSync) {
        if (_disposed) {
          return;
        }
        await _syncConversation(targetConversationId);
      }
      await _drainOutbox(ignoreRetrySchedule: true);
    } catch (error) {
      await _handleSecurityException(error);
      _errorMessage = formatUserFacingError(error);
      notifyListeners();
    } finally {
      _syncAfterHintInFlight = false;
      if (_queuedSyncConversationIds.isNotEmpty || _conversationRefreshQueued) {
        _scheduleSyncAfterRealtimeHint(refreshConversations: false);
      }
    }
  }

  void _mergeServerMessages(String conversationId, List<ChatMessage> serverMessages) {
    final current = _messagesByConversation[conversationId] ?? const <ChatMessage>[];
    _messagesByConversation[conversationId] =
        _reactions.decorate(conversationId, mergeMessageCollections(current, serverMessages));
    _applyBufferedReceipts(conversationId);
    _syncConversationPreviewFromMessages(conversationId);
  }

  // With read receipts off, a peer's read is shown as delivered only: this
  // device does not tell peers what it read, and does not learn it either.
  void _applyReceiptEvent(
    String messageId, {
    DateTime? deliveredAt,
    DateTime? readAt,
  }) {
    if (!_readReceiptsEnabled() && readAt != null) {
      deliveredAt ??= readAt;
      readAt = null;
    }
    for (final entry in _messagesByConversation.entries) {
      var changed = false;
      final updated = entry.value.map((message) {
        if (message.id != messageId) {
          return message;
        }

        changed = true;
        final mergedDeliveredAt = laterOf(message.deliveredAt, deliveredAt);
        final mergedReadAt = laterOf(message.readAt, readAt);
        return message.copyWith(
          deliveryState: resolveDeliveryState(
            base: message.deliveryState,
            deliveredAt: mergedDeliveredAt,
            readAt: mergedReadAt,
          ),
          deliveredAt: mergedDeliveredAt,
          readAt: mergedReadAt,
        );
      }).toList();

      if (changed) {
        _messagesByConversation[entry.key] = updated;
        unawaited(_persistConversationState(entry.key));
        notifyListeners();
        return;
      }
    }

    final existing = _receiptBacklogByMessageId[messageId];
    _receiptBacklogByMessageId[messageId] = _PendingReceiptUpdate(
      deliveredAt: laterOf(existing?.deliveredAt, deliveredAt),
      readAt: laterOf(existing?.readAt, readAt),
    );
  }

  /// Adds [emoji] to [message], or withdraws it if it is already this
  /// user's reaction. The reaction travels end to end as a message of kind
  /// reaction; the relay sees neither its target nor the emoji.
  Future<void> toggleReaction(ChatMessage message, String emoji) async {
    final myUserId = _session.userId;
    final conversationId = message.envelope.conversationId;
    if (myUserId == null ||
        message.isPending ||
        message.hasFailed ||
        message.isLocalNotice ||
        !ReactionPayload.isAcceptableEmoji(emoji)) {
      return;
    }
    final add = _reactions.emojiOf(conversationId, message.id, myUserId) != emoji;
    final sentAt = DateTime.now();
    // Shown only once queued: a send the trust layer refused, or that failed
    // to encrypt, never reaches the peer.
    final queued = await _sendEnvelope(
      conversationId: conversationId,
      body: ReactionPayload(target: message.id, emoji: emoji, add: add).encode(),
      messageKind: MessageKind.reaction,
    );
    if (!queued) return;
    _recordReaction(
      conversationId,
      target: message.id,
      reactor: myUserId,
      emoji: emoji,
      add: add,
      position: ReactionPosition(conversationOrder: null, sentAt: sentAt),
    );
  }

  // Applies an opened reaction message to its target in the same
  // conversation; the reaction message itself never renders.
  void _applyReactionMessage(ChatMessage message, MessageContentRecord content) {
    final payload = ReactionPayload.tryDecode(content.body);
    final reactor = message.isMine ? _session.userId : _reactorOf(message);
    if (payload == null || reactor == null) return;
    _recordReaction(
      content.conversationId,
      target: payload.target,
      reactor: reactor,
      emoji: payload.emoji,
      add: payload.add,
      position: ReactionPosition(conversationOrder: message.conversationOrder, sentAt: message.sentAt),
    );
  }

  // Group frames name a device, not a user, so in groups a device reacts.
  String? _reactorOf(ChatMessage message) {
    final conversation = conversationById(message.envelope.conversationId);
    if (conversation == null) return null;
    return conversation.type == ConversationType.direct
        ? conversation.recipientBundle.userId
        : 'device:${message.senderDeviceId}';
  }

  void _recordReaction(
    String conversationId, {
    required String target,
    required String reactor,
    required String emoji,
    required bool add,
    required ReactionPosition position,
  }) {
    final changed = _reactions.apply(
      conversationId: conversationId,
      target: target,
      reactor: reactor,
      emoji: emoji,
      add: add,
      position: position,
    );
    final messages = _messagesByConversation[conversationId];
    if (!changed || messages == null) return;
    _messagesByConversation[conversationId] = _reactions.decorate(conversationId, messages);
    notifyListeners();
  }

  void _noteTransientRelayInterruption() {
    if (_pendingByClientMessageId.isEmpty) {
      return;
    }
    _errorMessage = 'Relay connection interrupted. Queued sends will retry after reconnect.';
  }

  void _clearTransientRelayError() {
    if (_errorMessage == 'Relay connection interrupted. Queued sends will retry after reconnect.') {
      _errorMessage = null;
    }
  }

  void _updateLocalMessageState(
    String clientMessageId, {
    required MessageDeliveryState state,
    String? errorMessage,
  }) {
    for (final entry in _messagesByConversation.entries) {
      var changed = false;
      final updated = entry.value.map((message) {
        if (message.clientMessageId != clientMessageId) {
          return message;
        }

        changed = true;
        return message.copyWith(deliveryState: state);
      }).toList();
      if (changed) {
        _messagesByConversation[entry.key] = updated;
        unawaited(_persistConversationState(entry.key));
        if (errorMessage != null) {
          _errorMessage = errorMessage;
        }
        return;
      }
    }
  }

  Future<PendingMessageRecord> _preparePendingAttachment(
    PendingMessageRecord pending,
  ) async {
    var draft = pending.attachmentUploadDraft;
    if (draft == null) {
      return pending;
    }
    final tempStore = _attachmentTempFileStore;
    if (tempStore == null) {
      throw StateError('Local attachment staging is unavailable on this device.');
    }

    final conversation = conversationById(pending.conversationId);
    if (conversation == null) {
      throw StateError('The target conversation is no longer available.');
    }

    if (draft.sealedReference == null) {
      final (sealedDraft, plaintextPath) = await _sealAttachment(draft, conversation, tempStore);
      draft = sealedDraft;
      pending = pending.copyWith(attachmentUploadDraft: draft);
      _pendingByClientMessageId[pending.clientMessageId] = pending;
      await _cacheService?.upsertPendingMessage(pending);
      await tempStore.deleteTempFile(plaintextPath);
    } else if (draft.sealedReference!.attachmentId.isEmpty) {
      // Sealed by an older build under an empty id, which no recipient can
      // open, and the plaintext was deleted once sealed, so it cannot be
      // re-sealed either. Failing it for good lets the user attach it again.
      throw VeilApiException(
        'This attachment was prepared by an older version of VEIL. Attach the file again.',
        code: 'attachment_upload_invalid',
      );
    }

    draft = await _ensureUploadTicket(pending, draft);
    pending = pending.copyWith(attachmentUploadDraft: draft);
    _pendingByClientMessageId[pending.clientMessageId] = pending;
    await _cacheService?.upsertPendingMessage(pending);

    final signal = AttachmentUploadCancellationSignal();
    _activeUploadSignals[pending.clientMessageId] = signal;
    _updateAttachmentTransfer(
      pending.clientMessageId,
      phase: AttachmentTransferPhase.uploading,
      progress: _progressForDraft(draft),
      filename: draft.filename,
      contentType: draft.contentType,
      sizeBytes: draft.sizeBytes,
      canRetry: false,
      canCancel: true,
    );

    try {
      await _apiClient.uploadEncryptedBlobFile(
        uploadUrl: draft.uploadUrl!,
        headers: draft.uploadHeaders,
        file: File(draft.tempFilePath!),
        cancellationSignal: signal,
        onProgress: (sentBytes, totalBytes) {
          final current = _pendingByClientMessageId[pending.clientMessageId];
          final currentDraft = current?.attachmentUploadDraft;
          if (currentDraft == null) {
            return;
          }
          final updatedDraft = currentDraft.copyWith(
            bytesUploaded: sentBytes,
            lastUpdatedAt: DateTime.now(),
          );
          final updatedPending = current!.copyWith(attachmentUploadDraft: updatedDraft);
          _pendingByClientMessageId[pending.clientMessageId] = updatedPending;
          unawaited(_cacheService?.upsertPendingMessage(updatedPending) ?? Future<void>.value());
          _updateAttachmentTransfer(
            pending.clientMessageId,
            phase: AttachmentTransferPhase.uploading,
            progress: totalBytes == 0 ? 0 : sentBytes / totalBytes,
            filename: updatedDraft.filename,
            contentType: updatedDraft.contentType,
            sizeBytes: updatedDraft.sizeBytes,
            canRetry: false,
            canCancel: true,
          );
          notifyListeners();
        },
      );
    } catch (error) {
      _activeUploadSignals.remove(pending.clientMessageId);
      draft = await _markAttachmentTicketFailed(draft);
      pending = pending.copyWith(attachmentUploadDraft: draft);
      _pendingByClientMessageId[pending.clientMessageId] = pending;
      await _cacheService?.upsertPendingMessage(pending);
      rethrow;
    }

    await _apiClient.completeUpload(_session.accessToken!, {
      'attachmentId': draft.attachmentId,
      'uploadStatus': 'uploaded',
    });
    _activeUploadSignals.remove(pending.clientMessageId);
    _updateAttachmentTransfer(
      pending.clientMessageId,
      phase: AttachmentTransferPhase.finalizing,
      progress: 1,
      filename: draft.filename,
      contentType: draft.contentType,
      sizeBytes: draft.sizeBytes,
      canRetry: false,
      canCancel: false,
    );

    final attachment = draft.sealedReference!;
    await _contents.storeOutbound(
      conversationId: conversation.id,
      clientMessageId: pending.clientMessageId,
      body: 'Encrypted attachment',
      kind: MessageKind.file,
      attachment: attachment,
      expiresAt: pending.envelope.expiresAt,
    );
    final updatedEnvelope = await _encryptForConversation(
      conversation: conversation,
      senderDeviceId: pending.senderDeviceId,
      body: 'Encrypted attachment',
      messageKind: MessageKind.file,
      expiresAt: pending.envelope.expiresAt,
      attachment: attachment,
    );

    await tempStore.deleteTempFile(draft.tempFilePath);
    return pending.copyWith(
      envelope: updatedEnvelope,
      attachmentUploadDraft: null,
      state: MessageDeliveryState.pending,
    );
  }

  // Encrypts the staged file and swaps it for the ciphertext, which is the
  // only thing ever uploaded. Protocol v2 binds the attachment id into the
  // blob's AAD, so the id must exist before sealing, while the upload ticket
  // must name the ciphertext's hash: the client proposes a random id here and
  // tickets it later. The reference stays on the draft exactly as sealed, so
  // a retry after a restart re-tickets the same id for the same bytes. Its
  // storage key stays empty: that is a relay detail, and recipients download
  // by attachment id.
  Future<(AttachmentUploadDraft, String)> _sealAttachment(
    AttachmentUploadDraft draft,
    ConversationPreview conversation,
    AttachmentTempFileStore tempStore,
  ) async {
    final staged = await tempStore.createOpaqueBlob(
      filename: draft.filename,
      sizeBytes: draft.sizeBytes,
      existingPath: draft.tempFilePath,
    );
    final recipientBundle = conversation.type == ConversationType.group
        ? conversation.recipientBundle
        : await _bundleForSend(conversation);
    final cipher = await _cryptoEngine.encryptAttachment(
      attachmentId: randomUuidV4(),
      storageKey: '',
      contentType: draft.contentType,
      plaintext: await File(staged.path).readAsBytes(),
      recipientBundle: recipientBundle,
    );
    final sealedFile = File('${staged.path}.sealed');
    await sealedFile.writeAsBytes(cipher.ciphertext, flush: true);
    final sealed = await tempStore.createOpaqueBlob(
      filename: draft.filename,
      sizeBytes: cipher.ciphertext.length,
      existingPath: sealedFile.path,
    );
    final sealedDraft = draft.copyWith(
      tempFilePath: sealed.path,
      sizeBytes: sealed.sizeBytes,
      sha256: sealed.sha256,
      sealedReference: cipher.reference,
      lastUpdatedAt: DateTime.now(),
    );
    return (sealedDraft, staged.path);
  }

  Future<AttachmentUploadDraft> _ensureUploadTicket(
    PendingMessageRecord pending,
    AttachmentUploadDraft draft,
  ) async {
    if (draft.hasUploadTicket && !draft.uploadTicketExpired) {
      return draft;
    }
    final resetDraft = await _markAttachmentTicketFailed(draft, deleteRemoteObject: draft.hasUploadTicket);
    final sealedId = resetDraft.sealedReference!.attachmentId;
    final upload = await _apiClient.createUploadTicket(_session.accessToken!, {
      'attachmentId': sealedId,
      // The relay only ever holds ciphertext. The real type travels in the
      // sealed reference ('ct') alone, as the web client does it.
      'contentType': 'application/octet-stream',
      'sizeBytes': resetDraft.sizeBytes,
      'sha256': resetDraft.sha256,
    });
    // A ticket for any other id would carry a blob no recipient can open.
    if (upload['attachmentId'] != sealedId) {
      throw StateError('The relay ticketed a different attachment id than the one sealed.');
    }
    final uploadPayload = upload['upload'] as Map<String, dynamic>;
    return resetDraft.copyWith(
      attachmentId: sealedId,
      storageKey: uploadPayload['storageKey'] as String,
      uploadUrl: uploadPayload['uploadUrl'] as String,
      uploadHeaders: (uploadPayload['headers'] as Map<String, dynamic>? ?? const <String, dynamic>{})
          .map((key, value) => MapEntry(key, value.toString())),
      uploadExpiresAt: DateTime.parse(uploadPayload['expiresAt'] as String),
      bytesUploaded: 0,
      lastUpdatedAt: DateTime.now(),
    );
  }

  Future<AttachmentUploadDraft> _markAttachmentTicketFailed(
    AttachmentUploadDraft draft, {
    bool deleteRemoteObject = true,
  }) async {
    if (!deleteRemoteObject || draft.attachmentId == null || !_session.isAuthenticated || !VeilConfig.hasApi) {
      return draft.copyWith(
        attachmentId: null,
        storageKey: null,
        uploadUrl: null,
        uploadHeaders: const <String, String>{},
        uploadExpiresAt: null,
        bytesUploaded: 0,
        lastUpdatedAt: DateTime.now(),
      );
    }

    try {
      await _apiClient.completeUpload(_session.accessToken!, {
        'attachmentId': draft.attachmentId,
        'uploadStatus': 'failed',
      });
    } catch (_) {
      // Cleanup is best-effort. A later backend sweep still marks stale pending uploads failed.
    }
    return draft.copyWith(
      attachmentId: null,
      storageKey: null,
      uploadUrl: null,
      uploadHeaders: const <String, String>{},
      uploadExpiresAt: null,
      bytesUploaded: 0,
      lastUpdatedAt: DateTime.now(),
    );
  }

  void _applyBufferedReceipts(String conversationId) {
    final messages = _messagesByConversation[conversationId];
    if (messages == null || messages.isEmpty || _receiptBacklogByMessageId.isEmpty) {
      return;
    }

    var changed = false;
    final updated = messages.map((message) {
      final backlog = _receiptBacklogByMessageId[message.id];
      if (backlog == null) {
        return message;
      }

      changed = true;
      _receiptBacklogByMessageId.remove(message.id);
      final deliveredAt = laterOf(message.deliveredAt, backlog.deliveredAt);
      final readAt = laterOf(message.readAt, backlog.readAt);
      return message.copyWith(
        deliveredAt: deliveredAt,
        readAt: readAt,
        deliveryState: resolveDeliveryState(
          base: message.deliveryState,
          deliveredAt: deliveredAt,
          readAt: readAt,
        ),
      );
    }).toList();

    if (changed) {
      _messagesByConversation[conversationId] = updated;
      unawaited(_persistConversationState(conversationId));
    }
  }

  Future<void> _persistConversationState(String conversationId) async {
    final cache = _cacheService;
    // The cache refuses messages without their conversation; those of one the
    // list has not caught up with yet are saved by the sync that lists it.
    if (cache == null || conversationById(conversationId) == null) {
      return;
    }

    await cache.storeConversations(_conversations);
    await cache.storeMessages(conversationId, _messagesByConversation[conversationId] ?? const []);
  }

  Future<void> _reconcileExpiringState() async {
    final now = DateTime.now();
    var conversationsChanged = false;
    final changedMessageConversations = <String>{};
    final expiredMessages = <ChatMessage>[];

    for (final entry in _messagesByConversation.entries) {
      final beforeLength = entry.value.length;
      final retainedMessages = entry.value.where((message) {
        final expired = _isExpired(message.expiresAt, now);
        if (expired) {
          expiredMessages.add(message);
        }
        return !expired;
      }).toList(growable: true);
      if (retainedMessages.length != beforeLength) {
        _messagesByConversation[entry.key] = retainedMessages;
        changedMessageConversations.add(entry.key);
        _syncConversationPreviewFromMessages(entry.key);
        conversationsChanged = true;
      }
    }

    final updatedConversations = <ConversationPreview>[];
    for (final conversation in _conversations) {
      final loadedMessages = _messagesByConversation[conversation.id];
      if (loadedMessages == null && _isExpired(conversation.lastEnvelope?.expiresAt, now)) {
        updatedConversations.add(conversation.copyWith(lastEnvelope: null));
        conversationsChanged = true;
        continue;
      }

      updatedConversations.add(conversation);
    }

    if (conversationsChanged) {
      _conversations = updatedConversations..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }

    if (!conversationsChanged && changedMessageConversations.isEmpty) {
      return;
    }

    if (expiredMessages.isNotEmpty) {
      await _contents.deleteExpired(now, expiredMessages);
    }
    final cache = _cacheService;
    if (cache != null) {
      await cache.purgeExpiredMessages();
      for (final conversationId in changedMessageConversations.where(
        (id) => conversationById(id) != null,
      )) {
        await cache.storeMessages(
          conversationId,
          _messagesByConversation[conversationId] ?? const [],
        );
      }
      await cache.storeConversations(_conversations);
    }

    notifyListeners();
  }

  bool _isExpired(DateTime? expiresAt, DateTime now) {
    if (expiresAt == null) {
      return false;
    }

    return !expiresAt.isAfter(now);
  }

  void _syncConversationPreviewFromMessages(String conversationId) {
    final messages = _messagesByConversation[conversationId];
    if (messages == null) {
      return;
    }

    final conversationIndex = _conversations.indexWhere((item) => item.id == conversationId);
    if (conversationIndex == -1) {
      return;
    }

    final latestMessage = messages.isEmpty ? null : messages.last;
    final current = _conversations[conversationIndex];
    _conversations[conversationIndex] = current.copyWith(
      lastEnvelope: latestMessage?.envelope,
      updatedAt: latestMessage?.sentAt ?? current.updatedAt,
    );
    _conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    unawaited(_refreshLastContent(conversationId));
  }

  Future<void> _refreshLastContent(String conversationId) async {
    final latest = _messagesByConversation[conversationId]?.lastOrNull;
    final content = latest == null ? null : (await _contents.storedFor([latest]))[latest.id];
    if (_messagesByConversation[conversationId]?.lastOrNull?.id != latest?.id) {
      return;
    }
    final opened = content?.status == MessageContentStatus.ok ? content : null;
    final previous = _lastContents[conversationId];
    if (previous?.kind == opened?.kind && previous?.body == opened?.body) {
      return;
    }
    opened == null ? _lastContents.remove(conversationId) : _lastContents[conversationId] = opened;
    notifyListeners();
  }

  // Runs whenever content becomes bound to a relayed message (the ack path
  // applies the same clamp itself). Local expiry is the earlier of the
  // server's outer expiresAt and the authenticated inner one, so a server
  // that strips or extends the timer cannot keep the message around.
  void _onContentStored(ChatMessage message, MessageContentRecord record) {
    if (record.kind == MessageKind.reaction && record.status == MessageContentStatus.ok) {
      _applyReactionMessage(message, record);
    }
    final conversationId = record.conversationId;
    final messages = _messagesByConversation[conversationId];
    final index = messages?.indexWhere((item) => item.id == message.id) ?? -1;
    if (messages != null && index != -1) {
      final current = messages[index];
      final clamped = withInnerExpiry(current, record.innerExpiresAt);
      if (!identical(clamped, current)) {
        _messagesByConversation[conversationId] = List<ChatMessage>.of(messages)
          ..[index] = clamped;
        unawaited(_persistConversationState(conversationId));
      }
      if (index == messages.length - 1) {
        unawaited(_refreshLastContent(conversationId));
      }
    }
    notifyListeners();
  }

  /// The key [handle]'s active device currently publishes, as the directory
  /// serves it. Read-only: it claims no prekey and changes no session or pin.
  Future<KeyBundle> fetchPeerKeyBundle(String handle) async => (await _activeDeviceOf(handle, KeyClaim.none)).bundle;

  // Steady-state sends on an established session use the stored bundle and
  // never touch the directory, as long as the pins accept it as they stand
  // now: the user may since have verified another device of the contact,
  // and a conversation that lost what it knew names no identity at all.
  // Anything else asks the directory, whose answer must pass the pins
  // before anything is sealed to it. A pending recheck, and a stored bundle
  // the pins stopped accepting, ask it fresh rather than repeat a cached
  // answer; the recheck is only cleared once that answer has been applied.
  // A session the engine reports [sessionMoved] reaches nobody this
  // conversation chose, so it is replaced.
  //
  // So a pending identity change holds back only what would need it: a
  // steady-state send goes ahead while the pins still accept the identity
  // its session encrypts to, otherwise a single refused frame, which the
  // relay can forge at will, would stop the conversation.
  Future<KeyBundle> _bundleForSend(ConversationPreview conversation, {bool sessionMoved = false}) async {
    var recheck = sessionMoved || _directoryRecheck.contains(conversation.id);
    if (!recheck && _sessionBootstrapper.hasSessionFor(conversation.id)) {
      final bundle = conversation.recipientBundle;
      if (await _trust.trusts(bundle.userId, bundle.deviceId, bundle.identityPublicKey)) return bundle;
      recheck = true;
    }
    final handle = conversation.peerHandle;
    final served = (recheck ? null : _peerBundles.fresh(handle)) ?? await _fetchPeerBundle(handle, KeyClaim.active);
    final bundle = await _applyDirectoryAnswer(conversation.id, served, mustBootstrap: sessionMoved);
    _directoryRecheck.remove(conversation.id);
    return bundle;
  }

  // Best effort, once per inbound session whose handshake identity this
  // device did not see (one the engine already held when the conversation
  // first recorded it): gives the responder its peer's identity key for
  // safety numbers and later checks. Never bootstraps, so it cannot replace
  // the session the peer just opened, and claims no prekey it would not use.
  Future<void> _learnPeerIdentity(ConversationPreview conversation) async {
    final handle = conversation.peerHandle;
    final served = _peerBundles.fresh(handle) ?? await _fetchPeerBundle(handle, KeyClaim.none);
    await _applyDirectoryAnswer(conversation.id, served, mayBootstrap: false);
  }

  Future<DirectoryDevice> _fetchPeerBundle(String handle, KeyClaim claim) async {
    final active = await _activeDeviceOf(handle, claim);
    _peerBundles.remember(handle, active);
    return active;
  }

  Future<DirectoryDevice> _activeDeviceOf(String handle, KeyClaim claim) async {
    final entry = await _keys.lookup(handle, accessToken: _session.accessToken, claim: claim);
    return entry.activeDevice ?? (throw StateError('The directory lists no active device for @$handle.'));
  }

  // Fits a direct conversation to a directory answer: a bootstrap only when
  // no usable session exists, otherwise the session is kept (see
  // keepSession). Nothing is adopted or bootstrapped to before the identity
  // pins accept it. Returns the bundle the conversation now holds.
  Future<KeyBundle> _applyDirectoryAnswer(
    String conversationId,
    DirectoryDevice served, {
    bool mayBootstrap = true,
    bool mustBootstrap = false,
  }) async {
    final conversation = conversationById(conversationId);
    final bundle = served.bundle;
    if (conversation == null || !_session.isAuthenticated) {
      return bundle;
    }
    final peerUserId = conversation.recipientBundle.userId;
    if (bundle.userId != peerUserId) {
      throw StateError('The directory answered @${conversation.peerHandle} with another user.');
    }
    await _trust.require(conversationId, peerUserId, bundle.deviceId, bundle.identityPublicKey);
    final action = mustBootstrap
        ? SessionAction.bootstrap
        : decideSession(
            engineHasSession: _sessionBootstrapper.hasSessionFor(conversationId),
            session: conversation.sessionState,
            localDeviceId: _session.deviceId!,
            bundle: bundle,
          );
    if (action == SessionAction.reuse) {
      _updateConversation(conversationId, (preview) => keepSession(preview, bundle));
    } else if (mayBootstrap) {
      final material = await _sessionBootstrapper.bootstrapSession(
        SessionBootstrapRequest(
          conversationId: conversationId,
          localDeviceId: _session.deviceId!,
          localUserId: _session.userId!,
          remoteUserId: bundle.userId,
          remoteDeviceId: bundle.deviceId,
          remoteIdentityPublicKey: bundle.identityPublicKey,
          remoteSignedPrekeyBundle: bundle.signedPrekeyBundle,
          remoteOneTimePrekey: served.oneTimePrekey,
        ),
      );
      _peerBundles.spendOneTimePrekey(conversation.peerHandle);
      final sessionState = sessionStateFromMaterial(
        material,
        remoteIdentityPublicKey: bundle.identityPublicKey,
      );
      _updateConversation(
        conversationId,
        (preview) => preview.copyWith(recipientBundle: bundle, sessionState: sessionState),
      );
    }
    return conversationById(conversationId)?.recipientBundle ?? bundle;
  }

  void _updateConversation(
    String conversationId,
    ConversationPreview Function(ConversationPreview preview) update,
  ) {
    final index = _conversations.indexWhere((item) => item.id == conversationId);
    if (index == -1) {
      return;
    }
    _conversations = List<ConversationPreview>.of(_conversations)
      ..[index] = update(_conversations[index]);
    unawaited(_cacheService?.storeConversations(_conversations));
    notifyListeners();
  }

  ConversationPreview _conversationFromApi(dynamic raw) {
    final conversation = raw as Map<String, dynamic>;
    final rawMembers =
        (conversation['members'] as List<dynamic>).cast<Map<String, dynamic>>();
    final peer = rawMembers.firstWhere(
      (member) => member['handle'] != _session.handle,
      orElse: () => rawMembers.first,
    );
    final type = _conversationTypeFromApi(conversation['type']);
    // Only carry the full member list for groups — direct chats use the
    // peerHandle/recipientBundle fields and would just duplicate state.
    final members = type == ConversationType.group
        ? rawMembers
            .map((m) => GroupMember(
                  userId: m['userId'] as String,
                  handle: m['handle'] as String,
                  displayName: m['displayName'] as String?,
                ))
            .toList(growable: false)
        : const <GroupMember>[];
    return ConversationPreview(
      id: conversation['id'] as String,
      peerHandle: peer['handle'] as String,
      peerDisplayName: peer['displayName'] as String?,
      recipientBundle: KeyBundle(
        userId: peer['userId'] as String,
        deviceId: '',
        handle: peer['handle'] as String,
        identityPublicKey: '',
        signedPrekeyBundle: '',
      ),
      lastEnvelope: conversation['lastMessage'] == null
          ? null
          : _envelopeFromApi(conversation['lastMessage'] as Map<String, dynamic>),
      updatedAt: conversation['lastMessage'] == null
          ? DateTime.parse(conversation['createdAt'] as String)
          : DateTime.parse(
              (conversation['lastMessage'] as Map<String, dynamic>)['serverReceivedAt'] as String,
            ),
      sessionState: null,
      type: type,
      members: members,
      disappearingTimerSeconds: conversation['disappearingTimerSeconds'] as int?,
      useSenderKeys: type == ConversationType.group &&
          (conversation['useSenderKeys'] as bool? ?? false),
      groupEpoch: type == ConversationType.group
          ? (conversation['currentEpoch'] as num?)?.toInt()
          : null,
    );
  }

  ConversationType _conversationTypeFromApi(Object? raw) {
    switch (raw) {
      case 'group':
        return ConversationType.group;
      case 'channel':
        return ConversationType.channel;
      default:
        return ConversationType.direct;
    }
  }

  ChatMessage _messageFromApi(Map<String, dynamic> raw) {
    final deliveredAt = raw['deliveredAt'] == null
        ? null
        : DateTime.parse(raw['deliveredAt'] as String);
    final readAt = raw['readAt'] == null ? null : DateTime.parse(raw['readAt'] as String);
    final messageId = raw['id'] as String;
    final sentAt = DateTime.parse(raw['serverReceivedAt'] as String);
    return ChatMessage(
      id: messageId,
      clientMessageId: raw['clientMessageId'] as String?,
      senderDeviceId: raw['senderDeviceId'] as String,
      sentAt: sentAt,
      envelope: _envelopeFromApi(raw),
      conversationOrder: raw['conversationOrder'] as int?,
      deliveryState: readAt != null
          ? MessageDeliveryState.read
          : deliveredAt != null
              ? MessageDeliveryState.delivered
              : MessageDeliveryState.sent,
      deliveredAt: deliveredAt,
      readAt: readAt,
      expiresAt: raw['expiresAt'] == null ? null : DateTime.parse(raw['expiresAt'] as String),
      isMine: raw['senderDeviceId'] == _session.deviceId,
    );
  }

  CryptoEnvelope _envelopeFromApi(Map<String, dynamic> raw) {
    return _envelopeCodec.decodeApiEnvelope(raw);
  }

  Map<String, dynamic> _envelopeToJson(CryptoEnvelope envelope) {
    return _envelopeCodec.encodeApiEnvelope(envelope);
  }

  String _nextClientMessageId() {
    final entropy = _random.nextInt(1 << 32).toRadixString(36);
    return 'msg-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-$entropy';
  }

  Future<AttachmentTempBlob> _stageAttachmentBlob({
    required String filename,
    int sizeBytes = 2048,
  }) async {
    final tempStore = _attachmentTempFileStore;
    if (tempStore == null) {
      throw StateError('Local attachment staging is unavailable on this device.');
    }
    return tempStore.createOpaqueBlob(
      filename: filename,
      sizeBytes: sizeBytes,
    );
  }

  double _progressForDraft(AttachmentUploadDraft? draft) {
    if (draft == null || draft.sizeBytes <= 0) {
      return 0;
    }
    return (draft.bytesUploaded / draft.sizeBytes).clamp(0, 1).toDouble();
  }

  void _updateAttachmentTransfer(
    String clientMessageId, {
    required AttachmentTransferPhase phase,
    required double progress,
    String? errorMessage,
    String? filename,
    String? contentType,
    int? sizeBytes,
    required bool canRetry,
    required bool canCancel,
  }) {
    _attachmentTransfersByClientMessageId[clientMessageId] = AttachmentTransferSnapshot(
      clientMessageId: clientMessageId,
      phase: phase,
      progress: progress.clamp(0, 1).toDouble(),
      errorMessage: errorMessage,
      filename: filename,
      contentType: contentType,
      sizeBytes: sizeBytes,
      canRetry: canRetry,
      canCancel: canCancel,
    );
  }

  String _guessContentType(String filename) {
    final normalized = filename.toLowerCase();
    if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (normalized.endsWith('.png')) {
      return 'image/png';
    }
    if (normalized.endsWith('.webp')) {
      return 'image/webp';
    }
    if (normalized.endsWith('.pdf')) {
      return 'application/pdf';
    }
    return 'application/octet-stream';
  }

  String _normalizeSearchQuery(String value) {
    return value.trim().toLowerCase();
  }

  Future<void> _run(Future<void> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
    } on IdentityChangedException {
      // Shown in its conversation (pendingIdentityChangeFor), not globally.
    } catch (error) {
      await _handleSecurityException(error);
      _errorMessage = formatUserFacingError(error);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _expirationTicker?.cancel();
    _retryTicker?.cancel();
    _syncHintDebounce?.cancel();
    _typingClearTimer?.cancel();
    _localTypingDebounce?.cancel();
    for (final signal in _activeUploadSignals.values) {
      signal.cancel();
    }
    _realtimeService.disconnect();
    unawaited(_trustEvents.cancel());
    _disposed = true;
    super.dispose();
  }

  // Decrypts, uploads and syncs finish asynchronously and may land after the
  // owning provider has disposed this controller.
  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  Future<void> _handleSecurityException(Object error) async {
    if (_onSecurityException == null) {
      return;
    }
    await _onSecurityException(error);
  }
}

class _PendingReceiptUpdate {
  const _PendingReceiptUpdate({
    this.deliveredAt,
    this.readAt,
  });

  final DateTime? deliveredAt;
  final DateTime? readAt;
}

enum AttachmentTransferPhase {
  staged,
  preparing,
  uploading,
  finalizing,
  failed,
  canceled,
}

class AttachmentTransferSnapshot {
  const AttachmentTransferSnapshot({
    required this.clientMessageId,
    required this.phase,
    required this.progress,
    this.errorMessage,
    this.filename,
    this.contentType,
    this.sizeBytes,
    required this.canRetry,
    required this.canCancel,
  });

  final String clientMessageId;
  final AttachmentTransferPhase phase;
  final double progress;
  final String? errorMessage;
  final String? filename;
  final String? contentType;
  final int? sizeBytes;
  final bool canRetry;
  final bool canCancel;
}
