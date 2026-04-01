import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

void main() {
  test('sendText drains outbox and replaces optimistic message with server ack', () async {
    final api = _FakeVeilApiClient();
    final cache = _MemoryConversationCache();
    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: MockCryptoEngine(),
      realtimeService: _FakeRealtimeService(),
      cacheService: cache,
    );

    await controller.applySession(
      const AppSessionState(
        accessToken: 'token',
        userId: 'user-local',
        deviceId: 'device-local',
        handle: 'atlas',
        displayName: 'Atlas',
        onboardingAccepted: true,
        locked: false,
        initializing: false,
      ),
    );

    await controller.sendText(conversationId: 'conv-1', body: 'hello veil');
    await Future<void>.delayed(const Duration(milliseconds: 25));

    final messages = controller.messagesFor('conv-1');
    expect(messages, hasLength(1));
    expect(messages.first.id, 'srv-1');
    expect(messages.first.deliveryState, MessageDeliveryState.sent);
    expect(messages.first.clientMessageId, isNotNull);
    expect(controller.pendingCountFor('conv-1'), 0);
    expect(api.sentPayloads, hasLength(1));
  });

  test('applySession restores pending messages from cache and retryPendingMessages drains them', () async {
    final api = _FakeVeilApiClient();
    final cache = _MemoryConversationCache(
      pendingMessages: [
        PendingMessageRecord(
          clientMessageId: 'client-retry-1',
          conversationId: 'conv-1',
          senderDeviceId: 'device-local',
          recipientUserId: 'user-selene',
          envelope: api.makeEnvelope(
            conversationId: 'conv-1',
            senderDeviceId: 'device-local',
            recipientUserId: 'user-selene',
            ciphertext: 'opaque-retry',
            nonce: 'nonce-retry',
          ),
          createdAt: DateTime.utc(2026, 3, 30, 12, 0, 0),
          retryCount: 1,
          state: MessageDeliveryState.failed,
          errorMessage: 'Relay unavailable',
        ),
      ],
    );

    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: MockCryptoEngine(),
      realtimeService: _FakeRealtimeService(),
      cacheService: cache,
    );

    await controller.applySession(
      const AppSessionState(
        accessToken: 'token',
        userId: 'user-local',
        deviceId: 'device-local',
        handle: 'atlas',
        displayName: 'Atlas',
        onboardingAccepted: true,
        locked: false,
        initializing: false,
      ),
    );

    expect(controller.pendingCountFor('conv-1'), 1);

    await controller.retryPendingMessages('conv-1');
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(controller.pendingCountFor('conv-1'), 0);
    expect(controller.messagesFor('conv-1').single.id, 'srv-1');
    expect(api.sentPayloads, hasLength(1));
  });

  test('loadOlderConversationMessages appends older pages without reordering', () async {
    final api = _FakeVeilApiClient(
      pagedMessages: {
        const _PagedQuery('conv-1', null): {
          'items': [
            _FakeVeilApiClient.messageJson(
              id: 'srv-2',
              clientMessageId: 'client-2',
              conversationId: 'conv-1',
              senderDeviceId: 'device-local',
              conversationOrder: 2,
              ciphertext: 'opaque-2',
              nonce: 'nonce-2',
            ),
            _FakeVeilApiClient.messageJson(
              id: 'srv-3',
              clientMessageId: 'client-3',
              conversationId: 'conv-1',
              senderDeviceId: 'device-local',
              conversationOrder: 3,
              ciphertext: 'opaque-3',
              nonce: 'nonce-3',
            ),
          ],
          'nextCursor': 'srv-2',
        },
        const _PagedQuery('conv-1', 'srv-2'): {
          'items': [
            _FakeVeilApiClient.messageJson(
              id: 'srv-1',
              clientMessageId: 'client-1',
              conversationId: 'conv-1',
              senderDeviceId: 'device-local',
              conversationOrder: 1,
              ciphertext: 'opaque-1',
              nonce: 'nonce-1',
            ),
          ],
          'nextCursor': null,
        },
      },
    );

    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: MockCryptoEngine(),
      realtimeService: _FakeRealtimeService(),
      cacheService: _MemoryConversationCache(),
    );

    await controller.applySession(
      const AppSessionState(
        accessToken: 'token',
        userId: 'user-local',
        deviceId: 'device-local',
        handle: 'atlas',
        displayName: 'Atlas',
        onboardingAccepted: true,
        locked: false,
        initializing: false,
      ),
    );

    await controller.loadConversationMessages('conv-1');
    await controller.loadOlderConversationMessages('conv-1');

    expect(
      controller.messagesFor('conv-1').map((message) => message.id).toList(),
      ['srv-1', 'srv-2', 'srv-3'],
    );
    expect(controller.hasMoreHistoryFor('conv-1'), isFalse);
  });
}

