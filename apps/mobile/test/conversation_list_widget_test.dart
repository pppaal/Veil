import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

void main() {
  testWidgets('conversation list shows local search banner and archive results', (tester) async {
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

    final controller = _buildController(
      adapter: adapter,
      apiClient: _FakeConversationApiClient(envelope),
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
          child: ConversationListScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Selene'), findsWidgets);
    expect(find.text('ACTIVE CONVERSATION'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search conversations and cached messages'),
      'orbit',
    );
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();

    expect(find.text('Local search active'), findsOneWidget);
    expect(find.text('MESSAGES'), findsOneWidget);
    expect(find.textContaining('Orbit relay window'), findsWidgets);
  });

  testWidgets('conversation list shows empty state when no direct conversations exist', (tester) async {
    final adapter = createDefaultCryptoAdapter();
    final controller = _buildController(
      adapter: adapter,
      apiClient: _FakeConversationApiClient(null),
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
          child: ConversationListScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('DIRECT CONVERSATIONS'), findsOneWidget);
  });

  testWidgets('wide layout selection updates the active conversation pane', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final adapter = createDefaultCryptoAdapter();
    final firstEnvelope = await adapter.messaging.encryptMessage(
      conversationId: 'conv-1',
      senderDeviceId: 'device-local',
      recipientUserId: 'user-peer-1',
      body: 'Selene relay note',
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-peer-1',
        deviceId: 'device-peer-1',
        handle: 'selene',
        identityPublicKey: 'pub-peer-1',
        signedPrekeyBundle: 'bundle-peer-1',
      ),
    );
    final secondEnvelope = await adapter.messaging.encryptMessage(
      conversationId: 'conv-2',
      senderDeviceId: 'device-local',
      recipientUserId: 'user-peer-2',
      body: 'Rowan relay note',
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-peer-2',
        deviceId: 'device-peer-2',
        handle: 'rowan',
        identityPublicKey: 'pub-peer-2',
        signedPrekeyBundle: 'bundle-peer-2',
      ),
    );

    final controller = _buildController(
      adapter: adapter,
      apiClient: _FakeConversationApiClient.multiple(
        conversations: [
          _conversationMap(
            id: 'conv-1',
            peerHandle: 'selene',
            peerDisplayName: 'Selene',
            envelope: firstEnvelope,
          ),
          _conversationMap(
            id: 'conv-2',
            peerHandle: 'rowan',
            peerDisplayName: 'Rowan',
            envelope: secondEnvelope,
          ),
        ],
        messagesByConversation: {
          'conv-1': [
            _messageMap(
              id: 'msg-1',
              conversationId: 'conv-1',
              envelope: firstEnvelope,
              conversationOrder: 1,
              sentAt: DateTime.utc(2026, 4, 7, 9, 30),
            ),
          ],
          'conv-2': [
            _messageMap(
              id: 'msg-2',
              conversationId: 'conv-2',
              envelope: secondEnvelope,
              conversationOrder: 1,
              sentAt: DateTime.utc(2026, 4, 7, 9, 40),
            ),
          ],
        },
      ),
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
          child: ConversationListScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Selene relay note'), findsOneWidget);
    expect(find.text('Rowan relay note'), findsNothing);

    await tester.tap(find.text('Rowan').first);
    await tester.pumpAndSettle();

    expect(find.text('Rowan relay note'), findsOneWidget);
  });

  testWidgets('wide layout search result tap switches the active conversation', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final adapter = createDefaultCryptoAdapter();
    final firstEnvelope = await adapter.messaging.encryptMessage(
      conversationId: 'conv-1',
      senderDeviceId: 'device-local',
      recipientUserId: 'user-peer-1',
      body: 'Selene relay note',
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-peer-1',
        deviceId: 'device-peer-1',
        handle: 'selene',
        identityPublicKey: 'pub-peer-1',
        signedPrekeyBundle: 'bundle-peer-1',
      ),
    );
    final secondEnvelope = await adapter.messaging.encryptMessage(
      conversationId: 'conv-2',
      senderDeviceId: 'device-local',
      recipientUserId: 'user-peer-2',
      body: 'Anchor handoff note',
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-peer-2',
        deviceId: 'device-peer-2',
        handle: 'rowan',
        identityPublicKey: 'pub-peer-2',
        signedPrekeyBundle: 'bundle-peer-2',
      ),
    );

    final controller = _buildController(
      adapter: adapter,
      apiClient: _FakeConversationApiClient.multiple(
        conversations: [
          _conversationMap(
            id: 'conv-1',
            peerHandle: 'selene',
            peerDisplayName: 'Selene',
            envelope: firstEnvelope,
          ),
          _conversationMap(
            id: 'conv-2',
            peerHandle: 'rowan',
            peerDisplayName: 'Rowan',
            envelope: secondEnvelope,
          ),
        ],
        messagesByConversation: {
          'conv-1': [
            _messageMap(
              id: 'msg-1',
              conversationId: 'conv-1',
              envelope: firstEnvelope,
              conversationOrder: 1,
              sentAt: DateTime.utc(2026, 4, 7, 9, 30),
            ),
          ],
          'conv-2': [
            _messageMap(
              id: 'msg-2',
              conversationId: 'conv-2',
              envelope: secondEnvelope,
              conversationOrder: 1,
              sentAt: DateTime.utc(2026, 4, 7, 9, 40),
            ),
          ],
        },
      ),
      cacheService: _ConversationListCache(
        archiveResults: [
          MessageSearchResult(
            conversationId: 'conv-2',
            messageId: 'msg-2',
            peerHandle: 'rowan',
            peerDisplayName: 'Rowan',
            sentAt: DateTime.utc(2026, 4, 7, 9, 40),
            messageKind: MessageKind.text,
            isMine: false,
            bodySnippet: 'Anchor handoff note',
            conversationOrder: 1,
          ),
        ],
      ),
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
          child: ConversationListScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Selene relay note'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search conversations and cached messages'),
      'anchor',
    );
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();

    expect(find.text('MESSAGES'), findsOneWidget);
    expect(find.text('Rowan'), findsOneWidget);

    await tester.tap(find.text('Rowan'));
    await tester.pumpAndSettle();

    expect(find.text('Anchor handoff note'), findsWidgets);
  });
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

