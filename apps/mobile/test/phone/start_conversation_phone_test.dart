import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_direct_chat_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';
import 'package:veil_mobile/src/features/conversations/presentation/start_group_screen.dart';
import 'package:veil_mobile/src/features/safety/application/contact_trust.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../support/copy_finder.dart';
import '../support/layout_trust.dart';
import 'phone_app.dart';

// Starting a 1:1 chat or a group on a phone. New chat is a search field,
// then "New group" and "One-time link", then the contacts; a typed handle
// that is no contact's becomes "Chat with @…". New group is its fields, the
// members as chips with the one rule under them, and the button. A chat
// the user starts is theirs, never a message request; one a stranger
// starts is one. Opening a chat goes through the trust layer, attached to
// the world's messenger as on a phone.

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
      await withPhoneApp(tester, identities, location: '/conversations', afterSession: attachContactTrust, body: (world) async {
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

    // "rivera" is Sam Rivera's name, and also a handle a stranger could
    // hold: Go must not open a chat with the wrong person.
    testWidgets('Go opens the contact the text matches before a stranger with that handle', (tester) async {
      await withPhoneApp(tester, identities, location: '/start-chat', afterSession: attachContactTrust, body: (world) async {
        await tester.enterText(find.byType(TextField), 'rivera');
        await tester.pump();
        final contact = find.byKey(const ValueKey('start-contact-$peerHandle'));
        final stranger = find.byKey(const ValueKey('start-chat-with-handle'));
        expect(contact, findsOneWidget);
        expect(stranger, findsOneWidget, reason: 'the stranger is still there, for a tap');
        expect(tester.getRect(contact).top, lessThan(tester.getRect(stranger).top), reason: 'Go opens the first row');

        await tester.testTextInput.receiveAction(TextInputAction.go);
        await pumpFrames(tester, frames: 10);
        expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId, chatConversationId);
        expect(world.relay.conversations.keys, isNot(contains('conv-rivera')));
      });
    });

    testWidgets('says when the handle opens nothing, and only then', (tester) async {
      await withPhoneApp(tester, identities, location: '/start-chat', afterSession: attachContactTrust, prepare: (world) async {
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
        await tester.enterText(members, 'lena_berlin');
        await tester.pump();
        expect(find.text('1 member'), findsOneWidget);
        expect(find.byType(InputChip), findsNothing, reason: 'a handle still being typed');
        await tester.enterText(find.byType(TextField).at(2), 'lena_berlin, @omar_h  jonask');
        await tester.pump();
        expect(find.text('3 members'), findsOneWidget);
        expect(find.widgetWithText(InputChip, '@lena_berlin'), findsOneWidget);
        expect(find.widgetWithText(InputChip, '@omar_h'), findsOneWidget);
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

        await tester.enterText(fields.at(2), 'alex, lena_berlin');
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
        expect(world.api.createdGroups.single['memberHandles'], ['lena_berlin'], reason: 'the creator is not sent as a member');
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
        await tester.enterText(fields.at(2), 'lena_berlin, @omar_h');
        await tester.pump();
        await tester.tap(create);
        await pumpFrames(tester, frames: 10);

        final created = world.api.createdGroups.single;
        expect(created['name'], 'Movers');
        expect(created['description'], 'The 14th');
        expect(created['memberHandles'], ['lena_berlin', 'omar_h']);
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

  // Typed, from a contact, or a group of one's own: never a request. A chat
  // a stranger opens, or a group they put the user in, is one: its row in
  // Chats quotes nothing.
  testWidgets('a chat you start is never a request, and a stranger\'s chat is one', (tester) async {
    late ContactTrust trust;
    Finder rowOf(String title) => find.ancestor(of: find.text(title), matching: find.byType(ConversationRow));

    // A handle typed in New chat.
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      beforeSession: (relay) {
        addStranger(relay, identities, 'kim_new');
        addStranger(relay, identities, 'mallory');
      },
      afterSession: (world) async => trust = await attachContactTrust(world),
      body: (world) async {
        await openNewChat(tester);
        await tester.enterText(on(StartDirectChatScreen, TextField), 'kim_new');
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('start-chat-with-handle')));
        await pumpFrames(tester, frames: 10);
        final typed = tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId;
        expect(trust.isRequest(typed), isFalse, reason: 'a chat opened from a typed handle is the user\'s');
        expect(trust.startedByMe(typed), isTrue);
        await tester.tap(find.byTooltip('Back'));
        await pumpFrames(tester, frames: 6);

        // A stranger writes first: a request, and its row says only that.
        final stranger = await strangerWrites(world, 'mallory', ['hi, it\'s me. are you free later?']);
        await pumpFrames(tester, frames: 6);
        expect(trust.isRequest(stranger), isTrue);
        expect(find.descendant(of: rowOf('mallory'), matching: find.text(en.conversationsRequestPreview)), findsOneWidget);
        expect(find.textContaining('are you free'), findsNothing);
        expect(find.descendant(of: rowOf('kim_new'), matching: find.text(en.conversationsRequestPreview)), findsNothing);
      },
    );

    // Start chat in a contact's sheet, with a contact alex has no chat with
    // yet: the chat is made then, and accepted.
    await withPhoneApp(
      tester,
      identities,
      location: '/contacts',
      beforeSession: (relay) => relay.conversations.remove(emptyChatConversationId),
      afterSession: (world) async => trust = await attachContactTrust(world),
      body: (world) async {
        expect(world.messenger.conversationById(emptyChatConversationId), isNull);
        await tester.tap(find.text('Lena Fischer'));
        await pumpFrames(tester, frames: 4);
        await tester.tap(find.text(en.contactsStartChat));
        await pumpFrames(tester, frames: 8);
        expect(tester.widget<ChatRoomScreen>(find.byType(ChatRoomScreen)).conversationId, emptyChatConversationId);
        expect(trust.isRequest(emptyChatConversationId), isFalse, reason: 'a chat started from a contact is the user\'s');
        expect(trust.startedByMe(emptyChatConversationId), isTrue);
      },
    );

    // A group alex creates; then a stranger puts alex in a group of theirs.
    await withPhoneApp(
      tester,
      identities,
      location: '/start-group',
      beforeSession: (relay) => addStranger(relay, identities, 'mallory'),
      afterSession: (world) async => trust = await attachContactTrust(world),
      body: (world) async {
        await tester.enterText(find.byType(TextField).at(0), 'Movers');
        await tester.enterText(find.byType(TextField).at(2), 'lena_berlin, mallory');
        await tester.pump();
        await tester.tap(find.byType(FilledButton));
        await pumpFrames(tester, frames: 10);
        final created = world.relay.conversations.keys.singleWhere((id) => id.startsWith('conv-new-group-'));
        expect(world.messenger.conversationById(created), isNotNull);
        expect(trust.isRequest(created), isFalse, reason: 'the group createGroup answered with is the user\'s');

        world.relay.addGroup('conv-their-group', [selfHandle, 'mallory'], useSenderKeys: false, name: 'Prizes');
        await world.messenger.refreshConversations();
        await pumpFrames(tester, frames: 4);
        expect(world.messenger.conversationById('conv-their-group'), isNotNull);
        expect(trust.isRequest('conv-their-group'), isTrue, reason: 'a group a stranger made is a request');
      },
    );
  });
}
