import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

const _conv = 'conv-1';

/// What each relayed frame opens to, by ciphertext; the engine stands in
/// for the ratchet so a test can say exactly what decrypt reported.
class _ScriptedEngine implements MessageCryptoEngine {
  _ScriptedEngine(this._inner, this.outcomes);

  final MessageCryptoEngine _inner;
  final Map<String, DecryptedMessage> outcomes;

  @override
  Future<DecryptedMessage> decryptMessage(CryptoEnvelope envelope) async => outcomes[envelope.ciphertext]!;

  @override
  Future<CryptoEnvelope> encryptMessage({
    required String conversationId,
    required String senderDeviceId,
    required String recipientUserId,
    required String body,
    required MessageKind messageKind,
    required KeyBundle recipientBundle,
    DateTime? expiresAt,
    AttachmentReference? attachment,
  }) =>
      _inner.encryptMessage(
        conversationId: conversationId,
        senderDeviceId: senderDeviceId,
        recipientUserId: recipientUserId,
        body: body,
        messageKind: messageKind,
        recipientBundle: recipientBundle,
        expiresAt: expiresAt,
        attachment: attachment,
      );

  @override
  Future<AttachmentCipher> encryptAttachment({
    required String attachmentId,
    required String storageKey,
    required String contentType,
    required List<int> plaintext,
    required KeyBundle recipientBundle,
  }) =>
      throw UnimplementedError();

  @override
  Future<List<int>> decryptAttachment({
    required AttachmentReference reference,
    required List<int> ciphertext,
    required String localIdentityPrivateRef,
  }) =>
      throw UnimplementedError();
}

class _Relay extends VeilApiClient {
  _Relay(this.frames) : super(baseUrl: 'http://relay.invalid/v1');

  /// Ciphertext and outer message type of each frame, in conversation order.
  final List<(String, String)> frames;

  @override
  Future<Map<String, dynamic>> getConversations(String accessToken) async => {
        'items': [
          {
            'id': _conv,
            'type': 'direct',
            'createdAt': DateTime.utc(2026, 4, 1).toIso8601String(),
            'members': [
              {'userId': 'user-local', 'handle': 'atlas'},
              {'userId': 'user-peer', 'handle': 'selene'},
            ],
            'lastMessage': null,
          },
        ],
        'nextCursor': null,
      };

  @override
  Future<Map<String, dynamic>> getMessages(
    String accessToken,
    String conversationId, {
    String? cursor,
    int limit = 50,
  }) async =>
      {
        'items': [
          for (final (index, (ciphertext, type)) in frames.indexed)
            {
              'id': 'srv-${index + 1}',
              'clientMessageId': 'peer-${index + 1}',
              'conversationId': _conv,
              'senderDeviceId': 'device-peer',
              'conversationOrder': index + 1,
              'ciphertext': ciphertext,
              'nonce': 'nonce-$index',
              'messageType': type,
              'version': 'veil-envelope-v2',
              'serverReceivedAt': DateTime.utc(2026, 4, 1, 9, index).toIso8601String(),
            },
        ],
        'nextCursor': null,
      };

  @override
  Future<Map<String, dynamic>> markRead(String accessToken, String messageId) async => {'messageId': messageId};
}

class _Realtime extends RealtimeService {
  @override
  bool get isConnected => true;

  @override
  void connect({
    required String baseUrl,
    required String accessToken,
    required void Function(String event, dynamic payload) onEvent,
    void Function(bool connected)? onConnectionChanged,
  }) =>
      onConnectionChanged?.call(true);

  @override
  void disconnect() {}

  @override
  void emit(String event, Map<String, dynamic> payload) {}
}

DecryptedMessage _opened(String body, {MessageKind kind = MessageKind.text}) =>
    DecryptedMessage(body: body, messageKind: kind);

Future<VeilMessengerController> _pumpChat(
  WidgetTester tester,
  List<(String, String, DecryptedMessage)> frames,
) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final adapter = createDefaultCryptoAdapter();
  final controller = VeilMessengerController(
    apiClient: _Relay([for (final (ciphertext, type, _) in frames) (ciphertext, type)]),
    cryptoEngine: _ScriptedEngine(adapter.messaging, {for (final (ciphertext, _, outcome) in frames) ciphertext: outcome}),
    keyBundleCodec: adapter.keyBundles,
    envelopeCodec: adapter.envelopeCodec,
    sessionBootstrapper: adapter.sessions,
    realtimeService: _Realtime(),
    cacheService: null,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await controller.applySession(const AppSessionState(
    accessToken: 'token',
    userId: 'user-local',
    deviceId: 'device-local',
    handle: 'atlas',
    onboardingAccepted: true,
    locked: false,
    initializing: false,
  ));
  await tester.pumpWidget(ProviderScope(
    overrides: [messengerControllerProvider.overrideWith((ref) => controller)],
    child: MaterialApp(
      theme: VeilTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ChatRoomScreen(conversationId: _conv, embedded: true),
    ),
  ));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('peer text that looks like a failure renders as text', (tester) async {
    await _pumpChat(tester, [('frame-1', 'text', _opened('[Decryption failed]'))]);

    expect(find.text('[Decryption failed]'), findsOneWidget);
    expect(find.text("Couldn't decrypt this message"), findsNothing);
  });

  testWidgets('real failure renders chip', (tester) async {
    await _pumpChat(tester, [
      (
        'frame-1',
        'text',
        const DecryptedMessage(
          body: 'whatever an adapter put here',
          messageKind: MessageKind.text,
          status: DecryptStatus.failed,
        ),
      ),
      ('frame-2', 'text', const DecryptedMessage(body: '', messageKind: MessageKind.text, status: DecryptStatus.awaitingKey)),
    ]);

    expect(find.text("Couldn't decrypt this message"), findsOneWidget);
    expect(find.text("Waiting for the sender's key"), findsOneWidget);
    expect(find.text('whatever an adapter put here'), findsNothing);
  });

  testWidgets('a legacy frame renders its text with an unverified-sender badge', (tester) async {
    await _pumpChat(tester, [
      (
        'frame-1',
        'text',
        const DecryptedMessage(body: 'old client', messageKind: MessageKind.text, status: DecryptStatus.legacyUnauthenticated),
      ),
    ]);

    expect(find.text('old client'), findsOneWidget);
    expect(find.text('Unverified sender (legacy)'), findsOneWidget);
  });

  testWidgets('inbound reaction applies to target and renders no bubble', (tester) async {
    final reaction = json.encode({'v': 1, 'target': 'srv-1', 'emoji': '👍', 'op': 'add'});
    final controller = await _pumpChat(tester, [
      ('frame-1', 'text', _opened('react to me')),
      ('frame-2', 'reaction', _opened(reaction, kind: MessageKind.reaction)),
    ]);

    final target = controller.messagesFor(_conv).firstWhere((message) => message.id == 'srv-1');
    expect(target.reactions.single.emoji, '👍');
    expect(target.reactions.single.userId, 'user-peer');
    expect(find.text('react to me'), findsOneWidget);
    expect(find.textContaining('"target"'), findsNothing);
    expect(find.textContaining('👍'), findsOneWidget);
  });
}
