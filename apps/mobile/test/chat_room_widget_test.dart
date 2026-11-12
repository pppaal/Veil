import 'dart:io' show HttpDate;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/core/storage/in_memory_message_content_store.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

void main() {
  testWidgets('chat room shows delivery badge and local search context', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final adapter = createDefaultCryptoAdapter();
    final envelope = await adapter.messaging.encryptMessage(
      conversationId: 'conv-1',
      senderDeviceId: 'device-local',
      recipientUserId: 'user-peer',
      body: 'Orbit relay window',
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-peer',
        deviceId: 'device-peer',
        handle: 'selene',
        identityPublicKey: 'pub-peer',
        signedPrekeyBundle: 'bundle-peer',
      ),
    );
    final api = _FakeChatApiClient(envelope);
    // This device cannot open what it sealed: its own messages render from
    // the content it stored before sending, which the ack moved under the
    // relay's id.
    final cache = _MemoryConversationCache();
    final storedAt = DateTime.utc(2026, 4, 7, 9, 29);
    await cache.put(MessageContentRecord(
      messageKey: 'msg-1',
      conversationId: 'conv-1',
      serverMessageId: 'msg-1',
      body: 'Orbit relay window',
      kind: MessageKind.text,
      status: MessageContentStatus.ok,
      createdAt: storedAt,
      updatedAt: storedAt,
    ));
    final controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: adapter.messaging,
      keyBundleCodec: adapter.keyBundles,
      envelopeCodec: adapter.envelopeCodec,
      sessionBootstrapper: adapter.sessions,
      realtimeService: _FakeRealtimeService(),
      cacheService: cache,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          messengerControllerProvider.overrideWith((ref) => controller),
        ],
        child: const _TestApp(
          child: ChatRoomScreen(
            conversationId: 'conv-1',
            embedded: true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Orbit relay window'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search cached messages on this device'),
      'orbit',
    );
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();

    expect(find.text('Local message search'), findsOneWidget);
    expect(
      find.textContaining('Showing 1 cached match(es).'),
      findsOneWidget,
    );
  });

  testWidgets('chat room loads older history pages on demand', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final adapter = createDefaultCryptoAdapter();
    final newerEnvelope = await adapter.messaging.encryptMessage(
      conversationId: 'conv-1',
      senderDeviceId: 'device-peer',
      recipientUserId: 'user-local',
      body: 'Newest relay note',
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-peer',
        deviceId: 'device-peer',
        handle: 'selene',
        identityPublicKey: 'pub-peer',
        signedPrekeyBundle: 'bundle-peer',
      ),
    );
    final olderEnvelope = await adapter.messaging.encryptMessage(
      conversationId: 'conv-1',
      senderDeviceId: 'device-peer',
      recipientUserId: 'user-local',
      body: 'Older relay note',
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-peer',
        deviceId: 'device-peer',
        handle: 'selene',
        identityPublicKey: 'pub-peer',
        signedPrekeyBundle: 'bundle-peer',
      ),
    );

    final controller = VeilMessengerController(
      apiClient: _FakePagedChatApiClient(
        latestEnvelope: newerEnvelope,
        olderEnvelope: olderEnvelope,
      ),
      cryptoEngine: adapter.messaging,
      keyBundleCodec: adapter.keyBundles,
      envelopeCodec: adapter.envelopeCodec,
      sessionBootstrapper: adapter.sessions,
      realtimeService: _FakeRealtimeService(),
      cacheService: _MemoryConversationCache(),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

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

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          messengerControllerProvider.overrideWith((ref) => controller),
        ],
        child: const _TestApp(
          child: ChatRoomScreen(
            conversationId: 'conv-1',
            embedded: true,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Load older'), findsOneWidget);
    expect(find.text('Newest relay note'), findsOneWidget);
    expect(find.text('Paged'), findsOneWidget);

    await tester.tap(find.text('Load older'));
    await tester.pump();
    expect(find.text('Syncing older history'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpAndSettle();

    expect(find.text('Older relay note'), findsOneWidget);
    expect(find.text('Load older'), findsNothing);
    expect(find.text('Complete'), findsOneWidget);
    expect(find.text('Conversation window complete'), findsOneWidget);
  });

  group('a disappearing message on a device whose clock runs 15 minutes fast', () {
    const deviceClockAhead = Duration(minutes: 15);

    testWidgets('is shown, with the time the relay leaves it, while the relay keeps it', (tester) async {
      // Past by the device clock; ten minutes left by the relay's.
      final controller = await _pumpExpiringChat(
        tester,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        deviceClockAhead: deviceClockAhead,
      );

      expect(controller.messagesFor('conv-1'), hasLength(1));
      expect(find.text('Orbit relay window'), findsOneWidget);
      expect(find.textContaining(RegExp(r'^Expires in (9|10)m$')), findsOneWidget);
    });

    testWidgets('is hidden once the relay counts it expired too', (tester) async {
      await _pumpExpiringChat(
        tester,
        expiresAt: DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
        deviceClockAhead: deviceClockAhead,
      );

      expect(find.text('Orbit relay window'), findsNothing);
    });
  });
}

// Opens the chat room over one message of ours, 'Orbit relay window', that
// expires at [expiresAt], on a device whose clock runs [deviceClockAhead] of
// the relay's: the relay's Date header said so.
Future<VeilMessengerController> _pumpExpiringChat(
  WidgetTester tester, {
  required DateTime expiresAt,
  required Duration deviceClockAhead,
}) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final adapter = createDefaultCryptoAdapter();
  final envelope = await adapter.messaging.encryptMessage(
    conversationId: 'conv-1',
    senderDeviceId: 'device-local',
    recipientUserId: 'user-peer',
    body: 'Orbit relay window',
    messageKind: MessageKind.text,
    recipientBundle: const KeyBundle(
      userId: 'user-peer',
      deviceId: 'device-peer',
      handle: 'selene',
      identityPublicKey: 'pub-peer',
      signedPrekeyBundle: 'bundle-peer',
    ),
  );
  final api = _FakeChatApiClient(envelope, expiresAt: expiresAt);
  api.serverClock.observe(HttpDate.format(DateTime.now().toUtc().subtract(deviceClockAhead)));
  final cache = _MemoryConversationCache();
  final storedAt = DateTime.utc(2026, 4, 7, 9, 29);
  await cache.put(MessageContentRecord(
    messageKey: 'msg-1',
    conversationId: 'conv-1',
    serverMessageId: 'msg-1',
    senderDeviceId: 'device-local',
    body: 'Orbit relay window',
    kind: MessageKind.text,
    status: MessageContentStatus.ok,
    createdAt: storedAt,
    updatedAt: storedAt,
  ));
  final controller = VeilMessengerController(
    apiClient: api,
    cryptoEngine: adapter.messaging,
    keyBundleCodec: adapter.keyBundles,
    envelopeCodec: adapter.envelopeCodec,
    sessionBootstrapper: adapter.sessions,
    realtimeService: _FakeRealtimeService(),
    cacheService: cache,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
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
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        messengerControllerProvider.overrideWith((ref) => controller),
      ],
      child: const _TestApp(
        child: ChatRoomScreen(
          conversationId: 'conv-1',
          embedded: true,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: VeilTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }
}

class _FakeRealtimeService extends RealtimeService {
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  void connect({
    required String baseUrl,
    required String accessToken,
    required void Function(String event, dynamic payload) onEvent,
    void Function(bool connected)? onConnectionChanged,
  }) {
    _connected = true;
    onConnectionChanged?.call(true);
  }

  @override
  void disconnect() {
    _connected = false;
  }
}

// Durable content, as the Drift cache keeps it: a sign-in does not wipe it.
class _MemoryConversationCache implements ConversationCacheService, MessageContentStore {
  final InMemoryMessageContentStore _contents = InMemoryMessageContentStore();

  @override
  Future<void> put(MessageContentRecord record) => _contents.put(record);

  @override
  Future<MessageContentRecord?> get(String messageKey) => _contents.get(messageKey);

  @override
  Future<Map<String, MessageContentRecord>> getMany(Iterable<String> messageKeys) => _contents.getMany(messageKeys);

  @override
  Future<Map<String, DateTime>> innerExpiries(Iterable<String> messageKeys) => _contents.innerExpiries(messageKeys);

  @override
  Future<void> rekeyLocalToServer({required String clientMessageId, required String serverMessageId}) =>
      _contents.rekeyLocalToServer(clientMessageId: clientMessageId, serverMessageId: serverMessageId);

  @override
  Future<void> deleteConversation(String conversationId) => _contents.deleteConversation(conversationId);

  @override
  Future<void> deleteExpired(DateTime now, {Iterable<String> messageKeys = const []}) =>
      _contents.deleteExpired(now, messageKeys: messageKeys);

  @override
  Future<Set<String>> retiredAmong(Iterable<String> messageKeys) => _contents.retiredAmong(messageKeys);

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> purgeExpiredMessages({DateTime? now}) async {}

  @override
  Future<List<ConversationPreview>> readConversations() async => const [];

  @override
  Future<List<ChatMessage>> readMessages(String conversationId) async => const [];

  @override
  Future<List<PendingMessageRecord>> readPendingMessages() async => const [];

  @override
  Future<ConversationPagingState> readPagingState(String conversationId) async =>
      const ConversationPagingState();

  @override
  Future<void> removePendingMessage(String clientMessageId) async {}

  @override
  Future<void> indexMessageBody({
    required String conversationId,
    required String messageId,
    required String searchableBody,
  }) async {}

  @override
  Future<List<String>> searchCachedMessageIds({
    required String conversationId,
    required String query,
  }) async =>
      const [];

  @override
  Future<MessageSearchPage> searchMessageArchive({
    required MessageSearchQuery query,
    required String currentDeviceId,
  }) async =>
      const MessageSearchPage(items: <MessageSearchResult>[]);

  @override
  Future<void> storeConversations(List<ConversationPreview> conversations) async {}

  @override
  Future<void> storeMessages(String conversationId, List<ChatMessage> messages) async {}

  @override
  Future<void> storePagingState(
    String conversationId, {
    String? nextCursor,
    required bool hasMoreHistory,
    DateTime? lastSyncedAt,
  }) async {}

  @override
  Future<void> upsertPendingMessage(PendingMessageRecord pending) async {}
}

class _FakeChatApiClient extends VeilApiClient {
  _FakeChatApiClient(this._envelope, {this.expiresAt}) : super(baseUrl: 'http://localhost:3000/v1');

  final CryptoEnvelope _envelope;
  final DateTime? expiresAt;

  @override
  Future<Map<String, dynamic>> getConversations(String accessToken) async {
    return {
      'items': [
        {
          'id': 'conv-1',
          'createdAt': DateTime.utc(2026, 4, 7, 8).toIso8601String(),
          'members': [
            {
              'userId': 'user-local',
              'handle': 'atlas',
              'displayName': 'Atlas',
            },
            {
              'userId': 'user-peer',
              'handle': 'selene',
              'displayName': 'Selene',
            },
          ],
          'lastMessage': {
            'id': 'msg-1',
            'clientMessageId': null,
            'conversationId': 'conv-1',
            'senderDeviceId': 'device-local',
            'recipientUserId': 'user-peer',
            'ciphertext': _envelope.ciphertext,
            'nonce': _envelope.nonce,
            'version': _envelope.version,
            'messageType': _envelope.messageKind.name,
            'serverReceivedAt':
                DateTime.utc(2026, 4, 7, 9, 30).toIso8601String(),
            'conversationOrder': 1,
            'deliveredAt': DateTime.utc(2026, 4, 7, 9, 31).toIso8601String(),
            'readAt': null,
            if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
          },
        },
      ],
      'nextCursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> getMessages(
    String accessToken,
    String conversationId, {
    String? cursor,
    int limit = 50,
  }) async {
    return {
      'items': [
        {
          'id': 'msg-1',
          'clientMessageId': null,
          'conversationId': 'conv-1',
          'senderDeviceId': 'device-local',
          'recipientUserId': 'user-peer',
          'ciphertext': _envelope.ciphertext,
          'nonce': _envelope.nonce,
          'version': _envelope.version,
          'messageType': _envelope.messageKind.name,
          'serverReceivedAt': DateTime.utc(2026, 4, 7, 9, 30).toIso8601String(),
          'conversationOrder': 1,
          'deliveredAt': DateTime.utc(2026, 4, 7, 9, 31).toIso8601String(),
          'readAt': null,
          if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        },
      ],
      'nextCursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> markRead(
    String accessToken,
    String messageId,
  ) async {
    return const <String, dynamic>{};
  }
}

class _FakePagedChatApiClient extends VeilApiClient {
  _FakePagedChatApiClient({
    required this.latestEnvelope,
    required this.olderEnvelope,
  }) : super(baseUrl: 'http://localhost:3000/v1');

  final CryptoEnvelope latestEnvelope;
  final CryptoEnvelope olderEnvelope;

  @override
  Future<Map<String, dynamic>> getConversations(String accessToken) async {
    return {
      'items': [
        {
          'id': 'conv-1',
          'createdAt': DateTime.utc(2026, 4, 7, 8).toIso8601String(),
          'members': [
            {
              'userId': 'user-local',
              'handle': 'atlas',
              'displayName': 'Atlas',
            },
            {
              'userId': 'user-peer',
              'handle': 'selene',
              'displayName': 'Selene',
            },
          ],
          'lastMessage': {
            'id': 'msg-2',
            'clientMessageId': null,
            'conversationId': 'conv-1',
            'senderDeviceId': latestEnvelope.senderDeviceId,
            'recipientUserId': latestEnvelope.recipientUserId,
            'ciphertext': latestEnvelope.ciphertext,
            'nonce': latestEnvelope.nonce,
            'version': latestEnvelope.version,
            'messageType': latestEnvelope.messageKind.name,
            'serverReceivedAt':
                DateTime.utc(2026, 4, 7, 9, 30).toIso8601String(),
            'conversationOrder': 2,
            'deliveredAt': DateTime.utc(2026, 4, 7, 9, 31).toIso8601String(),
            'readAt': null,
          },
        },
      ],
      'nextCursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> getMessages(
    String accessToken,
    String conversationId, {
    String? cursor,
    int limit = 50,
  }) async {
    if (cursor == 'older-cursor') {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      return {
        'items': [
          {
            'id': 'msg-1',
            'clientMessageId': null,
            'conversationId': 'conv-1',
            'senderDeviceId': olderEnvelope.senderDeviceId,
            'recipientUserId': olderEnvelope.recipientUserId,
            'ciphertext': olderEnvelope.ciphertext,
            'nonce': olderEnvelope.nonce,
            'version': olderEnvelope.version,
            'messageType': olderEnvelope.messageKind.name,
            'serverReceivedAt': DateTime.utc(2026, 4, 7, 9, 0).toIso8601String(),
            'conversationOrder': 1,
            'deliveredAt': DateTime.utc(2026, 4, 7, 9, 1).toIso8601String(),
            'readAt': null,
          },
        ],
        'nextCursor': null,
      };
    }

    return {
      'items': [
        {
          'id': 'msg-2',
          'clientMessageId': null,
          'conversationId': 'conv-1',
          'senderDeviceId': latestEnvelope.senderDeviceId,
          'recipientUserId': latestEnvelope.recipientUserId,
          'ciphertext': latestEnvelope.ciphertext,
          'nonce': latestEnvelope.nonce,
          'version': latestEnvelope.version,
          'messageType': latestEnvelope.messageKind.name,
          'serverReceivedAt': DateTime.utc(2026, 4, 7, 9, 30).toIso8601String(),
          'conversationOrder': 2,
          'deliveredAt': DateTime.utc(2026, 4, 7, 9, 31).toIso8601String(),
          'readAt': null,
        },
      ],
      'nextCursor': 'older-cursor',
    };
  }

  @override
  Future<Map<String, dynamic>> markRead(
    String accessToken,
    String messageId,
  ) async {
    return const <String, dynamic>{};
  }
}
