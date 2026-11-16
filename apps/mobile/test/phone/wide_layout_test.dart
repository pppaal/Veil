import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/router/main_tab_shell.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_composer_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_phone.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_direct_chat_screen.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_numbers_screen.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_screen.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/layout_seed.dart';
import 'phone_app.dart';

// The wide layout (from 1120 px): the list and the open chat side by side,
// each the same content-first view a phone shows, under its own bar. What
// the hero cards, stat tiles and header cards of the old panes were for is
// in the two bars. From 1024 px the tabs are a rail at the start edge.

const _latest = "Section 7 is fine. Let's sign tomorrow.";

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
      ConversationRow row(String title) =>
          tester.widget<ConversationRow>(inList(find.widgetWithText(ConversationRow, title)));
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

  testWidgets('the pane\'s bar carries the safety number, the search and the menu with the timer', (tester) async {
    await withPhoneApp(tester, identities, size: wideSmall, location: '/conversations', body: (world) async {
      expect(inChat(find.text('Sam Rivera')), findsOneWidget);
      expect(inChat(find.byTooltip('Verified')), findsOneWidget);

      // Search: the field takes the title's place, and its back button
      // closes the search, not the chat.
      await tester.tap(inChat(find.byTooltip('Search')));
      await pumpFrames(tester, frames: 2);
      tester.testTextInput.enterText('lease');
      await pumpFrames(tester, frames: 4);
      // The hits are counted in the composer's place.
      expect(inChat(find.text('2 of 2')), findsOneWidget);
      await tester.tap(inChat(find.byTooltip('Back')));
      await pumpFrames(tester, frames: 4);
      expect(inChat(find.text('2 of 2')), findsNothing);
      expect(find.byTooltip('Back'), findsNothing);

      // The disappearing timer, from the bar's menu.
      await tester.tap(inChat(find.byTooltip('More options')));
      await pumpFrames(tester, frames: 3);
      await tester.tap(find.text('Disappearing messages'));
      await pumpFrames(tester, frames: 4);
      await tester.tap(find.text('1 day'));
      await pumpFrames(tester, frames: 4);
      expect(world.api.timers[chatConversationId], 86400);
      expect(inChat(find.byWidgetPredicate((widget) => widget is Text && widget.semanticsLabel == 'Disappearing: 1 day')), findsOneWidget);

      // The safety number.
      await tester.tap(inChat(find.byTooltip('Safety number')));
      await pumpFrames(tester);
      expect(find.byType(SafetyNumbersScreen), findsOneWidget);
      final loading = find.byKey(SafetyNumbersScreen.loadingKey);
      for (var i = 0; i < 250 && loading.evaluate().isNotEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump();
      }
      await pumpFrames(tester, frames: 3);
    });
  });

  testWidgets('a new conversation starts from the list\'s bar', (tester) async {
    await withPhoneApp(tester, identities, size: wideSmall, location: '/conversations', body: (world) async {
      await tester.tap(find.byTooltip('New chat'));
      await pumpFrames(tester);
      expect(find.byType(StartDirectChatScreen), findsOneWidget);
      expect(find.text('New group'), findsOneWidget);
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
        attention: const ChatAttention(identityChanged: true, accountHeld: true),
        body: (world) async {
          expect(inChat(find.byType(VeilNotice)), findsNWidgets(2));
          for (final action in ['Review', 'Talk to this account']) {
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

  testWidgets('with no conversation yet, the list says so once and the second pane has one muted line', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      size: wideSmall,
      location: '/conversations',
      account: LayoutAccount.signedInEmpty,
      body: (world) async {
        expect(find.byType(ChatRoomScreen), findsNothing);
        expect(find.text('No chats yet'), findsOneWidget);
        expect(find.text('New chat'), findsOneWidget);
        // The pane says what it is for in one muted line, as Telegram's does;
        // the empty state and its button are the list's alone.
        expect(find.text('Select a chat'), findsOneWidget);
        expect(find.byType(VeilEmptyState), findsOneWidget, reason: 'only the list\'s');
        expect(tester.takeException(), isNull);
      },
    );
  });

  // From 1024 px three tabs across the bottom would sit far apart: they are
  // a rail at the start edge, beside whichever tab is open.
  testWidgets('from 1024 px the tabs are a rail at the start edge, not a bar across the bottom', (tester) async {
    await withPhoneApp(tester, identities, size: tabletUpright, location: '/conversations', body: (world) async {
      final rail = find.byType(NavigationRail);
      expect(rail, findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      for (final tab in ['Chats', 'Contacts', 'Settings']) {
        expect(find.descendant(of: rail, matching: find.text(tab)), findsOneWidget, reason: tab);
      }
      // One pane on a tablet held upright, right of the rail.
      expect(find.byType(ChatRoomScreen), findsNothing);
      expect(tester.getRect(rail).left, 0);
      expect(tester.getRect(find.byType(ConversationListPhone)).left, greaterThanOrEqualTo(tester.getRect(rail).right));
      expect(tester.widget<NavigationRail>(rail).selectedIndex, 0);

      await tester.tap(find.descendant(of: rail, matching: find.text('Settings')));
      await pumpFrames(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(tester.widget<NavigationRail>(rail).selectedIndex, 2);
      expect(tester.getRect(find.byType(SettingsScreen)).left, greaterThanOrEqualTo(tester.getRect(rail).right));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('under 1024 px the tabs stay a bar across the bottom', (tester) async {
    const narrow = PhoneSize(1023, 800, topInset: 0, bottomInset: 0);
    await withPhoneApp(tester, identities, size: narrow, location: '/conversations', body: (world) async {
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });
  });

  // The two panes start at a 1120 px window whatever the rail takes, which
  // is also what a new chat decides on when it opens beside the list.
  testWidgets('at 1120 px, beside the rail, the list and the open chat are side by side', (tester) async {
    const edge = PhoneSize(1120, 800, topInset: 0, bottomInset: 0);
    await withPhoneApp(tester, identities, size: edge, location: '/conversations', body: (world) async {
      final rail = tester.getRect(find.byType(NavigationRail));
      final list = tester.getRect(find.byType(ConversationListPhone));
      final chat = tester.getRect(find.byType(ChatRoomScreen));
      expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).embedded, isTrue);
      expect(list.left, greaterThanOrEqualTo(rail.right));
      expect(list.width, ConversationListScreen.listPaneWidth);
      expect(chat.right, edge.width);
      expect(tester.takeException(), isNull);
    });
  });

  // A window resized, or a tablet turned, across a breakpoint changes the
  // frame around the open tab, not the tab: the list keeps its state, what
  // was typed in its search and the chat that was open.
  String searchText(WidgetTester tester) =>
      tester.widget<TextField>(inList(find.byType(TextField))).controller!.text;

  testWidgets('from rail to bar and back, the list keeps its state and its search', (tester) async {
    const rail = PhoneSize(1100, 800, topInset: 0, bottomInset: 0);
    const bar = PhoneSize(900, 800, topInset: 0, bottomInset: 0);
    await withPhoneApp(tester, identities, size: rail, location: '/conversations', body: (world) async {
      expect(find.byType(NavigationRail), findsOneWidget);
      final list = tester.state(find.byType(ConversationListScreen));
      await tester.enterText(inList(find.byType(TextField)), 'Sam');
      await pumpFrames(tester);
      for (final size in [bar, rail]) {
        usePhoneView(tester, size);
        await pumpFrames(tester);
        final railShown = MainTabShell.usesRail(size.width);
        expect(find.byType(NavigationRail), railShown ? findsOneWidget : findsNothing, reason: '${size.width}');
        expect(find.byType(NavigationBar), railShown ? findsNothing : findsOneWidget, reason: '${size.width}');
        expect(identical(tester.state(find.byType(ConversationListScreen)), list), isTrue,
            reason: 'the list was built anew at ${size.width} px');
        expect(searchText(tester), 'Sam', reason: '${size.width}');
        expect(inList(find.text('Sam Rivera')), findsOneWidget);
        expect(inList(find.text('Jonas Weber')), findsNothing, reason: 'still filtered at ${size.width} px');
      }
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('from two panes to one and back, the chat that was open stays open', (tester) async {
    const onePane = PhoneSize(1000, 800, topInset: 0, bottomInset: 0);
    await withPhoneApp(tester, identities, size: wideSmall, location: '/conversations', body: (world) async {
      final list = tester.state(find.byType(ConversationListScreen));
      await tester.tap(inList(find.text('Jonas Weber')));
      await pumpFrames(tester, frames: 4);
      expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId, timerChatConversationId);

      usePhoneView(tester, onePane);
      await pumpFrames(tester);
      expect(find.byType(ChatRoomScreen), findsNothing, reason: 'one pane: the list is the screen');
      expect(identical(tester.state(find.byType(ConversationListScreen)), list), isTrue);

      usePhoneView(tester, wideSmall);
      await pumpFrames(tester, frames: 4);
      expect(identical(tester.state(find.byType(ConversationListScreen)), list), isTrue);
      expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId, timerChatConversationId);
      expect(inChat(find.text('See you at nine.')), findsOneWidget);
      expect(tester.widget<ConversationRow>(inList(find.widgetWithText(ConversationRow, 'Jonas Weber'))).selected, isTrue);
      expect(tester.takeException(), isNull);
    });
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
