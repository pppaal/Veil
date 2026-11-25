import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/domain/chat_message.dart';
import 'package:veil_mobile/src/core/domain/conversation_preview.dart';
import 'package:veil_mobile/src/core/safety/message_risk.dart';
import 'package:veil_mobile/src/core/safety/rule_risk_checker.dart';
import 'package:veil_mobile/src/features/chat/application/message_safety.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';
import 'trust_support.dart';

// The risk line each message gets (MessageSafety), on real messengers over
// the fake relay: alice's phone keeps message requests and reads what bob,
// a stranger, sends. The relay stamps messages on its own clock; the trust
// layer's clock is moved by hand around those stamps.

// Alice's messenger, whose read of the members' pinned devices fails while
// [failing], as a keystore that cannot be reached does.
class _PinsFailing implements VeilMessengerController {
  _PinsFailing(this._inner);

  final VeilMessengerController _inner;
  bool failing = true;
  int failed = 0;

  @override
  Future<Map<String, String>> pinnedDeviceOwners(Iterable<String> userIds) async {
    if (failing) {
      failed++;
      throw StateError('keystore unavailable');
    }
    return _inner.pinnedDeviceOwners(userIds);
  }

  @override
  void addListener(VoidCallback listener) => _inner.addListener(listener);

  @override
  void removeListener(VoidCallback listener) => _inner.removeListener(listener);

  @override
  ConversationPreview? conversationById(String conversationId) => _inner.conversationById(conversationId);

  @override
  List<ChatMessage> messagesFor(String conversationId) => _inner.messagesFor(conversationId);

  @override
  Future<DecryptedMessage> decryptMessage(ChatMessage message) => _inner.decryptMessage(message);

  @override
  String? get localUserId => _inner.localUserId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  // A Sender Keys frame opens only once its chain key is picked up, and
  // that is when this phone pins the sender's device. Bob is known in the
  // family group (alice accepted it well before he wrote), so his code ask
  // reads as a known sender's, not a stranger's, as soon as it opens.
  test('a group member whose device is named only once their message opens is not read as a stranger', () async {
    const group = 'grp-family';
    final carol = await phone(relay, 'carol');
    addTearDown(carol.dispose);
    await carol.signIn();
    relay.addGroup(group, ['bob', 'alice', 'carol'], name: 'Family');
    await alice.controller.refreshConversations();
    await bob.controller.refreshConversations();
    final latest = now;
    now = DateTime.utc(2026, 3, 1);
    await alice.contactTrust.accept(group);
    now = latest;
    expect(await alice.controller.pinnedDeviceOwners(['user-bob']), isEmpty, reason: 'alice never talked to bob');

    // Bob's frame reaches alice while his chain key cannot be picked up.
    alice.api.failGroupKeyPickups = true;
    await bob.controller.sendText(conversationId: group, body: '인증번호 알려줘');
    await waitFor(() => bob.controller.pendingCountFor(group) == 0, reason: 'bob\'s text was not acked');
    await alice.controller.loadConversationMessages(group);
    await waitFor(() => alice.controller.messagesFor(group).any((message) => !message.isMine),
        reason: 'bob\'s text did not arrive');
    final code = alice.controller.messagesFor(group).firstWhere((message) => !message.isMine);
    expect((await alice.controller.decryptMessage(code)).status, DecryptStatus.awaitingKey);
    safety = MessageSafety(
        conversationId: group, messenger: alice.controller, trust: alice.contactTrust, checker: const RuleRiskChecker());
    await safety.settled;
    expect(safety.riskOf(code), MessageRisk.none, reason: 'nothing to read yet');

    // The key comes: the frame opens and bob's device is pinned. His line is
    // a known sender's (warn), not a stranger's (strong), while the chat
    // stays open.
    alice.api.failGroupKeyPickups = false;
    alice.controller.onGroupKeysChanged(group);
    await waitFor(() async => (await alice.controller.decryptMessage(code)).status == DecryptStatus.ok,
        reason: 'bob\'s text did not open');
    expect(await alice.controller.pinnedDeviceOwners(['user-bob']), {'dev-bob': 'user-bob'});
    await waitFor(() => safety.riskOf(code).level != RiskLevel.none, reason: 'the opened text got no line');
    await safety.settled;
    expect(safety.riskOf(code), const MessageRisk(level: RiskLevel.warn, reason: RiskReason.asksForCode),
        reason: 'read as a stranger\'s');
  });

  // The read of the members' pinned devices can fail. A failed read is not
  // a read: the next run, on any change, asks again, so a known member's
  // text is not left read as a stranger's for as long as the chat is open.
  test('a failed read of a group\'s pinned devices is tried again on the next change', () async {
    const group = 'grp-family';
    final carol = await phone(relay, 'carol');
    addTearDown(carol.dispose);
    await carol.signIn();
    relay.addGroup(group, ['bob', 'alice', 'carol'], name: 'Family');
    await alice.controller.refreshConversations();
    await bob.controller.refreshConversations();
    final latest = now;
    now = DateTime.utc(2026, 3, 1);
    await alice.contactTrust.accept(group);
    now = latest;
    await bob.controller.sendText(conversationId: group, body: '인증번호 알려줘');
    await waitFor(() => bob.controller.pendingCountFor(group) == 0, reason: 'bob\'s text was not acked');
    await alice.controller.loadConversationMessages(group);
    await waitFor(() => alice.controller.messagesFor(group).any((message) => !message.isMine),
        reason: 'bob\'s text did not arrive');
    final code = alice.controller.messagesFor(group).firstWhere((message) => !message.isMine);
    await waitFor(() async => (await alice.controller.decryptMessage(code)).status == DecryptStatus.ok,
        reason: 'bob\'s text did not open');
    expect(await alice.controller.pinnedDeviceOwners(['user-bob']), {'dev-bob': 'user-bob'});

    final messenger = _PinsFailing(alice.controller);
    safety = MessageSafety(conversationId: group, messenger: messenger, trust: alice.contactTrust, checker: const RuleRiskChecker());
    await safety.settled;
    expect(messenger.failed, greaterThanOrEqualTo(1));
    expect(safety.riskOf(code), const MessageRisk(level: RiskLevel.strong, reason: RiskReason.asksForCode),
        reason: 'no member is known for bob\'s device while the pins cannot be read');

    // The pins can be read again; alice writes in the group, and the run
    // that follows reads them.
    messenger.failing = false;
    await alice.controller.sendText(conversationId: group, body: 'which code?');
    await waitFor(() => safety.riskOf(code).level == RiskLevel.warn, reason: 'the pins were not read again');
    await safety.settled;
    expect(safety.riskOf(code), const MessageRisk(level: RiskLevel.warn, reason: RiskReason.asksForCode));
  });
}
