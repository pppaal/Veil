import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';

// Unread counts between two real phones (real ratchets, the encrypted
// cache, the fake relay): bob's count for what alice sent while he was
// elsewhere, and what alice sees when he opens the chat, which depends on
// bob's read receipts setting. Each phone's first list read what was there
// (a new install), so only what comes after it counts.

const conv = 'conv-ab';

void main() {
  late FakeRelay relay;
  late MessengerParty alice;
  late MessengerParty bob;

  setUp(() async {
    relay = FakeRelay();
    alice = await MessengerParty.join(relay, handle: 'alice', userId: 'user-alice', deviceId: 'dev-alice');
    bob = await MessengerParty.join(relay, handle: 'bob', userId: 'user-bob', deviceId: 'dev-bob');
    relay.addDirect(conv, 'alice', 'bob');
    await alice.signIn();
    await bob.signIn();
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
  });

  Future<void> sendThree() async {
    for (final body in ['are you home?', 'I have your keys', 'call me']) {
      await alice.controller.sendText(conversationId: conv, body: body);
    }
    await waitFor(() => alice.controller.pendingCountFor(conv) == 0, reason: 'alice\'s lines were not acked');
    await waitFor(() => bob.controller.messagesFor(conv).length == 3, reason: 'bob did not get the three lines');
    await waitFor(() async => (await bob.bodies(conv)).every((body) => body.isNotEmpty), reason: 'did not open');
  }

  ChatMessage alicesNewest() => alice.controller.messagesFor(conv).last;

  test('three lines while bob is elsewhere count 3; opening reads them, and alice sees the newest read', () async {
    await sendThree();
    expect(bob.controller.reads.unreadCount(conv), 3);
    expect(bob.notifications.shownForConversations, hasLength(3));

    bob.controller.setActiveConversation(conv);
    await waitFor(() => bob.api.markReadCalls.length == 1, reason: 'opening sent no receipt');
    expect(bob.controller.reads.unreadCount(conv), 0);
    await waitFor(() => alicesNewest().deliveryState == MessageDeliveryState.read,
        reason: 'alice does not see her newest line read');
    await settle();
    expect(bob.api.markReadCalls, hasLength(1), reason: 'one receipt for the three');
    expect(bob.notifications.cancelledForConversations, contains(conv));
  });

  test('with bob\'s receipts off, opening reads them on his phone and alice never sees them read', () async {
    bob.readReceipts = false;
    await sendThree();
    expect(bob.controller.reads.unreadCount(conv), 3);

    bob.controller.setActiveConversation(conv);
    await settle(const Duration(milliseconds: 500));
    expect(bob.controller.reads.unreadCount(conv), 0);
    expect(bob.api.markReadCalls, isEmpty);
    expect(alicesNewest().deliveryState, isNot(MessageDeliveryState.read));
  });

  test('bob\'s counts and marks come back after a restart', () async {
    await sendThree();
    bob.controller.setActiveConversation(conv);
    await waitFor(() => bob.controller.reads.unreadCount(conv) == 0);
    bob.controller.setActiveConversation(null);
    await alice.controller.sendText(conversationId: conv, body: 'one more');
    await waitFor(() => bob.controller.reads.unreadCount(conv) == 1);
    await bob.controller.flushPendingWrites();

    await bob.restart();
    await waitFor(() => bob.controller.messagesFor(conv).length == 4, reason: 'the history did not come back');
    expect(bob.controller.reads.unreadCount(conv), 1, reason: 'the read mark came back from the cache');
  });
}
