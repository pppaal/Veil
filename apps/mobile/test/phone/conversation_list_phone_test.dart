import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/domain/message_search.dart';
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
      expect(previews['Sam Rivera'], latestChatLine);
      expect(previews['Jonas Weber'], latestTimerChatLine);
      expect(previews['Mia Chen'], 'can you send the photos from saturday?');
      // Only text is quoted: other kinds are named by what they are.
      expect(previews['Omar Haddad'], 'Photo');
      expect(previews['Alexandra Montgomery-Whitfield'], 'Voice message');
      expect(previews['Lena Fischer'], 'No messages yet');
      expect(previews.values, isNot(contains('Encrypted message')));
      expect(find.text(latestChatLine), findsOneWidget, reason: 'drawn on its row');

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
        expect(find.textContaining(latestChatLine), findsNothing, reason: location);
        expect(find.text('Sam Rivera'), findsNothing, reason: location);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      world.dispose();
    }
  });

  testWidgets('a group is listed under its name, with the group avatar and its last message',
      (tester) async {
    await withPhoneApp(tester, identities, withGroup: true, location: '/conversations', body: (world) async {
      final row = tester.widget<ConversationRow>(find.byType(ConversationRow).first);
      // The relay's list leaves the name out; the app asked for it once.
      expect(row.title, groupName);
      expect(world.api.groupFetches, {groupConversationId: 1});
      expect(row.group, isTrue);
      expect(
        find.descendant(of: find.byType(ConversationRow).first, matching: find.byIcon(Icons.group_outlined)),
        findsOneWidget,
        reason: 'the neutral group disc, never a letter',
      );
      expect(row.semanticLabel, '$groupName, group chat');
      // Led by who wrote it, as Signal, WhatsApp and Telegram do in a group.
      expect(row.snippet, 'Omar: $latestGroupLine');

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

  testWidgets('a sync error is one line above the rows, with a retry and no box', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      attention: const ChatAttention(relayError: true),
      body: (world) async {
        expect(find.byType(VeilNotice), findsNothing);
        expect(findCopy("Couldn't refresh chats"), findsOneWidget);
        expect(find.textContaining('server'), findsNothing, reason: 'no second line on what the server did');
        expect(find.textContaining('The VEIL relay failed'), findsNothing, reason: 'the formatter\'s words');
        expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
        expect(find.byType(ConversationRow), findsWidgets);
      },
    );
  });

  testWidgets('the pencil opens New chat, whose first row starts a group', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.tap(find.byTooltip('New chat'));
      await pumpFrames(tester);
      expect(find.byType(StartDirectChatScreen), findsOneWidget, reason: 'no menu in between');
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

  testWidgets('a search has no filters, and lists what it found under plain headings', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      final emptyField = tester.getRect(find.byType(TextField));
      expect(emptyField.height, 44);
      await tester.enterText(find.byType(TextField), conversationSearchQuery);
      // The archive search waits 180 ms for the typing to stop.
      await pumpFrames(tester, frames: 4);

      // The clear button is as tall as the field: nothing moves under it.
      expect(tester.getRect(find.byType(TextField)), emptyField);
      expect(tester.getSize(find.widgetWithIcon(IconButton, Icons.close)), const Size.square(44));
      expect(find.byType(ChoiceChip), findsNothing, reason: 'no filter chips');
      expect(find.widgetWithText(ConversationListHeader, 'Chats'), findsOneWidget);
      // No message matches: that part is left out, heading and all.
      expect(find.widgetWithText(ConversationListHeader, 'Messages'), findsNothing);
      expect(find.byType(ConversationRow), findsNWidgets(2));
      // The headings count nothing the rows under them do not show.
      expect(find.text('2 matches'), findsNothing);
      expect(find.text('0 results'), findsNothing);
      expect(find.byType(VeilEmptyState), findsNothing);

      // Nothing at all: one line says so.
      await tester.enterText(find.byType(TextField), 'zzzz');
      await pumpFrames(tester, frames: 4);
      expect(find.text('No results for "zzzz"'), findsOneWidget);
      expect(find.byType(ConversationListHeader), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await pumpFrames(tester, frames: 4);
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

  // The empty state sits a little above the middle of the space under the
  // field, but that space is a floor: with the keyboard up or the phone on
  // its side the state is taller than it, and the list scrolls to the
  // button instead of cutting through it.
  for (final (name, size, keyboard, scale) in [
    ('with the keyboard up', phoneSmall, 300.0, 1.0),
    ('with the keyboard up and larger text', phoneSmall, 300.0, 1.3),
    ('on its side', const PhoneSize(640, 360, topInset: 0, bottomInset: 0), 0.0, 1.0),
  ]) {
    testWidgets('with no conversation yet and $name, the state does not overflow and its button takes a tap',
        (tester) async {
      await withPhoneApp(
        tester,
        identities,
        location: '/conversations',
        account: LayoutAccount.signedInEmpty,
        size: size,
        keyboardHeight: keyboard,
        textScale: scale,
        body: (world) async {
          expect(tester.takeException(), isNull, reason: 'the empty state overflowed its box');
          final button = find.widgetWithText(VeilButton, 'New chat');
          await tester.dragUntilVisible(button, find.byType(ListView), const Offset(0, -40));
          await pumpFrames(tester, frames: 2);
          final box = tester.renderObject<RenderBox>(find.descendant(of: button, matching: find.byType(OutlinedButton)));
          expect(whyNotWhollyTappable(tester, box), isNull);
          await tester.tap(button);
          await pumpFrames(tester);
          expect(find.byType(StartDirectChatScreen), findsOneWidget);
        },
      );
    });
  }

  // A message found in a group is shown under the group, as its row is: the
  // neutral disc and the group's name, not a letter and the name of one
  // member.
  testWidgets('a message found in a group shows the group\'s avatar and name', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      withGroup: true,
      location: '/conversations',
      prepare: (world) async {
        // The search reads the chat's peer, which in a group is a member.
        world.cache.archiveHits = [
          MessageSearchResult(
            conversationId: groupConversationId,
            messageId: 'group-hit',
            peerHandle: peerHandle,
            peerDisplayName: 'Sam Rivera',
            sentAt: DateTime.utc(2026, 4, 7, 9, 12),
            messageKind: MessageKind.text,
            isMine: false,
            bodySnippet: 'I can bring the van after six',
          ),
        ];
        return null;
      },
      body: (world) async {
        await tester.enterText(find.byType(TextField), 'van');
        // The archive search waits 180 ms for the typing to stop.
        await pumpFrames(tester, frames: 4);
        final tile = find.byType(MessageSearchResultTile);
        await tester.dragUntilVisible(tile, find.byType(ListView), const Offset(0, -200));
        await pumpFrames(tester, frames: 2);

        expect(find.descendant(of: tile, matching: find.byIcon(Icons.group_outlined)), findsOneWidget);
        expect(find.descendant(of: tile, matching: find.text('S')), findsNothing, reason: 'no letter on a group');
        expect(
          find.descendant(of: tile, matching: find.text(groupName)),
          findsOneWidget,
          reason: 'named as the group\'s row is',
        );
        expect(find.descendant(of: tile, matching: find.text('Sam Rivera')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  // As the group's row leads its last message ("Omar: …"): a hit in a
  // group says who wrote it, by the first name of the nickname this phone
  // gave them; the user's own by "You: "; and one from a device no member
  // is known for, by nothing.
  testWidgets('a message found in a group is led by who wrote it, as the group\'s row is', (tester) async {
    MessageSearchResult hit(String id, {required String body, String? device, bool mine = false}) => MessageSearchResult(
          conversationId: groupConversationId,
          messageId: id,
          peerHandle: peerHandle,
          peerDisplayName: null,
          sentAt: DateTime.utc(2026, 4, 7, 9, 12),
          messageKind: MessageKind.text,
          isMine: mine,
          bodySnippet: body,
          senderDeviceId: device,
        );
    await withPhoneApp(
      tester,
      identities,
      withGroup: true,
      location: '/conversations',
      prepare: (world) async {
        world.cache.archiveHits = [
          hit('omar-hit', body: 'the van after 6', device: 'dev-omar_h'),
          hit('own-hit', body: 'the van is booked', device: 'dev-$selfHandle', mine: true),
          hit('unknown-hit', body: 'van keys at the desk', device: 'dev-nobody'),
        ];
        return null;
      },
      body: (world) async {
        await tester.enterText(find.byType(TextField), 'van');
        // The archive search waits 180 ms for the typing to stop.
        await pumpFrames(tester, frames: 4);
        final tiles = find.byType(MessageSearchResultTile);
        await tester.dragUntilVisible(tiles.last, find.byType(ListView), const Offset(0, -200));
        await pumpFrames(tester, frames: 4);
        String snippetOf(String id) {
          final tile = find.byWidgetPredicate(
            (widget) => widget is MessageSearchResultTile && widget.result.messageId == id,
          );
          final snippet = find.descendant(of: tile, matching: find.byType(RichText)).last;
          return tester.widget<RichText>(snippet).text.toPlainText();
        }

        final l10n = lookupAppLocalizations(const Locale('en'));
        expect(snippetOf('omar-hit'), l10n.conversationsPreviewSender('Omar', 'the van after 6'));
        expect(snippetOf('own-hit'), l10n.conversationsPreviewYou('the van is booked'));
        expect(snippetOf('unknown-hit'), 'van keys at the desk');
        expect(tester.takeException(), isNull);
      },
    );
  });

  // As the chat's row leads its preview: the user's own words found by a
  // search say so, someone else's do not.
  testWidgets('a message of the user\'s own found by search is led by "You: "', (tester) async {
    MessageSearchResult hit(String id, {required bool mine, required String body}) => MessageSearchResult(
          conversationId: chatConversationId,
          messageId: id,
          peerHandle: peerHandle,
          peerDisplayName: 'Sam Rivera',
          sentAt: DateTime.utc(2026, 4, 7, 9, 12),
          messageKind: MessageKind.text,
          isMine: mine,
          bodySnippet: body,
        );
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      prepare: (world) async {
        world.cache.archiveHits = [
          hit('own-hit', mine: true, body: 'bring the van at six'),
          hit('their-hit', mine: false, body: 'the van is booked'),
        ];
        return null;
      },
      body: (world) async {
        await tester.enterText(find.byType(TextField), 'van');
        // The archive search waits 180 ms for the typing to stop.
        await pumpFrames(tester, frames: 4);
        final tiles = find.byType(MessageSearchResultTile);
        await tester.dragUntilVisible(tiles.last, find.byType(ListView), const Offset(0, -200));
        await pumpFrames(tester, frames: 2);
        String snippetOf(String id) {
          final tile = find.byWidgetPredicate(
            (widget) => widget is MessageSearchResultTile && widget.result.messageId == id,
          );
          final snippet = find.descendant(of: tile, matching: find.byType(RichText)).last;
          return tester.widget<RichText>(snippet).text.toPlainText();
        }

        final l10n = lookupAppLocalizations(const Locale('en'));
        expect(snippetOf('own-hit'), l10n.conversationsPreviewYou('bring the van at six'));
        expect(snippetOf('their-hit'), 'the van is booked');
        expect(tester.takeException(), isNull);
      },
    );
  });
}
