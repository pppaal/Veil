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
  VeilMessengerController({
    required VeilApiClient apiClient,
    required CryptoEngine cryptoEngine,
    required RealtimeService realtimeService,
    required ConversationCacheService? cacheService,
  })  : _apiClient = apiClient,
        _cryptoEngine = cryptoEngine,
        _realtimeService = realtimeService,
        _cacheService = cacheService {
    _expirationTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_reconcileExpiringState()),
    );
  }

  final VeilApiClient _apiClient;
  final CryptoEngine _cryptoEngine;
  final RealtimeService _realtimeService;
  final ConversationCacheService? _cacheService;
  final Random _random = Random.secure();

  Timer? _expirationTicker;
  List<ConversationPreview> _conversations = [];
  final Map<String, List<ChatMessage>> _messagesByConversation = {};
  final Map<String, ConversationPagingState> _pagingStateByConversation = {};
  final Map<String, PendingMessageRecord> _pendingByClientMessageId = {};
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

  List<ConversationPreview> get conversations => _conversations;
  bool get isBusy => _isBusy;
  bool get realtimeConnected => _realtimeConnected;
  String? get errorMessage => _errorMessage;
  String? get transferSessionId => _transferSessionId;
  String? get transferToken => _transferToken;
  String? get transferStatus => _transferStatus;
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
    await _drainOutbox(conversationId: conversationId, markFailuresAsRetrying: true);
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
      final upload = await _apiClient.createUploadTicket(_session.accessToken!, {
        'contentType': 'application/octet-stream',
        'sizeBytes': 2048,
        'sha256': 'mock-sha256-$filename',
      });

      final uploadPayload = upload['upload'] as Map<String, dynamic>;
      await _apiClient.uploadEncryptedPlaceholder(
        uploadUrl: uploadPayload['uploadUrl'] as String,
        headers: (uploadPayload['headers'] as Map<String, dynamic>? ?? const {}),
        filename: filename,
      );

      await _apiClient.completeUpload(_session.accessToken!, {
        'attachmentId': upload['attachmentId'],
        'uploadStatus': 'uploaded',
      });

      final bundle = await _fetchPeerBundle(conversation.peerHandle);
      final attachment = await _cryptoEngine.encryptAttachment(
        attachmentId: upload['attachmentId'] as String,
        storageKey: uploadPayload['storageKey'] as String,
        contentType: 'application/octet-stream',
        sizeBytes: 2048,
        sha256: 'mock-sha256-$filename',
        recipientBundle: bundle,
      );

      final clientMessageId = _nextClientMessageId();
      final envelope = await _cryptoEngine.encryptMessage(
        conversationId: conversationId,
        senderDeviceId: _session.deviceId!,
        recipientUserId: bundle.userId,
        body: 'Encrypted attachment',
        messageKind: MessageKind.file,
        recipientBundle: bundle,
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

    final response = await _apiClient.getDownloadTicket(_session.accessToken!, attachmentId);
    return (response['ticket'] as Map<String, dynamic>)['downloadUrl'] as String;
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
  }) async {
    final createdAt = DateTime.now();
    final pending = PendingMessageRecord(
      clientMessageId: clientMessageId,
      conversationId: conversation.id,
      senderDeviceId: _session.deviceId!,
      recipientUserId: envelope.recipientUserId,
      envelope: envelope,
      createdAt: createdAt,
    );

    _pendingByClientMessageId[clientMessageId] = pending;
    final optimisticMessage = ChatMessage(
      id: 'local-$clientMessageId',
      clientMessageId: clientMessageId,
      senderDeviceId: _session.deviceId!,
      sentAt: createdAt,
      envelope: envelope,
      deliveryState: MessageDeliveryState.pending,
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
  }) async {
    if (_isDrainingOutbox || !_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }

    _isDrainingOutbox = true;
    try {
      final pendingItems = _pendingByClientMessageId.values
          .where((item) => conversationId == null || item.conversationId == conversationId)
          .where((item) => markFailuresAsRetrying || item.state != MessageDeliveryState.failed)
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      for (final pending in pendingItems) {
        final marked = pending.copyWith(
          retryCount: pending.retryCount + 1,
          lastAttemptAt: DateTime.now(),
          state: MessageDeliveryState.pending,
          errorMessage: null,
        );
        _pendingByClientMessageId[pending.clientMessageId] = marked;
        await _cacheService?.upsertPendingMessage(marked);

        try {
          final response = await _apiClient.sendMessage(_session.accessToken!, {
            'conversationId': pending.conversationId,
            'clientMessageId': pending.clientMessageId,
            'envelope': _envelopeToJson(pending.envelope),
          });
          final serverMessage =
              _messageFromApi(response['message'] as Map<String, dynamic>);
          _pendingByClientMessageId.remove(pending.clientMessageId);
          await _cacheService?.removePendingMessage(pending.clientMessageId);
          _mergeServerMessages(pending.conversationId, <ChatMessage>[serverMessage]);
          await _persistConversationState(pending.conversationId);
        } catch (error) {
          final failed = marked.copyWith(
            state: MessageDeliveryState.failed,
            errorMessage: formatUserFacingError(error),
          );
          _pendingByClientMessageId[pending.clientMessageId] = failed;
          await _cacheService?.upsertPendingMessage(failed);
          _markLocalMessageFailed(pending.clientMessageId);
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
          unawaited(_drainOutbox());
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
          case 'conversation.sync':
            await _syncAfterRealtimeHint();
            break;
          default:
            break;
        }
      },
    );
    _realtimeConnected = true;
  }

  Future<void> _syncAfterRealtimeHint() async {
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }

    try {
      await _refreshConversationsCore();
      final activeConversationId = _activeConversationId;
      if (activeConversationId != null) {
        await _syncConversation(activeConversationId);
      }
      await _drainOutbox();
    } catch (error) {
      _errorMessage = formatUserFacingError(error);
      notifyListeners();
    }
  }

  void _mergeServerMessages(String conversationId, List<ChatMessage> serverMessages) {
    final current = _messagesByConversation[conversationId] ?? const <ChatMessage>[];
    _messagesByConversation[conversationId] = _mergeMessageCollections(current, serverMessages);
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
      mergedServerMessages[message.id] = message;
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
        return message.copyWith(
          deliveryState: readAt != null
              ? MessageDeliveryState.read
              : deliveredAt != null
                  ? MessageDeliveryState.delivered
                  : message.deliveryState,
          deliveredAt: deliveredAt ?? message.deliveredAt,
          readAt: readAt ?? message.readAt,
        );
      }).toList();

      if (changed) {
        _messagesByConversation[entry.key] = updated;
        unawaited(_persistConversationState(entry.key));
        notifyListeners();
        return;
      }
    }
  }

  void _markLocalMessageFailed(String clientMessageId) {
    for (final entry in _messagesByConversation.entries) {
      var changed = false;
      final updated = entry.value.map((message) {
        if (message.clientMessageId != clientMessageId) {
          return message;
        }

        changed = true;
        return message.copyWith(deliveryState: MessageDeliveryState.failed);
      }).toList();
      if (changed) {
        _messagesByConversation[entry.key] = updated;
        unawaited(_persistConversationState(entry.key));
        return;
      }
    }
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
    return KeyBundle(
      userId: bundle['userId'] as String,
      deviceId: bundle['deviceId'] as String,
      handle: bundle['handle'] as String,
      identityPublicKey: bundle['identityPublicKey'] as String,
      signedPrekeyBundle: bundle['signedPrekeyBundle'] as String,
    );
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
    return CryptoEnvelope.fromApiJson(raw);
  }

  Map<String, dynamic> _envelopeToJson(CryptoEnvelope envelope) {
    return envelope.toApiJson();
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
      _errorMessage = formatUserFacingError(error);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _expirationTicker?.cancel();
    _realtimeService.disconnect();
    super.dispose();
  }
}
