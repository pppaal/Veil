import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_temp_file_store.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

void main() {
  test('sendText drains outbox and replaces optimistic message with server ack',
      () async {
    final api = _FakeVeilApiClient();
    final cache = _MemoryConversationCache();
    final crypto = createDefaultCryptoAdapter();
    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
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

  test('sendText prefers the active device bundle from the local directory response',
      () async {
    final api = _FakeVeilApiClient();
    final crypto = createDefaultCryptoAdapter();
    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
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

    await controller.sendText(conversationId: 'conv-1', body: 'directory aware');
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(api.sentPayloads, hasLength(1));
    final payload = api.sentPayloads.single['envelope'] as Map<String, dynamic>;
    expect(payload['recipientUserId'], 'user-selene');
    final refreshedConversation = controller.conversations.firstWhere((item) => item.id == 'conv-1');
    expect(refreshedConversation.recipientBundle.deviceId, 'device-selene-primary');
    expect(refreshedConversation.recipientBundle.identityPublicKey, 'pub-selene-primary');
    expect(refreshedConversation.sessionState, isNotNull);
    expect(
      refreshedConversation.sessionState?.sessionEnvelopeVersion,
      crypto.envelopeCodec.defaultEnvelopeVersion,
    );
  });

  test(
      'applySession restores pending messages from cache and retryPendingMessages drains them',
      () async {
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
    final crypto = createDefaultCryptoAdapter();

    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
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

  test('loadOlderConversationMessages appends older pages without reordering',
      () async {
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
    final crypto = createDefaultCryptoAdapter();

    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
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

  test('reconnect after temporary network loss drains queued outbound messages',
      () async {
    final api = _FakeVeilApiClient(failSendAttempts: 1);
    final realtime = _FakeRealtimeService();
    final crypto = createDefaultCryptoAdapter();
    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
      realtimeService: realtime,
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

    await controller.sendText(conversationId: 'conv-1', body: 'hold the line');
    await Future<void>.delayed(const Duration(milliseconds: 25));

    expect(controller.pendingCountFor('conv-1'), 1);
    expect(controller.messagesFor('conv-1').single.deliveryState,
        MessageDeliveryState.pending);

    realtime.emitConnection(false);
    realtime.emitConnection(true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.pendingCountFor('conv-1'), 0);
    expect(controller.messagesFor('conv-1').single.id, 'srv-1');
    expect(api.sentPayloads, hasLength(1));
  });

  test(
      'stale socket reconnect backfills latest page for the active conversation',
      () async {
    final api = _FakeVeilApiClient(
      pagedMessages: {
        const _PagedQuery('conv-1', null): {
          'items': [
            _FakeVeilApiClient.messageJson(
              id: 'srv-10',
              clientMessageId: 'client-10',
              conversationId: 'conv-1',
              senderDeviceId: 'device-selene',
              conversationOrder: 10,
              ciphertext: 'opaque-10',
              nonce: 'nonce-10',
            ),
          ],
          'nextCursor': null,
        },
      },
    );
    final realtime = _FakeRealtimeService();
    final crypto = createDefaultCryptoAdapter();
    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
      realtimeService: realtime,
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

    controller.setActiveConversation('conv-1');
    realtime.emitConnection(false);
    realtime.emitConnection(true);
    await Future<void>.delayed(const Duration(milliseconds: 260));

    expect(controller.messagesFor('conv-1').single.id, 'srv-10');
    expect(
        api.messageFetches
            .where((entry) => entry.conversationId == 'conv-1')
            .length,
        greaterThan(0));
  });

  test('failed attachment upload remains queued for retry and succeeds later',
      () async {
    final api = _FakeVeilApiClient(failUploadAttempts: 1);
    final tempStore = _FakeAttachmentTempFileStore();
    final crypto = createDefaultCryptoAdapter();
    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
      realtimeService: _FakeRealtimeService(),
      cacheService: _MemoryConversationCache(),
      attachmentTempFileStore: tempStore,
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

    await controller.sendAttachmentPlaceholder('conv-1', filename: 'brief.enc');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(controller.pendingCountFor('conv-1'), 1);
    expect(
      controller.messagesFor('conv-1').single.deliveryState,
      MessageDeliveryState.uploading,
    );

    await controller.retryPendingMessages('conv-1');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(controller.pendingCountFor('conv-1'), 0);
    expect(controller.messagesFor('conv-1').single.deliveryState,
        MessageDeliveryState.sent);
    expect(api.completedUploads, contains('attachment-2'));
    expect(tempStore.deletedPaths, isNotEmpty);
  });

  test(
      'late receipt updates are buffered until the message is available locally',
      () async {
    final api = _FakeVeilApiClient(
      pagedMessages: {
        const _PagedQuery('conv-1', null): {
          'items': [
            _FakeVeilApiClient.messageJson(
              id: 'srv-late',
              clientMessageId: 'client-late',
              conversationId: 'conv-1',
              senderDeviceId: 'device-local',
              conversationOrder: 4,
              ciphertext: 'opaque-late',
              nonce: 'nonce-late',
            ),
          ],
          'nextCursor': null,
        },
      },
    );
    final realtime = _FakeRealtimeService();
    final crypto = createDefaultCryptoAdapter();
    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
      realtimeService: realtime,
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

    realtime.emit('message.read', {
      'messageId': 'srv-late',
      'readAt': DateTime.utc(2026, 3, 30, 12, 30, 0).toIso8601String(),
    });

    await controller.loadConversationMessages('conv-1');

    final message = controller.messagesFor('conv-1').single;
    expect(message.id, 'srv-late');
    expect(message.deliveryState, MessageDeliveryState.read);
    expect(message.readAt, isNotNull);
  });

  test('searchLoadedMessageIds matches locally decrypted message bodies',
      () async {
    final api = _FakeVeilApiClient(
      pagedMessages: {
        const _PagedQuery('conv-1', null): {
          'items': [
            _FakeVeilApiClient.messageJson(
              id: 'srv-search-1',
              clientMessageId: 'client-search-1',
              conversationId: 'conv-1',
              senderDeviceId: 'device-local',
              conversationOrder: 1,
              ciphertext: 'opaque-search-1',
              nonce: 'nonce-search-1',
            ),
            _FakeVeilApiClient.messageJson(
              id: 'srv-search-2',
              clientMessageId: 'client-search-2',
              conversationId: 'conv-1',
              senderDeviceId: 'device-selene',
              conversationOrder: 2,
              ciphertext: 'opaque-search-2',
              nonce: 'nonce-search-2',
            ),
          ],
          'nextCursor': null,
        },
      },
    );
    final crypto = createDefaultCryptoAdapter();
    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
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

    await controller.sendText(conversationId: 'conv-1', body: 'helios signal');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final matches = await controller.searchLoadedMessageIds(
      'conv-1',
      query: 'helios',
    );

    expect(matches, hasLength(1));
    expect(matches.single, 'srv-1');
  });

  test('coalesces repeated realtime sync hints into a single backfill pass',
      () async {
    final api = _FakeVeilApiClient(
      pagedMessages: {
        const _PagedQuery('conv-1', null): {
          'items': [
            _FakeVeilApiClient.messageJson(
              id: 'srv-hint-1',
              clientMessageId: 'client-hint-1',
              conversationId: 'conv-1',
              senderDeviceId: 'device-selene',
              conversationOrder: 1,
              ciphertext: 'opaque-hint-1',
              nonce: 'nonce-hint-1',
            ),
          ],
          'nextCursor': null,
        },
      },
    );
    final realtime = _FakeRealtimeService();
    final crypto = createDefaultCryptoAdapter();
    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
      realtimeService: realtime,
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

    api.conversationFetchCount = 0;
    api.messageFetches.clear();

    realtime.emit(
        'conversation.sync', {'conversationId': 'conv-1', 'reason': 'message'});
    realtime.emit(
        'conversation.sync', {'conversationId': 'conv-1', 'reason': 'refresh'});
    realtime.emit(
        'conversation.sync', {'conversationId': 'conv-1', 'reason': 'message'});
    await Future<void>.delayed(const Duration(milliseconds: 260));

    expect(api.conversationFetchCount, 1);
    expect(
      api.messageFetches
          .where((entry) => entry.conversationId == 'conv-1')
          .length,
      1,
    );
  });

  test('attachment download resolution exposes a transient resolving state',
      () async {
    final api = _FakeVeilApiClient(
        downloadTicketDelay: const Duration(milliseconds: 50));
    final crypto = createDefaultCryptoAdapter();
    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
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

    final future = controller.getAttachmentDownloadUrl('attachment-77');
    expect(controller.isResolvingAttachment('attachment-77'), isTrue);

    final ticketUrl = await future;
    expect(ticketUrl, 'https://signed-download.invalid/attachment-77');
    expect(controller.isResolvingAttachment('attachment-77'), isFalse);
  });

  test('canceling an attachment upload preserves the draft for retry',
      () async {
    final api =
        _FakeVeilApiClient(uploadDelay: const Duration(milliseconds: 80));
    final tempStore = _FakeAttachmentTempFileStore();
    final crypto = createDefaultCryptoAdapter();
    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
      realtimeService: _FakeRealtimeService(),
      cacheService: _MemoryConversationCache(),
      attachmentTempFileStore: tempStore,
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

    await controller.sendAttachmentPlaceholder('conv-1', filename: 'brief.enc');
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final clientMessageId =
        controller.messagesFor('conv-1').single.clientMessageId!;
    await controller.cancelPendingAttachment(clientMessageId);
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(controller.pendingCountFor('conv-1'), 1);
    expect(controller.messagesFor('conv-1').single.deliveryState,
        MessageDeliveryState.failed);
    expect(controller.attachmentTransferForMessage(clientMessageId)?.phase,
        AttachmentTransferPhase.canceled);
    expect(tempStore.deletedPaths, isEmpty);
  });

  test('archive search returns filtered local results from cached history',
      () async {
    final now = DateTime.now();
    final crypto = createDefaultCryptoAdapter();
    final cache = _MemoryConversationCache(
      conversations: [
        ConversationPreview(
          id: 'conv-1',
          peerHandle: 'selene',
          peerDisplayName: 'Selene',
          recipientBundle: const KeyBundle(
            userId: 'user-selene',
            deviceId: 'device-selene',
            handle: 'selene',
            identityPublicKey: 'pub-selene',
            signedPrekeyBundle: 'prekey-selene',
          ),
          lastEnvelope: null,
          updatedAt: now,
        ),
      ],
      messages: {
        'conv-1': [
          ChatMessage(
            id: 'msg-1',
            senderDeviceId: 'device-local',
            sentAt: now.subtract(const Duration(days: 1)),
            envelope: const CryptoEnvelope(
              version: 'veil-envelope-v1-dev',
              conversationId: 'conv-1',
              senderDeviceId: 'device-local',
              recipientUserId: 'user-selene',
              ciphertext: 'opaque-1',
              nonce: 'nonce-1',
              messageKind: MessageKind.text,
            ),
            searchableBody: 'orbit update',
            isMine: true,
          ),
          ChatMessage(
            id: 'msg-2',
            senderDeviceId: 'device-selene',
            sentAt: now.subtract(const Duration(hours: 8)),
            envelope: const CryptoEnvelope(
              version: 'veil-envelope-v1-dev',
              conversationId: 'conv-1',
              senderDeviceId: 'device-selene',
              recipientUserId: 'user-local',
              ciphertext: 'opaque-2',
              nonce: 'nonce-2',
              messageKind: MessageKind.file,
            ),
            searchableBody: 'orbit attachment',
            isMine: false,
          ),
        ],
      },
    );

    final controller = VeilMessengerController(
      apiClient: _FakeVeilApiClient(),
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
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

    final results = await controller.searchMessageArchive(
      query: const MessageSearchQuery(
        query: 'orbit',
        senderFilter: MessageSearchSenderFilter.theirs,
        typeFilter: MessageSearchTypeFilter.file,
      ),
    );

    expect(results.items, hasLength(1));
    expect(results.items.single.messageId, 'msg-2');
    expect(results.items.single.isMine, isFalse);
  });

  test('archive search pages forward without duplicating prior results',
      () async {
    final now = DateTime.now();
    final crypto = createDefaultCryptoAdapter();
    final cache = _MemoryConversationCache(
      conversations: [
        ConversationPreview(
          id: 'conv-1',
          peerHandle: 'selene',
          peerDisplayName: 'Selene',
          recipientBundle: const KeyBundle(
            userId: 'user-selene',
            deviceId: 'device-selene',
            handle: 'selene',
            identityPublicKey: 'pub-selene',
            signedPrekeyBundle: 'prekey-selene',
          ),
          lastEnvelope: null,
          updatedAt: now,
        ),
      ],
      messages: {
        'conv-1': List<ChatMessage>.generate(
          3,
          (index) => ChatMessage(
            id: 'msg-$index',
            senderDeviceId: 'device-local',
            sentAt: now.subtract(Duration(minutes: index)),
            envelope: CryptoEnvelope(
              version: 'veil-envelope-v1-dev',
              conversationId: 'conv-1',
              senderDeviceId: 'device-local',
              recipientUserId: 'user-selene',
              ciphertext: 'opaque-$index',
              nonce: 'nonce-$index',
              messageKind: MessageKind.text,
            ),
            searchableBody: 'archive page $index',
            isMine: true,
          ),
        ),
      },
    );

    final controller = VeilMessengerController(
      apiClient: _FakeVeilApiClient(),
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
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

    final firstPage = await controller.searchMessageArchive(
      query: const MessageSearchQuery(query: 'archive', limit: 2),
    );
    final secondPage = await controller.searchMessageArchive(
      query: MessageSearchQuery(
        query: 'archive',
        limit: 2,
        beforeSentAt: firstPage.nextBeforeSentAt,
        beforeMessageId: firstPage.nextBeforeMessageId,
      ),
    );

    expect(firstPage.items.map((item) => item.messageId).toList(), ['msg-0', 'msg-1']);
    expect(firstPage.hasMore, isTrue);
    expect(secondPage.items.map((item) => item.messageId).toList(), ['msg-2']);
  });
}

class _FakeVeilApiClient extends VeilApiClient {
  _FakeVeilApiClient({
    Map<_PagedQuery, Map<String, dynamic>>? pagedMessages,
    this.failSendAttempts = 0,
    this.failUploadAttempts = 0,
    this.downloadTicketDelay = Duration.zero,
    this.uploadDelay = Duration.zero,
  })  : _pagedMessages = pagedMessages ?? {},
        super(baseUrl: 'http://localhost:3000/v1');

  final List<Map<String, dynamic>> sentPayloads = [];
  final List<String> completedUploads = [];
  final List<_PagedQuery> messageFetches = [];
  int conversationFetchCount = 0;
  final Map<_PagedQuery, Map<String, dynamic>> _pagedMessages;
  final String _defaultEnvelopeVersion =
      createDefaultCryptoAdapter().envelopeCodec.defaultEnvelopeVersion;
  int failSendAttempts;
  int failUploadAttempts;
  int failDownloadAttempts = 0;
  final Duration downloadTicketDelay;
  final Duration uploadDelay;
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
      'serverReceivedAt':
          DateTime.utc(2026, 3, 30, 12, conversationOrder).toIso8601String(),
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
      version: _defaultEnvelopeVersion,
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
    conversationFetchCount += 1;
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
      'user': {
        'activeDeviceId': 'device-$handle-primary',
      },
      'bundle': {
        'userId': 'user-$handle',
        'deviceId': 'device-$handle',
        'handle': handle,
        'identityPublicKey': 'pub-$handle',
        'signedPrekeyBundle': 'prekey-$handle',
      },
      'deviceBundles': [
        {
          'userId': 'user-$handle',
          'deviceId': 'device-$handle-primary',
          'handle': handle,
          'identityPublicKey': 'pub-$handle-primary',
          'signedPrekeyBundle': 'prekey-$handle-primary',
        },
        {
          'userId': 'user-$handle',
          'deviceId': 'device-$handle-secondary',
          'handle': handle,
          'identityPublicKey': 'pub-$handle-secondary',
          'signedPrekeyBundle': 'prekey-$handle-secondary',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getMessages(
    String accessToken,
    String conversationId, {
    String? cursor,
    int limit = 50,
  }) async {
    messageFetches.add(_PagedQuery(conversationId, cursor));
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
    if (failSendAttempts > 0) {
      failSendAttempts -= 1;
      throw VeilApiException(
        'The VEIL relay failed to complete the request. Try again shortly.',
        statusCode: 503,
      );
    }
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
        'serverReceivedAt':
            DateTime.utc(2026, 3, 30, 12, _serverCounter).toIso8601String(),
        'deletedAt': null,
        'deliveredAt': null,
        'readAt': null,
      },
      'idempotent': false,
    };
  }

  @override
  Future<Map<String, dynamic>> createUploadTicket(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    final ticketId = 'attachment-${completedUploads.length + 1}';
    return {
      'attachmentId': ticketId,
      'upload': {
        'storageKey': 'attachments/$ticketId/blob',
        'uploadUrl': 'https://signed-upload.invalid/$ticketId',
        'headers': {
          'Content-Type': body['contentType'],
          'Content-Length': body['sizeBytes'].toString(),
          'Cache-Control': 'no-store',
        },
        'contentType': body['contentType'],
        'sizeBytes': body['sizeBytes'],
        'expiresAt': DateTime.utc(2026, 3, 30, 12, 10, 0).toIso8601String(),
      },
      'constraints': {
        'maxSizeBytes': 50 * 1024 * 1024,
        'allowedMimeTypes': const ['image/png', 'application/octet-stream'],
      },
    };
  }

  @override
  Future<void> uploadEncryptedBlobFile({
    required String uploadUrl,
    required Map<String, dynamic> headers,
    required dynamic file,
    void Function(int sentBytes, int totalBytes)? onProgress,
    AttachmentUploadCancellationSignal? cancellationSignal,
  }) async {
    if (uploadDelay > Duration.zero) {
      await Future<void>.delayed(uploadDelay);
    }
    if (cancellationSignal?.isCanceled ?? false) {
      throw VeilApiException(
        'Attachment upload canceled.',
        code: 'attachment_upload_canceled',
      );
    }
    if (failUploadAttempts > 0) {
      failUploadAttempts -= 1;
      throw VeilApiException(
        'Attachment upload failed: HTTP 503',
        code: 'attachment_upload_failed',
        statusCode: 503,
      );
    }
    onProgress?.call(1024, 2048);
    onProgress?.call(2048, 2048);
  }

  @override
  Future<Map<String, dynamic>> completeUpload(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    completedUploads.add(body['attachmentId'] as String);
    return {
      'attachmentId': body['attachmentId'],
      'uploadStatus': body['uploadStatus'],
    };
  }

  @override
  Future<Map<String, dynamic>> getDownloadTicket(
    String accessToken,
    String attachmentId,
  ) async {
    if (downloadTicketDelay > Duration.zero) {
      await Future<void>.delayed(downloadTicketDelay);
    }
    if (failDownloadAttempts > 0) {
      failDownloadAttempts -= 1;
      throw VeilApiException(
        'Attachment download ticket failed: HTTP 503',
        code: 'attachment_download_failed',
        statusCode: 503,
      );
    }
    return {
      'ticket': {
        'attachmentId': attachmentId,
        'downloadUrl': 'https://signed-download.invalid/$attachmentId',
      },
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

  void emitConnection(bool connected) {
    _onConnectionChanged?.call(connected);
  }
}

class _FakeAttachmentTempFileStore implements AttachmentTempFileStore {
  final List<String> deletedPaths = <String>[];

  @override
  Future<void> cleanupOrphanedFiles({
    Iterable<String> keepPaths = const <String>[],
    Duration maxAge = DefaultAttachmentTempFileStore.defaultMaxAge,
    int maxFileCount = DefaultAttachmentTempFileStore.defaultMaxFileCount,
  }) async {}

  @override
  Future<AttachmentTempBlob> createOpaqueBlob({
    required String filename,
    required int sizeBytes,
    String? existingPath,
  }) async {
    return AttachmentTempBlob(
      path: existingPath ?? 'temp://$filename',
      filename: filename,
      sizeBytes: sizeBytes,
      sha256: 'sha256-$filename',
      createdAt: DateTime.utc(2026, 3, 30, 12, 0, 0),
    );
  }

  @override
  Future<void> deleteTempFile(String? path) async {
    if (path != null) {
      deletedPaths.add(path);
    }
  }

  @override
  Future<void> purgeAll() async {
    deletedPaths.add('__purged__');
  }
}

class _MemoryConversationCache implements ConversationCacheService {
  _MemoryConversationCache({
    List<ConversationPreview>? conversations,
    Map<String, List<ChatMessage>>? messages,
    List<PendingMessageRecord>? pendingMessages,
    Map<String, ConversationPagingState>? pagingStates,
  })  : _conversations = {
          for (final item in conversations ?? const []) item.id: item
        },
        _messages = {
          for (final entry
              in (messages ?? const <String, List<ChatMessage>>{}).entries)
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
  final Map<String, Map<String, String>> _searchIndex = {};

  @override
  Future<void> purgeExpiredMessages() async {}

  @override
  Future<void> clearAll() async {
    _conversations.clear();
    _messages.clear();
    _pendingMessages.clear();
    _pagingStates.clear();
    _searchIndex.clear();
  }

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
  Future<void> indexMessageBody({
    required String conversationId,
    required String messageId,
    required String searchableBody,
  }) async {
    _searchIndex.putIfAbsent(
        conversationId, () => <String, String>{})[messageId] = searchableBody;
  }

  @override
  Future<List<String>> searchCachedMessageIds({
    required String conversationId,
    required String query,
  }) async {
    final normalized = query.trim().toLowerCase();
    return (_searchIndex[conversationId] ?? const <String, String>{})
        .entries
        .where((entry) => entry.value.contains(normalized))
        .map((entry) => entry.key)
        .toList(growable: false);
  }

  @override
  Future<MessageSearchPage> searchMessageArchive({
    required MessageSearchQuery query,
    required String currentDeviceId,
  }) async {
    final normalized = query.normalizedQuery;
    final cutoff = query.resolveCutoff(DateTime.now());
    final results = <MessageSearchResult>[];
    for (final conversation in _conversations.values) {
      if (query.conversationId != null &&
          conversation.id != query.conversationId) {
        continue;
      }
      for (final message
          in _messages[conversation.id] ?? const <ChatMessage>[]) {
        final body = message.searchableBody ??
            _searchIndex[conversation.id]?[message.id];
        if (body == null || !body.contains(normalized)) {
          continue;
        }
        if (query.beforeSentAt != null &&
            !message.sentAt.isBefore(query.beforeSentAt!)) {
          if (!message.sentAt.isAtSameMomentAs(query.beforeSentAt!) ||
              query.beforeMessageId == null ||
              message.id.compareTo(query.beforeMessageId!) >= 0) {
            continue;
          }
        }
        if (cutoff != null && message.sentAt.isBefore(cutoff)) {
          continue;
        }
        final isMine = message.senderDeviceId == currentDeviceId;
        if (query.senderFilter == MessageSearchSenderFilter.mine && !isMine) {
          continue;
        }
        if (query.senderFilter == MessageSearchSenderFilter.theirs && isMine) {
          continue;
        }
        if (!_matchesTypeFilter(
            message.envelope.messageKind, query.typeFilter)) {
          continue;
        }
        results.add(
          MessageSearchResult(
            conversationId: conversation.id,
            messageId: message.id,
            peerHandle: conversation.peerHandle,
            peerDisplayName: conversation.peerDisplayName,
            sentAt: message.sentAt,
            messageKind: message.envelope.messageKind,
            isMine: isMine,
            bodySnippet: body,
            conversationOrder: message.conversationOrder,
          ),
        );
      }
    }
    results.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    final pageItems = results.take(query.limit).toList(growable: false);
    if (results.length <= query.limit) {
      return MessageSearchPage(items: pageItems);
    }
    final last = pageItems.last;
    return MessageSearchPage(
      items: pageItems,
      nextBeforeSentAt: last.sentAt,
      nextBeforeMessageId: last.messageId,
    );
  }

  @override
  Future<void> storeConversations(
      List<ConversationPreview> conversations) async {
    for (final conversation in conversations) {
      _conversations[conversation.id] = conversation;
    }
  }

  @override
  Future<void> storeMessages(
      String conversationId, List<ChatMessage> messages) async {
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

  bool _matchesTypeFilter(MessageKind kind, MessageSearchTypeFilter filter) {
    return switch (filter) {
      MessageSearchTypeFilter.all => true,
      MessageSearchTypeFilter.text => kind == MessageKind.text,
      MessageSearchTypeFilter.media =>
        kind == MessageKind.image || kind == MessageKind.file,
      MessageSearchTypeFilter.file => kind == MessageKind.file,
      MessageSearchTypeFilter.system => kind == MessageKind.system,
    };
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



