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
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_unread_divider.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_bubble.dart';
import 'package:veil_mobile/src/features/chat/presentation/scroll_to_bottom_button.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_bubble.dart';
import 'package:veil_mobile/src/shared/presentation/veil_shell.dart';

import '../layout/support/layout_seed.dart';
import '../layout/support/unread_seed.dart';
import 'phone_app.dart';

// The unread divider and where a chat opens (spec D48), and the button
// that goes back to the newest message (D49): the divider stays while the
// screen shows the chat, a sheet and the lock screen included, and is gone
// the next time it opens.

const _chat = '/chat/$chatConversationId';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  Finder divider() => find.byType(ChatUnreadDivider);
  Finder scrollButton() => find.byIcon(Icons.keyboard_arrow_down);
  Rect onScreenRect(WidgetTester tester, Finder finder) => tester.getRect(finder);
  Rect messages(WidgetTester tester) => tester.getRect(find.byType(ChatMessageList));

  testWidgets('a short run opens at the bottom with the divider above its first message', (tester) async {
    await withPhoneApp(tester, identities,
        size: phoneMedium, location: _chat, afterSession: seedShortUnreadRun, body: (world) async {
      await pumpFrames(tester);
      expect(find.text('4 unread messages'), findsOneWidget);
      final band = onScreenRect(tester, divider());
      final first = tester.getRect(find.text(samShortRun.first));
      expect(band.bottom, lessThanOrEqualTo(first.top), reason: 'the divider sits above the first unread message');
      expect(tester.getRect(find.text(samShortRun.last)).bottom, lessThan(messages(tester).bottom),
          reason: 'the newest message is on screen');
      expect(scrollButton(), findsNothing);
      expect(world.messenger.reads.unreadCount(chatConversationId), 0);
    });
  });

  testWidgets('a long run opens at the divider, a third down, with the button; arrivals away count on it',
      (tester) async {
    await withPhoneApp(tester, identities,
        size: phoneMedium, location: _chat, afterSession: seedLongUnreadRun, body: (world) async {
      await pumpFrames(tester, frames: 12);
      expect(find.text('$samLongRunLength unread messages'), findsOneWidget);
      final area = messages(tester);
      final band = onScreenRect(tester, divider());
      final share = (band.top - area.top) / area.height;
      expect(share, inInclusiveRange(0.2, 0.45), reason: 'the divider is about a third down (at $share)');
      expect(scrollButton(), findsOneWidget);
      expect(find.byType(UnreadBadge), findsNothing, reason: 'nothing arrived while away');

      // Two more while the list is away from the bottom.
      await _deliver(world, ['are you on your way?', 'bring tape']);
      await pumpFrames(tester, frames: 4);
      final badge = find.descendant(of: find.byType(ScrollToBottomButton), matching: find.byType(UnreadBadge));
      expect(tester.widget<UnreadBadge>(badge).count, 2);

      await tester.tap(scrollButton());
      await pumpFrames(tester, frames: 6);
      expect(find.text('bring tape'), findsOneWidget);
      expect(scrollButton(), findsNothing, reason: 'at the bottom the button goes');
      expect(badge, findsNothing);
      // The divider stays where it was.
      expect(world.messenger.reads.dividerFor(chatConversationId, viewer: _screenState(tester))?.count,
          samLongRunLength);
    });
  });

  testWidgets('in a group the divider starts a new group: the first unread message names its sender', (tester) async {
    // Omar's read line at 10:13, then his two unread ones a few minutes
    // later: without the divider all three would be one group.
    const unread = ['also the van is booked', 'for 9am'];
    await withPhoneApp(tester, identities,
        size: phoneMedium,
        withGroup: true,
        location: '/chat/$groupConversationId',
        afterSession: (world) => deliverLines(world, 'omar_h', unread,
            firstAt: DateTime.utc(2026, 4, 7, 10, 15), inChat: groupConversationId), body: (world) async {
      await pumpFrames(tester);
      expect(find.text('2 unread messages'), findsOneWidget);
      MessageBubble bubble(String text) =>
          tester.widget<MessageBubble>(find.ancestor(of: find.text(text), matching: find.byType(MessageBubble)));
      final read = bubble(latestGroupLine);
      final first = bubble(unread.first);
      expect(read.position, VeilBubblePosition.single, reason: 'the read line closes its group, with the avatar');
      expect(first.position, VeilBubblePosition.first);
      expect(first.senderName, isNotNull, reason: 'the first unread message names its sender');
      expect(first.senderName, read.senderName);

      // The divider brings its own space: none under the read line, none
      // over the unread one, 16 around the band.
      final band = tester.getRect(divider());
      final above = tester.getRect(find.ancestor(of: find.text(latestGroupLine), matching: find.byType(MessageBubble)));
      final below = tester.getRect(find.ancestor(of: find.text(unread.first), matching: find.byType(MessageBubble)));
      expect(band.top - above.bottom, moreOrLessEquals(0));
      expect(below.top - band.bottom, moreOrLessEquals(0));
      expect(band.height, ChatUnreadDivider.extent);
    });
  });

  testWidgets('at the largest text the band grows and a long run still opens at the divider', (tester) async {
    await withPhoneApp(tester, identities,
        size: phoneMedium,
        textScale: 2,
        location: _chat,
        afterSession: seedLongUnreadRun, body: (world) async {
      await pumpFrames(tester, frames: 12);
      final words = find.text('$samLongRunLength unread messages');
      expect(words, findsOneWidget);
      final band = tester.getRect(find.descendant(of: divider(), matching: find.byType(ColoredBox)));
      expect(band.height, greaterThan(ChatUnreadDivider.bandHeight));
      expect(tester.getRect(words).bottom, lessThanOrEqualTo(band.bottom), reason: 'the words fit in the band');
      final area = messages(tester);
      final share = (onScreenRect(tester, divider()).top - area.top) / area.height;
      expect(share, inInclusiveRange(0.2, 0.45), reason: 'the divider is about a third down (at $share)');
    });
  });

  testWidgets('a chat marked unread with nothing new opens at the bottom with no divider', (tester) async {
    await withPhoneApp(tester, identities,
        size: phoneMedium,
        location: _chat,
        afterSession: (world) async => world.messenger.reads.markUnread(chatConversationId),
        body: (world) async {
      await pumpFrames(tester);
      expect(divider(), findsNothing);
      expect(scrollButton(), findsNothing);
      expect(find.text(latestChatLine), findsOneWidget);
      expect(world.messenger.reads.markedUnread(chatConversationId), isFalse, reason: 'opening it read it');
    });
  });

  testWidgets('the divider stays through the timer sheet and the lock screen, and is gone when the chat reopens',
      (tester) async {
    usePhoneView(tester, phoneMedium);
    final world = await LayoutWorld.create(identities: identities, account: LayoutAccount.signedIn, locale: 'en');
    try {
      await seedShortUnreadRun(world);
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
      unawaited(router.push(_chat));
      await pumpFrames(tester);
      expect(find.text('4 unread messages'), findsOneWidget);
      expect(world.messenger.reads.unreadCount(chatConversationId), 0);

      // The timer sheet over the chat, then closed.
      await tester.tap(find.byTooltip(lookupAppLocalizations(const Locale('en')).chatMenuTooltip));
      await pumpFrames(tester, frames: 3);
      await tester.tap(find.byKey(const ValueKey('chat-menu-timer')));
      await pumpFrames(tester, frames: 4);
      expect(world.messenger.activeConversationId, isNull, reason: 'a sheet covers the chat');
      await tester.tapAt(const Offset(195, 60));
      await pumpFrames(tester, frames: 4);
      expect(world.messenger.activeConversationId, chatConversationId);
      expect(find.text('4 unread messages'), findsOneWidget);

      // The lock screen takes the chat away; unlock puts it back.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      final session = world.container.read(appSessionProvider.notifier);
      session.lock();
      await pumpFrames(tester, frames: 6);
      expect(find.byType(AppLockScreen), findsOneWidget);
      expect(find.byType(ChatRoomScreen), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      session.unlock();
      await pumpFrames(tester, frames: 6);
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(find.text('4 unread messages'), findsOneWidget, reason: 'the divider came back with the chat');

      // Left and opened again: nothing was unread this time.
      await tester.tap(find.byType(VeilBackButton));
      await pumpFrames(tester);
      expect(find.byType(ConversationListScreen), findsOneWidget);
      await tester.tap(find.widgetWithText(ConversationRow, 'Sam Rivera'));
      await pumpFrames(tester);
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(divider(), findsNothing);
      expect(world.api.markReadCalls, hasLength(1), reason: 'one receipt, when the chat was first read');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      world.dispose();
    }
  });
}

/// The chat screen's state, the viewer its divider was taken for.
State _screenState(WidgetTester tester) => tester.state(find.byType(ChatRoomScreen));

final _sealer = createDefaultCryptoAdapter();

/// Sam's [lines], delivered live while the chat is open.
Future<void> _deliver(LayoutWorld world, List<String> lines) async {
  for (final body in lines) {
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
    final stored = world.relay.inject(
      senderHandle: peerHandle,
      conversationId: chatConversationId,
      envelope: _sealer.envelopeCodec.encodeApiEnvelope(envelope),
    );
    stored['serverReceivedAt'] = DateTime.utc(2026, 4, 7, 10, 19).toIso8601String();
    world.relay.realtimeFor(selfHandle).deliver('message.new', Map<String, dynamic>.of(stored));
  }
}
