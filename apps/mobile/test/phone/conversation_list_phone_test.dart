import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_parts.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_direct_chat_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_group_screen.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/layout_seed.dart';
import '../support/copy_finder.dart';
import 'phone_app.dart';

// The Chats list on a phone: the search field and the chats under a bar
// titled Chats, with nothing between them: no status line, no hero card, no
// stat tiles. The bar names the connection only while there is none.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  testWidgets('starts with the search and the chats, under a bar titled Chats', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      expect(find.byType(VeilHeroPanel), findsNothing);
      expect(find.byType(VeilMetricStrip), findsNothing);
      expect(find.text('Chats'), findsWidgets, reason: 'the bar and the tab');
      expect(find.text('VEIL'), findsNothing);
      // No status line: no count, no standing reminder, no connection while
      // there is one.
      expect(find.textContaining('8 chats'), findsNothing);
      expect(find.textContaining('No backup'), findsNothing);
      expect(find.text('Connected'), findsNothing);
      expect(find.text('Connecting…'), findsNothing);
      expect(find.widgetWithText(TextField, 'Search'), findsOneWidget);

      final rows = find.byType(ConversationRow);
      final firstRow = onScreen(tester, rows);
      expect(firstRow.top, lessThan(screenHeight(tester) * 0.3), reason: 'the first conversation is near the top');
      final whole = [
        for (final element in rows.evaluate())
          if (element.renderObject case final RenderBox box when visibleRect(tester, box).height == box.size.height)
            box,
      ];
      expect(whole.length, greaterThanOrEqualTo(4), reason: 'a 360x640 phone shows at least four whole rows');
      expect(tester.takeException(), isNull);
    });
  });

  // Larger text makes the rows taller; names and messages end in an
  // ellipsis rather than wrap or overflow.
  testWidgets('with larger text the rows grow and nothing overflows', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', textScale: 1.3, body: (world) async {
      final row = tester.getRect(find.byType(ConversationRow).first);
      expect(row.height, greaterThanOrEqualTo(64));
      expect(row.width, 360, reason: 'the row runs edge to edge');
      expect(tester.takeException(), isNull);
    });
  });

  // A row says what its last message is. The text comes from this device's
  // own store of what it decrypted, for every conversation the list names
  // and not only for chats that were opened; nothing is marked read for it.
  testWidgets('each row previews its last message, without its chat being opened', (tester) async {
    // A screen tall enough that every conversation has its row built.
    const tall = PhoneSize(412, 1400, topInset: 32, bottomInset: 24);
    await withPhoneApp(tester, identities, size: tall, location: '/conversations', body: (world) async {
      final previews = {
        for (final row in tester.widgetList<ConversationRow>(find.byType(ConversationRow))) row.title: row.snippet,
      };
      expect(previews, hasLength(8));
      expect(previews['Sam Rivera'], 'Section 7 is fine. Let us sign tomorrow.');
      expect(previews['Jonas Weber'], 'See you at nine.');
      expect(previews['Mia Chen'], 'The second mock-up is closer, but the header still feels heavy to me.');
      // Only text is quoted: other kinds are named by what they are.
      expect(previews['Omar Haddad'], 'Photo');
      expect(previews['Alexandra Montgomery-Whitfield'], 'Voice message');
      expect(previews['Lena Fischer'], 'No messages yet');
      expect(previews.values, isNot(contains('Encrypted message')));
      expect(find.text('Section 7 is fine. Let us sign tomorrow.'), findsOneWidget, reason: 'drawn on its row');

      expect(find.byType(ChatRoomScreen), findsNothing);
      expect(world.messenger.activeConversationId, isNull);
      expect(world.api.markReadCalls, isEmpty, reason: 'a preview is not a read receipt');
    });
  });

  // The list is not built behind the app lock: there is no row, and so no
  // preview, to read off a locked phone.
  testWidgets('behind the app lock there is no list, and no preview', (tester) async {
    usePhoneView(tester, phoneSmall);
    final world = await LayoutWorld.create(identities: identities, account: LayoutAccount.locked, locale: 'en');
    try {
      // The app's own router, guard and all: the guard is what keeps a
      // locked session on the lock screen.
      final router = world.container.read(appRouterProvider);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: world.container,
        child: MaterialApp.router(
          routerConfig: router,
          theme: VeilTheme.dark(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ));
      await pumpFrames(tester);
      // The messenger behind the lock holds what a row would quote.
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(world.messenger.lastMessagePreviewFor(chatConversationId), isNotNull);

      for (final location in ['/conversations', '/chat/$chatConversationId']) {
        router.go(location);
        await pumpFrames(tester, frames: 3);
        expect(find.byType(AppLockScreen), findsOneWidget, reason: location);
        expect(find.byType(ConversationListScreen), findsNothing, reason: location);
        expect(find.byType(ChatRoomScreen), findsNothing, reason: location);
        expect(find.byType(ConversationRow), findsNothing, reason: location);
        expect(find.textContaining('Section 7'), findsNothing, reason: location);
        expect(find.text('Sam Rivera'), findsNothing, reason: location);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      world.dispose();
    }
  });

  testWidgets('a group is listed under its members\' names, with the group avatar and its last message',
      (tester) async {
    await withPhoneApp(tester, identities, withGroup: true, location: '/conversations', body: (world) async {
      final row = tester.widget<ConversationRow>(find.byType(ConversationRow).first);
      expect(row.title, 'Sam Rivera, Priya Nair, Omar Haddad');
      expect(row.group, isTrue);
      expect(
        find.descendant(of: find.byType(ConversationRow).first, matching: find.byIcon(Icons.group_outlined)),
        findsOneWidget,
        reason: 'the neutral group disc, never a letter',
      );
      expect(row.semanticLabel, 'Group chat with Sam Rivera, Priya Nair, Omar Haddad');
      expect(row.snippet, 'I can bring the van after six, if someone helps me carry the shelves down.');

      await tester.tap(find.byType(ConversationRow).first);
      await pumpFrames(tester);
      expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId, groupConversationId);
    });
  });

  testWidgets('while the first list is on its way, shows nothing under the field, not an empty state',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      account: LayoutAccount.signedInEmpty,
      attention: const ChatAttention(loading: true),
      body: (world) async {
        expect(find.widgetWithText(TextField, 'Search'), findsOneWidget);
        expect(find.text('No chats yet'), findsNothing);
        expect(find.byType(VeilEmptyState), findsNothing);
        expect(find.byType(ConversationRow), findsNothing);
        expect(find.textContaining('0 chats'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('a sync error is one notice above the rows, in the app\'s words, with a retry', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      attention: const ChatAttention(relayError: true),
      body: (world) async {
        expect(find.byType(VeilNotice), findsOneWidget);
        expect(findCopy("Couldn't refresh"), findsOneWidget);
        expect(findCopy('The server could not complete the request. Try again shortly.'), findsOneWidget);
        expect(find.textContaining('The VEIL relay failed'), findsNothing, reason: 'the formatter\'s words');
        expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
        expect(find.byType(ConversationRow), findsWidgets);
      },
    );
  });

  testWidgets('starts a direct chat or a group from the bar', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.tap(find.byTooltip('New chat'));
      await pumpFrames(tester, frames: 3);
      expect(find.text('New group'), findsOneWidget);
      await tester.tap(find.text('New chat'));
      await pumpFrames(tester);
      expect(find.byType(StartDirectChatScreen), findsOneWidget);
    });
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.tap(find.byTooltip('New chat'));
      await pumpFrames(tester, frames: 3);
      await tester.tap(find.text('New group'));
      await pumpFrames(tester);
      expect(find.byType(StartGroupScreen), findsOneWidget);
    });
  });

  // The bar's one action starts a chat. Settings is a tab of the bottom bar,
  // and the security status is under it: neither has a button up here.
  testWidgets('has one action in the bar, and settings as a tab', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      expect(find.byTooltip('Security'), findsNothing);
      expect(find.byIcon(Icons.verified_user_outlined), findsNothing);
      expect(find.byTooltip('Settings'), findsNothing, reason: 'no second way to settings in the bar');
      await tester.tap(find.text('Settings'));
      await pumpFrames(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  testWidgets('a search shows its filters and lists what it found under plain headings', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.enterText(find.byType(TextField), conversationSearchQuery);
      // The archive search waits 180 ms for the typing to stop.
      await pumpFrames(tester, frames: 4);

      expect(find.text('All senders'), findsOneWidget);
      expect(find.widgetWithText(ConversationListHeader, 'Chats'), findsOneWidget);
      expect(find.widgetWithText(ConversationListHeader, 'Messages'), findsOneWidget);
      expect(find.byType(ConversationRow), findsNWidgets(2));
      // The headings count nothing the rows under them do not show.
      expect(find.text('2 matches'), findsNothing);
      expect(find.text('0 results'), findsNothing);
      // No message matches: one line says so, without a second empty state
      // under the rows that did match.
      expect(find.text('No message matches these filters.'), findsOneWidget);
      expect(find.byType(VeilEmptyState), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await pumpFrames(tester, frames: 4);
      expect(find.text('All senders'), findsNothing);
      expect(find.text('Messages'), findsNothing);
    });
  });

  testWidgets('with no conversation yet, offers to start one', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      account: LayoutAccount.signedInEmpty,
      body: (world) async {
        expect(find.text('No chats yet'), findsOneWidget);
        await tester.tap(find.text('New chat'));
        await pumpFrames(tester);
        expect(find.byType(StartDirectChatScreen), findsOneWidget);
      },
    );
  });
}
