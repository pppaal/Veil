import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/domain/chat_message.dart';
import 'package:veil_mobile/src/core/safety/message_risk.dart';
import 'package:veil_mobile/src/core/safety/rule_risk_checker.dart';
import 'package:veil_mobile/src/features/chat/application/message_safety.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';
import 'trust_support.dart';

// The risk line each message gets (MessageSafety), on real messengers over
// the fake relay: alice's phone keeps message requests and reads what bob,
// a stranger, sends. The relay stamps messages on its own clock; the trust
// layer's clock is moved by hand around those stamps.

void main() {
  late FakeRelay relay;
  late MessengerParty alice;
  late MessengerParty bob;
  late DateTime now;
  late MessageSafety safety;
  const chat = 'conv-bob';

  setUp(() async {
    relay = trustRelay();
    // After the relay's stamps (April 1): what the trust layer records at
    // this time (an accept, a text alice sent) is later than every message,
    // so it makes no one known when those were sent.
    now = DateTime.utc(2026, 11, 2, 9);
    alice = await phone(relay, 'alice', requests: true);
    alice.clock = () => now;
    bob = await phone(relay, 'bob');
    await alice.signIn();
    await bob.signIn();
    await trustReady(alice);
    relay.addDirect(chat, 'bob', 'alice');
  });

  tearDown(() async {
    safety.dispose();
    await alice.dispose();
    await bob.dispose();
  });

  MessageSafety watch() =>
      safety = MessageSafety(conversationId: chat, messenger: alice.controller, trust: alice.contactTrust, checker: const RuleRiskChecker());

  Future<ChatMessage> fromBob(String body) async {
    await deliver(bob, alice, chat, body);
    final messages = alice.controller.messagesFor(chat);
    final bodies = await Future.wait(messages.map(alice.controller.decryptMessage));
    return messages[bodies.lastIndexWhere((message) => message.body == body)];
  }

  Future<ChatMessage> fromAlice(String body) async {
    await deliver(alice, bob, chat, body);
    return alice.controller.messagesFor(chat).lastWhere((message) => message.isMine);
  }

  Future<void> verifyBob() async {
    for (final pin in await alice.pins.pinsForUser('user-bob')) {
      await alice.trust.markVerified(pin.userId, pin.deviceId, pin.identityKey);
    }
    await waitFor(() => alice.verifiedAccounts.isVerified('user-bob'), reason: 'bob was not verified');
  }

  test('a flagged message gets one line with one reason, and a verified sender\'s at most a mild one', () async {
    final code = await fromBob('인증번호 알려줘');
    final story = await fromBob('엄마 나야 폰 고장나서 새 계정이야 인증번호 알려줘');
    final plain = await fromBob('see you at the station at 6');
    final own = await fromAlice('인증번호 알려줘');
    watch();
    await waitFor(() => safety.riskOf(code).level != RiskLevel.none, reason: 'the code ask was not flagged');

    // A stranger: one level and one reason each, the strongest pattern's.
    expect(safety.riskOf(code), const MessageRisk(level: RiskLevel.strong, reason: RiskReason.asksForCode));
    expect(safety.riskOf(story), const MessageRisk(level: RiskLevel.strong, reason: RiskReason.newPhoneClaim),
        reason: 'a new phone, family and a code ask: the one line names the new phone');
    expect(safety.riskOf(plain), MessageRisk.none);
    expect(safety.riskOf(own), MessageRisk.none, reason: 'never on the user\'s own message');

    // Verified now: every line of bob's, old ones too, is mild at most.
    await verifyBob();
    await waitFor(() => safety.riskOf(code).level == RiskLevel.mild, reason: 'the verified sender\'s line stayed strong');
    expect(safety.riskOf(code), const MessageRisk(level: RiskLevel.mild, reason: RiskReason.asksForCode));
    for (final message in [code, story, plain]) {
      expect(safety.riskOf(message).level.index, lessThanOrEqualTo(RiskLevel.mild.index), reason: '${safety.riskOf(message)}');
    }
    expect(safety.riskOf(story).reason, isNot(RiskReason.newPhoneClaim), reason: 'a verified sender claims nothing');
    expect(safety.linksOpenAtOnce(code), isTrue, reason: 'a verified sender\'s links open without a sheet');
  });

  test('a line keeps the relationship of the time the message was sent', () async {
    // Bob, new, asks for money: warn.
    final first = await fromBob('돈 좀 보내줘');
    watch();
    await waitFor(() => safety.riskOf(first).level != RiskLevel.none, reason: 'the first ask was not flagged');
    expect(safety.riskOf(first), const MessageRisk(level: RiskLevel.warn, reason: RiskReason.asksForMoney));
    expect(safety.linksOpenAtOnce(first), isFalse, reason: 'a stranger\'s links ask first');

    // Alice answers, so the chat is accepted with a text she sent, half a
    // second less than a week before bob's first message by the trust
    // layer's clock: bob is known from then on, which that message was not.
    now = first.sentAt.subtract(const Duration(days: 7)).add(const Duration(milliseconds: 500));
    await fromAlice('who is this?');
    final second = await fromBob('돈 좀 보내줘');
    expect(second.sentAt.isAfter(first.sentAt), isTrue);
    await waitFor(() => safety.riskOf(second) == MessageRisk.none && safety.riskOf(first).level != RiskLevel.none,
        reason: 'the second ask, from someone known, was flagged');
    expect(safety.riskOf(first), const MessageRisk(level: RiskLevel.warn, reason: RiskReason.asksForMoney),
        reason: 'the first ask keeps the line bob had when he sent it');

    // Time passing changes neither.
    now = second.sentAt.add(const Duration(days: 30));
    await fromAlice('ok');
    await safety.settled;
    expect(safety.riskOf(first), const MessageRisk(level: RiskLevel.warn, reason: RiskReason.asksForMoney));
    expect(safety.riskOf(second), MessageRisk.none);
  });
}
