import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/safety/handle_lookalike.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';
import 'trust_support.dart';

// Which accounts a stranger's handle is compared with (ContactTrust
// .anchorsFor), and which groups the phone already trusts enough not to
// hold as requests, on real messengers over the fake relay with the trust
// layer's clock moved by hand.

void main() {
  late FakeRelay relay;
  late MessengerParty alice;
  late DateTime now;

  setUp(() async {
    relay = trustRelay();
    now = DateTime.utc(2026, 11, 2, 9);
    alice = await phone(relay, 'alice', requests: true);
    alice.clock = () => now;
  });

  tearDown(() async {
    await alice.dispose();
  });

  Future<List<MessengerParty>> phones(List<String> handles) async {
    final parties = [for (final handle in handles) await phone(relay, handle)];
    for (final party in parties) {
      addTearDown(party.dispose);
    }
    for (final party in [alice, ...parties]) {
      await party.signIn();
    }
    await trustReady(alice);
    return parties;
  }

  Future<void> verify(String userId) async {
    for (final pin in await alice.pins.pinsForUser(userId)) {
      await alice.trust.markVerified(pin.userId, pin.deviceId, pin.identityKey);
    }
    await waitFor(() => alice.verifiedAccounts.isVerified(userId), reason: '$userId was not verified');
  }

  List<LookalikeAnchor> anchorsIn(String conversationId) =>
      alice.contactTrust.anchorsFor(alice.controller.conversationById(conversationId)!).toList();

  test('a contact verified only from a group\'s member page is compared with a look-alike stranger', () async {
    final [bob, carol, b0b] = await phones(['bob', 'carol', 'b0b']);
    relay.addGroup('grp', ['carol', 'alice', 'bob'], name: 'Climbing');
    await alice.controller.refreshConversations();
    await bob.controller.refreshConversations();
    await carol.controller.refreshConversations();
    await deliver(bob, alice, 'grp', 'see you at the wall at 7');
    // What the group member's Safety number page does. Alice has no 1:1 with
    // bob and no nickname for him.
    await verify('user-bob');
    expect(alice.controller.boundPeers.values.where((peer) => peer.userId == 'user-bob'), isEmpty);

    relay.addDirect('conv-b0b', 'b0b', 'alice');
    await deliver(b0b, alice, 'conv-b0b', 'hey, it is bob, new account');
    final anchors = anchorsIn('conv-b0b');
    expect(anchors, [(userId: 'user-bob', handle: 'bob', name: null, verified: true)]);
    expect(findLookalike('b0b', null, anchors, peerUserId: 'user-b0b'), isNotNull,
        reason: 'the look-alike of a contact verified in a group got no banner');
  });

  test('a contact saved under a nickname is compared with look-alikes only once the nickname is a week old', () async {
    final [_, car0l] = await phones(['carol', 'car0l']);
    final saved = now;
    await alice.saveNickname('carol', 'Carol', userId: 'user-carol');
    await settle();
    relay.addDirect('conv-car0l', 'car0l', 'alice');
    await deliver(car0l, alice, 'conv-car0l', 'hi, it is carol on my new phone');

    now = saved.add(const Duration(days: 6));
    expect(anchorsIn('conv-car0l'), isEmpty, reason: 'a nickname six days old made an anchor');
    now = saved.add(const Duration(days: 8));
    final anchors = anchorsIn('conv-car0l');
    expect(anchors, [(userId: 'user-carol', handle: 'carol', name: 'Carol', verified: false)]);
    expect(findLookalike('car0l', null, anchors, peerUserId: 'user-car0l'), isNotNull);
  });

  test('a group whose only other member is verified, or known through my own 1:1, is not a request', () async {
    final [bob, dave, erin] = await phones(['bob', 'dave', 'erin']);
    final t0 = now;

    // bob, whom alice verified.
    relay.addDirect('conv-bob', 'bob', 'alice');
    await deliver(bob, alice, 'conv-bob', 'hi alice');
    await verify('user-bob');
    // dave, in a 1:1 alice accepted and wrote in eight days ago.
    relay.addDirect('conv-dave', 'dave', 'alice');
    await deliver(dave, alice, 'conv-dave', 'hi alice, dave here');
    await deliver(alice, dave, 'conv-dave', 'hi dave');
    now = t0.add(const Duration(days: 8));

    relay.addGroup('grp-bob', ['bob', 'alice'], useSenderKeys: false, name: 'Bob and Alice');
    relay.addGroup('grp-dave', ['dave', 'alice'], useSenderKeys: false, name: 'Dave and Alice');
    relay.addGroup('grp-erin', ['erin', 'alice'], useSenderKeys: false, name: 'Erin and Alice');
    await alice.controller.refreshConversations();
    await waitFor(() => alice.controller.conversationById('grp-erin') != null, reason: 'the groups were not listed');
    expect(alice.contactTrust.isRequest('grp-bob'), isFalse, reason: 'its other member is verified');
    expect(alice.contactTrust.isRequest('grp-dave'), isFalse, reason: 'its other member is known through a 1:1');
    expect(alice.contactTrust.isRequest('grp-erin'), isTrue, reason: 'a stranger\'s group of two');
    await erin.controller.refreshConversations();
  });
}
