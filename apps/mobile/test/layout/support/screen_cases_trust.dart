import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/safety/message_risk.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_composer_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_request_bar.dart';
import 'package:veil_mobile/src/features/chat/presentation/chat_room_screen.dart';
import 'package:veil_mobile/src/features/chat/presentation/message_risk_line.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_list_screen.dart';
import 'package:veil_mobile/src/features/conversations/presentation/conversation_row.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import 'layout_world.dart';
import 'phone_layout_probe.dart';
import 'screen_cases.dart';
import 'trust_seed.dart';

// The layout cases of message requests and trust banners (trust_seed.dart):
// a stranger's 1:1 request in Chats and open, a group request, a look-alike
// of Sam's verified handle after Accept and before it (over the request
// bar), a new account that says it is family with its Verify, each of those
// two with the keyboard up too, the claim under a "Safety number changed"
// notice with the keyboard, and the nudge to verify in Sam's busy chat while
// his number was never compared; and a stranger's request holding a warn
// line (a money ask) and a strong one (a code ask) under an everyday line
// that has none. The seeds are English, as every layout seed is.

final _en = lookupAppLocalizations(const Locale('en'));

const List<ScreenCase> trustScreenCases = [
  ScreenCase(
    'conversation-list-request',
    screen: ConversationListScreen,
    file: 'conversation_list_screen.dart',
    location: '/conversations',
    attention: ChatAttention(trust: TrustCase.request),
    primaryExtent: conversationRowsExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _expectRequestRow,
  ),
  ScreenCase(
    'chat-request',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$strangerConversationId',
    attention: ChatAttention(trust: TrustCase.request),
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _expectDirectRequest,
  ),
  ScreenCase(
    'chat-request-larger-text',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$strangerConversationId',
    attention: ChatAttention(trust: TrustCase.request),
    textScale: largerText,
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
    settle: _expectDirectRequest,
  ),
  ScreenCase(
    'chat-request-risk-lines',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$riskStrangerConversationId',
    attention: ChatAttention(trust: TrustCase.riskLines),
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _expectRiskLines,
  ),
  ScreenCase(
    'chat-request-group',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$strangerGroupId',
    attention: ChatAttention(trust: TrustCase.groupRequest),
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _expectGroupRequest,
  ),
  ScreenCase(
    'chat-lookalike',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$lookalikeConversationId',
    attention: ChatAttention(trust: TrustCase.lookalike),
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
    settle: _expectLookalike,
  ),
  ScreenCase(
    'chat-lookalike-keyboard',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$lookalikeConversationId',
    attention: ChatAttention(trust: TrustCase.lookalike),
    keyboardHeight: 300,
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
    settle: _expectLookalike,
  ),
  ScreenCase(
    'chat-lookalike-request',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$lookalikeConversationId',
    attention: ChatAttention(trust: TrustCase.lookalikeRequest),
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
    settle: _expectLookalikeRequest,
  ),
  ScreenCase(
    'chat-claim',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$claimConversationId',
    attention: ChatAttention(trust: TrustCase.claim),
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
    settle: _expectClaim,
  ),
  ScreenCase(
    'chat-claim-keyboard',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$claimConversationId',
    attention: ChatAttention(trust: TrustCase.claim),
    keyboardHeight: 300,
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
    settle: _expectClaim,
  ),
  ScreenCase(
    'chat-claim-identity-keyboard',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$claimConversationId',
    attention: ChatAttention(trust: TrustCase.claim, identityChanged: true),
    keyboardHeight: 300,
    primaryExtent: chatMessagesExtent,
    minPrimaryExtent: minSqueezedMessagesExtent,
    settle: _expectClaimUnderIdentity,
  ),
  ScreenCase(
    'chat-verify-nudge',
    screen: ChatRoomScreen,
    file: 'chat_room_screen.dart',
    location: '/chat/$chatConversationId',
    attention: ChatAttention(trust: TrustCase.nudge),
    primaryExtent: chatMessagesExtent,
    minPrimaryShare: minPrimaryContentShare,
    settle: _expectNudge,
  ),
];

// The stranger's row is in the list, in time order, with the others.
Future<void> _expectRequestRow(WidgetTester tester) async {
  await pumpFrames(tester, frames: 4);
  expect(find.byType(ConversationRow), findsWidgets);
  expect(find.widgetWithText(ConversationRow, strangerHandle), findsOneWidget, reason: 'the request has no row');
}

