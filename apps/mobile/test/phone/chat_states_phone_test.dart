import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_bubble.dart';
import 'package:veil_mobile/src/features/chat/presentation/reaction_chips_row.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_numbers_screen.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/layout_seed.dart';
import '../support/copy_finder.dart';
import 'phone_app.dart';

// The states of a chat beyond a quiet 1:1: nothing sent yet, a group, a
// history that would not load, a key change of the peer's that waits in
// another chat, someone typing, and the least room a chat ever has.

const _chat = '/chat/$chatConversationId';
const _emptyChat = '/chat/$emptyChatConversationId';
const _group = '/chat/$groupConversationId';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  Future<void> awaitSafetyNumber(WidgetTester tester) async {
    final loading = find.byType(VeilLoadingBlock);
    for (var i = 0; i < 250 && loading.evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await pumpFrames(tester, frames: 3);
  }

  group('an empty chat', () {
    // The button used to say "Send" and only moved the focus to the
    // composer right under it. What is worth doing before the first message
    // is comparing safety numbers, and that is what it does.
    testWidgets('offers to compare safety numbers with a peer not verified yet, and opens them', (tester) async {
      await withPhoneApp(tester, identities, location: _emptyChat, body: (world) async {
        expect(find.text('No messages yet'), findsOneWidget);
        expect(
          find.text('What you send here is encrypted on this device, for the people in this chat only.'),
          findsOneWidget,
        );
        expect(find.text('Send'), findsNothing);

        await tester.tap(find.text('Compare safety numbers'));
        await pumpFrames(tester);
        final opened = tester.widget<SafetyNumbersScreen>(find.byType(SafetyNumbersScreen));
        expect(opened.conversationId, emptyChatConversationId);
        await awaitSafetyNumber(tester);
      });
    });
  });

  group('a group chat', () {
    testWidgets('is titled with its other members and says how many are in it', (tester) async {
      await withPhoneApp(tester, identities, withGroup: true, location: _group, body: (world) async {
        // The relay lists a group's members, not a name for it.
        expect(find.text('Sam Rivera, Priya Nair, Omar Haddad'), findsOneWidget);
        expect(find.text('4 members'), findsOneWidget);
        expect(find.textContaining(selfDisplayName), findsNothing, reason: 'the user is not named in their own title');
      });
    });

    testWidgets('names who wrote each message, and never the user', (tester) async {
      await withPhoneApp(tester, identities, withGroup: true, location: _group, body: (world) async {
        String? nameOn(String body) => tester
            .widget<MessageBubble>(find.ancestor(of: find.text(body), matching: find.byType(MessageBubble)))
            .senderName;

        expect(nameOn('The movers can do the 14th or the 16th.'), 'Sam Rivera');
        expect(nameOn('The 14th works for me.'), 'Priya Nair');
        expect(nameOn('14th then. I will book the lift for the morning.'), isNull);
        expect(nameOn('I can bring the van after six, if someone helps me carry the shelves down.'), 'Omar Haddad');
        // Drawn, above the words, inside the bubble.
        final name = tester.getRect(find.text('Priya Nair'));
        final words = tester.getRect(find.text('The 14th works for me.'));
        expect(name.bottom, lessThanOrEqualTo(words.top));
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('names a sender once for messages in a row', (tester) async {
      await withPhoneApp(
        tester,
        identities,
        withGroup: true,
        location: _group,
        prepare: (world) async {
          await _injectGroupLine(world, from: 'omar', body: 'And the lamp.');
          return null;
        },
        body: (world) async {
          MessageBubble bubble(String body) =>
              tester.widget<MessageBubble>(find.ancestor(of: find.text(body), matching: find.byType(MessageBubble)));
          expect(bubble('I can bring the van after six, if someone helps me carry the shelves down.').senderName,
              'Omar Haddad');
          expect(bubble('And the lamp.').senderName, isNull);
          expect(find.text('Omar Haddad'), findsOneWidget);
        },
      );
    });

    // The relay decides what a group's history lists. A frame from a device
    // this device has pinned for none of the members must not sit, without
    // a name, under the name of whoever wrote the message above it.
    testWidgets('says so when it cannot tell which member a message is from', (tester) async {
      await withPhoneApp(
        tester,
        identities,
        withGroup: true,
        location: _group,
        prepare: (world) async {
          // jonas is on the relay, but not in this group.
          await _injectGroupLine(world, from: 'jonas', body: 'Change of plan: the 16th.');
          return null;
        },
        body: (world) async {
          final bubble = tester.widget<MessageBubble>(
            find.ancestor(of: find.text('Change of plan: the 16th.'), matching: find.byType(MessageBubble)),
          );
          expect(bubble.senderName, 'Unknown sender');
          expect(find.text('Unknown sender'), findsOneWidget);
        },
      );
    });

    testWidgets('a 1:1 names nobody: the side a bubble is on says who wrote it', (tester) async {
      await withPhoneApp(tester, identities, location: _chat, body: (world) async {
        final names = tester.widgetList<MessageBubble>(find.byType(MessageBubble)).map((bubble) => bubble.senderName);
        expect(names, isNotEmpty);
        expect(names.nonNulls, isEmpty);
      });
    });

    testWidgets('says who is typing; a 1:1 only that they are', (tester) async {
      await withPhoneApp(tester, identities, withGroup: true, location: _group, body: (world) async {
        world.messenger.presenceTyping.typingStarted(groupConversationId, 'priya');
        await tester.pump();
        expect(find.text('@priya is typing…'), findsOneWidget);
        // The indicator clears by itself.
        await tester.pump(const Duration(seconds: 6));
        expect(find.textContaining('typing'), findsNothing);
      });
      await withPhoneApp(tester, identities, location: _chat, body: (world) async {
        world.messenger.presenceTyping.typingStarted(chatConversationId, peerHandle);
        await tester.pump();
        expect(find.text('typing…'), findsOneWidget);
        expect(find.textContaining('@$peerHandle is'), findsNothing);
        await tester.pump(const Duration(seconds: 6));
      });
    });
  });

  group('a history that could not be loaded', () {
    testWidgets('says so once, with the reason and a retry that fetches again', (tester) async {
      await withPhoneApp(
        tester,
        identities,
        location: _emptyChat,
        attention: const ChatAttention(relayError: true),
        body: (world) async {
          expect(find.text('Could not load messages'), findsOneWidget);
          expect(find.text('The VEIL relay could not complete the request. Try again shortly.'), findsOneWidget,
              reason: 'the reason, said once');
          expect(find.byType(VeilInlineBanner), findsNothing, reason: 'no banner repeats it');
          expect(find.text('No messages yet'), findsNothing, reason: 'nobody knows that yet');

          final before = world.api.messageFetches;
          await tester.tap(find.text('Retry'));
          await pumpFrames(tester, frames: 3);
          expect(world.api.messageFetches, greaterThan(before));
        },
      );
    });

    testWidgets('with messages on screen an error is a banner above them, in the app\'s words', (tester) async {
      await withPhoneApp(
        tester,
        identities,
        location: _chat,
        attention: const ChatAttention(relayError: true),
        body: (world) async {
          expect(find.byType(VeilInlineBanner), findsOneWidget);
          expect(findCopy('Conversation issue'), findsOneWidget);
          expect(findCopy('The VEIL relay could not complete the request. Try again shortly.'), findsOneWidget);
          expect(find.textContaining('The VEIL relay failed'), findsNothing, reason: 'the formatter\'s words');
          expect(onScreen(tester, find.byType(ChatMessageList)).height / screenHeight(tester), greaterThan(0.4));
        },
      );
    });

    testWidgets('while it is still loading, says that and nothing else', (tester) async {
      await withPhoneApp(
        tester,
        identities,
        location: _emptyChat,
        attention: const ChatAttention(loading: true),
        body: (world) async {
          expect(find.text('Loading messages'), findsOneWidget);
          expect(find.text('No messages yet'), findsNothing);
          expect(find.text('Compare safety numbers'), findsNothing);
        },
      );
    });
  });

  // The peer showed another key in a group they share with the user. The
  // group holds the change; this 1:1 still talks to the key it pinned, but
  // it must not look verified, and it says where the question is open.
  testWidgets('a key change that waits in another chat is announced here, with the way to it', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      withGroup: true,
      location: _chat,
      attention: const ChatAttention(identityChangedInGroup: true),
      body: (world) async {
        expect(find.text('Safety number changed in another chat'), findsOneWidget);
        expect(find.byTooltip('Verified'), findsNothing);
        expect(find.text('Safety number changed'), findsNothing, reason: 'this chat itself is not paused');

        await tester.tap(find.widgetWithText(TextButton, 'Review'));
        await pumpFrames(tester);
        final opened = tester.widget<SafetyNumbersScreen>(find.byType(SafetyNumbersScreen));
        expect(opened.conversationId, chatConversationId);
        await awaitSafetyNumber(tester);
      },
    );
  });

  // The least room a chat ever has: 360x640, the keyboard up, two warnings,
  // and text at 1.3x. Both warnings keep their action, whole, in reach.
  testWidgets('with the keyboard up and larger text, both warning actions are wholly tappable', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: _chat,
      keyboardHeight: 300,
      textScale: 1.3,
      attention: const ChatAttention(identityChanged: true, failedSends: 2),
      body: (world) async {
        expect(find.byType(VeilNoticeRow), findsNWidgets(2));
        for (final action in ['Review', 'Retry failed sends']) {
          final button = tester.renderObject<RenderBox>(find.widgetWithText(TextButton, action));
          expect(whyNotWhollyTappable(tester, button), isNull, reason: '"$action"');
          expect(button.size.height, greaterThanOrEqualTo(44), reason: '"$action"');
        }
        // The composer stays whole, and a tap target, above the keyboard.
        final composer = tester.renderObject<RenderBox>(find.byType(TextField));
        expect(whyNotWhollyTappable(tester, composer), isNull);
        expect(composer.size.height, greaterThanOrEqualTo(44));
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('each reaction under a message takes a tap over 44 px, and a tap toggles this user\'s own',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: _chat,
      prepare: (world) async {
        await _reactToLatest(world, '\u{1F44D}');
        return null;
      },
      body: (world) async {
        await pumpFrames(tester, frames: 3);
        final chips = find.descendant(of: find.byType(ReactionChipsRow), matching: find.byType(InkWell));
        expect(chips, findsOneWidget);
        final chip = tester.renderObject<RenderBox>(chips);
        expect(chip.size.height, greaterThanOrEqualTo(44));
        expect(chip.size.width, greaterThanOrEqualTo(44));
        expect(whyNotWhollyTappable(tester, chip), isNull);
        expect(
          find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == '\u{1F44D}, 1 reaction'),
          findsOneWidget,
          reason: 'a screen reader hears the emoji and how many reacted with it',
        );
        expect(tester.takeException(), isNull);

        // It is this user's reaction: a tap withdraws it.
        await tester.tap(chips);
        await pumpFrames(tester, frames: 4);
        expect(find.byType(ReactionChipsRow), findsNothing);
      },
    );
  });
}

final _sealer = createDefaultCryptoAdapter();

/// A text message from [from] at the end of the group's history, as the
/// relay lists it.
Future<void> _injectGroupLine(LayoutWorld world, {required String from, required String body}) async {
  final envelope = await _sealer.messaging.encryptMessage(
    conversationId: groupConversationId,
    senderDeviceId: 'dev-$from',
    recipientUserId: 'user-$selfHandle',
    body: body,
    messageKind: MessageKind.text,
    recipientBundle: const KeyBundle(
      userId: 'user-$selfHandle',
      deviceId: 'dev-$selfHandle',
      handle: selfHandle,
      identityPublicKey: 'ik',
      signedPrekeyBundle: 'spk',
    ),
  );
  final stored = world.relay.inject(
    senderHandle: from,
    conversationId: groupConversationId,
    envelope: _sealer.envelopeCodec.encodeApiEnvelope(envelope),
  );
  stored['serverReceivedAt'] = DateTime.utc(2026, 4, 7, 11).toIso8601String();
}

/// The peer reacts to the newest message of the chat.
Future<void> _reactToLatest(LayoutWorld world, String emoji) async {
  await world.messenger.loadConversationMessages(chatConversationId);
  final latest = world.messenger.messagesFor(chatConversationId).last;
  await world.messenger.toggleReaction(latest, emoji);
}
