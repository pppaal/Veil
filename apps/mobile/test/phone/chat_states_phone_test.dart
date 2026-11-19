import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_bubble.dart';
import 'package:veil_mobile/src/features/chat/presentation/reaction_chips_row.dart';
import 'package:veil_mobile/src/features/chat/presentation/typing_indicator.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_numbers_screen.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import '../layout/support/layout_seed.dart';
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
    final loading = find.byKey(SafetyNumbersScreen.loadingKey);
    for (var i = 0; i < 250 && loading.evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await pumpFrames(tester, frames: 3);
  }

  // At 48 each, the three actions left a verified 10-letter name about
  // 88 px: "Sam Rive…" on every verified chat at the most common width.
  testWidgets('at 360 wide a verified name fits beside the three actions, each 44 square', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      expect(find.byTooltip('Verified'), findsOneWidget, reason: 'the seeded peer is verified');
      final name = tester.renderObject<RenderParagraph>(find.descendant(
        of: find.descendant(of: find.byType(ChatBarTitle), matching: find.text('Sam Rivera')),
        matching: find.byType(RichText),
      ));
      expect(name.didExceedMaxLines, isFalse, reason: '"Sam Rivera" is whole');
      for (final action in ['Safety number', 'Search', 'More options']) {
        expect(tester.getSize(find.byTooltip(action)), const Size.square(ChatBarActions.actionSize), reason: action);
      }
    });
  });

  // In dark the menu's fill (surfaceRaised) is the colour of the hairline
  // `stroke`, which drew the line above Report invisible.
  testWidgets('in dark, the menu\'s line above Report shows against the menu', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      await tester.tap(find.byKey(const ValueKey('chat-menu')));
      await pumpFrames(tester, frames: 4);
      final context = tester.element(find.byKey(const ValueKey('chat-menu-report')));
      expect(Theme.of(context).brightness, Brightness.dark);
      final divider = tester.widget<PopupMenuDivider>(find.byType(PopupMenuDivider));
      expect(divider.color, context.veilPalette.strokeStrong);
      expect(divider.color, isNot(context.veilPalette.surfaceRaised));
    });
  });

  group('an empty chat', () {
    // One muted line, as Telegram's "No messages here yet": no line on
    // encryption, and no button. The safety number is in the bar.
    testWidgets('says it has no messages, and nothing else', (tester) async {
      await withPhoneApp(tester, identities, location: _emptyChat, body: (world) async {
        expect(find.text('No messages yet'), findsOneWidget);
        expect(find.textContaining('encrypted'), findsNothing);
        expect(find.text('Compare safety numbers'), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);

        await tester.tap(find.byTooltip('Safety number'));
        await pumpFrames(tester);
        final opened = tester.widget<SafetyNumbersScreen>(find.byType(SafetyNumbersScreen));
        expect(opened.conversationId, emptyChatConversationId);
        await awaitSafetyNumber(tester);
      });
    });
  });

  group('a group chat', () {
    testWidgets('is titled with its name and says how many are in it', (tester) async {
      await withPhoneApp(tester, identities, withGroup: true, location: _group, body: (world) async {
        expect(find.text(groupName), findsOneWidget);
        expect(find.text('4 members'), findsOneWidget);
        expect(find.textContaining(selfDisplayName), findsNothing, reason: 'the user is not named in their own title');
      });
    });

    testWidgets('names who wrote each message, and never the user', (tester) async {
      await withPhoneApp(tester, identities, withGroup: true, location: _group, body: (world) async {
        String? nameOn(String body) => tester
            .widget<MessageBubble>(find.ancestor(of: find.text(body), matching: find.byType(MessageBubble)))
            .senderName;

        expect(nameOn('movers can do the 14th or 16th'), 'Sam Rivera');
        expect(nameOn('14th works for me'), 'Priya Nair');
        expect(nameOn("14th then, I'll book the lift"), isNull);
        expect(nameOn(latestGroupLine), 'Omar Haddad');
        // Drawn, above the words, inside the bubble.
        final name = tester.getRect(find.text('Priya Nair'));
        final words = tester.getRect(find.text('14th works for me'));
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
          await _injectGroupLine(world, from: 'omar_h', body: 'And the lamp.', at: _lastGroupLineAt.add(const Duration(minutes: 2)));
          return null;
        },
        body: (world) async {
          MessageBubble bubble(String body) =>
              tester.widget<MessageBubble>(find.ancestor(of: find.text(body), matching: find.byType(MessageBubble)));
          expect(bubble(latestGroupLine).senderName, 'Omar Haddad');
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
          // Jonas is on the relay, but not in this group.
          await _injectGroupLine(world, from: timerChatPeerHandle, body: 'Change of plan: the 16th.');
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

    // The dots bubble starts where the peer's bubbles above it do: past
    // the avatar column in a group.
    void expectDotsInLineWithBubbles(WidgetTester tester, String peerLine) {
      final dots = find.descendant(of: find.byType(TypingIndicator), matching: find.byType(DecoratedBox)).first;
      final bubble = find.ancestor(of: find.text(peerLine), matching: find.byType(MessageBubble));
      expect(tester.getTopLeft(dots).dx, tester.getTopLeft(bubble).dx);
    }

    testWidgets('says who is typing; a 1:1 only that they are', (tester) async {
      await withPhoneApp(tester, identities, withGroup: true, location: _group, body: (world) async {
        world.messenger.presenceTyping.typingStarted(groupConversationId, 'priya');
        await tester.pump();
        // Called as her bubbles are: by the nickname saved for her handle.
        expect(find.text('Priya Nair is typing…'), findsOneWidget);
        expectDotsInLineWithBubbles(tester, latestGroupLine);
        // The indicator clears by itself.
        await tester.pump(const Duration(seconds: 6));
        expect(find.textContaining('typing'), findsNothing);
      });
      await withPhoneApp(tester, identities, location: _chat, body: (world) async {
        world.messenger.presenceTyping.typingStarted(chatConversationId, peerHandle);
        await tester.pump();
        // The dots alone; a screen reader still hears it.
        expect(find.bySemanticsLabel('Typing…'), findsOneWidget);
        expectDotsInLineWithBubbles(tester, latestChatLine);
        expect(find.text('Typing…'), findsNothing);
        expect(find.textContaining(' is typing'), findsNothing);
        await tester.pump(const Duration(seconds: 6));
      });
    });
  });

  group('a history that could not be loaded', () {
    testWidgets('says so once, with a retry that fetches again', (tester) async {
      await withPhoneApp(
        tester,
        identities,
        location: _emptyChat,
        attention: const ChatAttention(relayError: true),
        body: (world) async {
          expect(find.text("Couldn't load messages"), findsOneWidget);
          expect(find.textContaining('server'), findsNothing, reason: 'the title and Retry say it');
          expect(find.byIcon(Icons.error_outline), findsNothing);
          expect(find.byType(VeilNotice), findsNothing, reason: 'no notice repeats it');
          expect(find.text('No messages yet'), findsNothing, reason: 'nobody knows that yet');

          final before = world.api.messageFetches;
          await tester.tap(find.text('Retry'));
          await pumpFrames(tester, frames: 3);
          expect(world.api.messageFetches, greaterThan(before));
        },
      );
    });

    testWidgets('with messages on screen an earlier error puts nothing above them', (tester) async {
      await withPhoneApp(
        tester,
        identities,
        location: _chat,
        attention: const ChatAttention(relayError: true),
        body: (world) async {
          // A failure while the chat is open is a toast; one from before it
          // opened is not this chat's to say, and no line is pinned here.
          expect(find.byType(VeilNotice), findsNothing);
          expect(find.textContaining('server'), findsNothing);
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
          // A spinner alone; a screen reader hears what it is for.
          expect(find.bySemanticsLabel('Loading messages…'), findsOneWidget);
          expect(find.text('Loading messages…'), findsNothing);
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
        expect(find.text('Safety number changed in a group you share'), findsOneWidget);
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
      attention: const ChatAttention(identityChanged: true, accountHeld: true),
      body: (world) async {
        expect(find.byWidgetPredicate((widget) => widget is VeilNotice && widget.dense), findsNWidgets(2));
        for (final action in ['Review', 'Talk to this account']) {
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
Future<void> _injectGroupLine(LayoutWorld world, {required String from, required String body, DateTime? at}) async {
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
  stored['serverReceivedAt'] = (at ?? DateTime.utc(2026, 4, 7, 11)).toIso8601String();
}

/// When the seed's last group line (Omar's) was sent, as layout_seed.dart
/// dates it.
final _lastGroupLineAt = DateTime.utc(2026, 4, 7, 10, 13);

/// The peer reacts to the newest message of the chat.
Future<void> _reactToLatest(LayoutWorld world, String emoji) async {
  await world.messenger.loadConversationMessages(chatConversationId);
  final latest = world.messenger.messagesFor(chatConversationId).last;
  await world.messenger.toggleReaction(latest, emoji);
}
