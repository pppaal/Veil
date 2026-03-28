import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/config/veil_config.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/network/veil_api_client.dart';
import '../../../core/realtime/realtime_service.dart';
import '../../../core/storage/conversation_cache_service.dart';
import '../../../app/app_state.dart';
import 'mock_messenger_repository.dart';

class VeilMessengerController extends ChangeNotifier {
  VeilMessengerController({
    required VeilApiClient apiClient,
    required CryptoEngine cryptoEngine,
    required RealtimeService realtimeService,
    required ConversationCacheService? cacheService,
    required MockMessengerRepository mockRepository,
  })  : _apiClient = apiClient,
        _cryptoEngine = cryptoEngine,
        _realtimeService = realtimeService,
        _cacheService = cacheService,
        _mockRepository = mockRepository {
    _expirationTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_reconcileExpiringState()),
    );
  }

  final VeilApiClient _apiClient;
  final CryptoEngine _cryptoEngine;
  final RealtimeService _realtimeService;
  final ConversationCacheService? _cacheService;
  final MockMessengerRepository _mockRepository;
  Timer? _expirationTicker;

  List<ConversationPreview> _conversations = [];
  final Map<String, List<ChatMessage>> _messagesByConversation = {};
  AppSessionState _session = const AppSessionState();
  bool _isBusy = false;
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

  List<ChatMessage> messagesFor(String conversationId) =>
      _messagesByConversation[conversationId] ?? const [];

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
      _conversations = _mockRepository.listConversations();
      _messagesByConversation.clear();
      notifyListeners();
      return;
    }

    await _hydrateFromCache();
    await refreshConversations();
    await _connectRealtime();
  }

  void setActiveConversation(String conversationId) {
    _activeConversationId = conversationId;
  }

  Future<void> refreshConversations() async {
    await _run(() async {
      if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      _conversations = _mockRepository.listConversations();
      return;
    }

      final response = await _apiClient.getConversations(_session.accessToken!);
      _conversations = response.map(_conversationFromApi).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      await _cacheService?.storeConversations(_conversations);
      await _reconcileExpiringState();
    });
  }

  Future<void> loadConversationMessages(String conversationId) async {
    await _run(() async {
      if (!_session.isAuthenticated || !VeilConfig.hasApi) {
        _messagesByConversation[conversationId] = _mockRepository.listMessages(conversationId);
        return;
      }

      final response = await _apiClient.getMessages(_session.accessToken!, conversationId);
      final items = (response['items'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(_messageFromApi)
          .toList();
      _messagesByConversation[conversationId] = items;
      _syncConversationPreviewFromMessages(conversationId);
      await _cacheService?.storeMessages(conversationId, items);
      await _cacheService?.storeConversations(_conversations);
    });
  }

  Future<void> startConversationByHandle(String handle) async {
    await _run(() async {
      if (!_session.isAuthenticated || !VeilConfig.hasApi) {
        await _mockRepository.startConversation(handle);
        _conversations = _mockRepository.listConversations();
        return;
      }

      await _apiClient.createDirectConversation(_session.accessToken!, handle);
      await refreshConversations();
    });
  }

  Future<void> sendText({
    required String conversationId,
    required String body,
    Duration? disappearAfter,
  }) async {
    await _run(() async {
      if (!_session.isAuthenticated || !VeilConfig.hasApi) {
        await _mockRepository.sendText(
          conversationId: conversationId,
          body: body,
          disappearAfter: disappearAfter,
        );
        _messagesByConversation[conversationId] = _mockRepository.listMessages(conversationId);
        _conversations = _mockRepository.listConversations();
        return;
      }

      final conversation = _conversations.firstWhere((item) => item.id == conversationId);
      final bundle = await _fetchPeerBundle(conversation.peerHandle);
      final envelope = await _cryptoEngine.encryptMessage(
        conversationId: conversationId,
        senderDeviceId: _session.deviceId!,
        recipientUserId: bundle.userId,
        body: body,
        messageKind: MessageKind.text,
        recipientBundle: bundle,
        expiresAt: disappearAfter == null ? null : DateTime.now().add(disappearAfter),
      );

      await _apiClient.sendMessage(_session.accessToken!, {
        'conversationId': conversationId,
        'envelope': _envelopeToJson(envelope),
      });
      await loadConversationMessages(conversationId);
      await refreshConversations();
    });
  }

  Future<void> sendAttachmentPlaceholder(
    String conversationId, {
    String filename = 'dossier.enc',
  }) async {
    await _run(() async {
      if (!_session.isAuthenticated || !VeilConfig.hasApi) {
        await _mockRepository.sendAttachment(
          conversationId: conversationId,
          filename: filename,
        );
        _messagesByConversation[conversationId] = _mockRepository.listMessages(conversationId);
        _conversations = _mockRepository.listConversations();
        return;
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
      final envelope = await _cryptoEngine.encryptMessage(
        conversationId: conversationId,
        senderDeviceId: _session.deviceId!,
        recipientUserId: bundle.userId,
        body: 'Encrypted attachment',
        messageKind: MessageKind.file,
        recipientBundle: bundle,
        attachment: attachment,
      );

      await _apiClient.sendMessage(_session.accessToken!, {
        'conversationId': conversationId,
        'envelope': _envelopeToJson(envelope),
      });
      await loadConversationMessages(conversationId);
      await refreshConversations();
    });
  }

  Future<void> markRead(String messageId) async {
    if (!_session.isAuthenticated || !VeilConfig.hasApi) {
      return;
    }
    await _apiClient.markRead(_session.accessToken!, messageId);
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

  Future<void> approveTransfer() async {
    await _run(() async {
      if (_transferSessionId == null || !_session.isAuthenticated || !VeilConfig.hasApi) {
        _transferStatus = 'Start transfer first.';
        return;
      }

      final newDeviceId = 'device-transfer-${DateTime.now().microsecondsSinceEpoch}';
      final identity = await _cryptoEngine.generateDeviceIdentity(newDeviceId);
      await _apiClient.approveTransfer(_session.accessToken!, {
        'sessionId': _transferSessionId,
        'newDeviceName': 'VEIL New Device',
        'platform': 'android',
        'publicIdentityKey': identity.identityPublicKey,
        'signedPrekeyBundle': identity.signedPrekeyBundle,
        'authPublicKey': identity.authPublicKey,
      });
      _transferStatus = 'Approved on old device.';
    });
  }

  Future<void> completeTransfer() async {
    await _run(() async {
      if (_transferSessionId == null || _transferToken == null || !VeilConfig.hasApi) {
        _transferStatus = 'Init and approve transfer first.';
        return;
      }

      await _apiClient.completeTransfer({
        'sessionId': _transferSessionId,
        'transferToken': _transferToken,
      });
      _transferStatus = 'Transfer completed. Old device revoked.';
      _session = _session.copyWith(
        accessToken: null,
        userId: null,
        deviceId: null,
        handle: null,
        displayName: null,
      );
      _conversations = [];
      _messagesByConversation.clear();
      _realtimeService.disconnect();
      _realtimeConnected = false;
    });
  }

  Future<DecryptedMessage> decryptEnvelope(CryptoEnvelope envelope) {
    return _cryptoEngine.decryptMessage(envelope);
  }

  Future<void> _hydrateFromCache() async {
    final cache = _cacheService;
    if (cache == null) {
      return;
    }

    await cache.purgeExpiredMessages();
    _conversations = await cache.readConversations();
    for (final conversation in _conversations) {
      final cachedMessages = await cache.readMessages(conversation.id);
      _messagesByConversation[conversation.id] = cachedMessages
          .map(
            (message) => ChatMessage(
              id: message.id,
              senderDeviceId: message.senderDeviceId,
              sentAt: message.sentAt,
              envelope: message.envelope,
              expiresAt: message.expiresAt,
              isMine: message.senderDeviceId == _session.deviceId,
            ),
          )
          .toList();
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
      onEvent: (event, payload) async {
        if (event == 'conversation.sync' || event == 'message.new' || event == 'message.read') {
          await refreshConversations();
          final activeConversationId = _activeConversationId;
          if (activeConversationId != null) {
            await loadConversationMessages(activeConversationId);
          }
        }
      },
    );
    _realtimeConnected = true;
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
    return ChatMessage(
      id: raw['id'] as String,
      senderDeviceId: raw['senderDeviceId'] as String,
      sentAt: DateTime.parse(raw['serverReceivedAt'] as String),
      envelope: _envelopeFromApi(raw),
      expiresAt: raw['expiresAt'] == null ? null : DateTime.parse(raw['expiresAt'] as String),
      isMine: raw['senderDeviceId'] == _session.deviceId,
    );
  }

  CryptoEnvelope _envelopeFromApi(Map<String, dynamic> raw) {
    final attachment = raw['attachment'] as Map<String, dynamic>?;
    return CryptoEnvelope(
      version: raw['version'] as String? ?? 'veil-envelope-v1-dev',
      conversationId: raw['conversationId'] as String,
      senderDeviceId: raw['senderDeviceId'] as String,
      recipientUserId: '',
      ciphertext: raw['ciphertext'] as String,
      nonce: raw['nonce'] as String,
      messageKind: MessageKind.values.byName(raw['messageType'] as String),
      expiresAt: raw['expiresAt'] == null ? null : DateTime.parse(raw['expiresAt'] as String),
      attachment: attachment == null
          ? null
          : AttachmentReference(
              attachmentId: attachment['attachmentId'] as String,
              storageKey: attachment['storageKey'] as String,
              contentType: attachment['contentType'] as String,
              sizeBytes: attachment['sizeBytes'] as int,
              sha256: attachment['sha256'] as String,
              encryptedKey:
                  (attachment['encryption'] as Map<String, dynamic>)['encryptedKey'] as String,
              nonce: (attachment['encryption'] as Map<String, dynamic>)['nonce'] as String,
            ),
    );
  }

  Map<String, dynamic> _envelopeToJson(CryptoEnvelope envelope) {
    return {
      'version': envelope.version,
      'conversationId': envelope.conversationId,
      'senderDeviceId': envelope.senderDeviceId,
      'recipientUserId': envelope.recipientUserId,
      'ciphertext': envelope.ciphertext,
      'nonce': envelope.nonce,
      'messageType': envelope.messageKind.name,
      'expiresAt': envelope.expiresAt?.toIso8601String(),
      'attachment': envelope.attachment == null
          ? null
          : {
              'attachmentId': envelope.attachment!.attachmentId,
              'storageKey': envelope.attachment!.storageKey,
              'contentType': envelope.attachment!.contentType,
              'sizeBytes': envelope.attachment!.sizeBytes,
              'sha256': envelope.attachment!.sha256,
              'encryption': {
                'encryptedKey': envelope.attachment!.encryptedKey,
                'nonce': envelope.attachment!.nonce,
                'algorithmHint': 'dev-wrap',
              },
            },
    };
  }

  Future<void> _run(Future<void> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _errorMessage = error.toString();
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
