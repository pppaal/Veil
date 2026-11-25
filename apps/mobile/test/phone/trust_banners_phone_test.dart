import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_composer_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_request_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_status_banners.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_names.dart';
import 'package:veil_mobile/src/features/safety/application/relationship.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_numbers_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../layout/support/layout_seed.dart';
import '../layout/support/trust_seed.dart';
import 'phone_app.dart';

// The trust banners of a chat on a phone: a look-alike of an account alex
// saved or verified (sam.official, beside Sam's verified @sam), a new
// account that says it is family, and the nudge to verify a saved contact
// alex talks to a lot. Only verifying ends the first two; the nudge shows
// on three chat openings.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));
  const sam = 'Sam Rivera';

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  Finder inBanners(Finder finder) => find.descendant(of: find.byType(ChatStatusBanners), matching: finder);
  Finder lookalikeTitle() => find.text(en.chatLookalikeTitle(sam));
  Finder claimTitle() => find.text(en.chatClaimTitle);

  // Opens [conversationId] from Chats, as a person does, and lets the
  // checks of the chat run.
  Future<void> open(WidgetTester tester, String conversationId) async {
    GoRouter.of(tester.element(find.byType(Navigator).first)).go('/chat/$conversationId');
    await pumpFrames(tester, frames: 8);
  }

  // Marks [handle]'s device verified, as the safety number page does.
  Future<void> verify(WidgetTester tester, LayoutWorld world, String handle) async {
    final party = world.relay.partiesByHandle[handle]!;
    await pinParty(world.trust, party);
    await world.trust.markVerified(party.userId, party.deviceId, party.identity.identityPublicKey);
    await pumpFrames(tester, frames: 4);
  }

  testWidgets('a lookalike of a verified contact shows the warning and keeps it after Accept', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      // It also says it is family, which the look-alike warning stands for.
      afterSession: (world) => strangerWrites(world, lookalikeHandle, [...lookalikeLines, claimLines.first]),
      body: (world) async {
        await open(tester, lookalikeConversationId);
        expect(world.contactTrust.isRequest(lookalikeConversationId), isTrue);
        expect(lookalikeTitle(), findsOneWidget, reason: 'sam.official reads as Sam\'s verified @sam');
        expect(find.text(en.chatLookalikeBody(lookalikeHandle, sam)), findsOneWidget);
        expect(inBanners(find.byType(TextButton)), findsNothing, reason: 'the warning has no action');
        // Under the warning Accept is as plain as Block and Report.
        expect(find.byType(ChatRequestBar), findsOneWidget);
        expect(tester.widget(find.byKey(const ValueKey('request-accept'))), isA<TextButton>());

        await tester.tap(find.byKey(const ValueKey('request-accept')));
        await pumpFrames(tester, frames: 6);
        expect(find.byType(ChatComposerBar), findsOneWidget, reason: 'accepted');
        expect(lookalikeTitle(), findsOneWidget, reason: 'Accept does not end the warning');
        expect(find.text(en.chatClaimTitle), findsNothing, reason: 'one trust banner at a time');
        expect(world.contactTrust.claimHolds(lookalikeConversationId), isFalse,
            reason: 'a claim is recorded once on screen, and this one never was');

        // Sam's own chat, which he is, has none.
        await open(tester, chatConversationId);
        expect(lookalikeTitle(), findsNothing);
      },
    );
  });

  testWidgets('a new account that says it\'s family shows the claim banner, and Verify opens the safety number page',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      attention: const ChatAttention(trust: TrustCase.claim),
      body: (world) async {
        await open(tester, claimConversationId);
        expect(claimTitle(), findsOneWidget, reason: '"Hi mum, this is my new number" from a new account');
        expect(find.text(en.chatClaimBody), findsOneWidget);
        expect(world.contactTrust.claimHolds(claimConversationId), isTrue, reason: 'the banner is recorded');
        final verify = inBanners(find.widgetWithText(TextButton, en.chatVerifyAction));
        expect(verify, findsOneWidget);

        await tester.tap(verify);
        await pumpFrames(tester, frames: 8);
        expect(find.byType(SafetyNumbersScreen), findsOneWidget);
        expect(
            tester.widget<SafetyNumbersScreen>(find.byType(SafetyNumbersScreen)).conversationId, claimConversationId);
      },
    );
  });

  testWidgets('saving a nickname or waiting a week does not end the claim or lookalike banner; verifying does',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      attention: const ChatAttention(trust: TrustCase.claim),
      afterSession: (world) async {
        await strangerWrites(world, lookalikeHandle, lookalikeLines);
        await world.contactTrust.accept(lookalikeConversationId);
      },
      body: (world) async {
        await open(tester, claimConversationId);
        expect(claimTitle(), findsOneWidget);
        await open(tester, lookalikeConversationId);
        expect(lookalikeTitle(), findsOneWidget);

        // Both accounts get a nickname, as their scripts ask; a week and a
        // day go by.
        final book = world.container.read(contactNameBookProvider);
        await tester.runAsync(() async {
          await book.write(claimHandle, 'Jess', anew: true);
          await book.write(lookalikeHandle, 'Sam new', anew: true);
        });
        await pumpFrames(tester, frames: 4);
        world.now = world.now.add(const Duration(days: 8));
        await open(tester, claimConversationId);
        expect(claimTitle(), findsOneWidget, reason: 'a nickname and a week do not end the claim banner');
        await open(tester, lookalikeConversationId);
        expect(lookalikeTitle(), findsOneWidget, reason: 'a nickname and a week do not end the warning');

        // Verifying each ends its banner.
        await verify(tester, world, lookalikeHandle);
        expect(lookalikeTitle(), findsNothing, reason: 'verified');
        await verify(tester, world, claimHandle);
        await open(tester, claimConversationId);
        expect(claimTitle(), findsNothing, reason: 'verified');
        expect(world.contactTrust.claimHolds(claimConversationId), isFalse);
      },
    );
  });

  testWidgets('a chat I started from a handle shows no claim banner for family words', (tester) async {
    const typed = 'eomma';
    const stranger = 'umma';
    const lines = ['Hi sweetie, this is my new number', 'mum here, my old phone broke'];
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      afterSession: (world) async {
        // alex typed @eomma in New chat; @umma wrote first.
        trustParty(world.relay, world.identities, typed);
        final id = await world.contactTrust.startDirect(typed);
        expect(id, 'conv-$typed');
        await sealLines(world.relay, id!, typed, lines, firstAt: layoutNow.subtract(const Duration(minutes: 5)));
        await world.messenger.loadConversationMessages(id);
        await strangerWrites(world, stranger, lines);
        await world.contactTrust.accept('conv-$stranger');
      },
      body: (world) async {
        expect(world.contactTrust.startedByMe('conv-$typed'), isTrue);
        await open(tester, 'conv-$typed');
        expect(find.text(lines.first), findsOneWidget);
        expect(claimTitle(), findsNothing, reason: 'alex chose this handle');

        await open(tester, 'conv-$stranger');
        expect(claimTitle(), findsOneWidget, reason: 'the same words from a chat alex did not start');
      },
    );
  });

  testWidgets('a two-person group gets the claim and lookalike checks', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      afterSession: (world) async {
        await strangerWrites(world, lookalikeHandle, lookalikeLines, conversationId: 'conv-pair-look', groupWith: []);
        await strangerWrites(world, claimHandle, claimLines, conversationId: 'conv-pair-claim', groupWith: []);
        // With one more member, a group is too large for either check.
        await strangerWrites(world, 'sam_new', claimLines,
            conversationId: 'conv-three', groupWith: ['ines.v'], groupName: 'Three of us');
      },
      body: (world) async {
        await open(tester, 'conv-pair-look');
        expect(lookalikeTitle(), findsOneWidget, reason: 'the one other member reads as Sam');
        await open(tester, 'conv-pair-claim');
        expect(claimTitle(), findsOneWidget, reason: 'the one other member says they are family');
        expect(inBanners(find.widgetWithText(TextButton, en.chatVerifyAction)), findsOneWidget);
        await open(tester, 'conv-three');
        expect(find.byType(ChatRoomScreen), findsOneWidget);
        expect(find.text(claimLines.first), findsOneWidget);
        expect(lookalikeTitle(), findsNothing);
        expect(claimTitle(), findsNothing);
      },
    );
  });

  testWidgets('a long-saved contact under a verified contact\'s nickname gets no look-alike warning', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      afterSession: (world) async {
        // Priya, saved before trust records began, now under Sam's name too.
        await world.container.read(contactNameBookProvider).write(noticeChatPeerHandle, sam, anew: true);
      },
      body: (world) async {
        final priya = world.messenger.conversationById(noticeChatConversationId)!;
        expect(
          world.contactTrust
              .relationshipAt(priya.recipientBundle.userId, noticeChatPeerHandle, chat: priya, at: world.now),
          Relationship.saved,
        );
        await open(tester, noticeChatConversationId);
        expect(find.byType(ChatRoomScreen), findsOneWidget);
        expect(lookalikeTitle(), findsNothing, reason: 'two long-saved contacts under one name are no impostors');
      },
    );
  });

  testWidgets('the verify nudge shows in a busy saved chat and stops after three openings', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      attention: const ChatAttention(trust: TrustCase.nudge),
      body: (world) async {
        final nudge = find.text(en.chatVerifyNudge(sam));
        for (var opening = 1; opening <= 4; opening++) {
          await tester.tap(find.widgetWithText(ConversationRow, sam));
          await pumpFrames(tester, frames: 8);
          expect(find.byType(ChatRoomScreen), findsOneWidget);
          if (opening <= 3) {
            expect(nudge, findsOneWidget, reason: 'opening $opening of Sam\'s busy chat');
            expect(inBanners(find.widgetWithText(TextButton, en.chatVerifyAction)), findsOneWidget);
          } else {
            expect(nudge, findsNothing, reason: 'three openings showed it');
          }
          await tester.tap(find.byTooltip('Back'));
          await pumpFrames(tester, frames: 6);
          expect(find.byType(ConversationListScreen), findsOneWidget);
        }
        // A chat with few messages never had it.
        await tester.tap(find.widgetWithText(ConversationRow, 'Priya Nair'));
        await pumpFrames(tester, frames: 8);
        expect(find.textContaining('safety number'), findsNothing);
      },
    );
  });
}