class _FakeVeilApiClient extends VeilApiClient {
  _FakeVeilApiClient({
    Map<_PagedQuery, Map<String, dynamic>>? pagedMessages,
  })  : _pagedMessages = pagedMessages ?? {},
        super(baseUrl: 'http://localhost:3000/v1');

  final List<Map<String, dynamic>> sentPayloads = [];
  final Map<_PagedQuery, Map<String, dynamic>> _pagedMessages;
  int _serverCounter = 0;

  static Map<String, dynamic> messageJson({
    required String id,
    required String clientMessageId,
    required String conversationId,
    required String senderDeviceId,
    required int conversationOrder,
    required String ciphertext,
    required String nonce,
  }) {
    return {
      'id': id,
      'clientMessageId': clientMessageId,
      'conversationId': conversationId,
      'senderDeviceId': senderDeviceId,
      'conversationOrder': conversationOrder,
      'ciphertext': ciphertext,
      'nonce': nonce,
      'messageType': 'text',
      'expiresAt': null,
      'serverReceivedAt': DateTime.utc(2026, 3, 30, 12, conversationOrder).toIso8601String(),
      'deletedAt': null,
      'deliveredAt': null,
      'readAt': null,
    };
  }

  CryptoEnvelope makeEnvelope({
    required String conversationId,
    required String senderDeviceId,
    required String recipientUserId,
    required String ciphertext,
    required String nonce,
  }) {
    return CryptoEnvelope(
      version: devEnvelopeVersion,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientUserId: recipientUserId,
      ciphertext: ciphertext,
      nonce: nonce,
      messageKind: MessageKind.text,
    );
  }

