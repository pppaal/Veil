import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_unread_divider.dart';
import 'package:veil_mobile/src/features/chat/presentation/scroll_to_bottom_button.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';

import 'layout_world.dart';
import 'phone_layout_probe.dart';
import 'screen_cases.dart';
import 'unread_seed.dart';

// The layout cases of unread counts: the Chats list with its badges and row
// menu, the unread divider and the scroll button in a chat. Each seeds its
// unread messages after the first list (unread_seed.dart), which a new
// phone reads through, so every other case stays free of badges.

const _chat = '/chat/$chatConversationId';

const List<ScreenCase> unreadScreenCases = [
  // Priya 3, Mia 1, Jonas 2 in grey (his chat is muted, as Sam's is),
  // Omar's photo marked unread (the disc), and 3 on the Chats tab.
  ScreenCase(
    'conversation-list-unread',
    screen: ConversationListScreen,
    file: 'conversation_list_screen.dart',
    location: '/conversations',
    attention: ChatAttention(muted: true),
    afterSession: seedUnreadChats,
    primaryExtent: conversationRowsExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _expectUnreadRows,
  ),
  ScreenCase(
    'conversation-list-unread-larger-text',
    screen: ConversationListScreen,
    file: 'conversation_list_screen.dart',
    location: '/conversations',
    attention: ChatAttention(muted: true),
    textScale: largerText,
    afterSession: seedUnreadChats,
    primaryExtent: conversationRowsExtent,
    settle: _expectUnreadRows,
  ),
  // The menu a long press on Priya's row opens.
  ScreenCase(
    'conversation-list-row-menu',
    screen: ConversationListScreen,
    file: 'conversation_list_screen.dart',
    location: '/conversations',
    attention: ChatAttention(muted: true),
    afterSession: seedUnreadChats,
    settle: _openRowMenu,
  ),
  // Sam's chat with four new lines, which fit on the screen: it opens at
  // the bottom with the divider above them.
  ScreenCase(
    'chat-room-unread-divider',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    afterSession: seedShortUnreadRun,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _expectDivider,
  ),
  // Thirty new lines, more than a screen: the chat opens at the divider,
  // with the button that goes to the newest.
  ScreenCase(
    'chat-room-unread-long',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: _chat,
    afterSession: seedLongUnreadRun,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _expectOpenedAtDivider,
  ),
  // The wide shell: the rail carries the Chats badge. The newest chat
  // (Priya's) opens beside the list and is read, so Mia and Omar are left.
  ScreenCase(
    'wide-conversation-list-unread',
    screen: ConversationListScreen,
    file: 'conversation_list_screen.dart',
    location: '/conversations',
    attention: ChatAttention(muted: true),
    sizes: [wideSmall],
    chatInPane: true,
    afterSession: seedUnreadChats,
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _expectRailBadge,
  ),
];

Future<void> _expectUnreadRows(WidgetTester tester) async {
  await pumpFrames(tester, frames: 4);
  final badges = tester.widgetList<UnreadBadge>(find.byType(UnreadBadge)).map((badge) => badge.count).toList();
  expect(badges, containsAll(<int?>[3, 1, 2, null]), reason: 'the rows do not show their counts and the disc');
  _expectTabBadge(tester, find.byType(NavigationBar), '3');
}

// The Chats destination of [bar] carries a badge reading [count].
void _expectTabBadge(WidgetTester tester, Finder bar, String count) {
  final badge = tester.widget<Badge>(find.descendant(of: bar, matching: find.byType(Badge)).first);
  expect(badge.isLabelVisible, isTrue, reason: 'the Chats tab has no badge');
  expect((badge.label! as Text).data, count);
}

Future<void> _openRowMenu(WidgetTester tester) async {
  await pumpFrames(tester, frames: 4);
  await tester.longPress(find.widgetWithText(ConversationRow, 'Priya Nair'));
  await pumpFrames(tester, frames: 6);
  expect(find.text('Mark as read'), findsOneWidget, reason: 'the row menu did not open');
}

Future<void> _expectDivider(WidgetTester tester) async {
  await pumpFrames(tester, frames: 6);
  expect(find.text('4 unread messages'), findsOneWidget, reason: 'the divider is not on screen');
  expect(find.byType(ScrollToBottomButton), findsOneWidget);
  expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing, reason: 'a run that fits opens at the bottom');
}

Future<void> _expectOpenedAtDivider(WidgetTester tester) async {
  await pumpFrames(tester, frames: 12);
  expect(find.byType(ChatUnreadDivider), findsOneWidget, reason: 'the chat did not open at its divider');
  expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget, reason: 'the scroll button is not shown');
}

// On a phone (the light render) the same list has the badge in its bar.
Future<void> _expectRailBadge(WidgetTester tester) async {
  await pumpFrames(tester, frames: 6);
  if (find.byType(NavigationRail).evaluate().isEmpty) return _expectTabBadge(tester, find.byType(NavigationBar), '3');
  expect(find.byType(ChatRoomScreen), findsOneWidget, reason: 'the newest chat did not open beside the list');
  _expectTabBadge(tester, find.byType(NavigationRail), '2');
}