Future<void> _expectDirectRequest(WidgetTester tester) async {
  await pumpFrames(tester, frames: 6);
  expect(find.byType(ChatRequestBar), findsOneWidget, reason: 'the request bar is not in the composer\'s place');
  expect(find.byType(ChatComposerBar), findsNothing);
  for (final label in [_en.blockAction, _en.reportAction, _en.chatRequestAccept]) {
    expect(find.descendant(of: find.byType(ChatRequestBar), matching: find.text(label)), findsOneWidget);
  }
}

// The request frame with the message body's lines: one warn, one strong,
// each under its own bubble, and none under the everyday line.
Future<void> _expectRiskLines(WidgetTester tester) async {
  await pumpFrames(tester, frames: 10);
  expect(find.byType(ChatRequestBar), findsOneWidget, reason: 'the request bar is not in the composer\'s place');
  final lines = find.byType(MessageRiskLine);
  expect(lines, findsNWidgets(2), reason: 'a warn and a strong line, nothing under the everyday line');
  final levels = tester.widgetList<MessageRiskLine>(lines).map((line) => line.risk);
  expect(levels, unorderedEquals(const [
    MessageRisk(level: RiskLevel.warn, reason: RiskReason.asksForMoney),
    MessageRisk(level: RiskLevel.strong, reason: RiskReason.asksForCode),
  ]));
  expect(find.text(_en.riskLineMoney), findsOneWidget);
  expect(find.text(_en.riskLineCode), findsOneWidget);
}

Future<void> _expectGroupRequest(WidgetTester tester) async {
  await pumpFrames(tester, frames: 6);
  expect(find.byType(ChatRequestBar), findsOneWidget, reason: 'the request bar is not in the composer\'s place');
  for (final label in [_en.chatRequestLeave, _en.chatRequestAccept]) {
    expect(find.descendant(of: find.byType(ChatRequestBar), matching: find.text(label)), findsOneWidget);
  }
}

Future<void> _expectLookalike(WidgetTester tester) async {
  await pumpFrames(tester, frames: 8);
  expect(find.text(_en.chatLookalikeTitle('Sam Rivera')), findsOneWidget, reason: 'the look-alike warning is not up');
  expect(find.byType(ChatComposerBar), findsOneWidget, reason: 'the chat was accepted');
}

// Before Accept: the warning, and under it the request bar, whose Accept is
// as plain as Block and Report.
Future<void> _expectLookalikeRequest(WidgetTester tester) async {
  await pumpFrames(tester, frames: 8);
  expect(find.text(_en.chatLookalikeTitle('Sam Rivera')), findsOneWidget, reason: 'the look-alike warning is not up');
  expect(find.byType(ChatRequestBar), findsOneWidget, reason: 'the request bar is not in the composer\'s place');
  expect(tester.widget(find.byKey(const ValueKey('request-accept'))), isA<TextButton>(),
      reason: 'Accept is filled under the warning');
}

Future<void> _expectClaim(WidgetTester tester) async {
  await pumpFrames(tester, frames: 8);
  expect(find.text(_en.chatClaimTitle), findsOneWidget, reason: 'the claim banner is not up');
  expect(chatWarningActions(), findsOneWidget, reason: 'the claim banner has no Verify');
}

// Under the identity notice, whose Review is the chat's one action, the
// claim keeps its title and loses its Verify.
Future<void> _expectClaimUnderIdentity(WidgetTester tester) async {
  await pumpFrames(tester, frames: 8);
  expect(find.text(_en.chatClaimTitle), findsOneWidget, reason: 'the claim banner is not up');
  expect(find.text(_en.chatIdentityChangedTitle), findsOneWidget, reason: 'the identity notice is not up');
  expect(find.widgetWithText(TextButton, _en.chatIdentityChangedReview), findsOneWidget);
  expect(find.widgetWithText(TextButton, _en.chatVerifyAction), findsNothing, reason: 'two banner actions');
}

Future<void> _expectNudge(WidgetTester tester) async {
  await pumpFrames(tester, frames: 8);
  expect(find.text(_en.chatVerifyNudge('Sam Rivera')), findsOneWidget, reason: 'the nudge is not up');
}
