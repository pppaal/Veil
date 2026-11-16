import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_direct_chat_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_group_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../support/copy_finder.dart';
import 'phone_app.dart';

// Starting a 1:1 chat or a group on a phone. New chat is a search field,
// then "New group" and "One-time link", then the contacts; a typed handle
// that is no contact's becomes "Chat with @…". New group is its fields, the
// members as chips with the one rule under them, and the button.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  // New chat as a user reaches it: the pencil in the list's bar.
  Future<void> openNewChat(WidgetTester tester) async {
    await tester.tap(find.byTooltip(en.conversationsNewTooltip));
    await pumpFrames(tester);
  }

  // Within the start screen: the list under it has a field of its own.
  Finder on(Type screen, Type widget) => find.descendant(of: find.byType(screen), matching: find.byType(widget));

  group('a direct chat', () {
    testWidgets('opens on the search field, then New group and One-time link, then the contacts', (tester) async {
      await withPhoneApp(tester, identities, location: '/start-chat', body: (world) async {
        final field = tester.getRect(find.byType(TextField));
        final group = tester.getRect(find.text(en.conversationsNewGroup));
        final link = tester.getRect(find.text(en.oneTimeLinkTitle));
        expect(field.top, lessThan(140), reason: 'the field is the first thing under the bar');
        expect(field.bottom, lessThan(group.top));
        expect(group.bottom, lessThan(link.top));
        expect(find.text(en.startDirectContactsHeader), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing, reason: 'a row is the action');
        expect(find.byType(VeilNotice), findsNothing, reason: 'no notice for information');
        // Typing filters: the rows that start something else go.
        await tester.enterText(find.byType(TextField), 'zzzz');
        await tester.pump();
        expect(find.text(en.conversationsNewGroup), findsNothing);
      });
    });

    testWidgets('opens the chat with the handle that was typed, in the screen\'s place', (tester) async {
      await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
        await openNewChat(tester);
        expect(find.byType(StartDirectChatScreen), findsOneWidget);

        // A contact's handle filters the contacts down to them: their row
        // opens the chat.
        await tester.enterText(on(StartDirectChatScreen, TextField), '@$emptyChatPeerHandle');
        await tester.pump();
        expect(find.text(en.startDirectChatWith(emptyChatPeerHandle)), findsNothing, reason: 'a contact has their row');
        await tester.tap(find.byKey(const ValueKey('start-contact-$emptyChatPeerHandle')));
        await pumpFrames(tester, frames: 10);

        expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId, emptyChatConversationId);
        expect(find.byType(StartDirectChatScreen, skipOffstage: false), findsNothing);

        // Back leads to the list, not to the form again.
        await tester.tap(find.byTooltip('Back'));
        await pumpFrames(tester, frames: 6);
        expect(find.byType(ConversationListScreen), findsOneWidget);
        expect(find.byType(StartDirectChatScreen, skipOffstage: false), findsNothing);
      });
    });

    testWidgets('says when the handle opens nothing, and only then', (tester) async {
      await withPhoneApp(tester, identities, location: '/start-chat', prepare: (world) async {
        // The messenger failed at something else before the screen opened.
        await world.messenger.startConversationByHandle('nobody');
        expect(world.messenger.errorMessage, isNotNull);
        return null;
      }, body: (world) async {
        expect(findCopy(en.safetyAccountNotFound('nobody')), findsNothing, reason: 'another screen\'s failure is not shown here');

        // A handle nobody has: a toast names it, and the screen stays.
        await tester.enterText(find.byType(TextField), 'nobody');
        await tester.pump();
        await tester.tap(find.text(en.startDirectChatWith('nobody')));
        await pumpFrames(tester, frames: 6);
        expect(find.byType(StartDirectChatScreen), findsOneWidget);
        expect(findCopy(en.safetyAccountNotFound('nobody')), findsOneWidget);
        expect(find.byType(VeilNotice), findsNothing);
      });
    });
  });

  group('a group', () {
    testWidgets('opens on its fields and the button, all on the first screenful of a 360x640 phone', (tester) async {
      await withPhoneApp(tester, identities, location: '/start-group', body: (world) async {
        final fields = find.byType(TextField);
        expect(fields, findsNWidgets(3));
        final button = tester.getRect(find.byType(FilledButton));
        expect(tester.getRect(fields.first).top, lessThan(140));
        expect(tester.getRect(fields.last).bottom, lessThan(button.top));
        expect(find.text(en.startGroupNameInput), findsOneWidget, reason: 'the label says it is required');
        expect(button.bottom, lessThanOrEqualTo(640));

        // This build has no public groups and cannot add members later:
        // the screen offers neither, and says the second.
        expect(find.byType(Switch), findsNothing);
        expect(findCopy(en.startGroupMembersCaption), findsOneWidget);
        await scrollToEnd(tester);
        expect(findCopy(en.startGroupNote), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('makes a chip of each handle a space or a comma ends, and counts the members', (tester) async {
      await withPhoneApp(tester, identities, location: '/start-group', body: (world) async {
        final members = find.byType(TextField).at(2);
        expect(find.textContaining(RegExp(r'^\d+ members?$')), findsNothing);
        await tester.enterText(members, 'lena');
        await tester.pump();
        expect(find.text('1 member'), findsOneWidget);
        expect(find.byType(InputChip), findsNothing, reason: 'a handle still being typed');
        await tester.enterText(find.byType(TextField).at(2), 'lena, @omar  jonas');
        await tester.pump();
        expect(find.text('3 members'), findsOneWidget);
        expect(find.widgetWithText(InputChip, '@lena'), findsOneWidget);
        expect(find.widgetWithText(InputChip, '@omar'), findsOneWidget);
      });
    });

    // This build cannot add members to a group later, and the relay puts
    // the creator in by itself: a group made without anyone else would stay
    // a group of one.
    testWidgets('waits for a name and for a member other than the creator', (tester) async {
      await withPhoneApp(tester, identities, location: '/start-group', body: (world) async {
        final fields = find.byType(TextField);
        FilledButton create() => tester.widget(find.byType(FilledButton));
        expect(create().onPressed, isNull, reason: 'nothing typed');

        await tester.enterText(fields.at(0), 'Movers');
        await tester.pump();
        expect(create().onPressed, isNull, reason: 'a name and no member');

        // The creator's own handle, however it is written, is nobody else.
        await tester.enterText(fields.at(2), '@Alex, alex');
        await tester.pump();
        expect(create().onPressed, isNull, reason: 'only the creator');
        expect(find.textContaining(RegExp(r'^\d+ members?$')), findsNothing, reason: 'no member is counted');

        await tester.enterText(fields.at(2), 'alex, lena');
        await tester.pump();
        expect(find.text('1 member'), findsOneWidget);
        expect(create().onPressed, isNotNull);

        await tester.enterText(fields.at(0), '   ');
        await tester.pump();
        expect(create().onPressed, isNull, reason: 'a member and no name');

        await tester.enterText(fields.at(0), 'Movers');
        await tester.pump();
        await tester.tap(find.byType(FilledButton));
        await pumpFrames(tester, frames: 10);
        expect(world.api.createdGroups.single['memberHandles'], ['lena'], reason: 'the creator is not sent as a member');
        // Opened by itself, with no list under it to go back to.
        expect(find.byType(StartGroupScreen, skipOffstage: false), findsNothing);
        expect(find.byType(ConversationListScreen), findsOneWidget);
      });
    });

    testWidgets('creates the group with its name and members, never public, and returns to the list',
        (tester) async {
      await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
        await openNewChat(tester);
        await tester.tap(find.text(en.conversationsNewGroup));
        await pumpFrames(tester);
        final fields = on(StartGroupScreen, TextField);
        final create = on(StartGroupScreen, FilledButton);
        expect(tester.widget<FilledButton>(create).onPressed, isNull, reason: 'no name yet');

        await tester.enterText(fields.at(0), 'Movers');
        await tester.pump();
        expect(tester.widget<FilledButton>(create).onPressed, isNull, reason: 'no member yet');
        await tester.enterText(fields.at(1), 'The 14th');
        await tester.enterText(fields.at(2), 'lena, @omar');
        await tester.pump();
        await tester.tap(create);
        await pumpFrames(tester, frames: 10);

        final created = world.api.createdGroups.single;
        expect(created['name'], 'Movers');
        expect(created['description'], 'The 14th');
        expect(created['memberHandles'], ['lena', 'omar']);
        expect(created['isPublic'], isFalse);
        expect(find.byType(StartGroupScreen, skipOffstage: false), findsNothing);
        expect(find.byType(ConversationListScreen), findsOneWidget);
      });
    });

    testWidgets('says when the relay refuses, and keeps what was typed', (tester) async {
      await withPhoneApp(tester, identities, location: '/start-group', body: (world) async {
        await tester.enterText(find.byType(TextField).at(0), 'Moving day');
        await tester.enterText(find.byType(TextField).at(2), 'icarus');
        await tester.pump();
        await tester.tap(find.byType(FilledButton));
        await pumpFrames(tester, frames: 6);

        expect(world.api.createdGroups, isEmpty);
        expect(find.byType(StartGroupScreen), findsOneWidget);
        // The members' field names the handle nobody has, as its error.
        expect(findCopy(en.safetyAccountNotFound('icarus')), findsOneWidget);
        expect(find.byType(VeilNotice), findsNothing);
        expect(find.text('Moving day'), findsOneWidget);
      });
    });
  });
}
