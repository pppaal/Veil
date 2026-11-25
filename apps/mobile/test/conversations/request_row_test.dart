import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';
import 'package:veil_mobile/src/features/conversations/presentation/unread_chats.dart';
import 'package:veil_mobile/src/features/safety/application/contact_trust.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../phone/phone_app.dart';
import '../support/layout_trust.dart';

// A message request in Chats (A7): the row stays in time order, says
// "Message request" instead of quoting the stranger, counts its messages
// in grey, and the Chats tab leaves it out of its count, as it leaves out a
// muted chat. Once accepted it is an ordinary row.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  Finder rowOf(String title) => find.ancestor(of: find.text(title), matching: find.byType(ConversationRow));

  testWidgets('a request row quotes no text, has a grey badge and is left out of the Chats count', (tester) async {
    late ContactTrust trust;
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      beforeSession: (relay) => addStranger(relay, identities, 'mallory'),
      afterSession: (world) async => trust = await attachContactTrust(world),
      body: (world) async {
        final counted = world.container.read(unreadChatsProvider);
        final stranger = await strangerWrites(world, 'mallory', [
          'hi, this is my new number',
          'can you send me the code you just got?',
        ]);
        await pumpFrames(tester, frames: 6);
        expect(trust.isRequest(stranger), isTrue);

        // At the top, the newest, as any chat would be.
        final rows = find.byType(ConversationRow);
        expect(find.descendant(of: rows.first, matching: find.text('mallory')), findsOneWidget);
        final row = rowOf('mallory');
        expect(find.descendant(of: row, matching: find.text(en.conversationsRequestPreview)), findsOneWidget);
        expect(find.textContaining('the code you just got'), findsNothing, reason: 'no word of it outside the chat');
        expect(find.textContaining('my new number'), findsNothing);
        final badge = tester.widget<UnreadBadge>(find.descendant(of: row, matching: find.byType(UnreadBadge)));
        expect(badge.count, greaterThan(0), reason: 'its messages are still counted on the row');
        expect(badge.muted, isTrue, reason: 'in grey, as a muted chat\'s');
        expect(world.container.read(unreadChatsProvider), counted, reason: 'the Chats tab does not count it');

        // Accepted: the row quotes its last message, in the brand colour,
        // and the tab counts it.
        await trust.accept(stranger);
        await pumpFrames(tester, frames: 6);
        expect(find.descendant(of: rowOf('mallory'), matching: find.text(en.conversationsRequestPreview)), findsNothing);
        expect(find.descendant(of: rowOf('mallory'), matching: find.textContaining('the code you just got')),
            findsOneWidget);
        final accepted = tester.widget<UnreadBadge>(find.descendant(of: rowOf('mallory'), matching: find.byType(UnreadBadge)));
        expect(accepted.muted, isFalse);
        expect(world.container.read(unreadChatsProvider), counted + 1);
      },
    );
  });
}
