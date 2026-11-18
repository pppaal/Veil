import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../layout/support/layout_seed.dart';
import '../phone/phone_app.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';
import '../support/mock_relay_parties.dart';
import '../support/strict_mock_crypto_adapter.dart';

// What arrives in a chat that is open but not on screen (the app in the
// background, behind the lock screen) is read when the chat is back, with
// one receipt; and what a history sync brings into the open chat is read
// and receipted like a live message. Before the read state took this over,
// the chat marked read once when it loaded, and neither happened.

const conv = 'conv-1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Lifecycle changes arrive one legal step at a time, as on a device.
  void background(WidgetTester tester) {
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void foreground(WidgetTester tester) {
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  Future<void> settleFrames(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('a message that arrives while the app is in the background is read on return, with one receipt',
      (tester) async {
    final relay = FakeRelay();
    seedMockParties(relay, conv, ['atlas', 'selene']);
    final notifications = RecordingNotifications();
    final crypto = StrictMockCryptoAdapter(localDeviceId: 'dev-atlas');
    final atlas = VeilMessengerController(
      apiClient: relay.clientFor('atlas'),
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
      realtimeService: relay.realtimeFor('atlas'),
      cacheService: null,
      notificationService: notifications,
    );
    final selene = mockPartyController(relay, 'selene');
    await atlas.applySession(mockPartySession('atlas'));
    await selene.applySession(mockPartySession('selene'));

    await tester.pumpWidget(ProviderScope(
      overrides: [messengerControllerProvider.overrideWith((ref) => atlas)],
      child: MaterialApp(
        theme: VeilTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ChatRoomScreen(conversationId: conv, embedded: true),
      ),
    ));
    await settleFrames(tester);
    expect(atlas.activeConversationId, conv);

    background(tester);
    expect(atlas.activeConversationId, isNull);
    await selene.sendText(conversationId: conv, body: 'are you still up?');
    await settleFrames(tester);
    expect(atlas.messagesFor(conv), hasLength(1));
    expect(atlas.reads.unreadCount(conv), 1);
    expect(notifications.shownForConversations, [conv]);
    expect(relay.clientFor('atlas').markReadCalls, isEmpty);

    foreground(tester);
    await settleFrames(tester);
    expect(atlas.reads.unreadCount(conv), 0);
    expect(relay.clientFor('atlas').markReadCalls, [atlas.messagesFor(conv).single.id]);
    expect(notifications.cancelledForConversations, contains(conv));

    // The scope disposes atlas; selene's timers go with her.
    selene.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  group('in the app', () {
    late LayoutIdentities identities;

    setUpAll(() async {
      await loadBundledFonts();
      identities = await LayoutIdentities.generate();
    });

    testWidgets('a message that arrives behind the lock screen is read after the unlock, with one receipt',
        (tester) async {
      usePhoneView(tester, phoneMedium);
      final world = await LayoutWorld.create(identities: identities, account: LayoutAccount.signedIn, locale: 'en');
      try {
        final router = world.container.read(appRouterProvider);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: world.container,
          child: MaterialApp.router(
            theme: VeilTheme.dark(fontFamily: layoutFontFamily),
            locale: const Locale('en'),
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ));
        await pumpFrames(tester);
        unawaited(router.push('/chat/$chatConversationId'));
        await pumpFrames(tester);
        expect(world.messenger.activeConversationId, chatConversationId);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        final session = world.container.read(appSessionProvider.notifier);
        session.lock();
        await pumpFrames(tester, frames: 4);
        expect(find.byType(AppLockScreen), findsOneWidget);
        _deliverLive(world, await _sealedFromSam(world, 'there now'));
        await pumpFrames(tester, frames: 4);
        expect(world.messenger.reads.unreadCount(chatConversationId), 1);
        expect(world.api.markReadCalls, isEmpty, reason: 'nothing is read behind the lock screen');

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        session.unlock();
        await pumpFrames(tester, frames: 6);
        expect(find.byType(ChatRoomScreen), findsOneWidget);
        expect(world.messenger.reads.unreadCount(chatConversationId), 0);
        expect(world.api.markReadCalls, [world.messenger.messagesFor(chatConversationId).last.id]);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        world.dispose();
      }
    });

    testWidgets('a message a history sync brings into the open chat is read and receipted', (tester) async {
      await withPhoneApp(tester, identities, location: '/chat/$chatConversationId', body: (world) async {
        await pumpFrames(tester);
        expect(world.messenger.activeConversationId, chatConversationId);
        expect(world.api.markReadCalls, isEmpty, reason: 'the first list read the morning');

        // On the relay, not pushed: the next sync brings it.
        final stored = await _sealedFromSam(world, 'fetched, not pushed');
        world.relay.realtimeFor(selfHandle).deliver('conversation.sync', {
          'conversationId': chatConversationId,
          'reason': 'message',
        });
        await pumpFrames(tester, frames: 6);
        expect(world.messenger.messagesFor(chatConversationId).last.id, stored['id']);
        expect(world.messenger.reads.unreadCount(chatConversationId), 0);
        expect(world.api.markReadCalls, [stored['id']]);
      });
    });
  });
}

final _sealer = createDefaultCryptoAdapter();

/// A line from Sam, stored by the relay (and not pushed).
Future<Map<String, dynamic>> _sealedFromSam(LayoutWorld world, String body) async {
  final envelope = await _sealer.messaging.encryptMessage(
    conversationId: chatConversationId,
    senderDeviceId: 'dev-$peerHandle',
    recipientUserId: 'user-$selfHandle',
    body: body,
    messageKind: MessageKind.text,
    recipientBundle: const KeyBundle(
      userId: 'user-$selfHandle',
      deviceId: 'dev-$selfHandle',
      handle: selfHandle,
      identityPublicKey: 'ik',
      signedPrekeyBundle: 'spk',
    ),
  );
  return world.relay.inject(
    senderHandle: peerHandle,
    conversationId: chatConversationId,
    envelope: _sealer.envelopeCodec.encodeApiEnvelope(envelope),
  );
}

void _deliverLive(LayoutWorld world, Map<String, dynamic> stored) =>
    world.relay.realtimeFor(selfHandle).deliver('message.new', Map<String, dynamic>.of(stored));
