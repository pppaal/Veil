import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_composer_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_phone.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_direct_chat_screen.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_numbers_screen.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/layout_seed.dart';
import 'phone_app.dart';

// The wide layout (from 1120 px): the list and the open chat side by side,
// each the same content-first view a phone shows, under its own bar. What
// the hero cards, stat tiles and header cards of the old panes were for is
// in the two bars.

const _latest = 'Section 7 is fine. Let us sign tomorrow.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  Finder inChat(Finder finder) => find.descendant(of: find.byType(ChatRoomScreen), matching: finder);
  Finder inList(Finder finder) => find.descendant(of: find.byType(ConversationListPhone), matching: finder);

  for (final size in [wideSmall, wideLarge]) {
    testWidgets('shows the list and the open chat with nothing above the rows or the messages ($size)',
        (tester) async {
      await withPhoneApp(tester, identities, size: size, location: '/conversations', body: (world) async {
        expect(find.byType(VeilHeroPanel), findsNothing);
        expect(find.byType(VeilMetricStrip), findsNothing);
        expect(find.byType(VeilStatusPill), findsNothing);

        final list = tester.getRect(find.byType(ConversationListPhone));
        final chat = tester.getRect(find.byType(ChatRoomScreen));
        expect(list.width, ConversationListScreen.listPaneWidth);
        expect(chat.left, greaterThanOrEqualTo(list.right));
        expect(chat.right, size.width);
        // Both panes start under a bar as tall as a phone's, at the top.
        expect(list.top, ChatPaneBar.height);
        expect(chat.top, 0);
        expect(tester.getRect(inChat(find.byType(ChatPaneBar))).height, ChatPaneBar.height);

        // The newest conversation is open, at its latest message, and the
        // messages have most of the pane.
        final open = tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen));
        expect((open.conversationId, open.embedded), (chatConversationId, true));
        expect(inChat(find.text(_latest)), findsOneWidget);
        final messages = tester.getRect(find.byType(ChatMessageList));
        expect(messages.height / chat.height, greaterThan(0.7));
        expect(messages.width, lessThanOrEqualTo(760), reason: 'bubbles do not stretch across a wide pane');
        final composer = tester.renderObject<RenderBox>(find.byType(ChatComposerBar));
        expect(visibleRect(tester, composer).size, composer.size, reason: 'the composer is whole');
        expect(tester.takeException(), isNull, reason: 'nothing overflows');
      });
    });
  }

  testWidgets('a tap on a row opens that chat in the pane and marks the row', (tester) async {
    await withPhoneApp(tester, identities, size: wideSmall, location: '/conversations', body: (world) async {
      VeilConversationCard row(String title) =>
          tester.widget<VeilConversationCard>(inList(find.widgetWithText(VeilConversationCard, title)));
      expect(row('Sam Rivera').selected, isTrue);
      expect(row('Jonas Weber').selected, isFalse);

      await tester.tap(inList(find.text('Jonas Weber')));
      await pumpFrames(tester, frames: 4);
      expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId, timerChatConversationId);
      expect(row('Jonas Weber').selected, isTrue);
      expect(row('Sam Rivera').selected, isFalse);
      expect(inChat(find.text('See you at nine.')), findsOneWidget);
      // The list is still there: the pane's bar has no back button.
      expect(find.byType(ConversationListPhone), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);
    });
  });

  testWidgets('the pane\'s bar carries the safety number, the search and the timer', (tester) async {
    await withPhoneApp(tester, identities, size: wideSmall, location: '/conversations', body: (world) async {
      expect(inChat(find.text('Sam Rivera')), findsOneWidget);
      expect(inChat(find.byTooltip('Verified')), findsOneWidget);

      // Search: the field takes the title's place, and its back button
      // closes the search, not the chat.
      await tester.tap(inChat(find.byTooltip('Search messages')));
      await pumpFrames(tester, frames: 2);
      tester.testTextInput.enterText('lease');
      await pumpFrames(tester, frames: 4);
      expect(inChat(find.text('2 matches on this device')), findsOneWidget);
      expect(inChat(find.text(_latest)), findsNothing);
      await tester.tap(inChat(find.byTooltip('Back')));
      await pumpFrames(tester, frames: 4);
      expect(inChat(find.text(_latest)), findsOneWidget);
      expect(find.byTooltip('Back'), findsNothing);

      // The disappearing timer.
      await tester.tap(inChat(find.byTooltip('Disappearing messages: Off')));
      await pumpFrames(tester, frames: 4);
      await tester.tap(find.text('1 day'));
      await pumpFrames(tester, frames: 4);
      expect(world.api.timers[chatConversationId], 86400);
      expect(inChat(find.byTooltip('Disappearing messages: 1 day')), findsOneWidget);

      // The safety number.
      await tester.tap(inChat(find.byTooltip('Safety number')));
      await pumpFrames(tester);
      expect(find.byType(SafetyNumbersScreen), findsOneWidget);
      final loading = find.byType(VeilLoadingBlock);
      for (var i = 0; i < 250 && loading.evaluate().isNotEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await pumpFrames(tester, frames: 3);
    });
  });

  testWidgets('a new conversation starts from the list\'s bar', (tester) async {
    await withPhoneApp(tester, identities, size: wideSmall, location: '/conversations', body: (world) async {
      await tester.tap(find.byTooltip('New conversation'));
      await pumpFrames(tester, frames: 3);
      expect(find.text('New group'), findsOneWidget);
      await tester.tap(find.text('New direct chat'));
      await pumpFrames(tester);
      expect(find.byType(StartDirectChatScreen), findsOneWidget);
    });
  });

  for (final size in [wideSmall, wideLarge]) {
    testWidgets('with two warnings the pane keeps both actions in reach and the messages most of its height ($size)',
        (tester) async {
      await withPhoneApp(
        tester,
        identities,
        size: size,
        location: '/conversations',
        attention: const ChatAttention(identityChanged: true, failedSends: 2),
        body: (world) async {
          expect(inChat(find.byType(VeilInlineBanner)), findsNWidgets(2));
          for (final action in ['Review', 'Retry failed sends']) {
            final button = tester.renderObject<RenderBox>(inChat(find.widgetWithText(TextButton, action)));
            expect(whyNotWhollyTappable(tester, button), isNull, reason: '"$action"');
            expect(button.size.height, greaterThanOrEqualTo(44), reason: '"$action"');
          }
          final chat = tester.getRect(find.byType(ChatRoomScreen));
          expect(tester.getRect(find.byType(ChatMessageList)).height / chat.height, greaterThan(0.4));
          expect(tester.takeException(), isNull);
        },
      );
    });
  }

  testWidgets('a group\'s pane is titled with its members and names who wrote each message', (tester) async {
    await withPhoneApp(tester, identities, size: wideSmall, withGroup: true, location: '/conversations',
        body: (world) async {
      expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId, groupConversationId);
      expect(inChat(find.text('Sam Rivera, Priya Nair, Omar Haddad')), findsOneWidget);
      expect(inChat(find.text('4 members')), findsOneWidget);
      for (final name in ['Sam Rivera', 'Priya Nair', 'Omar Haddad']) {
        expect(inChat(find.text(name)), findsOneWidget, reason: name);
      }
    });
  });

  testWidgets('with no conversation yet, the second pane says what to do', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      size: wideSmall,
      location: '/conversations',
      account: LayoutAccount.signedInEmpty,
      body: (world) async {
        expect(find.byType(ChatRoomScreen), findsNothing);
        expect(find.text('Select a conversation'), findsOneWidget);
        expect(find.text('No conversations yet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('under 1120 px the list is the screen and a chat opens on top of it', (tester) async {
    const narrow = PhoneSize(1119, 800, topInset: 0, bottomInset: 0);
    await withPhoneApp(tester, identities, size: narrow, location: '/conversations', body: (world) async {
      expect(find.byType(ChatRoomScreen), findsNothing);
      await tester.tap(find.text('Sam Rivera'));
      await pumpFrames(tester);
      expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).embedded, isFalse);
      expect(find.byTooltip('Back'), findsOneWidget);
    });
  });
}
