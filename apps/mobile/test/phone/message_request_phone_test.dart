import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/security/platform_security_service.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_composer_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_request_bar.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';
import 'package:veil_mobile/src/features/reactions/presentation/reaction_picker_widget.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../layout/support/trust_seed.dart';
import '../support/copy_finder.dart';
import '../support/fake_platform_security.dart';
import 'phone_app.dart';

// A message request on a phone: a chat from an account alex never talked
// to (noah_park), or a group noah_park added alex to. The request bar takes
// the composer's place until alex accepts; until then nothing tells the
// other side the chat was seen: no screenshot line, no reaction, no timer.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LayoutIdentities identities;
  final en = lookupAppLocalizations(const Locale('en'));
  const stranger = '@$strangerHandle';

  setUpAll(() async {
    await loadBundledFonts();
    identities = await LayoutIdentities.generate();
  });

  Finder inBar(Finder finder) => find.descendant(of: find.byType(ChatRequestBar), matching: finder);
  Finder barButton(String key) => find.byKey(ValueKey('request-$key'));

  testWidgets('a request shows Block, Report and Accept in place of the composer', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/chat/$strangerConversationId',
      attention: const ChatAttention(trust: TrustCase.request),
      body: (world) async {
        await pumpFrames(tester, frames: 4);
        expect(world.contactTrust.isRequest(strangerConversationId), isTrue);
        expect(find.byType(ChatRequestBar), findsOneWidget);
        expect(find.byType(ChatComposerBar), findsNothing, reason: 'nothing can be typed before Accept');
        expect(find.byType(TextField), findsNothing);
        expect(inBar(find.text(en.chatRequestTitle)), findsOneWidget);
        expect(inBar(find.text(en.chatRequestDirectBody(stranger))), findsOneWidget);

        // One row of equal buttons, 44 high: Block, Report, then Accept,
        // which is the filled one.
        final block = tester.getRect(barButton('block'));
        final report = tester.getRect(barButton('report'));
        final accept = tester.getRect(barButton('accept'));
        expect(tester.widget(barButton('accept')), isA<FilledButton>());
        expect(inBar(find.text(en.blockAction)), findsOneWidget);
        expect(inBar(find.text(en.reportAction)), findsOneWidget);
        expect(inBar(find.text(en.chatRequestAccept)), findsOneWidget);
        expect(barButton('leave'), findsNothing, reason: 'a 1:1 has nothing to leave');
        expect(block.right, lessThan(report.left));
        expect(report.right, lessThan(accept.left));
        expect(block.top, report.top);
        expect(report.top, accept.top);
        expect(block.width, moreOrLessEquals(accept.width, epsilon: 0.5));
        expect(accept.height, greaterThanOrEqualTo(44));
        expect(accept.bottom, lessThanOrEqualTo(640));

        // Report opens the report sheet, which offers to block too.
        await tester.tap(barButton('report'));
        await pumpFrames(tester, frames: 4);
        expect(find.text(en.reportTitle(stranger)), findsOneWidget);
        await tester.tap(find.text(en.reportReasonSpam));
        await pumpFrames(tester, frames: 4);
        expect(find.byKey(const ValueKey('report-also-block')), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  testWidgets('Accept brings the composer back and Block opens the block dialog', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/chat/$strangerConversationId',
      attention: const ChatAttention(trust: TrustCase.request),
      body: (world) async {
        await pumpFrames(tester, frames: 4);
        await tester.tap(barButton('block'));
        await pumpFrames(tester, frames: 4);
        expect(find.text(en.blockConfirmTitle(stranger)), findsOneWidget);
        expect(find.text(en.blockConfirmBody), findsOneWidget);
        await tester.tap(find.text(en.commonCancel));
        await pumpFrames(tester, frames: 4);
        expect(world.relay.blocks['user-$selfHandle'] ?? const {}, isEmpty, reason: 'Cancel blocks no one');
        expect(find.byType(ChatRequestBar), findsOneWidget);

        await tester.tap(barButton('accept'));
        await pumpFrames(tester, frames: 4);
        expect(find.byType(ChatRequestBar), findsNothing);
        expect(find.byType(ChatComposerBar), findsOneWidget, reason: 'the composer is back');
        expect(world.contactTrust.isRequest(strangerConversationId), isFalse);
        final stored = await storedDocument(world);
        expect(stored.chats[strangerConversationId]?.accepted, isNotNull, reason: 'the accept is written at once');
      },
    );
  });

  testWidgets('a group request offers Leave and Accept', (tester) async {
    await withPhoneApp(
      tester,
      identities,
      location: '/conversations',
      attention: const ChatAttention(trust: TrustCase.groupRequest),
      body: (world) async {
        await tester.tap(find.widgetWithText(ConversationRow, strangerGroupName));
        await pumpFrames(tester, frames: 6);
        expect(find.byType(ChatRequestBar), findsOneWidget);
        expect(inBar(find.text(en.chatRequestGroupBody)), findsOneWidget);
        expect(inBar(find.text(en.chatRequestLeave)), findsOneWidget);
        expect(inBar(find.text(en.chatRequestAccept)), findsOneWidget);
        expect(barButton('block'), findsNothing);
        expect(barButton('report'), findsNothing);

        // The relay cannot find the group: a toast says so and the chat stays.
        final group = world.relay.conversations.remove(strangerGroupId)!;
        await tester.tap(barButton('leave'));
        await pumpFrames(tester, frames: 4);
        expect(find.text(en.chatLeaveGroupTitle(strangerGroupName)), findsOneWidget);
        expect(find.text(en.chatLeaveGroupBody), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('leave-confirm')));
        await pumpFrames(tester, frames: 4);
        expect(findCopy(en.chatLeaveGroupFailed), findsOneWidget);
        expect(find.byType(ChatRequestBar), findsOneWidget);

        // Left: the leave route is posted, and Chats no longer lists it.
        world.relay.conversations[strangerGroupId] = group;
        await tester.pump(const Duration(seconds: 6));
        await pumpFrames(tester, frames: 2);
        await tester.tap(barButton('leave'));
        await pumpFrames(tester, frames: 4);
        await tester.tap(find.byKey(const ValueKey('leave-confirm')));
        await pumpFrames(tester, frames: 8);
        expect(world.api.leaveCalls, [strangerGroupId, strangerGroupId]);
        expect(find.byType(ConversationListScreen), findsOneWidget);
        expect(find.widgetWithText(ConversationRow, strangerGroupName), findsNothing);
      },
    );
  });

  testWidgets('a screenshot or a long press in a request sends nothing and the timer is not offered', (tester) async {
    final platform = RecordingPlatformSecurity();
    await withPhoneApp(
      tester,
      identities,
      location: '/chat/$strangerConversationId',
      attention: const ChatAttention(trust: TrustCase.request),
      overrides: [platformSecurityServiceProvider.overrideWithValue(platform)],
      body: (world) async {
        await pumpFrames(tester, frames: 4);
        int relayed() => world.relay.conversations[strangerConversationId]!.messages.length;
        final before = relayed();

        platform.emit(PlatformSecurityEvent.screenshotDetected);
        await pumpFrames(tester, frames: 6);
        expect(relayed(), before, reason: 'a screenshot line would tell the stranger the chat was seen');
        expect(world.messenger.pendingCountFor(strangerConversationId), 0);

        // The long press offers Report, and no reactions.
        await tester.longPress(find.text(strangerLines.last));
        await pumpFrames(tester, frames: 4);
        expect(find.byKey(const ValueKey('message-report')), findsOneWidget);
        expect(find.byType(ReactionPickerWidget), findsNothing);
        await tester.tapAt(const Offset(20, 120));
        await pumpFrames(tester, frames: 4);

        // The menu offers no timer.
        await tester.tap(find.byTooltip(en.chatMenuTooltip));
        await pumpFrames(tester, frames: 3);
        expect(find.byKey(const ValueKey('chat-menu-mute')), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-menu-timer')), findsNothing);
        await tester.tapAt(const Offset(20, 300));
        await pumpFrames(tester, frames: 3);
        expect(relayed(), before);

        // Once accepted, the chat is like any other: a screenshot says so
        // and the timer is back.
        await tester.tap(barButton('accept'));
        await pumpFrames(tester, frames: 4);
        platform.emit(PlatformSecurityEvent.screenshotDetected);
        await pumpFrames(tester, frames: 8);
        expect(relayed(), before + 1, reason: 'an accepted chat gets the screenshot line');
        await tester.tap(find.byTooltip(en.chatMenuTooltip));
        await pumpFrames(tester, frames: 3);
        expect(find.byKey(const ValueKey('chat-menu-timer')), findsOneWidget);
        await tester.tapAt(const Offset(20, 300));
        await pumpFrames(tester, frames: 3);
      },
    );
  });
}
