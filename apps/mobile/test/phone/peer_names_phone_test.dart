import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_bubble.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_names.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_nicknames.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_parts.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../layout/support/layout_seed.dart';
import 'phone_app.dart';

// The names on the screens come from this phone. The relay keeps none: it
// lists a conversation's members as an account and a handle
// (ConversationMemberSummary) and a contact as a handle (ContactSummary),
// and the fake relay here lists them the same way. What the user saved in
// Contacts, the nickname of a handle, is what Chats, the chat bar, search
// and group bubbles call that person, as WhatsApp and Signal do; anyone
// without one is called by their handle.

final _en = lookupAppLocalizations(const Locale('en'));

Finder _row(String title) => find.byWidgetPredicate((widget) => widget is ConversationRow && widget.title == title);

Finder _inBar(String text) => find.descendant(of: find.byType(ChatBarTitle), matching: find.text(text));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  testWidgets('the relay lists no names: Chats calls a peer by the nickname saved on this phone', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      final listing = await world.api.getConversations('token-$selfHandle');
      for (final conversation in (listing['items'] as List).cast<Map<String, dynamic>>()) {
        for (final member in (conversation['members'] as List).cast<Map<String, dynamic>>()) {
          expect(member.keys.toSet(), {'userId', 'handle'}, reason: 'a member as the relay lists one');
        }
      }
      for (final contact in (await world.api.getContacts('token-$selfHandle')).cast<Map<String, dynamic>>()) {
        expect(contact.keys.toSet(), {'handle', 'addedAt'}, reason: 'a contact as the relay lists one');
      }
      final saved = await ContactNicknames(world.storage.scoped(SecureScope.contacts)).readAll();
      expect(saved[peerHandle], 'Sam Rivera');

      expect(_row('Sam Rivera'), findsOneWidget);
      expect(_row(peerHandle), findsNothing);
      // No nickname: the handle, bare on a row.
      expect(_row('tom_walsh'), findsOneWidget);

      // Searching finds the chat by the saved name.
      await tester.enterText(find.byType(TextField), 'riv');
      await pumpFrames(tester, frames: 4);
      expect(find.widgetWithText(ConversationListHeader, _en.conversationsSectionLabel), findsOneWidget);
      expect(find.byType(ConversationRow), findsOneWidget);
      expect(_row('Sam Rivera'), findsOneWidget);
    });
  });

  testWidgets('a nickname changed in Contacts renames the chat at once', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await world.container.read(contactNameBookProvider).write(peerHandle, 'Sammy');
      await pumpFrames(tester, frames: 2);
      expect(_row('Sammy'), findsOneWidget);
      expect(_row('Sam Rivera'), findsNothing);

      // Cleared: the handle again.
      await world.container.read(contactNameBookProvider).remove(peerHandle);
      await pumpFrames(tester, frames: 2);
      expect(_row(peerHandle), findsOneWidget);
    });
  });

  testWidgets('the chat bar shows the nickname with the handle under it', (tester) async {
    await withPhoneApp(tester, identities, location: '/chat/$chatConversationId', body: (world) async {
      expect(_inBar('Sam Rivera'), findsOneWidget);
      expect(_inBar('@$peerHandle'), findsOneWidget);
    });
  });

  testWidgets('a peer with no nickname is called by their handle, once', (tester) async {
    await withPhoneApp(tester, identities, location: '/chat/conv-tom_walsh', body: (world) async {
      expect(_inBar('@tom_walsh'), findsOneWidget, reason: 'the handle is the title, and not repeated under it');
    });
  });

  // The nickname names the account the user knew as @sam. A chat held for
  // its handle is with another account, and its banner says so: it is
  // called by the handle the server listed it under.
  testWidgets('a chat held for its handle is called by the handle, never by the nickname', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/chat/$chatConversationId',
      attention: const ChatAttention(accountHeld: true),
      body: (world) async {
        expect(find.text(_en.chatAccountHoldOtherTitle), findsOneWidget);
        expect(_inBar('@$peerHandle'), findsOneWidget);
        expect(find.text('Sam Rivera'), findsNothing);
      },
    );
  });

  testWidgets('a group\'s bubbles and its row in Chats name members by their nicknames', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', withGroup: true, body: (world) async {
      final group = tester.widget<ConversationRow>(_row(groupName));
      expect(group.snippet, 'Omar: $latestGroupLine');

      await tester.tap(_row(groupName));
      await pumpFrames(tester, frames: 8);
      for (final name in ['Sam Rivera', 'Priya Nair', 'Omar Haddad']) {
        expect(
          find.descendant(of: find.byType(MessageBubble), matching: find.text(name)),
          findsWidgets,
          reason: '$name over their messages',
        );
      }
      expect(find.text('@$peerHandle'), findsNothing);

      // Who is typing is called the same.
      world.messenger.presenceTyping.typingStarted(groupConversationId, peerHandle);
      await pumpFrames(tester, frames: 2);
      expect(find.text(_en.chatTypingSuffix('Sam Rivera')), findsOneWidget);
      world.messenger.presenceTyping.typingStopped(groupConversationId);
      await pumpFrames(tester, frames: 2);
    });
  });
}
