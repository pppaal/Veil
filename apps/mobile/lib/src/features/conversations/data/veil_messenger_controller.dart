import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../app/app_state.dart';
import '../../../core/config/veil_config.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/network/veil_api_client.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../../core/storage/conversation_cache_service.dart';
import '../../attachments/data/attachment_temp_file_store.dart';
import 'conversation_models.dart';

class VeilMessengerController extends ChangeNotifier {
  static const _maxAutomaticRetryAttempts = 5;
  static const _retrySweepInterval = Duration(seconds: 3);
  static const _syncHintDebounceDuration = Duration(milliseconds: 180);
  static const _maxDecryptedCacheEntries = 600;
  static const _maxSearchBodyEntries = 1200;

  VeilMessengerController({
    required VeilApiClient apiClient,
    required MessageCryptoEngine cryptoEngine,
    required KeyBundleCodec keyBundleCodec,
    required CryptoEnvelopeCodec envelopeCodec,
    required ConversationSessionBootstrapper sessionBootstrapper,
    required RealtimeService realtimeService,
    required ConversationCacheService? cacheService,
    AttachmentTempFileStore? attachmentTempFileStore,
    Future<void> Function(Object error)? onSecurityException,
  })  : _apiClient = apiClient,
        _cryptoEngine = cryptoEngine,
        _keyBundleCodec = keyBundleCodec,
        _envelopeCodec = envelopeCodec,
        _sessionBootstrapper = sessionBootstrapper,
        _realtimeService = realtimeService,
        _cacheService = cacheService,
        _attachmentTempFileStore = attachmentTempFileStore,
        _onSecurityException = onSecurityException {
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
  final KeyBundleCodec _keyBundleCodec;
  final CryptoEnvelopeCodec _envelopeCodec;
  final ConversationSessionBootstrapper _sessionBootstrapper;
  final RealtimeService _realtimeService;
  final ConversationCacheService? _cacheService;
  final AttachmentTempFileStore? _attachmentTempFileStore;
  final Future<void> Function(Object error)? _onSecurityException;
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
  final LinkedHashMap<String, Future<DecryptedMessage>> _decryptedMessageCache =
      LinkedHashMap<String, Future<DecryptedMessage>>();
  final LinkedHashMap<String, String> _searchableBodyByMessageKey =
      LinkedHashMap<String, String>();
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
    final sessionChanged =
        session.accessToken != _session.accessToken || session.handle != _session.handle;
    _session = session;

    if (!sessionChanged) {
      return;
    }

    _realtimeService.disconnect();
    _realtimeConnected = false;

    if (!_session.isAuthenticated) {
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
      _decryptedMessageCache.clear();
      _searchableBodyByMessageKey.clear();
      _activeConversationId = null;
      _transferSessionId = null;
      _transferToken = null;
      _transferStatus = null;
      _transferExpiresAt = null;
      notifyListeners();
      return;
    }

    await _hydrateFromCache();
    await _refreshConversationsCore();
    await _connectRealtime();
    unawaited(_drainOutbox());
  }

  void setActiveConversation(String conversationId) {
    _activeConversationId = conversationId;
  }

  Future<void> handleAppResumed() async {
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }

    await _refreshRealtimeAndSync(forceReconnect: true);
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
      });
      await _refreshConversationsCore();
    });
  }

  void notifyTyping(String conversationId) {
    if (!_realtimeConnected) return;
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

  Future<void> _sendEnvelope({
    required String conversationId,
    required String body,
    required MessageKind messageKind,
    Duration? disappearAfter,
    AttachmentReference? attachment,
  }) async {
    await _run(() async {
      if (!_session.isAuthenticated || !VeilConfig.hasApi) {
        throw StateError('Authenticated API session required.');
      }

      final conversation =
          _conversations.firstWhere((item) => item.id == conversationId);
      final bundle = conversation.type == ConversationType.group
          ? conversation.recipientBundle
          : await _fetchPeerBundle(conversation.peerHandle);
      final recipientUserId = conversation.type == ConversationType.group
          ? ''
          : bundle.userId;
      final clientMessageId = _nextClientMessageId();
      final envelope = await _cryptoEngine.encryptMessage(
        conversationId: conversationId,
        senderDeviceId: _session.deviceId!,
        recipientUserId: recipientUserId,
        body: body,
        messageKind: messageKind,
        recipientBundle: bundle,
        expiresAt:
            disappearAfter == null ? null : DateTime.now().add(disappearAfter),
        attachment: attachment,
      );

      await _enqueuePendingMessage(
        conversation: conversation,
        clientMessageId: clientMessageId,
        envelope: envelope,
      );
      unawaited(_drainOutbox(conversationId: conversationId));
    });
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
      final recipientUserId = conversation.type == ConversationType.group
          ? ''
          : conversation.recipientBundle.userId;
      final envelope = await _cryptoEngine.encryptMessage(
        conversationId: conversationId,
        senderDeviceId: _session.deviceId!,
        recipientUserId: recipientUserId,
        body: 'Encrypted attachment',
        messageKind: MessageKind.file,
        recipientBundle: conversation.recipientBundle,
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
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }

    try {
      await _apiClient.markRead(_session.accessToken!, messageId);
      _applyReceiptEvent(messageId, readAt: DateTime.now());
    } catch (_) {
      // Server resync reconciles later.
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

  Future<DecryptedMessage> decryptEnvelope(CryptoEnvelope envelope) {
    return _cryptoEngine.decryptMessage(envelope);
  }

  Future<DecryptedMessage> decryptMessage(ChatMessage message) {
    final cacheKey = _messageCacheKey(message);
    final existing = _decryptedMessageCache.remove(cacheKey);
    if (existing != null) {
      _decryptedMessageCache[cacheKey] = existing;
      return existing;
    }

    final future = () async {
      final decrypted = await _cryptoEngine.decryptMessage(message.envelope);
      final searchableBody = _searchableMessageBody(decrypted);
      _rememberSearchableBody(cacheKey, searchableBody);
      _setMessageSearchableBody(
        message.envelope.conversationId,
        message.id,
        searchableBody,
      );
      await _cacheService?.indexMessageBody(
        conversationId: message.envelope.conversationId,
        messageId: message.id,
        searchableBody: searchableBody,
      );
      return decrypted;
    }();
    _decryptedMessageCache[cacheKey] = future;
    _trimMessageCaches();
    return future;
  }

  Future<List<String>> searchLoadedMessageIds(
    String conversationId, {
    required String query,
  }) async {
    final normalizedQuery = _normalizeSearchQuery(query);
    if (normalizedQuery.isEmpty) {
      return messagesFor(conversationId).map((message) => message.id).toList();
    }

    final matchedIds = <String>{};
    for (final message in messagesFor(conversationId)) {
      final cacheKey = _messageCacheKey(message);
      final searchableBody = _searchableBodyByMessageKey[cacheKey] ??
          _searchableMessageBody(await decryptMessage(message));
      if (searchableBody.contains(normalizedQuery)) {
        matchedIds.add(message.id);
      }
    }

    final cachedMatches = await _cacheService?.searchCachedMessageIds(
          conversationId: conversationId,
          query: normalizedQuery,
        ) ??
        const <String>[];
    matchedIds.addAll(cachedMatches);
    return matchedIds.toList(growable: false);
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
    _conversations = response.map(_conversationFromApi).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _cacheService?.storeConversations(_conversations);
    await _reconcileExpiringState();
  }

  Future<void> _syncConversation(
    String conversationId, {
    bool loadMore = false,
  }) async {
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      _messagesByConversation[conversationId] = [];
      return;
    }

    final pagingState = _pagingStateByConversation[conversationId] ?? const ConversationPagingState();
    final response = await _apiClient.getMessages(
      _session.accessToken!,
      conversationId,
      cursor: loadMore ? pagingState.nextCursor : null,
      limit: 50,
    );
    final items = (response['items'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(_messageFromApi)
        .toList();

    _mergeServerMessages(conversationId, items);

    final nextCursor = response['nextCursor'] as String?;
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
    _messagesByConversation[conversation.id] = _mergeMessageCollections(
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
    if (_isDrainingOutbox || !_session.isAuthenticated || !VeilConfig.hasApi) {
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

          final response = await _apiClient.sendMessage(_session.accessToken!, {
            'conversationId': marked.conversationId,
            'clientMessageId': marked.clientMessageId,
            'envelope': _envelopeToJson(marked.envelope),
          });
          final serverMessage =
              _messageFromApi(response['message'] as Map<String, dynamic>);
          _pendingByClientMessageId.remove(marked.clientMessageId);
          await _cacheService?.removePendingMessage(marked.clientMessageId);
          _mergeServerMessages(marked.conversationId, <ChatMessage>[serverMessage]);
          await _persistConversationState(marked.conversationId);
          _attachmentTransfersByClientMessageId.remove(marked.clientMessageId);
        } catch (error) {
          await _handleSecurityException(error);
          final isTransient = _shouldRetryAutomatically(error, marked.retryCount);
          final nextRetryAt = isTransient
              ? now.add(_retryDelayForAttempt(marked.retryCount))
              : null;
          final failed = marked.copyWith(
            state: isTransient
                ? (marked.attachmentUploadDraft == null
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
          _errorMessage = failed.errorMessage;
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
    _conversations = await cache.readConversations();
    _messagesByConversation.clear();
    _pagingStateByConversation.clear();
    _pendingByClientMessageId.clear();
    _decryptedMessageCache.clear();
    _searchableBodyByMessageKey.clear();
    _attachmentTransfersByClientMessageId.clear();

    for (final conversation in _conversations) {
      final cachedMessages = await cache.readMessages(conversation.id);
      _messagesByConversation[conversation.id] = cachedMessages
          .map(
            (message) => message.copyWith(
              isMine: message.senderDeviceId == _session.deviceId,
            ),
          )
          .toList();
      for (final message in _messagesByConversation[conversation.id] ?? const <ChatMessage>[]) {
        if (message.searchableBody case final body?) {
          _rememberSearchableBody(_messageCacheKey(message), body);
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
      _messagesByConversation[pending.conversationId] = _mergeMessageCollections(
        _messagesByConversation[pending.conversationId] ?? const [],
        <ChatMessage>[optimisticMessage],
      );
    }

    await _attachmentTempFileStore?.cleanupOrphanedFiles(keepPaths: keepTempPaths);
    _pruneDecryptedCache();
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
          _scheduleSyncAfterRealtimeHint();
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
            _mergeServerMessages(message.envelope.conversationId, <ChatMessage>[message]);
            unawaited(_persistConversationState(message.envelope.conversationId));
            notifyListeners();
            if (!message.isMine && message.envelope.conversationId == _activeConversationId) {
              await markRead(message.id);
            }
            _scheduleSyncAfterRealtimeHint(conversationId: message.envelope.conversationId);
            break;
          case 'message.reaction':
            final data = payload as Map<String, dynamic>;
            _applyReactionEvent(
              messageId: data['messageId'] as String,
              userId: data['userId'] as String,
              emoji: (data['emoji'] as String?) ?? '',
              action: (data['action'] as String?) ?? 'add',
            );
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
          default:
            break;
        }
      },
    );
  }

  Future<void> _refreshRealtimeAndSync({bool forceReconnect = false}) async {
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }

    if (forceReconnect || !_realtimeService.isConnected || !_realtimeConnected) {
      _realtimeService.disconnect();
      _realtimeConnected = false;
      notifyListeners();
      await _connectRealtime();
    }
    _scheduleSyncAfterRealtimeHint(conversationId: _activeConversationId);
    await _drainOutbox(ignoreRetrySchedule: true);
  }

  void _scheduleSyncAfterRealtimeHint({String? conversationId}) {
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
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }
    if (_syncAfterHintInFlight) {
      return;
    }

    _syncAfterHintInFlight = true;
    try {
      await _refreshConversationsCore();
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
        await _syncConversation(targetConversationId);
      }
      await _drainOutbox(ignoreRetrySchedule: true);
    } catch (error) {
      await _handleSecurityException(error);
      _errorMessage = formatUserFacingError(error);
      notifyListeners();
    } finally {
      _syncAfterHintInFlight = false;
      if (_queuedSyncConversationIds.isNotEmpty) {
        _scheduleSyncAfterRealtimeHint();
      }
    }
  }

  void _mergeServerMessages(String conversationId, List<ChatMessage> serverMessages) {
    final current = _messagesByConversation[conversationId] ?? const <ChatMessage>[];
    _messagesByConversation[conversationId] = _mergeMessageCollections(current, serverMessages);
    _pruneDecryptedCache();
    _applyBufferedReceipts(conversationId);
    _syncConversationPreviewFromMessages(conversationId);
  }

  List<ChatMessage> _mergeMessageCollections(
    List<ChatMessage> current,
    List<ChatMessage> incoming,
  ) {
    final mergedServerMessages = <String, ChatMessage>{};
    final currentPending = current.where((message) => message.isPending || message.hasFailed).toList();

    for (final message in current.where((item) => !item.isPending && !item.hasFailed)) {
      mergedServerMessages[message.id] = message;
    }
    for (final message in incoming) {
      final existing = mergedServerMessages[message.id];
      mergedServerMessages[message.id] =
          existing == null ? message : _mergeServerMessage(existing, message);
    }

    final ackedClientIds = incoming
        .map((message) => message.clientMessageId)
        .whereType<String>()
        .toSet();

    final merged = <ChatMessage>[
      ...mergedServerMessages.values,
      ...currentPending.where((message) => !ackedClientIds.contains(message.clientMessageId)),
    ];
    merged.sort(_compareMessages);
    return merged;
  }

  ChatMessage _mergeServerMessage(ChatMessage current, ChatMessage incoming) {
    final deliveredAt = _laterOf(current.deliveredAt, incoming.deliveredAt);
    final readAt = _laterOf(current.readAt, incoming.readAt);
    return incoming.copyWith(
      clientMessageId: incoming.clientMessageId ?? current.clientMessageId,
      conversationOrder: incoming.conversationOrder ?? current.conversationOrder,
      searchableBody: incoming.searchableBody ?? current.searchableBody,
      deliveredAt: deliveredAt,
      readAt: readAt,
      deliveryState: _resolveDeliveryState(
        base: incoming.deliveryState,
        deliveredAt: deliveredAt,
        readAt: readAt,
      ),
    );
  }

  int _compareMessages(ChatMessage a, ChatMessage b) {
    final aOrder = a.conversationOrder;
    final bOrder = b.conversationOrder;
    if (aOrder != null && bOrder != null) {
      return aOrder.compareTo(bOrder);
    }
    if (aOrder != null) {
      return -1;
    }
    if (bOrder != null) {
      return 1;
    }
    return a.sentAt.compareTo(b.sentAt);
  }

  void _applyReceiptEvent(
    String messageId, {
    DateTime? deliveredAt,
    DateTime? readAt,
  }) {
    for (final entry in _messagesByConversation.entries) {
      var changed = false;
      final updated = entry.value.map((message) {
        if (message.id != messageId) {
          return message;
        }

        changed = true;
        final mergedDeliveredAt = _laterOf(message.deliveredAt, deliveredAt);
        final mergedReadAt = _laterOf(message.readAt, readAt);
        return message.copyWith(
          deliveryState: _resolveDeliveryState(
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
      deliveredAt: _laterOf(existing?.deliveredAt, deliveredAt),
      readAt: _laterOf(existing?.readAt, readAt),
    );
  }

  void _applyReactionEvent({
    required String messageId,
    required String userId,
    required String emoji,
    required String action,
  }) {
    for (final entry in _messagesByConversation.entries) {
      var changed = false;
      final updated = entry.value.map((message) {
        if (message.id != messageId) {
          return message;
        }
        final next = _mergeReaction(
          current: message.reactions,
          messageId: messageId,
          userId: userId,
          emoji: emoji,
          action: action,
          sentAt: message.sentAt,
        );
        if (identical(next, message.reactions)) {
          return message;
        }
        changed = true;
        return message.copyWith(reactions: next);
      }).toList();

      if (changed) {
        _messagesByConversation[entry.key] = updated;
        unawaited(_persistConversationState(entry.key));
        notifyListeners();
        return;
      }
    }
  }

  List<Reaction> _mergeReaction({
    required List<Reaction> current,
    required String messageId,
    required String userId,
    required String emoji,
    required String action,
    required DateTime sentAt,
  }) {
    final withoutUser = current.where((r) => r.userId != userId).toList();
    if (action == 'remove' || emoji.isEmpty) {
      if (withoutUser.length == current.length) {
        return current;
      }
      return withoutUser;
    }
    withoutUser.add(
      Reaction(
        messageId: messageId,
        userId: userId,
        emoji: emoji,
        createdAt: DateTime.now(),
      ),
    );
    return withoutUser;
  }

  Future<void> toggleReaction(ChatMessage message, String emoji) async {
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }
    final accessToken = _session.accessToken;
    if (accessToken == null) {
      return;
    }
    final myUserId = _session.userId;
    if (myUserId == null) {
      return;
    }

    final existingMine = message.reactions.firstWhere(
      (r) => r.userId == myUserId,
      orElse: () => Reaction(
        messageId: message.id,
        userId: myUserId,
        emoji: '',
        createdAt: DateTime.now(),
      ),
    );
    final isRemoval = existingMine.emoji == emoji;
    final previous = message.reactions;

    _applyReactionEvent(
      messageId: message.id,
      userId: myUserId,
      emoji: isRemoval ? '' : emoji,
      action: isRemoval ? 'remove' : 'add',
    );

    try {
      if (isRemoval) {
        await _apiClient.removeReaction(accessToken, message.id);
      } else {
        await _apiClient.addReaction(accessToken, message.id, emoji);
      }
    } catch (error) {
      _restoreReactionsForMessage(message.id, previous);
      _errorMessage = 'Reaction failed: $error';
      notifyListeners();
    }
  }

  void _restoreReactionsForMessage(String messageId, List<Reaction> previous) {
    for (final entry in _messagesByConversation.entries) {
      var changed = false;
      final updated = entry.value.map((message) {
        if (message.id != messageId) {
          return message;
        }
        changed = true;
        return message.copyWith(reactions: previous);
      }).toList();
      if (changed) {
        _messagesByConversation[entry.key] = updated;
        notifyListeners();
        return;
      }
    }
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

  void _setMessageSearchableBody(
    String conversationId,
    String messageId,
    String searchableBody,
  ) {
    final messages = _messagesByConversation[conversationId];
    if (messages == null) {
      return;
    }

    var changed = false;
    final updated = messages.map((message) {
      if (message.id != messageId || message.searchableBody == searchableBody) {
        return message;
      }
      changed = true;
      return message.copyWith(searchableBody: searchableBody);
    }).toList(growable: false);

    if (changed) {
      _messagesByConversation[conversationId] = updated;
      unawaited(_persistConversationState(conversationId));
      notifyListeners();
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

    final conversation = _findConversation(pending.conversationId);
    if (conversation == null) {
      throw StateError('The target conversation is no longer available.');
    }

    final tempBlob = await tempStore.createOpaqueBlob(
      filename: draft.filename,
      sizeBytes: draft.sizeBytes,
      existingPath: draft.tempFilePath,
    );
    draft = draft.copyWith(
      tempFilePath: tempBlob.path,
      sizeBytes: tempBlob.sizeBytes,
      sha256: tempBlob.sha256,
      lastUpdatedAt: DateTime.now(),
    );
    pending = pending.copyWith(attachmentUploadDraft: draft);
    _pendingByClientMessageId[pending.clientMessageId] = pending;
    await _cacheService?.upsertPendingMessage(pending);

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
        file: File(tempBlob.path),
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

    final bundle = conversation.type == ConversationType.group
        ? conversation.recipientBundle
        : await _fetchPeerBundle(conversation.peerHandle);
    final recipientUserId = conversation.type == ConversationType.group
        ? ''
        : bundle.userId;
    final attachment = await _cryptoEngine.encryptAttachment(
      attachmentId: draft.attachmentId!,
      storageKey: draft.storageKey!,
      contentType: draft.contentType,
      sizeBytes: draft.sizeBytes,
      sha256: draft.sha256,
      recipientBundle: bundle,
    );

    final updatedEnvelope = await _cryptoEngine.encryptMessage(
      conversationId: pending.conversationId,
      senderDeviceId: pending.senderDeviceId,
      recipientUserId: recipientUserId,
      body: 'Encrypted attachment',
      messageKind: MessageKind.file,
      recipientBundle: bundle,
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

  Future<AttachmentUploadDraft> _ensureUploadTicket(
    PendingMessageRecord pending,
    AttachmentUploadDraft draft,
  ) async {
    if (draft.hasUploadTicket && !draft.uploadTicketExpired) {
      return draft;
    }
    final resetDraft = await _markAttachmentTicketFailed(draft, deleteRemoteObject: draft.hasUploadTicket);
    final upload = await _apiClient.createUploadTicket(_session.accessToken!, {
      'contentType': resetDraft.contentType,
      'sizeBytes': resetDraft.sizeBytes,
      'sha256': resetDraft.sha256,
    });
    final uploadPayload = upload['upload'] as Map<String, dynamic>;
    return resetDraft.copyWith(
      attachmentId: upload['attachmentId'] as String,
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

  ConversationPreview? _findConversation(String conversationId) {
    for (final conversation in _conversations) {
      if (conversation.id == conversationId) {
        return conversation;
      }
    }
    return null;
  }

  bool _shouldRetryAutomatically(Object error, int retryCount) {
    if (retryCount >= _maxAutomaticRetryAttempts) {
      return false;
    }
    if (error is VeilApiException) {
      if (error.code == 'device_not_active' ||
          error.code == 'attachment_not_found' ||
          error.code == 'attachment_upload_invalid' ||
          error.code == 'attachment_upload_canceled' ||
          error.code == 'conversation_membership_required' ||
          error.code == 'direct_peer_mismatch') {
        return false;
      }

      final statusCode = error.statusCode;
      if (statusCode != null) {
        return statusCode >= 500 || statusCode == 408 || statusCode == 409 || statusCode == 429;
      }
      return error.code == 'attachment_upload_failed';
    }

    return true;
  }

  Duration _retryDelayForAttempt(int retryCount) {
    final seconds = min<int>(30, 1 << (retryCount.clamp(1, 5) - 1));
    return Duration(seconds: seconds);
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
      final deliveredAt = _laterOf(message.deliveredAt, backlog.deliveredAt);
      final readAt = _laterOf(message.readAt, backlog.readAt);
      return message.copyWith(
        deliveredAt: deliveredAt,
        readAt: readAt,
        deliveryState: _resolveDeliveryState(
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

  DateTime? _laterOf(DateTime? left, DateTime? right) {
    if (left == null) {
      return right;
    }
    if (right == null) {
      return left;
    }
    return left.isAfter(right) ? left : right;
  }

  MessageDeliveryState _resolveDeliveryState({
    required MessageDeliveryState base,
    required DateTime? deliveredAt,
    required DateTime? readAt,
  }) {
    if (readAt != null) {
      return MessageDeliveryState.read;
    }
    if (deliveredAt != null) {
      return MessageDeliveryState.delivered;
    }
    return base;
  }

  Future<void> _persistConversationState(String conversationId) async {
    final cache = _cacheService;
    if (cache == null) {
      return;
    }

    await cache.storeMessages(conversationId, _messagesByConversation[conversationId] ?? const []);
    await cache.storeConversations(_conversations);
  }

  Future<void> _reconcileExpiringState() async {
    final now = DateTime.now();
    var conversationsChanged = false;
    final changedMessageConversations = <String>{};

    for (final entry in _messagesByConversation.entries) {
      final beforeLength = entry.value.length;
      final retainedMessages = entry.value.where((message) {
        final expired = _isExpired(message.expiresAt, now);
        if (expired) {
          final cacheKey = _messageCacheKey(message);
          _decryptedMessageCache.remove(cacheKey);
          _searchableBodyByMessageKey.remove(cacheKey);
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

    final cache = _cacheService;
    if (cache != null) {
      await cache.purgeExpiredMessages();
      for (final conversationId in changedMessageConversations) {
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
  }

  Future<KeyBundle> _fetchPeerBundle(String handle) async {
    final response = await _apiClient.getKeyBundle(handle);
    final activeDeviceId =
        (response['user'] as Map<String, dynamic>?)?['activeDeviceId'] as String?;
    final directoryJson =
        (response['deviceBundles'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];
    if (directoryJson.isNotEmpty) {
      final bundles = _keyBundleCodec.decodeDirectoryBundles(directoryJson);
      final selected = bundles.firstWhere(
        (bundle) => bundle.deviceId == activeDeviceId,
        orElse: () => bundles.first,
      );
      final sessionState = await _ensureConversationSession(handle, selected);
      _refreshConversationBundle(handle, selected, sessionState: sessionState);
      return selected;
    }

    final bundle = response['bundle'] as Map<String, dynamic>;
    final selected = _keyBundleCodec.decodeDirectoryBundle(bundle);
    final sessionState = await _ensureConversationSession(handle, selected);
    _refreshConversationBundle(handle, selected, sessionState: sessionState);
    return selected;
  }

  Future<ConversationSessionState?> _ensureConversationSession(
    String handle,
    KeyBundle bundle,
  ) async {
    if (!_session.isAuthenticated) {
      return null;
    }

    ConversationPreview? conversation;
    for (final item in _conversations) {
      if (item.peerHandle == handle) {
        conversation = item;
        break;
      }
    }
    if (conversation == null) {
      return null;
    }

    if (conversation.sessionState != null &&
        conversation.sessionState!.belongsToLocalDevice(_session.deviceId!) &&
        conversation.sessionState!.matchesBundle(bundle)) {
      return conversation.sessionState;
    }

    final bootstrapped = await _sessionBootstrapper.bootstrapSession(
      SessionBootstrapRequest(
        conversationId: conversation.id,
        localDeviceId: _session.deviceId!,
        localUserId: _session.userId!,
        remoteUserId: bundle.userId,
        remoteDeviceId: bundle.deviceId,
        remoteIdentityPublicKey: bundle.identityPublicKey,
        remoteSignedPrekeyBundle: bundle.signedPrekeyBundle,
      ),
    );
    return ConversationSessionState(
      sessionLocator: bootstrapped.sessionLocator,
      sessionEnvelopeVersion: bootstrapped.sessionEnvelopeVersion,
      requiresLocalPersistence: bootstrapped.requiresLocalPersistence,
      sessionSchemaVersion: bootstrapped.sessionSchemaVersion,
      localDeviceId: bootstrapped.localDeviceId,
      remoteDeviceId: bootstrapped.remoteDeviceId,
      remoteIdentityFingerprint: bootstrapped.remoteIdentityFingerprint,
      bootstrappedAt: DateTime.now(),
      auditHint: bootstrapped.auditHint,
    );
  }

  void _refreshConversationBundle(
    String handle,
    KeyBundle bundle, {
    ConversationSessionState? sessionState,
  }) {
    var changed = false;
    _conversations = _conversations.map((conversation) {
      if (conversation.peerHandle != handle) {
        return conversation;
      }
      final shouldUpdateBundle =
          conversation.recipientBundle.deviceId != bundle.deviceId;
      final shouldUpdateSession =
          sessionState != null &&
          (conversation.sessionState?.sessionLocator != sessionState.sessionLocator ||
              conversation.sessionState?.sessionEnvelopeVersion !=
                  sessionState.sessionEnvelopeVersion ||
              conversation.sessionState?.sessionSchemaVersion !=
                  sessionState.sessionSchemaVersion ||
              conversation.sessionState?.localDeviceId !=
                  sessionState.localDeviceId ||
              conversation.sessionState?.remoteDeviceId !=
                  sessionState.remoteDeviceId ||
              conversation.sessionState?.remoteIdentityFingerprint !=
                  sessionState.remoteIdentityFingerprint);
      if (!shouldUpdateBundle && !shouldUpdateSession) {
        return conversation;
      }
      changed = true;
      return conversation.copyWith(
        recipientBundle: bundle,
        sessionState: sessionState,
      );
    }).toList(growable: false);
    if (changed) {
      unawaited(_cacheService?.storeConversations(_conversations));
      notifyListeners();
    }
  }

  ConversationPreview _conversationFromApi(dynamic raw) {
    final conversation = raw as Map<String, dynamic>;
    final members = (conversation['members'] as List<dynamic>).cast<Map<String, dynamic>>();
    final peer = members.firstWhere(
      (member) => member['handle'] != _session.handle,
      orElse: () => members.first,
    );
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
    );
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
      reactions: _reactionsFromApi(messageId, raw['reactions'], sentAt),
    );
  }

  List<Reaction> _reactionsFromApi(
    String messageId,
    Object? raw,
    DateTime fallbackCreatedAt,
  ) {
    if (raw is! List) {
      return const <Reaction>[];
    }
    final parsed = <Reaction>[];
    for (final entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final userId = entry['userId'];
      final emoji = entry['emoji'];
      if (userId is! String || emoji is! String || emoji.isEmpty) {
        continue;
      }
      parsed.add(
        Reaction(
          messageId: messageId,
          userId: userId,
          emoji: emoji,
          createdAt: fallbackCreatedAt,
        ),
      );
    }
    return parsed;
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

  String _messageCacheKey(ChatMessage message) {
    return '${message.id}:${message.envelope.ciphertext}:${message.envelope.nonce}';
  }

  String _searchableMessageBody(DecryptedMessage message) {
    final attachment = message.attachment;
    return _normalizeSearchQuery([
      message.body,
      message.messageKind.name,
      if (attachment != null) attachment.contentType,
      if (attachment != null) attachment.attachmentId,
    ].join(' '));
  }

  String _normalizeSearchQuery(String value) {
    return value.trim().toLowerCase();
  }

  void _pruneDecryptedCache() {
    final validKeys = _messagesByConversation.values
        .expand((messages) => messages)
        .map(_messageCacheKey)
        .toSet();
    final keysToRemove = _decryptedMessageCache.keys
        .where((key) => !validKeys.contains(key))
        .toList(growable: false);
    for (final key in keysToRemove) {
      _decryptedMessageCache.remove(key);
      _searchableBodyByMessageKey.remove(key);
    }
    _trimMessageCaches();
  }

  void _rememberSearchableBody(String cacheKey, String searchableBody) {
    _searchableBodyByMessageKey.remove(cacheKey);
    _searchableBodyByMessageKey[cacheKey] = searchableBody;
    _trimMessageCaches();
  }

  void _trimMessageCaches() {
    while (_decryptedMessageCache.length > _maxDecryptedCacheEntries) {
      final oldestKey = _decryptedMessageCache.keys.first;
      _decryptedMessageCache.remove(oldestKey);
      _searchableBodyByMessageKey.remove(oldestKey);
    }
    while (_searchableBodyByMessageKey.length > _maxSearchBodyEntries) {
      final oldestKey = _searchableBodyByMessageKey.keys.first;
      _searchableBodyByMessageKey.remove(oldestKey);
      _decryptedMessageCache.remove(oldestKey);
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
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
    super.dispose();
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