VeilMessengerController _buildController({
  required CryptoAdapter adapter,
  required VeilApiClient apiClient,
  ConversationCacheService? cacheService,
}) {
  return VeilMessengerController(
    apiClient: apiClient,
    cryptoEngine: adapter.messaging,
    keyBundleCodec: adapter.keyBundles,
    envelopeCodec: adapter.envelopeCodec,
    sessionBootstrapper: adapter.sessions,
    realtimeService: _FakeRealtimeService(),
    cacheService: cacheService ?? _ConversationListCache(),
  );
}

class _ConversationListCache implements ConversationCacheService {
  _ConversationListCache({
    this.archiveResults = const <MessageSearchResult>[],
  });

  final List<MessageSearchResult> archiveResults;

  @override
  Future<void> clearAll() async {}

  @override
  Future<void> purgeExpiredMessages() async {}

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
  }) async {
    if (query.normalizedQuery.isEmpty) {
      return const MessageSearchPage(items: <MessageSearchResult>[]);
    }
    return MessageSearchPage(
      items: archiveResults
          .where((item) => item.bodySnippet.toLowerCase().contains(query.normalizedQuery))
          .toList(growable: false),
    );
  }

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

class _FakeConversationApiClient extends VeilApiClient {
  _FakeConversationApiClient(this._envelope)
      : _conversations = null,
        _messagesByConversation = null,
        super(baseUrl: 'http://localhost:3000/v1');

