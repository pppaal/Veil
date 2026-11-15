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

// Starting a 1:1 chat or a group on a phone: the field and its button are
// the first things on the screen, the explanation is one note under them,
// and nothing on either screen offers what this build cannot do.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  // The start screen as a user reaches it: from the list's bar.
  Future<void> openFromList(WidgetTester tester, String menuItem) async {
    await tester.tap(find.byTooltip(en.conversationsNewTooltip));
    await pumpFrames(tester, frames: 3);
    await tester.tap(find.text(menuItem));
    await pumpFrames(tester);
  }

  // Within the start screen: the list under it has a field of its own.
  Finder on(Type screen, Type widget) => find.descendant(of: find.byType(screen), matching: find.byType(widget));

  void expectNoDecoration() {
    expect(find.byType(VeilHeroPanel), findsNothing);
    expect(find.byType(VeilStatusPill), findsNothing);
    expect(find.byType(VeilMetricStrip), findsNothing);
  }

  group('a direct chat', () {
    testWidgets('opens on the handle and its button, with one note under them', (tester) async {
      await withPhoneApp(tester, identities, location: '/start-chat', body: (world) async {
        final field = tester.getRect(find.byType(TextField));
        final button = tester.getRect(find.byType(FilledButton));
        final note = tester.getRect(findCopy(en.startDirectNote));
        expect(field.top, lessThan(140), reason: 'the field is the first thing under the bar');
        expect(field.bottom, lessThan(button.top));
        expect(button.bottom, lessThan(640 / 2), reason: 'the button is on the upper half of a 360x640 phone');
        expect(button.bottom, lessThan(note.top), reason: 'the explanation comes after');
        expect(note.bottom, lessThanOrEqualTo(640));
        expectNoDecoration();
        expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull, reason: 'no handle yet');
      });
    });

    testWidgets('opens the chat with the handle that was typed, in the screen\'s place', (tester) async {
      await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
        await openFromList(tester, en.conversationsNewChat);
        expect(find.byType(StartDirectChatScreen), findsOneWidget);

        await tester.enterText(on(StartDirectChatScreen, TextField), '@$emptyChatPeerHandle');
        await tester.pump();
        await tester.tap(on(StartDirectChatScreen, FilledButton));
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
        expect(findCopy(en.startDirectErrorTitle), findsNothing, reason: 'another screen\'s failure is not shown here');

        // An example handle nobody has: what is typed is the user's own.
        await tester.enterText(find.byType(TextField), 'icarus');
        await tester.pump();
        await tester.tap(find.byType(FilledButton));
        await pumpFrames(tester, frames: 6);
        expect(find.byType(StartDirectChatScreen), findsOneWidget);
        expect(findCopy(en.startDirectErrorTitle), findsOneWidget);
        expect(findCopy(en.startDirectErrorBody), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'icaru');
        await tester.pump();
        expect(findCopy(en.startDirectErrorTitle), findsNothing, reason: 'a new handle clears the failure');
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
        expect(button.bottom, lessThanOrEqualTo(640));
        expectNoDecoration();

        // This build has no public groups and cannot add members later:
        // the screen offers neither, and says the second.
        expect(find.byType(Switch), findsNothing);
        expect(findCopy(en.startGroupMembersCaption), findsOneWidget);
        await scrollToEnd(tester);
        expect(findCopy(en.startGroupNote), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('counts the handles as they are typed', (tester) async {
      await withPhoneApp(tester, identities, location: '/start-group', body: (world) async {
        final members = find.byType(TextField).at(1);
        expect(find.textContaining(RegExp(r'^\d+ handles?$')), findsNothing);
        await tester.enterText(members, 'lena');
        await tester.pump();
        expect(find.text('1 handle'), findsOneWidget);
        await tester.enterText(members, 'lena, @omar  jonas');
        await tester.pump();
        expect(find.text('3 handles'), findsOneWidget);
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
        await tester.enterText(fields.at(1), '@Alex, alex');
        await tester.pump();
        expect(create().onPressed, isNull, reason: 'only the creator');
        expect(find.textContaining(RegExp(r'^\d+ handles?$')), findsNothing, reason: 'no member is counted');

        await tester.enterText(fields.at(1), 'alex, lena');
        await tester.pump();
        expect(find.text('1 handle'), findsOneWidget);
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
        await openFromList(tester, en.conversationsNewGroup);
        final fields = on(StartGroupScreen, TextField);
        final create = on(StartGroupScreen, FilledButton);
        expect(tester.widget<FilledButton>(create).onPressed, isNull, reason: 'no name yet');

        await tester.enterText(fields.at(0), 'Movers');
        await tester.pump();
        expect(tester.widget<FilledButton>(create).onPressed, isNull, reason: 'no member yet');
        await tester.enterText(fields.at(1), 'lena, @omar');
        await tester.enterText(fields.at(2), 'The 14th');
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
        await tester.enterText(find.byType(TextField).at(1), 'icarus');
        await tester.pump();
        await tester.tap(find.byType(FilledButton));
        await pumpFrames(tester, frames: 6);

        expect(world.api.createdGroups, isEmpty);
        expect(find.byType(StartGroupScreen), findsOneWidget);
        expect(findCopy(en.startGroupErrorTitle), findsOneWidget);
        expect(findCopy(en.startGroupErrorBody), findsOneWidget);
        expect(find.text('Moving day'), findsOneWidget);
      });
    });
  });
}
