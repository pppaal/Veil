import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/router/main_tab_shell.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_unread_divider.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_phone.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';
import 'package:veil_mobile/src/features/conversations/presentation/unread_chats.dart';
import 'package:veil_mobile/src/shared/presentation/veil_shell.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/layout_seed.dart';
import '../layout/support/unread_seed.dart';
import 'phone_app.dart';

// Unread counts in the app on a phone and in the wide layout: the rows'
// badges, the Chats tab, the long-press menu, and what opening a chat or
// "Mark as read" sends. The world's first list reads the seeded morning
// through; what arrives after it (unread_seed.dart) is unread.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  Finder row(String title) => find.widgetWithText(ConversationRow, title);
  ConversationRow rowOf(WidgetTester tester, String title) => tester.widget<ConversationRow>(row(title));
  UnreadBadge? badgeOf(WidgetTester tester, String title) {
    final badge = find.descendant(of: row(title), matching: find.byType(UnreadBadge));
    return badge.evaluate().isEmpty ? null : tester.widget<UnreadBadge>(badge);
  }

  Badge tabBadge(WidgetTester tester, Type bar) =>
      tester.widget<Badge>(find.descendant(of: find.byType(bar), matching: find.byType(Badge)).first);
  // What the Chats badge of [bar] reads.
  String? tabBadgeText(WidgetTester tester, Type bar) => tester
      .widget<Text>(find.descendant(
          of: find.descendant(of: find.byType(bar), matching: find.byType(Badge)).first, matching: find.byType(Text)))
      .data;

  Future<void> longPressRow(WidgetTester tester, String title) async {
    await tester.longPress(row(title));
    await pumpFrames(tester, frames: 4);
  }

  testWidgets('arrivals count on their rows, a muted chat in grey, and the tab counts unread chats', (tester) async {
    await withPhoneApp(tester, identities,
        size: phoneLarge,
        location: '/conversations',
        attention: const ChatAttention(muted: true),
        afterSession: seedUnreadChats, body: (world) async {
      expect(badgeOf(tester, 'Priya Nair')?.count, 3);
      expect(badgeOf(tester, 'Mia Chen')?.count, 1);
      expect((badgeOf(tester, 'Jonas Weber')?.count, badgeOf(tester, 'Jonas Weber')?.muted), (2, true));
      expect(badgeOf(tester, 'Omar Haddad')?.count, isNull, reason: 'marked unread: the disc');
      expect(rowOf(tester, 'Omar Haddad').markedUnread, isTrue);
      expect(badgeOf(tester, 'Sam Rivera'), isNull);
      expect(badgeOf(tester, 'Alexandra Montgomery-Whitfield'), isNull, reason: 'the first list read the morning');

      // Priya, Mia and Omar; Jonas is muted.
      final badge = tabBadge(tester, NavigationBar);
      expect(badge.isLabelVisible, isTrue);
      expect(tabBadgeText(tester, NavigationBar), '3');
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp('3 unread chats')), findsOneWidget);
      // The count rides on the icon, which the destination reads before its
      // name (design system, section 16).
      expect(tester.getSemantics(find.byType(NavigationDestination).first).label,
          '3 unread chats\nChats\nTab 1 of 3');
      semantics.dispose();
    });
  });

  testWidgets('opening a chat and coming back clears its badge, with one read receipt', (tester) async {
    await withPhoneApp(tester, identities,
        size: phoneLarge, location: '/conversations', afterSession: seedUnreadChats, body: (world) async {
      expect(world.api.markReadCalls, isEmpty);
      await tester.tap(row('Priya Nair'));
      await pumpFrames(tester);
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(find.text('3 unread messages'), findsOneWidget);

      await tester.tap(find.byType(VeilBackButton));
      await pumpFrames(tester);
      expect(badgeOf(tester, 'Priya Nair'), isNull);
      expect(rowOf(tester, 'Priya Nair').unreadCount, 0);
      final newest = world.messenger.messagesFor(noticeChatConversationId).last;
      expect(world.api.markReadCalls, [newest.id], reason: 'one receipt, for the newest of the three');
      // Mia, Jonas and Omar are left.
      expect(tabBadgeText(tester, NavigationBar), '3');
    });
  });

  testWidgets('Mark as unread from the menu draws the disc and sends nothing; Mark as read sends one receipt',
      (tester) async {
    await withPhoneApp(tester, identities,
        size: phoneLarge, location: '/conversations', afterSession: seedUnreadChats, body: (world) async {
      // Sam's chat was read by the first list.
      await longPressRow(tester, 'Sam Rivera');
      expect(find.text('Mark as read'), findsNothing);
      await tester.tap(find.text('Mark as unread'));
      await pumpFrames(tester, frames: 4);
      expect(rowOf(tester, 'Sam Rivera').markedUnread, isTrue);
      expect(badgeOf(tester, 'Sam Rivera')?.count, isNull);
      expect(world.api.markReadCalls, isEmpty, reason: 'marking unread is local');

      await longPressRow(tester, 'Sam Rivera');
      await tester.tap(find.text('Mark as read'));
      await pumpFrames(tester, frames: 4);
      expect(rowOf(tester, 'Sam Rivera').markedUnread, isFalse);
      expect(world.api.markReadCalls, isEmpty, reason: 'nothing new was read');

      await longPressRow(tester, 'Mia Chen');
      expect(find.text('Mute notifications'), findsOneWidget);
      await tester.tap(find.text('Mark as read'));
      await pumpFrames(tester, frames: 4);
      expect(badgeOf(tester, 'Mia Chen'), isNull);
      final newest = world.messenger.messagesFor('conv-mia').last;
      expect(world.api.markReadCalls, [newest.id]);
      expect(find.byType(ChatRoomScreen), findsNothing, reason: 'marking does not open the chat');
    });
  });

  testWidgets('a blocked peer\'s chat counts in grey and is left out of the tab', (tester) async {
    await withPhoneApp(tester, identities,
        size: phoneLarge,
        location: '/conversations',
        attention: const ChatAttention(peerBlocked: true),
        afterSession: (world) async {
      // What Sam sent just before the block, which the relay had taken.
      final blocks = Map.of(world.relay.blocks);
      world.relay.blocks.clear();
      await deliverLines(world, peerHandle, ['one more thing'], firstAt: DateTime.utc(2026, 4, 7, 10, 10));
      world.relay.blocks.addAll(blocks);
    }, body: (world) async {
      final badge = badgeOf(tester, 'Sam Rivera')!;
      expect((badge.count, badge.muted), (1, true));
      expect(find.descendant(of: row('Sam Rivera'), matching: find.byIcon(Icons.notifications_off_outlined)),
          findsNothing);
      expect(tabBadge(tester, NavigationBar).isLabelVisible, isFalse);
    });
  });

  testWidgets('a chat held for who its peer is clears its badge when opened, and sends no receipt', (tester) async {
    await withPhoneApp(tester, identities,
        size: phoneLarge,
        location: '/conversations',
        withGroup: true,
        attention: const ChatAttention(identityChangedInGroup: true),
        afterSession: (world) =>
            deliverLines(world, peerHandle, samShortRun, firstAt: DateTime.utc(2026, 4, 7, 10, 15)),
        body: (world) async {
      expect(world.messenger.reads.receiptsWithheld(chatConversationId), isTrue);
      expect(badgeOf(tester, 'Sam Rivera')?.count, samShortRun.length);
      await tester.tap(row('Sam Rivera'));
      await pumpFrames(tester);
      await tester.tap(find.byType(VeilBackButton));
      await pumpFrames(tester);
      expect(badgeOf(tester, 'Sam Rivera'), isNull);
      expect(world.api.markReadCalls, isEmpty);
    });
  });

  testWidgets('the wide layout badges Chats in the rail, and offers no Mark as unread for the open chat',
      (tester) async {
    await withPhoneApp(tester, identities,
        size: wideSmall, location: '/conversations', afterSession: seedUnreadChats, body: (world) async {
      Finder inList(Finder finder) => find.descendant(of: find.byType(ConversationListPhone), matching: finder);
      // The newest chat, Priya's, is open beside the list, and read.
      expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId, noticeChatConversationId);
      // Mia, Jonas and Omar are left.
      expect(tabBadgeText(tester, NavigationRail), '3');

      await tester.longPress(inList(row('Priya Nair')));
      await pumpFrames(tester, frames: 4);
      expect(find.text('Mark as unread'), findsNothing);
      expect(find.text('Mark as read'), findsNothing);
      expect(find.text('Mute notifications'), findsOneWidget);
      // A tap outside the menu closes it.
      await tester.tapAt(const Offset(900, 700));
      await pumpFrames(tester, frames: 4);
      expect(find.text('Mute notifications'), findsNothing);

      await tester.longPress(inList(row('Sam Rivera')));
      await pumpFrames(tester, frames: 4);
      expect(find.text('Mark as unread'), findsOneWidget, reason: 'a chat not open beside the list can be');
    });
  });

  testWidgets('the Chats badge reads 99, then 99+, its pill ringed in the bar\'s colour where the platform puts it',
      (tester) async {
    for (final (count, label) in [(99, '99'), (100, '99+')]) {
      await withPhoneApp(tester, identities,
          size: phoneMedium,
          location: '/conversations',
          overrides: [unreadChatsProvider.overrideWith((ref) => count)], body: (world) async {
        expect(tabBadgeText(tester, NavigationBar), label);
        final pill = find.byKey(const ValueKey('chats-badge-pill'));
        // The badge's own pill, closest above the label, is the ring.
        final ring = find.ancestor(of: pill, matching: find.byType(Container)).first;
        final palette = tester.element(pill).veilPalette;
        expect((tester.widget<Container>(ring).decoration! as ShapeDecoration).color, palette.canvas);
        expect((tester.widget<Container>(pill).decoration! as ShapeDecoration).color, palette.primary);
        expect(tester.getRect(pill), tester.getRect(ring).deflate(MainTabShell.badgeRing));
        // Material's place for a badge: 12 in from the glyph's start, 4 above it.
        final glyph = tester.getRect(find.descendant(of: find.byType(Badge).first, matching: find.byType(Icon)));
        expect(tester.getRect(pill).topLeft - glyph.topLeft, const Offset(12, -4));
      });
    }
  });

  testWidgets('in the wide layout the unread band runs to both edges of the pane', (tester) async {
    await withPhoneApp(tester, identities,
        size: wideSmall, location: '/conversations', afterSession: seedUnreadChats, body: (world) async {
      // Priya's chat opens beside the list with her three lines unread; the
      // chat's column is narrower than the pane.
      expect(find.text('3 unread messages'), findsOneWidget);
      final pane = tester.getRect(find.byType(ChatRoomScreen));
      final list = tester.getRect(find.byType(ChatMessageList));
      expect(list.width, lessThan(pane.width));
      final band = tester.getRect(find.descendant(of: find.byType(ChatUnreadDivider), matching: find.byType(ColoredBox)));
      expect(band.left, moreOrLessEquals(pane.left));
      expect(band.right, moreOrLessEquals(pane.right));
      // The message area clips above and below, not at the column's sides.
      final clip = tester.renderObject<RenderClipRect>(
          find.descendant(of: find.byType(ChatMessageList), matching: find.byType(ClipRect)).first);
      final clipped = clip.clipper!.getClip(clip.size).shift(clip.localToGlobal(Offset.zero));
      expect(clipped.left, lessThanOrEqualTo(band.left + 0.01));
      expect(clipped.right, greaterThanOrEqualTo(band.right - 0.01));
    });
  });
}