  @override
  Future<List<dynamic>> getConversations(String accessToken) async {
    return [
      {
        'id': 'conv-1',
        'type': 'direct',
        'createdAt': DateTime.utc(2026, 3, 30, 10, 0, 0).toIso8601String(),
        'members': [
          {
            'userId': 'user-local',
            'handle': 'atlas',
            'displayName': 'Atlas',
          },
          {
            'userId': 'user-selene',
            'handle': 'selene',
            'displayName': 'Selene',
          },
        ],
        'lastMessage': null,
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> getKeyBundle(String handle) async {
    return {
      'bundle': {
        'userId': 'user-$handle',
        'deviceId': 'device-$handle',
        'handle': handle,
        'identityPublicKey': 'pub-$handle',
        'signedPrekeyBundle': 'prekey-$handle',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getMessages(
    String accessToken,
    String conversationId, {
    String? cursor,
    int limit = 50,
  }) async {
    final paged = _pagedMessages[_PagedQuery(conversationId, cursor)];
    if (paged != null) {
      return paged;
    }

    return {
      'items': const <Map<String, dynamic>>[],
      'nextCursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> sendMessage(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    sentPayloads.add(body);
    _serverCounter += 1;
    final envelope = body['envelope'] as Map<String, dynamic>;
    return {
      'message': {
        'id': 'srv-$_serverCounter',
        'clientMessageId': body['clientMessageId'],
        'conversationId': body['conversationId'],
        'senderDeviceId': envelope['senderDeviceId'],
        'conversationOrder': _serverCounter,
        'ciphertext': envelope['ciphertext'],
        'nonce': envelope['nonce'],
        'messageType': envelope['messageType'],
        'attachment': envelope['attachment'],
        'expiresAt': envelope['expiresAt'],
        'serverReceivedAt': DateTime.utc(2026, 3, 30, 12, _serverCounter).toIso8601String(),
        'deletedAt': null,
        'deliveredAt': null,
        'readAt': null,
      },
      'idempotent': false,
    };
  }
}

class _FakeRealtimeService extends RealtimeService {
  void Function(String event, dynamic payload)? _onEvent;
  void Function(bool connected)? _onConnectionChanged;

  @override
  void connect({
    required String baseUrl,
    required String accessToken,
    required void Function(String event, dynamic payload) onEvent,
    void Function(bool connected)? onConnectionChanged,
  }) {
    _onEvent = onEvent;
    _onConnectionChanged = onConnectionChanged;
    _onConnectionChanged?.call(true);
  }

  @override
  void disconnect() {
    _onConnectionChanged?.call(false);
  }

  void emit(String event, dynamic payload) {
    _onEvent?.call(event, payload);
  }
}

class _MemoryConversationCache implements ConversationCacheService {
  _MemoryConversationCache({
    List<ConversationPreview>? conversations,
    Map<String, List<ChatMessage>>? messages,
    List<PendingMessageRecord>? pendingMessages,
    Map<String, ConversationPagingState>? pagingStates,
  })  : _conversations = {for (final item in conversations ?? const []) item.id: item},
        _messages = {
          for (final entry in (messages ?? const <String, List<ChatMessage>>{}).entries)
            entry.key: List<ChatMessage>.from(entry.value),
        },
        _pendingMessages = {
          for (final item in pendingMessages ?? const <PendingMessageRecord>[])
            item.clientMessageId: item,
        },
        _pagingStates = {...?pagingStates};

  final Map<String, ConversationPreview> _conversations;
  final Map<String, List<ChatMessage>> _messages;
  final Map<String, PendingMessageRecord> _pendingMessages;
  final Map<String, ConversationPagingState> _pagingStates;

  @override
  Future<void> purgeExpiredMessages() async {}

  @override
  Future<List<ConversationPreview>> readConversations() async {
    return _conversations.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<List<ChatMessage>> readMessages(String conversationId) async {
    return List<ChatMessage>.from(_messages[conversationId] ?? const []);
  }

  @override
  Future<ConversationPagingState> readPagingState(String conversationId) async {
    return _pagingStates[conversationId] ?? const ConversationPagingState();
  }

  @override
  Future<List<PendingMessageRecord>> readPendingMessages() async {
    return _pendingMessages.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<void> removePendingMessage(String clientMessageId) async {
    _pendingMessages.remove(clientMessageId);
  }

  @override
  Future<void> storeConversations(List<ConversationPreview> conversations) async {
    for (final conversation in conversations) {
      _conversations[conversation.id] = conversation;
    }
  }

  @override
  Future<void> storeMessages(String conversationId, List<ChatMessage> messages) async {
    _messages[conversationId] = List<ChatMessage>.from(messages);
  }

  @override
  Future<void> storePagingState(
    String conversationId, {
    String? nextCursor,
    required bool hasMoreHistory,
    DateTime? lastSyncedAt,
  }) async {
    _pagingStates[conversationId] = ConversationPagingState(
      nextCursor: nextCursor,
      hasMoreHistory: hasMoreHistory,
      lastSyncedAt: lastSyncedAt,
    );
  }

  @override
  Future<void> upsertPendingMessage(PendingMessageRecord pending) async {
    _pendingMessages[pending.clientMessageId] = pending;
  }
}

class _PagedQuery {
  const _PagedQuery(this.conversationId, this.cursor);

  final String conversationId;
  final String? cursor;

  @override
  bool operator ==(Object other) {
    return other is _PagedQuery &&
        other.conversationId == conversationId &&
        other.cursor == cursor;
  }

  @override
  int get hashCode => Object.hash(conversationId, cursor);
}
