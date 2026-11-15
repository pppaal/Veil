import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_number_cards.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_numbers_screen.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations_en.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/layout_seed.dart';
import '../support/copy_finder.dart';
import 'phone_app.dart';

// "Verified" says: this is the person whose number you compared. While a key
// change of theirs waits for review, in whichever conversation it was
// raised, no screen may say it: not the chat with them that is already
// open, not their safety number, not a group's member list. And every such
// screen leads to where the change is reviewed.
//
// Sam is the seeded contact the user compared numbers with: the peer of
// the 1:1 `chatConversationId` and a member of the group.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final AppLocalizations l10n = AppLocalizationsEn();
  const peerId = 'user-$peerHandle';
  final peerName = peerNames[peerHandle]!;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  // Sam's device presents another key in [conversationId]: held there
  // for review. The pin the user verified stays as it is.
  Future<void> raiseChange(WidgetTester tester, LayoutWorld world, String conversationId) async {
    final peer = world.relay.partiesByHandle[peerHandle]!;
    final admitted = await tester.runAsync(
      () => world.trust.admit(conversationId, peer.userId, peer.deviceId, identities.self.identityPublicKey),
    );
    expect(admitted, isFalse);
    expect(world.messenger.pendingIdentityChangeFor(conversationId)?.userId, peerId);
    expect((await world.trust.resolver.pinsForUser(peerId)).every((pin) => pin.isVerified), isTrue,
        reason: 'the pin that was verified is untouched while the change is pending');
  }

  // The safety number is derived on a background isolate, which only real
  // time moves forward.
  Future<void> awaitSafetyNumber(WidgetTester tester) async {
    final loading = find.byKey(SafetyNumbersScreen.loadingKey);
    for (var i = 0; i < 250 && loading.evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(loading, findsNothing, reason: 'the safety number never loaded');
    await pumpFrames(tester, frames: 3);
  }

  // Every text of the screen on top, from its first screenful to its last:
  // a list only builds the rows near what is on screen.
  Future<Set<String>> textsOfScreen(WidgetTester tester) async {
    Set<String> shown() => {
          for (final text in tester.widgetList<Text>(find.byType(Text)))
            text.data ?? text.textSpan?.toPlainText() ?? '',
        };
    final list = find.descendant(of: find.byType(SafetyNumbersScreen), matching: find.byType(Scrollable)).first;
    tester.state<ScrollableState>(list).position.jumpTo(0);
    await tester.pump();
    final texts = shown();
    await scrollToEnd(tester, onPage: (_) async => texts.addAll(shown()));
    return texts;
  }

  final verifiedOn = l10n.safetyNumbersVerifiedOn('').trim();

  // What a safety-number page says while it may not call the contact
  // verified because another conversation holds a change of theirs.
  void expectInQuestion(Set<String> texts) {
    expect(texts, contains(l10n.safetyNumbersChangedElsewhereTitle));
    expect(texts, contains(l10n.safetyNumbersChangedElsewhereBody(peerName)));
    expect(texts, contains(l10n.safetyNumbersUnverified));
    expect(texts, isNot(contains(l10n.safetyNumbersVerified)));
    expect(texts.where((text) => text.startsWith(verifiedOn)), isEmpty, reason: 'no "Verified on" card');
    // The pinned number is still shown, as the current one; what would
    // confirm the old key (marking it verified, its QR code, a scan against
    // it) is not offered here: the change is reviewed where it is held.
    expect(texts, contains(l10n.safetyNumbersCurrentNumberHeader));
    expect(texts, contains(l10n.safetyNumbersReviewChange));
    expect(texts, isNot(contains(l10n.safetyNumbersMarkVerified)));
    expect(texts, isNot(contains(l10n.safetyNumbersScanAction)));
  }

  Future<void> tapReview(WidgetTester tester) async {
    final review = find.text(l10n.safetyNumbersReviewChange);
    await tester.dragUntilVisible(review, find.byType(Scrollable).last, const Offset(0, 200));
    await pumpFrames(tester, frames: 2);
    await tester.tap(review);
    await pumpFrames(tester);
    await awaitSafetyNumber(tester);
  }

  testWidgets('a change raised in a group: the 1:1 safety number is not verified, leads to the review, and is again after it',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      size: phoneMedium,
      withGroup: true,
      location: '/safety-numbers/$chatConversationId',
      prepare: (world) async {
        await raiseChange(tester, world, groupConversationId);
        return null;
      },
      body: (world) async {
        await awaitSafetyNumber(tester);
        // Said before anything else on the page.
        final banner = onScreen(tester, findCopy(l10n.safetyNumbersChangedElsewhereTitle));
        expect(banner.height, greaterThan(0));
        expect(banner.top, lessThan(onScreen(tester, find.byType(SafetyPeerHeader)).top));
        expectInQuestion(await textsOfScreen(tester));

        // The review is Sam's page in the group that holds the change.
        await tapReview(tester);
        expect(find.byType(SafetyNumbersScreen), findsOneWidget, reason: 'the page under it is off stage');
        final review = tester.widget<SafetyNumbersScreen>(find.byType(SafetyNumbersScreen));
        expect((review.conversationId, review.memberUserId), (groupConversationId, peerId));
        final reviewTexts = await textsOfScreen(tester);
        expect(reviewTexts, contains(l10n.safetyNumbersKeyChangedTitle));
        expect(reviewTexts, contains(l10n.safetyNumbersNewNumberHeader));
        expect(reviewTexts, isNot(contains(l10n.safetyNumbersVerified)));

        // The user keeps the key they compared. Back on the 1:1's page she
        // is verified again, without the page having been reopened.
        final keep = find.text(l10n.safetyNumbersKeepCurrentKey);
        await tester.dragUntilVisible(keep, find.byType(Scrollable).last, const Offset(0, 200));
        await pumpFrames(tester, frames: 2);
        await tester.tap(keep);
        await pumpFrames(tester, frames: 3);
        await awaitSafetyNumber(tester);
        expect(world.messenger.pendingIdentityChangeAbout(peerId), isNull);
        await tester.pageBack();
        await pumpFrames(tester);
        await awaitSafetyNumber(tester);
        final settled = await textsOfScreen(tester);
        expect(settled, contains(l10n.safetyNumbersVerified));
        expect(settled.where((text) => text.startsWith(verifiedOn)), hasLength(1));
        expect(settled, isNot(contains(l10n.safetyNumbersChangedElsewhereTitle)));
        expect(settled, isNot(contains(l10n.safetyNumbersReviewChange)));
      },
    );
  });

  // Nobody reopens the page: the change is settled where it is held (the
  // user decides it on another screen, or the relay lists the old key
  // again), and the page that stands back for it reads again.
  testWidgets('a safety number that stays open says "verified" again once the change held elsewhere is settled',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      size: phoneMedium,
      withGroup: true,
      location: '/safety-numbers/$chatConversationId',
      prepare: (world) async {
        await raiseChange(tester, world, groupConversationId);
        return null;
      },
      body: (world) async {
        await awaitSafetyNumber(tester);
        expectInQuestion(await textsOfScreen(tester));
        final page = tester.state(find.byType(SafetyNumbersScreen));

        final change = world.messenger.pendingIdentityChangeFor(groupConversationId)!;
        await tester.runAsync(() => world.messenger.declineIdentityChange(groupConversationId, reviewed: change));
        await pumpFrames(tester, frames: 3);
        await awaitSafetyNumber(tester);

        expect(tester.state(find.byType(SafetyNumbersScreen)), same(page), reason: 'the page was not reopened');
        final settled = await textsOfScreen(tester);
        expect(settled, contains(l10n.safetyNumbersVerified));
        expect(settled.where((text) => text.startsWith(verifiedOn)), hasLength(1));
        expect(settled, isNot(contains(l10n.safetyNumbersChangedElsewhereTitle)));
        expect(settled, isNot(contains(l10n.safetyNumbersReviewChange)));
        expect(settled, isNot(contains(l10n.safetyNumbersUnverified)));
      },
    );
  });

  testWidgets('a group list that stays open says "verified" again once a member\'s change is settled in their 1:1',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      size: phoneMedium,
      withGroup: true,
      location: '/safety-numbers/$groupConversationId',
      body: (world) async {
        await awaitSafetyNumber(tester);
        final row = find.widgetWithText(VeilRow, peerName);
        expect(find.descendant(of: row, matching: find.text(l10n.safetyNumbersVerified)), findsOneWidget);

        // Raised while the list is open: the app's own check of the 1:1 at
        // start would withdraw a change raised before it.
        await raiseChange(tester, world, chatConversationId);
        await pumpFrames(tester, frames: 3);
        await awaitSafetyNumber(tester);
        expect(find.descendant(of: row, matching: find.text(l10n.safetyNumbersVerified)), findsNothing);

        final change = world.messenger.pendingIdentityChangeFor(chatConversationId)!;
        await tester.runAsync(() => world.messenger.declineIdentityChange(chatConversationId, reviewed: change));
        await pumpFrames(tester, frames: 3);
        await awaitSafetyNumber(tester);
        expect(find.descendant(of: row, matching: find.text(l10n.safetyNumbersVerified)), findsOneWidget);
      },
    );
  });

  testWidgets('a change raised in the 1:1: the group list and the member page are not verified, and lead to the review',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      size: phoneMedium,
      withGroup: true,
      location: '/safety-numbers/$groupConversationId',
      body: (world) async {
        await awaitSafetyNumber(tester);
        // Of the group's members only Sam was compared.
        expect(find.byType(VeilRow), findsNWidgets(groupMemberHandles.length));
        expect(find.text(l10n.safetyNumbersVerified), findsOneWidget);
        expect(
          find.descendant(
            of: find.widgetWithText(VeilRow, peerName),
            matching: find.text(l10n.safetyNumbersVerified),
          ),
          findsOneWidget,
        );

        // Her key changes in the 1:1 while the list is open: the list reads
        // again and no longer calls her verified.
        await raiseChange(tester, world, chatConversationId);
        await pumpFrames(tester, frames: 3);
        await awaitSafetyNumber(tester);
        expect(find.byType(VeilRow), findsNWidgets(groupMemberHandles.length));
        expect(find.text(l10n.safetyNumbersVerified), findsNothing);
        expect(find.text(l10n.safetyNumbersUnverified), findsNWidgets(groupMemberHandles.length));

        // Her page in the group says why, and leads to the 1:1 that holds
        // the change.
        await tester.tap(find.widgetWithText(VeilRow, peerName));
        await pumpFrames(tester);
        await awaitSafetyNumber(tester);
        final member = tester.widget<SafetyNumbersScreen>(find.byType(SafetyNumbersScreen));
        expect((member.conversationId, member.memberUserId), (groupConversationId, peerId));
        expectInQuestion(await textsOfScreen(tester));

        await tapReview(tester);
        final review = tester.widget<SafetyNumbersScreen>(find.byType(SafetyNumbersScreen));
        expect((review.conversationId, review.memberUserId), (chatConversationId, null));
        expect(findCopy(l10n.safetyNumbersKeyChangedTitle), findsOneWidget);
      },
    );
  });

  testWidgets('a member verified on their page is verified in the group list on the way back', (tester) async {
    const priyaId = 'user-priya';
    await withPhoneApp(
      tester,
      identities,
      size: phoneMedium,
      withGroup: true,
      location: '/safety-numbers/$groupConversationId',
      prepare: (world) async {
        // This device has talked to Priya: there is a pin to compare.
        final priya = world.relay.partiesByHandle['priya']!;
        await world.trust.resolver.evaluate(priya.userId, priya.deviceId, priya.identity.identityPublicKey);
        return null;
      },
      body: (world) async {
        await awaitSafetyNumber(tester);
        final row = find.widgetWithText(VeilRow, peerNames['priya']!);
        expect(find.descendant(of: row, matching: find.text(l10n.safetyNumbersUnverified)), findsOneWidget);

        await tester.tap(row);
        await pumpFrames(tester);
        await awaitSafetyNumber(tester);
        final mark = find.text(l10n.safetyNumbersMarkVerified);
        await tester.dragUntilVisible(mark, find.byType(Scrollable).last, const Offset(0, -200));
        await pumpFrames(tester, frames: 2);
        await tester.tap(mark);
        await pumpFrames(tester, frames: 3);
        await awaitSafetyNumber(tester);
        expect(await world.messenger.isUserVerified(priyaId), isTrue);

        await tester.pageBack();
        await pumpFrames(tester);
        await awaitSafetyNumber(tester);
        expect(find.descendant(of: row, matching: find.text(l10n.safetyNumbersVerified)), findsOneWidget);
      },
    );
  });

  testWidgets('a chat that is open loses its verified mark when the peer\'s key changes in a group, until it is settled',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      withGroup: true,
      location: '/chat/$chatConversationId',
      body: (world) async {
        expect(find.byType(ChatRoomScreen), findsOneWidget);
        expect(find.byTooltip(l10n.chatPeerVerified), findsOneWidget);

        await raiseChange(tester, world, groupConversationId);
        await pumpFrames(tester, frames: 3);
        expect(world.messenger.pendingIdentityChangeFor(chatConversationId), isNull,
            reason: 'the change is held by the group, not by this chat');
        expect(find.byTooltip(l10n.chatPeerVerified), findsNothing);
        expect(world.messenger.peerIdentityInQuestion(chatConversationId), isTrue);

        // Declined in the group: the key she was verified with is kept, and
        // the mark is back.
        final change = world.messenger.pendingIdentityChangeFor(groupConversationId)!;
        await tester.runAsync(() => world.messenger.declineIdentityChange(groupConversationId, reviewed: change));
        await pumpFrames(tester, frames: 3);
        expect(find.byTooltip(l10n.chatPeerVerified), findsOneWidget);
      },
    );
  });

  testWidgets('a chat opened while the peer\'s key change waits in a group shows the mark once it is settled',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      withGroup: true,
      location: '/chat/$chatConversationId',
      prepare: (world) async {
        await raiseChange(tester, world, groupConversationId);
        return null;
      },
      body: (world) async {
        expect(find.byTooltip(l10n.chatPeerVerified), findsNothing);

        final change = world.messenger.pendingIdentityChangeFor(groupConversationId);
        await tester.runAsync(
          () => world.messenger.approveIdentityChange(groupConversationId, reverified: true, reviewed: change),
        );
        await pumpFrames(tester, frames: 3);
        expect(await world.messenger.isPeerVerified(chatConversationId), isTrue);
        expect(find.byTooltip(l10n.chatPeerVerified), findsOneWidget);
      },
    );
  });

  // The safety number is the one thing on its page a person reads digit by
  // digit: it must be drawn in the theme's text colour, in both themes.
  testWidgets('the safety number is drawn in the text colour of the theme', (tester) async {
    for (final themeMode in [ThemeMode.dark, ThemeMode.light]) {
      usePhoneView(tester, phoneMedium);
      final world = await LayoutWorld.create(identities: identities, account: LayoutAccount.signedIn, locale: 'en');
      try {
        await tester.pumpWidget(world.app(location: '/safety-numbers/$chatConversationId', themeMode: themeMode));
        await pumpFrames(tester);
        await awaitSafetyNumber(tester);
        final context = tester.element(find.byType(SafetyNumberCard));
        final palette = context.veilPalette;
        expect(palette.text.computeLuminance() > 0.5, themeMode == ThemeMode.dark);
        final digits = tester.widgetList<Text>(
          find.descendant(of: find.byType(SafetyNumberCard), matching: find.textContaining(RegExp(r'^\d{5}$'))),
        );
        expect(digits, hasLength(12));
        expect({for (final group in digits) group.style?.color}, {palette.text}, reason: '$themeMode');

        // The page keeps the 16 px side gutter of the other form screens.
        final card = tester.getRect(find.byType(SafetyNumberCard));
        expect((card.left, phoneMedium.width - card.right), (16.0, 16.0), reason: '$themeMode');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        world.dispose();
      }
    }
  });
}
