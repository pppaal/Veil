import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../support/fake_relay.dart';
import '../support/mock_relay_parties.dart';
import '../support/strict_mock_crypto_adapter.dart';

const conv = 'conv-1';

const _atlasBundle = KeyBundle(
  userId: 'user-atlas',
  deviceId: 'dev-atlas',
  handle: 'atlas',
  identityPublicKey: 'ik-atlas',
  signedPrekeyBundle: 'spk-atlas',
);

void main() {
  late FakeRelay relay;

  setUp(() {
    relay = FakeRelay();
    seedMockParties(relay, conv, ['atlas', 'selene']);
  });

  /// Relays a message from selene whose sealed kind is [innerKind] while the
  /// server-visible messageType says [outerKind].
  Future<void> relayFromSelene(String body, {
    required MessageKind innerKind,
    required MessageKind outerKind,
  }) async {
    final selene = StrictMockCryptoAdapter();
    final envelope = await selene.messaging.encryptMessage(
      conversationId: conv,
      senderDeviceId: 'dev-selene',
      recipientUserId: 'user-atlas',
      body: body,
      messageKind: innerKind,
      recipientBundle: _atlasBundle,
    );
    relay.inject(
      senderHandle: 'selene',
      conversationId: conv,
      envelope: selene.envelopeCodec.encodeApiEnvelope(envelope)..['messageType'] = outerKind.name,
    );
  }

  Future<VeilMessengerController> openChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final controller = mockPartyController(relay, 'atlas');
    await controller.applySession(mockPartySession('atlas'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [messengerControllerProvider.overrideWith((ref) => controller)],
        child: MaterialApp(
          theme: VeilTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ChatRoomScreen(conversationId: conv, embedded: true),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    return controller;
  }

  testWidgets('outer messageKind system without inner system renders as normal bubble', (tester) async {
    await relayFromSelene(
      'Just a normal message',
      innerKind: MessageKind.text,
      outerKind: MessageKind.system,
    );

    await openChat(tester);

    expect(find.text('Just a normal message'), findsOneWidget);
    expect(find.byType(VeilMessageBubbleCard), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_outlined), findsNothing);
  });

  testWidgets('inner system kind renders as a system notice whatever the envelope says', (tester) async {
    await relayFromSelene(
      'Screenshot taken',
      innerKind: MessageKind.system,
      outerKind: MessageKind.text,
    );

    await openChat(tester);

    expect(find.text('Screenshot taken'), findsOneWidget);
    expect(find.byIcon(Icons.camera_alt_outlined), findsOneWidget);
    expect(find.byType(VeilMessageBubbleCard), findsNothing);
  });

  testWidgets('the conversation list labels the last message by its decrypted kind', (tester) async {
    await relayFromSelene('a photo', innerKind: MessageKind.image, outerKind: MessageKind.system);
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = mockPartyController(relay, 'atlas');
    await controller.applySession(mockPartySession('atlas'));
    await controller.loadConversationMessages(conv);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [messengerControllerProvider.overrideWith((ref) => controller)],
        child: MaterialApp(
          theme: VeilTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ConversationListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Encrypted image'), findsOneWidget);
    expect(find.text('System envelope'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('the chat is the active conversation only while it is visible', (tester) async {
    final controller = await openChat(tester);
    expect(controller.activeConversationId, conv);

    _background(tester);
    expect(controller.activeConversationId, isNull);
    _foreground(tester);
    expect(controller.activeConversationId, conv);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('elsewhere'))));
    await tester.pumpAndSettle();
    expect(controller.activeConversationId, isNull);

    // Coming back to the foreground on another screen must not re-arm it.
    _background(tester);
    _foreground(tester);
    expect(controller.activeConversationId, isNull);

    navigator.pop();
    await tester.pumpAndSettle();
    expect(controller.activeConversationId, conv);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.activeConversationId, isNull);
  });
}

// Lifecycle changes arrive one legal step at a time, as on a device.
void _background(WidgetTester tester) {
  for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}

void _foreground(WidgetTester tester) {
  for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}
