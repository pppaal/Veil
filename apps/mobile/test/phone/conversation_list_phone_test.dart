import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_parts.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_direct_chat_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_group_screen.dart';
import 'package:veil_mobile/src/features/security_status/presentation/security_status_screen.dart';
import 'package:veil_mobile/src/features/settings/presentation/settings_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/layout_seed.dart';
import '../support/copy_finder.dart';
import 'phone_app.dart';

// The conversation list on a phone: conversations first, and what the hero
// card, the stat tiles and the buttons at the end of the list carried is in
// the status line and the bar.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  testWidgets('starts with the conversations, under one line of status and the search', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      expect(find.byType(VeilHeroPanel), findsNothing);
      expect(find.byType(VeilMetricStrip), findsNothing);
      // What the hero card said: the relay, the count, and that nothing is
      // backed up.
      expect(find.text('Relay linked  ·  8 conversations  ·  No backup'), findsOneWidget,
          reason: 'one line at the default text size');
      expect(find.widgetWithText(TextField, 'Search chats and messages'), findsOneWidget);

      final rows = find.byType(VeilConversationCard);
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

  // Where the line is too long (360 px at 1.3x) it breaks between two
  // parts, and the dot that separates parts is drawn only between two that
  // share a line: no line ends with one, and none starts with one.
  testWidgets('with larger text the status line wraps between its parts, with no separator left hanging',
      (tester) async {
    const lines = ['Relay linked  ·  8 conversations', 'No backup'];
    await withPhoneApp(tester, identities, location: '/conversations', textScale: 1.3, body: (world) async {
      final rects = [for (final line in lines) tester.getRect(find.text(line))];
      for (final (index, rect) in rects.indexed) {
        expect(rect.height, rects.first.height, reason: '"${lines[index]}" is one line');
        expect(rect.right, lessThanOrEqualTo(360), reason: '"${lines[index]}" fits the screen');
        if (index > 0) expect(rect.top, greaterThanOrEqualTo(rects[index - 1].bottom));
      }
      // Nothing drawn on the list starts or ends with the separator.
      final hanging = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .where((data) => data.trim().startsWith('·') || data.trim().endsWith('·'));
      expect(hanging, isEmpty);
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
        for (final row in tester.widgetList<VeilConversationCard>(find.byType(VeilConversationCard)))
          row.title: row.subtitle,
      };
      expect(previews, hasLength(8));
      expect(previews['Sam Rivera'], 'Section 7 is fine. Let us sign tomorrow.');
      expect(previews['Jonas Weber'], 'See you at nine.');
      expect(previews['Mia Chen'], 'The second mock-up is closer, but the header still feels heavy to me.');
      // Only text is quoted: other kinds are named by what they are.
      expect(previews['Omar Haddad'], 'Encrypted image');
      expect(previews['Alexandra Montgomery-Whitfield'], 'Encrypted voice note');
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
        expect(find.byType(VeilConversationCard), findsNothing, reason: location);
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

  testWidgets('a group is listed under its members\' names, with the group mark and its last message',
      (tester) async {
    await withPhoneApp(tester, identities, withGroup: true, location: '/conversations', body: (world) async {
      final row = tester.widget<VeilConversationCard>(find.byType(VeilConversationCard).first);
      expect(row.title, 'Sam Rivera, Priya Nair, Omar Haddad');
      expect(row.titleIcon, Icons.group_rounded);
      expect(row.semanticLabel, 'Group conversation with Sam Rivera, Priya Nair, Omar Haddad');
      expect(row.subtitle, 'I can bring the van after six, if someone helps me carry the shelves down.');
      expect(find.textContaining('9 conversations'), findsOneWidget);

      await tester.tap(find.byType(VeilConversationCard).first);
      await pumpFrames(tester);
      expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId, groupConversationId);
    });
  });

  testWidgets('while the first list is on its way, shows rows to come, not an empty state', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      account: LayoutAccount.signedInEmpty,
      attention: const ChatAttention(loading: true),
      body: (world) async {
        expect(find.byType(ConversationListSkeleton), findsOneWidget);
        expect(find.text('No conversations yet'), findsNothing);
        // Nobody knows the count yet, so the status line does not give one.
        expect(find.text('Relay linked  ·  No backup'), findsOneWidget);
        expect(find.textContaining('0 conversations'), findsNothing);
        expect(find.byType(VeilSurfaceCard), findsNothing, reason: 'placeholders have the shape of rows, not of cards');
        expect(
          find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Loading…'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('a sync error is one banner above the rows, in the app\'s words', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      attention: const ChatAttention(relayError: true),
      body: (world) async {
        expect(find.byType(VeilInlineBanner), findsOneWidget);
        expect(findCopy('The VEIL relay could not complete the request. Try again shortly.'), findsOneWidget);
        expect(find.textContaining('The VEIL relay failed'), findsNothing, reason: 'the formatter\'s words');
        expect(find.byType(VeilConversationCard), findsWidgets);
      },
    );
  });

  testWidgets('starts a direct chat or a group from the bar', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.tap(find.byTooltip('New conversation'));
      await pumpFrames(tester, frames: 3);
      expect(find.text('New group'), findsOneWidget);
      await tester.tap(find.text('New direct chat'));
      await pumpFrames(tester);
      expect(find.byType(StartDirectChatScreen), findsOneWidget);
    });
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.tap(find.byTooltip('New conversation'));
      await pumpFrames(tester, frames: 3);
      await tester.tap(find.text('New group'));
      await pumpFrames(tester);
      expect(find.byType(StartGroupScreen), findsOneWidget);
    });
  });

  // Settings is a tab of the bottom bar, so the bar above keeps only what
  // has no tab: security status.
  testWidgets('keeps security status in the bar, and has settings as a tab', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.tap(find.byTooltip('Security status'));
      await pumpFrames(tester);
      expect(find.byType(SecurityStatusScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await pumpFrames(tester);

      expect(find.byTooltip('Settings'), findsNothing, reason: 'no second way to settings in the bar');
      await tester.tap(find.text('Settings'));
      await pumpFrames(tester);
      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  testWidgets('a search shows its filters, says it stays on the device, and lists what it found',
      (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.enterText(find.byType(TextField), conversationSearchQuery);
      // The archive search waits 180 ms for the typing to stop.
      await pumpFrames(tester, frames: 4);

      expect(find.text('All senders'), findsOneWidget);
      expect(find.text('Search stays on this device.'), findsOneWidget);
      expect(find.text('CONVERSATIONS'), findsOneWidget);
      expect(find.text('2 matches'), findsOneWidget);
      expect(find.text('MESSAGES'), findsOneWidget);
      expect(find.byType(VeilConversationCard), findsNWidgets(2));
      // No message matches: the heading counts none and one line says so,
      // without a second empty state under the rows that did match.
      expect(find.text('0 results'), findsOneWidget);
      expect(find.text('No message on this device matches with these filters.'), findsOneWidget);
      expect(find.byType(VeilEmptyState), findsNothing);
      // The status line still counts every conversation, not the matches.
      expect(find.textContaining('8 conversations'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear search'));
      await pumpFrames(tester, frames: 4);
      expect(find.text('All senders'), findsNothing);
      expect(find.text('MESSAGES'), findsNothing);
    });
  });

  testWidgets('with no conversation yet, offers to start one', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      account: LayoutAccount.signedInEmpty,
      body: (world) async {
        expect(find.text('No conversations yet'), findsOneWidget);
        await tester.tap(find.text('Start direct chat'));
        await pumpFrames(tester);
        expect(find.byType(StartDirectChatScreen), findsOneWidget);
      },
    );
  });
}
