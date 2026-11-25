import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/domain/chat_message.dart';
import 'package:veil_mobile/src/core/safety/message_risk.dart';
import 'package:veil_mobile/src/core/safety/rule_risk_checker.dart';
import 'package:veil_mobile/src/features/chat/application/message_safety.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';
import 'trust_support.dart';

// What the trust layer records can only add to a line a message already
// had, never take it away after the fact: a reply sent after a stranger's
// ask, or the stranger's handle typed in New chat, is no reason to read the
// ask as a known sender's or as one in a chat the user started. On real
// messengers over the fake relay; the relay stamps messages on its own
// clock (April 1) and the trust layer's clock is moved around those stamps.

void main() {
  late FakeRelay relay;
  late MessengerParty alice;
  late DateTime now;
  MessageSafety? safety;

  setUp(() async {
    relay = trustRelay();
    now = DateTime.utc(2026, 11, 2, 9);
    alice = await phone(relay, 'alice', requests: true);
    alice.clock = () => now;
    await alice.signIn();
    await trustReady(alice);
  });

  tearDown(() async {
    safety?.dispose();
    safety = null;
    await alice.dispose();
  });

  MessageSafety watch(String conversationId) => safety =
      MessageSafety(conversationId: conversationId, messenger: alice.controller, trust: alice.contactTrust, checker: const RuleRiskChecker());

  Future<ChatMessage> from(MessengerParty sender, String conversationId, String body) async {
    await deliver(sender, alice, conversationId, body);
    final messages = alice.controller.messagesFor(conversationId);
    final bodies = await Future.wait(messages.map(alice.controller.decryptMessage));
    return messages[bodies.lastIndexWhere((message) => message.body == body)];
  }

  Future<void> rereadAfterRestart(String conversationId, ChatMessage message) async {
    safety?.dispose();
    safety = null;
    await alice.restart();
    await trustReady(alice);
    final watching = watch(conversationId);
    await waitFor(() => watching.riskOf(message).level != RiskLevel.none, reason: 'no line after the restart');
    await watching.settled;
  }

  test('a reply sent after a stranger\'s ask does not take the ask\'s line away, after a restart too', () async {
    final bob = await phone(relay, 'bob');
    addTearDown(bob.dispose);
    await bob.signIn();
    const chat = 'conv-bob';
    relay.addDirect(chat, 'bob', 'alice');
    final hi = await from(bob, chat, 'hi');

    // Accepted eight days before the ask, and nothing sent.
    now = hi.sentAt.subtract(const Duration(days: 8));
    await alice.contactTrust.accept(chat);
    final ask = await from(bob, chat, 'Hi mum, this is my new number. Can you send me 300 for the bill?');
    now = ask.sentAt.add(const Duration(minutes: 2));
    final watching = watch(chat);
    await waitFor(() => watching.riskOf(ask).level != RiskLevel.none, reason: 'the ask was not flagged');
    await watching.settled;
    const line = MessageRisk(level: RiskLevel.strong, reason: RiskReason.newPhoneClaim);
    expect(watching.riskOf(ask), line);

    // Alice answers two minutes after the ask: bob is known from her reply
    // on, which the ask was sent before.
    await deliver(alice, bob, chat, 'who is this?');
    expect((await storedTrust(alice))!.chats[chat]!.sent, now.millisecondsSinceEpoch);
    await settle();
    await watching.settled;
    expect(watching.riskOf(ask), line, reason: 'the reply made the earlier ask a known sender\'s');

    await rereadAfterRestart(chat, ask);
    expect(safety!.riskOf(ask), line, reason: 'the line went after a restart');
  });

  test('typing the handle of a stranger who wrote first accepts the chat but does not make it one I started', () async {
    final mom = await phone(relay, 'mom_new');
    addTearDown(mom.dispose);
    await mom.signIn();
    const chat = 'conv-mom';
    relay.addDirect(chat, 'mom_new', 'alice');
    final claim = await from(mom, chat, '엄마 나야 폰 고장나서 새 계정이야');
    final watching = watch(chat);
    await waitFor(() => watching.riskOf(claim).level != RiskLevel.none, reason: 'the claim was not flagged');
    const line = MessageRisk(level: RiskLevel.strong, reason: RiskReason.newPhoneClaim);
    expect(watching.riskOf(claim), line);
    expect(alice.contactTrust.isRequest(chat), isTrue);

    // The handle in the request header, typed in New chat: the relay hands
    // back the chat that exists.
    final started = await alice.contactTrust.startDirect('mom_new');
    expect(started, chat);
    expect(alice.contactTrust.isRequest(chat), isFalse, reason: 'starting the chat accepts it');
    expect(alice.contactTrust.startedByMe(chat), isFalse, reason: 'a chat the stranger wrote first in counts as mine');
    await settle();
    await watching.settled;
    expect(watching.riskOf(claim), line, reason: 'the family claim line went');
    expect((await storedTrust(alice))!.chats[chat]!.typed, isFalse);

    await rereadAfterRestart(chat, claim);
    expect(alice.contactTrust.startedByMe(chat), isFalse);
    expect(alice.contactTrust.isRequest(chat), isFalse);
    expect(safety!.riskOf(claim), line);
  });

  test('typing a new handle still makes the chat one I started', () async {
    final dave = await phone(relay, 'dave');
    addTearDown(dave.dispose);
    await dave.signIn();
    final started = await alice.contactTrust.startDirect('dave');
    expect(started, isNotNull);
    expect(alice.contactTrust.startedByMe(started!), isTrue);
    expect((await storedTrust(alice))!.chats[started]!.typed, isTrue);
  });
}
