import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../app/app_state.dart';
import '../../../core/config/veil_config.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/network/veil_api_client.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../../core/storage/conversation_cache_service.dart';
import 'conversation_models.dart';

class VeilMessengerController extends ChangeNotifier {
  static const _maxAutomaticRetryAttempts = 5;
  static const _retrySweepInterval = Duration(seconds: 3);

  VeilMessengerController({
    required VeilApiClient apiClient,
    required MessageCryptoEngine cryptoEngine,
    required KeyBundleCodec keyBundleCodec,
    required CryptoEnvelopeCodec envelopeCodec,
    required RealtimeService realtimeService,
    required ConversationCacheService? cacheService,
    Future<void> Function(Object error)? onSecurityException,
  })  : _apiClient = apiClient,
        _cryptoEngine = cryptoEngine,
        _keyBundleCodec = keyBundleCodec,
        _envelopeCodec = envelopeCodec,
        _realtimeService = realtimeService,
        _cacheService = cacheService,
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
  final RealtimeService _realtimeService;
  final ConversationCacheService? _cacheService;
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

  List<ConversationPreview> get conversations => _conversations;
  bool get isBusy => _isBusy;
  bool get realtimeConnected => _realtimeConnected;
  String? get errorMessage => _errorMessage;
  String? get transferSessionId => _transferSessionId;
  String? get transferToken => _transferToken;
  String? get transferStatus => _transferStatus;
  DateTime? get transferExpiresAt => _transferExpiresAt;
  bool get hasPendingWork => _pendingByClientMessageId.isNotEmpty;
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
      _conversations = [];
      _messagesByConversation.clear();
      _pagingStateByConversation.clear();
      _pendingByClientMessageId.clear();
      _receiptBacklogByMessageId.clear();
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

  Future<void> startConversationByHandle(String handle) async {
    await _run(() async {
      if (!_session.isAuthenticated || !VeilConfig.hasApi) {
        throw StateError('Authenticated API session required.');
      }

      await _apiClient.createDirectConversation(_session.accessToken!, handle);
      await _refreshConversationsCore();
    });
  }

