import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/attachments/attachments_feature.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_composer_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_numbers_screen.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/layout_seed.dart';
import '../support/copy_finder.dart';
import 'phone_app.dart';

// A chat on a phone: the messages have the screen, and everything the
// header cards carried in the wide layout is still one tap away in the bar.

const _latest = latestChatLine;
// The oldest message, from Thursday evening, and the first of the
// morning, which a search for "lease" finds.
const _oldest = 'the landlord wants two months up front';
const _morning = legacyMessageBody;
const _chat = '/chat/$chatConversationId';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  // The safety number is derived on a background isolate, which only real
  // time moves forward; leaving before it finishes would leave it running.
  Future<void> awaitSafetyNumber(WidgetTester tester) async {
    final loading = find.byKey(SafetyNumbersScreen.loadingKey);
    for (var i = 0; i < 250 && loading.evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await pumpFrames(tester, frames: 3);
  }

  testWidgets('opens at its latest message and gives the messages the screen', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {

      final messages = onScreen(tester, find.byType(ChatMessageList));
      expect(messages.height / screenHeight(tester), greaterThan(0.6));
      expect(onScreen(tester, find.text(_latest)).height, greaterThan(0), reason: 'the newest message is in view');
      expect(find.textContaining(_oldest), findsNothing, reason: 'the oldest is above, not where the chat opens');

      final composer = tester.renderObject<RenderBox>(find.byType(ChatComposerBar));
      expect(onScreen(tester, find.byType(ChatComposerBar)).height, composer.size.height,
          reason: 'the whole composer is on screen');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('names the peer in the bar, with the verified mark only for a verified peer', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      expect(find.text('Sam Rivera'), findsOneWidget);
      expect(find.text('@sam'), findsOneWidget);
      expect(find.byTooltip('Verified'), findsOneWidget);
    });
    await withPhoneApp(tester, identities, location: '/chat/$emptyChatConversationId', body: (world) async {
      expect(find.text('Lena Fischer'), findsOneWidget);
      expect(find.byTooltip('Verified'), findsNothing);
    });
  });

  testWidgets('opens the safety number from the bar, and comes back', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      await tester.tap(find.byTooltip('Safety number'));
      await pumpFrames(tester);
      expect(find.byType(SafetyNumbersScreen), findsOneWidget);
      await awaitSafetyNumber(tester);

      await tester.tap(find.byTooltip('Back'));
      await pumpFrames(tester);
      expect(find.byType(SafetyNumbersScreen), findsNothing);
      expect(find.byType(ChatRoomScreen), findsOneWidget);
      expect(find.byTooltip('Verified'), findsOneWidget);
    });
  });

  // A group has no one safety number: its action opens the list of its
  // members, each with their own.
  testWidgets('a group chat opens the safety numbers of its members from the bar', (tester) async {
    await withPhoneApp(tester, identities, withGroup: true, location: '/chat/$groupConversationId',
        body: (world) async {
      expect(find.byTooltip('Verified'), findsNothing, reason: 'a group is never verified as a whole');
      await tester.tap(find.byTooltip('Safety number'));
      await pumpFrames(tester);
      await awaitSafetyNumber(tester);
      final opened = tester.widget<SafetyNumbersScreen>(find.byType(SafetyNumbersScreen));
      expect((opened.conversationId, opened.memberUserId), (groupConversationId, null));
      expect(find.byType(VeilRow), findsNWidgets(groupMemberHandles.length));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('searches from the bar: the field replaces the title, the hits are counted under the messages, and back closes it',
      (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      await tester.tap(find.byTooltip('Search'));
      await pumpFrames(tester, frames: 2);
      expect(find.widgetWithText(TextField, 'Search this chat'), findsOneWidget);
      expect(find.text('Sam Rivera'), findsNothing);
      expect(find.byTooltip('Safety number'), findsNothing);
      final searchField = find.descendant(of: find.byType(ChatBarSearchField), matching: find.byType(TextField));
      final emptyHeight = tester.getSize(searchField).height;

      // Typed where the focus is: opening the search moved it to the bar.
      tester.testTextInput.enterText('lease');
      await pumpFrames(tester, frames: 4);
      // In the composer's place: which hit is shown, and the arrows.
      expect(find.text('2 of 2'), findsOneWidget);
      expect(find.byType(ChatComposerBar), findsNothing);
      expect(find.byTooltip('Previous result'), findsOneWidget);
      // The clear button is as tall as the field: nothing moves under it.
      expect(find.byTooltip('Clear search'), findsOneWidget);
      expect(tester.getSize(searchField).height, emptyHeight);
      // The older hit is one arrow away.
      await tester.tap(find.byTooltip('Previous result'));
      await pumpFrames(tester, frames: 6);
      expect(find.text('1 of 2'), findsOneWidget);
      expect(find.textContaining(_morning, findRichText: true), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await pumpFrames(tester, frames: 4);
      expect(find.byType(ChatRoomScreen), findsOneWidget, reason: 'back closed the search, not the chat');
      expect(find.text('Sam Rivera'), findsOneWidget);
      // The chat stays where the search left it, under the composer again.
      expect(find.byType(ChatComposerBar), findsOneWidget);
      expect(find.text('2 of 2'), findsNothing);
      expect(find.textContaining('on this device'), findsNothing);
    });
  });

  // The timer is in the bar's menu; the bar shows it once it is set.
  testWidgets('sets the disappearing timer from the bar\'s menu and shows it in the bar', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      await tester.tap(find.byTooltip('More options'));
      await pumpFrames(tester, frames: 3);
      await tester.tap(find.text('Disappearing messages'));
      await pumpFrames(tester, frames: 4);
      expect(find.text('Disappearing messages'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'the sheet fits a 360x640 screen');

      await tester.tap(find.text('1 day'));
      await pumpFrames(tester, frames: 4);
      expect(world.api.timers[chatConversationId], 86400);
      expect(find.byWidgetPredicate((widget) => widget is Text && widget.semanticsLabel == 'Disappearing: 1 day'), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget, reason: 'under the name, while a timer is set');
    });
  });

  testWidgets('shows a timer the conversation already has', (tester) async {
    await withPhoneApp(tester, identities, location: '/chat/$timerChatConversationId', body: (world) async {
      expect(find.byWidgetPredicate((widget) => widget is Text && widget.semanticsLabel == 'Disappearing: 1 day'), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget);
    });
  });

  // The attach button is there only in a build that can send a file
  // (kAttachmentsEnabled); without it nothing stands before the draft (the
  // composer has no padlock, design system 7.7).
  testWidgets('offers no attachment from the composer while attachments are switched off', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      expect(find.byTooltip('Attach'), kAttachmentsEnabled ? findsOneWidget : findsNothing);
      expect(
        find.descendant(of: find.byType(ChatComposerBar), matching: find.byIcon(Icons.lock_outline)),
        findsNothing,
      );
    });
  });

  // The mark says the peer is who the user compared numbers with. A key
  // change of theirs puts exactly that in question, so the mark goes the
  // moment the change is pending, and stays away until it is settled.
  testWidgets('shows the verified mark only while no identity change is pending', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      expect(find.byTooltip('Verified'), findsOneWidget);

      // The peer's device presents another key while the chat is open.
      final peer = world.relay.partiesByHandle[peerHandle]!;
      await tester.runAsync(
        () => world.trust.admit(chatConversationId, peer.userId, peer.deviceId, identities.self.identityPublicKey),
      );
      await pumpFrames(tester, frames: 3);
      // The banner, and the line in the chat where the change happened.
      expect(find.widgetWithText(VeilNotice, 'Safety number changed'), findsOneWidget);
      expect(find.byTooltip('Verified'), findsNothing);
    });

    // Opened with the change already pending: the mark never shows.
    await withPhoneApp(
      tester,
      identities,
      location: _chat,
      attention: const ChatAttention(identityChanged: true),
      body: (world) async {
        expect(find.widgetWithText(VeilNotice, 'Safety number changed'), findsOneWidget);
        expect(find.byTooltip('Verified'), findsNothing);
      },
    );

    // Nor while the chat is held because it is listed with another account.
    await withPhoneApp(
      tester,
      identities,
      location: _chat,
      attention: const ChatAttention(accountHeld: true),
      body: (world) async {
        expect(_fullNotices(), findsOneWidget);
        expect(find.byTooltip('Verified'), findsNothing);
        expect(await world.messenger.isPeerVerified(chatConversationId), isFalse);
      },
    );
  });

  testWidgets('keeps an identity change above the messages with its action; failed sends say so on their bubbles',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: _chat,
      attention: const ChatAttention(identityChanged: true, failedSends: 2),
      body: (world) async {
        for (final text in ['Safety number changed', 'Review']) {
          final rect = onScreen(tester, find.text(text));
          expect(rect.height, greaterThan(0), reason: '"$text" is on screen');
        }
        // As Signal does: no banner for them, the bubble is the retry.
        expect(_fullNotices(), findsOneWidget);
        expect(find.text('Not sent. Tap to retry.'), findsWidgets);
        expect(find.text('Retry now'), findsNothing);
        expect(onScreen(tester, find.byType(ChatMessageList)).height, greaterThanOrEqualTo(96));
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Review'));
        await pumpFrames(tester);
        expect(find.byType(SafetyNumbersScreen), findsOneWidget);
        await awaitSafetyNumber(tester);
      },
    );
  });

  // The least room a chat has: 360x640 with the keyboard up. The banners
  // would not fit there, and a strip that scrolls them cuts the first one's
  // action off, which is the one thing the user must be able to reach.
  testWidgets('with the keyboard up, each warning keeps its title and its action on one row', (tester) async {
    const titles = ['Safety number changed', 'A different account'];
    const actions = ['Review', 'Talk to this account'];
    await withPhoneApp(
      tester,
      identities,
      location: _chat,
      keyboardHeight: 300,
      attention: const ChatAttention(identityChanged: true, accountHeld: true),
      body: (world) async {
        expect(_denseNotices(), findsNWidgets(2));
        expect(_fullNotices(), findsNothing, reason: 'the full notices are not what is shown');
        for (final title in titles) {
          final box = tester.renderObject<RenderBox>(findCopy(title));
          expect(visibleRect(tester, box).size, box.size, reason: '"$title" is whole');
        }
        for (final action in actions) {
          final button = tester.renderObject<RenderBox>(find.widgetWithText(TextButton, action));
          expect(whyNotWhollyTappable(tester, button), isNull, reason: '"$action"');
          expect(button.size.height, greaterThanOrEqualTo(44));
        }
        expect(onScreen(tester, find.byType(ChatMessageList)).height, greaterThanOrEqualTo(96));
        expect(tester.takeException(), isNull);

        await tester.tap(find.text(actions.first));
        // The composer loses the focus to the screen that opens, and the
        // keyboard goes with it.
        tester.view.viewInsets = FakeViewPadding.zero;
        await pumpFrames(tester);
        expect(find.byType(SafetyNumbersScreen), findsOneWidget);
        await awaitSafetyNumber(tester);
      },
    );
  });

  testWidgets('with room for them again, the warnings are banners with their explanation', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: _chat,
      attention: const ChatAttention(identityChanged: true, accountHeld: true),
      body: (world) async {
        expect(_fullNotices(), findsNWidgets(2));
        expect(_denseNotices(), findsNothing);
        expect(find.text('Nothing is sent until you review it.'), findsOneWidget);

        // The keyboard comes up, and goes again.
        tester.view.viewInsets = const FakeViewPadding(bottom: 600);
        await pumpFrames(tester, frames: 3);
        expect(_denseNotices(), findsNWidgets(2));
        expect(find.text('Nothing is sent until you review it.'), findsNothing);
        tester.view.viewInsets = FakeViewPadding.zero;
        await pumpFrames(tester, frames: 3);
        expect(_fullNotices(), findsNWidgets(2));
        expect(_denseNotices(), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('every warning stays whole with larger text and the keyboard up; failed sends add none',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: _chat,
      keyboardHeight: 300,
      textScale: 1.3,
      attention: const ChatAttention(identityChanged: true, accountHeld: true, failedSends: 2),
      body: (world) async {
        expect(_denseNotices(), findsNWidgets(2));
        Finder action(String label) => find.widgetWithText(TextButton, label);
        expect(whyNotWhollyTappable(tester, tester.renderObject<RenderBox>(action('Review'))), isNull);
        expect(whyNotWhollyTappable(tester, tester.renderObject<RenderBox>(action('Talk to this account'))), isNull);
        expect(action('Retry now'), findsNothing);
        expect(onScreen(tester, find.byType(ChatMessageList)).height, greaterThanOrEqualTo(96));
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('shows a held account with the button that releases it', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: _chat,
      attention: const ChatAttention(accountHeld: true),
      body: (world) async {
        expect(onScreen(tester, find.text('A different account')).height, greaterThan(0));
        expect(onScreen(tester, find.text('Talk to this account')).height, greaterThan(0));
        expect(find.textContaining('New messages stay locked and nothing is sent until you confirm'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('goes back to the list it was opened from', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.tap(find.text('Sam Rivera'));
      await pumpFrames(tester);
      expect(find.byType(ChatRoomScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await pumpFrames(tester);
      expect(find.byType(ChatRoomScreen), findsNothing);
      expect(find.byType(ConversationListScreen), findsOneWidget);
    });
  });

  testWidgets('leaves for the list when it was the first screen', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      await tester.tap(find.byTooltip('Back'));
      await pumpFrames(tester);
      expect(find.byType(ChatRoomScreen), findsNothing);
      expect(find.byType(ConversationListScreen), findsOneWidget);
    });
  });
}

// The warnings of a chat in their full form (title, explanation, action)
// and as one row each.
Finder _fullNotices() => find.byWidgetPredicate((widget) => widget is VeilNotice && !widget.dense);
Finder _denseNotices() => find.byWidgetPredicate((widget) => widget is VeilNotice && widget.dense);
