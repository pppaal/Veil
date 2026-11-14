import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/attachments/presentation/attachment_preview_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_composer_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_header.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_message_list.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/security/presentation/safety_numbers_screen.dart';
import 'package:veil_mobile/src/shared/presentation/veil_ui.dart';

import 'phone_app.dart';

// A chat on a phone: the messages have the screen, and everything the
// header cards carried in the wide layout is still one tap away in the bar.

const _latest = 'Section 7 is fine. Let us sign tomorrow.';
const _first = 'Did the signed lease come through on your side?';
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
    final loading = find.byType(VeilLoadingBlock);
    for (var i = 0; i < 250 && loading.evaluate().isNotEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    await pumpFrames(tester, frames: 3);
  }

  testWidgets('opens at its latest message and gives the messages the screen', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      expect(find.byType(VeilHeroPanel), findsNothing);
      expect(find.byType(VeilMetricStrip), findsNothing);
      expect(find.byType(ChatHeader), findsNothing);

      final messages = onScreen(tester, find.byType(ChatMessageList));
      expect(messages.height / screenHeight(tester), greaterThan(0.6));
      expect(onScreen(tester, find.text(_latest)).height, greaterThan(0), reason: 'the newest message is in view');
      expect(find.text(_first), findsNothing, reason: 'the oldest is above, not where the chat opens');

      final composer = tester.renderObject<RenderBox>(find.byType(ChatComposerBar));
      expect(onScreen(tester, find.byType(ChatComposerBar)).height, composer.size.height,
          reason: 'the whole composer is on screen');
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('names the peer in the bar, with the verified mark only for a verified peer', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      expect(find.text('Selene Park'), findsOneWidget);
      expect(find.text('@selene'), findsOneWidget);
      expect(find.byTooltip('Verified'), findsOneWidget);
    });
    await withPhoneApp(tester, identities, location: '/chat/$emptyChatConversationId', body: (world) async {
      expect(find.text('Mira'), findsOneWidget);
      expect(find.byTooltip('Verified'), findsNothing);
    });
  });

  testWidgets('opens the safety number from the bar, and comes back', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      await tester.tap(find.byTooltip('Safety Number'));
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

  testWidgets('searches from the bar: the field replaces the title, and back closes it', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      await tester.tap(find.byTooltip('Search messages'));
      await pumpFrames(tester, frames: 2);
      expect(find.widgetWithText(TextField, 'Search cached messages on this device'), findsOneWidget);
      expect(find.text('Selene Park'), findsNothing);
      expect(find.byTooltip('Safety Number'), findsNothing);

      // Typed where the focus is: opening the search moved it to the bar.
      tester.testTextInput.enterText('lease');
      await pumpFrames(tester, frames: 4);
      expect(find.text('2 matches on this device'), findsOneWidget);
      expect(find.text(_first), findsOneWidget);
      expect(find.text(_latest), findsNothing);

      await tester.tap(find.byTooltip('Back'));
      await pumpFrames(tester, frames: 4);
      expect(find.byType(ChatRoomScreen), findsOneWidget, reason: 'back closed the search, not the chat');
      expect(find.text('Selene Park'), findsOneWidget);
      expect(find.text(_latest), findsOneWidget);
      expect(find.textContaining('on this device'), findsNothing);
    });
  });

  testWidgets('sets the disappearing timer from the bar and shows it there', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      await tester.tap(find.byTooltip('Disappearing messages: Off'));
      await pumpFrames(tester, frames: 4);
      expect(find.text('Disappearing messages'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'the sheet fits a 360x640 screen');

      await tester.tap(find.text('1 day'));
      await pumpFrames(tester, frames: 4);
      expect(world.api.timers[chatConversationId], 86400);
      expect(find.byTooltip('Disappearing messages: 1 day'), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget, reason: 'under the name, while a timer is set');
    });
  });

  testWidgets('shows a timer the conversation already has', (tester) async {
    await withPhoneApp(tester, identities, location: '/chat/$timerChatConversationId', body: (world) async {
      expect(find.byTooltip('Disappearing messages: 1 day'), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget);
    });
  });

  testWidgets('opens attachments from the composer', (tester) async {
    await withPhoneApp(tester, identities, location: _chat, body: (world) async {
      await tester.tap(find.byTooltip('Attach'));
      await pumpFrames(tester);
      expect(find.byType(AttachmentPreviewScreen), findsOneWidget);
    });
  });

  testWidgets('keeps an identity change and failed sends above the messages, each with its action',
      (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: _chat,
      attention: const ChatAttention(identityChanged: true, failedSends: 2),
      body: (world) async {
        for (final text in ['Safety number changed', 'Review', 'Delivery stalled', 'Retry failed sends']) {
          final rect = onScreen(tester, find.text(text));
          expect(rect.height, greaterThan(0), reason: '"$text" is on screen');
        }
        expect(onScreen(tester, find.byType(ChatMessageList)).height, greaterThanOrEqualTo(96));
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Review'));
        await pumpFrames(tester);
        expect(find.byType(SafetyNumbersScreen), findsOneWidget);
        await awaitSafetyNumber(tester);
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
        expect(find.textContaining('Nothing is sent or opened here'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('goes back to the list it was opened from', (tester) async {
    await withPhoneApp(tester, identities, location: '/conversations', body: (world) async {
      await tester.tap(find.text('Selene Park'));
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