  Future<void> sendText({
    required String conversationId,
    required String body,
    Duration? disappearAfter,
  }) async {
    await _run(() async {
      if (!_session.isAuthenticated || !VeilConfig.hasApi) {
        throw StateError('Authenticated API session required.');
      }

      final conversation = _conversations.firstWhere((item) => item.id == conversationId);
      final bundle = await _fetchPeerBundle(conversation.peerHandle);
      final clientMessageId = _nextClientMessageId();
      final envelope = await _cryptoEngine.encryptMessage(
        conversationId: conversationId,
        senderDeviceId: _session.deviceId!,
        recipientUserId: bundle.userId,
        body: body,
        messageKind: MessageKind.text,
        recipientBundle: bundle,
        expiresAt: disappearAfter == null ? null : DateTime.now().add(disappearAfter),
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
      final envelope = await _cryptoEngine.encryptMessage(
        conversationId: conversationId,
        senderDeviceId: _session.deviceId!,
        recipientUserId: conversation.recipientBundle.userId,
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
          contentType: 'application/octet-stream',
          sizeBytes: 2048,
          sha256: 'mock-sha256-$filename',
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

    try {
      final response = await _apiClient.getDownloadTicket(_session.accessToken!, attachmentId);
      return (response['ticket'] as Map<String, dynamic>)['downloadUrl'] as String;
    } catch (error) {
      await _handleSecurityException(error);
      _errorMessage = formatUserFacingError(error);
      notifyListeners();
      return null;
    }
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

        try {
          if (marked.attachmentUploadDraft != null) {
            marked = await _preparePendingAttachment(marked);
            _pendingByClientMessageId[marked.clientMessageId] = marked;
            await _cacheService?.upsertPendingMessage(marked);
            _updateLocalMessageState(
              marked.clientMessageId,
              state: MessageDeliveryState.pending,
            );
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

    for (final conversation in _conversations) {
      final cachedMessages = await cache.readMessages(conversation.id);
      _messagesByConversation[conversation.id] = cachedMessages
          .map(
            (message) => message.copyWith(
              isMine: message.senderDeviceId == _session.deviceId,
            ),
          )
          .toList();
      _pagingStateByConversation[conversation.id] = await cache.readPagingState(conversation.id);
    }

    final pendingMessages = await cache.readPendingMessages();
    for (final pending in pendingMessages) {
      _pendingByClientMessageId[pending.clientMessageId] = pending;
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
        notifyListeners();
        if (connected) {
          unawaited(_syncAfterRealtimeHint());
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
            if (!message.isMine && message.envelope.conversationId == _activeConversationId) {
              await markRead(message.id);
            }
            await _syncAfterRealtimeHint(conversationId: message.envelope.conversationId);
            break;
          case 'conversation.sync':
            final data = payload as Map<String, dynamic>;
            await _syncAfterRealtimeHint(conversationId: data['conversationId'] as String?);
            break;
          default:
            break;
        }
      },
    );
  }

  Future<void> _syncAfterRealtimeHint({String? conversationId}) async {
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }

    try {
      await _refreshConversationsCore();
      final conversationsToSync = <String>{
        ..._messagesByConversation.keys,
        ..._pendingByClientMessageId.values.map((item) => item.conversationId),
      };
      final activeConversationId = _activeConversationId;
      if (activeConversationId != null) {
        conversationsToSync.add(activeConversationId);
      }
      if (conversationId != null && conversationId.isNotEmpty) {
        conversationsToSync.add(conversationId);
      }

      for (final targetConversationId in conversationsToSync) {
        await _syncConversation(targetConversationId);
      }
      await _drainOutbox(ignoreRetrySchedule: true);
    } catch (error) {
      await _handleSecurityException(error);
      _errorMessage = formatUserFacingError(error);
      notifyListeners();
    }
  }

  void _mergeServerMessages(String conversationId, List<ChatMessage> serverMessages) {
    final current = _messagesByConversation[conversationId] ?? const <ChatMessage>[];
    _messagesByConversation[conversationId] = _mergeMessageCollections(current, serverMessages);
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
    final draft = pending.attachmentUploadDraft;
    if (draft == null) {
      return pending;
    }

    final conversation = _findConversation(pending.conversationId);
    if (conversation == null) {
      throw StateError('The target conversation is no longer available.');
    }

    final upload = await _apiClient.createUploadTicket(_session.accessToken!, {
      'contentType': draft.contentType,
      'sizeBytes': draft.sizeBytes,
      'sha256': draft.sha256,
    });

    final uploadPayload = upload['upload'] as Map<String, dynamic>;
    await _apiClient.uploadEncryptedPlaceholder(
      uploadUrl: uploadPayload['uploadUrl'] as String,
      headers: (uploadPayload['headers'] as Map<String, dynamic>? ?? const {}),
      filename: draft.filename,
    );

    await _apiClient.completeUpload(_session.accessToken!, {
      'attachmentId': upload['attachmentId'],
      'uploadStatus': 'uploaded',
    });

    final bundle = await _fetchPeerBundle(conversation.peerHandle);
    final attachment = await _cryptoEngine.encryptAttachment(
      attachmentId: upload['attachmentId'] as String,
      storageKey: uploadPayload['storageKey'] as String,
      contentType: draft.contentType,
      sizeBytes: draft.sizeBytes,
      sha256: draft.sha256,
      recipientBundle: bundle,
    );

    final updatedEnvelope = await _cryptoEngine.encryptMessage(
      conversationId: pending.conversationId,
      senderDeviceId: pending.senderDeviceId,
      recipientUserId: bundle.userId,
      body: 'Encrypted attachment',
      messageKind: MessageKind.file,
      recipientBundle: bundle,
      expiresAt: pending.envelope.expiresAt,
      attachment: attachment,
    );

    return pending.copyWith(
      envelope: updatedEnvelope,
      attachmentUploadDraft: null,
      state: MessageDeliveryState.pending,
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
      entry.value.removeWhere((message) => _isExpired(message.expiresAt, now));
      if (entry.value.length != beforeLength) {
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
  }

  Future<KeyBundle> _fetchPeerBundle(String handle) async {
    final response = await _apiClient.getKeyBundle(handle);
    final bundle = response['bundle'] as Map<String, dynamic>;
    return _keyBundleCodec.decodeDirectoryBundle(bundle);
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
    );
  }

  ChatMessage _messageFromApi(Map<String, dynamic> raw) {
    final deliveredAt = raw['deliveredAt'] == null
        ? null
        : DateTime.parse(raw['deliveredAt'] as String);
    final readAt = raw['readAt'] == null ? null : DateTime.parse(raw['readAt'] as String);
    return ChatMessage(
      id: raw['id'] as String,
      clientMessageId: raw['clientMessageId'] as String?,
      senderDeviceId: raw['senderDeviceId'] as String,
      sentAt: DateTime.parse(raw['serverReceivedAt'] as String),
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