  _FakeConversationApiClient.multiple({
    required List<Map<String, dynamic>> conversations,
    required Map<String, List<Map<String, dynamic>>> messagesByConversation,
  })  : _envelope = null,
        _conversations = conversations,
        _messagesByConversation = messagesByConversation,
        super(baseUrl: 'http://localhost:3000/v1');

  final CryptoEnvelope? _envelope;
  final List<Map<String, dynamic>>? _conversations;
  final Map<String, List<Map<String, dynamic>>>? _messagesByConversation;

  @override
  Future<List<dynamic>> getConversations(String accessToken) async {
    final conversations = _conversations;
    if (conversations != null) {
      return conversations;
    }
    return _envelope == null ? const [] : [_conversationMap(
      id: 'conv-1',
      peerHandle: 'selene',
      peerDisplayName: 'Selene',
      envelope: _envelope,
    )];
  }

  @override
  Future<Map<String, dynamic>> getMessages(
    String accessToken,
    String conversationId, {
    String? cursor,
    int limit = 50,
  }) async {
    final messagesByConversation = _messagesByConversation;
    if (messagesByConversation != null) {
      return {
        'items': messagesByConversation[conversationId] ?? const <Map<String, dynamic>>[],
        'nextCursor': null,
      };
    }
    final envelope = _envelope;
    if (envelope == null) {
      return const {
        'items': <Map<String, dynamic>>[],
        'nextCursor': null,
      };
    }
    return {
      'items': [
        {
          'id': 'msg-1',
          'clientMessageId': null,
          'conversationId': 'conv-1',
          'senderDeviceId': 'device-local',
          'recipientUserId': 'user-peer',
          'ciphertext': envelope.ciphertext,
          'nonce': envelope.nonce,
          'version': envelope.version,
          'messageType': envelope.messageKind.name,
          'serverReceivedAt': DateTime.utc(2026, 4, 7, 9, 30).toIso8601String(),
          'conversationOrder': 1,
          'deliveredAt': DateTime.utc(2026, 4, 7, 9, 31).toIso8601String(),
          'readAt': null,
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

Map<String, dynamic> _conversationMap({
  required String id,
  required String peerHandle,
  required String peerDisplayName,
  CryptoEnvelope? envelope,
}) {
  return {
    'id': id,
    'createdAt': DateTime.utc(2026, 4, 7, 8).toIso8601String(),
    'members': [
      {
        'userId': 'user-local',
        'handle': 'atlas',
        'displayName': 'Atlas',
      },
      {
        'userId': 'user-peer',
        'handle': peerHandle,
        'displayName': peerDisplayName,
      },
    ],
    'lastMessage': envelope == null
        ? null
        : {
            'id': 'msg-1',
            'clientMessageId': null,
            'conversationId': id,
            'senderDeviceId': 'device-local',
            'recipientUserId': 'user-peer',
            'ciphertext': envelope.ciphertext,
            'nonce': envelope.nonce,
            'version': envelope.version,
            'messageType': envelope.messageKind.name,
            'serverReceivedAt': DateTime.utc(2026, 4, 7, 9, 30).toIso8601String(),
            'conversationOrder': 1,
            'deliveredAt': DateTime.utc(2026, 4, 7, 9, 31).toIso8601String(),
            'readAt': null,
          },
  };
}

Map<String, dynamic> _messageMap({
  required String id,
  required String conversationId,
  required CryptoEnvelope envelope,
  required int conversationOrder,
  required DateTime sentAt,
}) {
  return {
    'id': id,
    'clientMessageId': null,
    'conversationId': conversationId,
    'senderDeviceId': 'device-local',
    'recipientUserId': 'user-peer',
    'ciphertext': envelope.ciphertext,
    'nonce': envelope.nonce,
    'version': envelope.version,
    'messageType': envelope.messageKind.name,
    'serverReceivedAt': sentAt.toIso8601String(),
    'conversationOrder': conversationOrder,
    'deliveredAt': sentAt.add(const Duration(minutes: 1)).toIso8601String(),
    'readAt': null,
  };
}
