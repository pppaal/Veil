import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';

// A key check reads a key (the directory's answer for a contact) and only
// then asks the pins. A pinned key presented again withdraws a change
// pending for that device, which is right for an answer read after the
// change and wrong for one read before it: an answer that was on its way
// while bob's device presented another key says nothing about that key.
// If it cleared the change, "Safety number changed" would vanish without
// the user ever seeing it.

void main() {
  const conversationId = 'conv-alice-bob';
  late FakeRelay relay;
  late MessengerParty alice;
  late MessengerParty bob;

  setUp(() async {
    relay = FakeRelay();
    alice = await MessengerParty.join(relay, handle: 'alice', userId: 'user-alice', deviceId: 'dev-alice');
    bob = await MessengerParty.join(relay, handle: 'bob', userId: 'user-bob', deviceId: 'dev-bob');
    relay.addDirect(conversationId, 'alice', 'bob');
    await alice.signIn();
    await bob.signIn();
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
  });

  Future<void> deliver(MessengerParty from, MessengerParty to, String body) async {
    await from.controller.sendText(conversationId: conversationId, body: body);
    await waitFor(() => from.controller.pendingCountFor(conversationId) == 0, reason: '"$body" was not acked');
    await waitFor(() async => (await to.bodies(conversationId)).contains(body), reason: '"$body" did not arrive');
  }

  test('a key check that read the directory before a newer identity change does not clear that change', () async {
    await deliver(alice, bob, 'hi bob');
    await deliver(bob, alice, 'hi alice');
    final pinned = bob.device.identity.identityPublicKey;
    expect(await alice.trust.trusts('user-bob', 'dev-bob', pinned), isTrue);

    // Alice renews the session; the directory works out bob's answer (the
    // pinned key) and the network holds it.
    final gate = relay.clientFor('alice').directoryGate = Completer<void>();
    final lookups = relay.clientFor('alice').directoryLookups['bob'] ?? 0;
    final renewal = alice.controller.renewSession(conversationId);
    await waitFor(() => (relay.clientFor('alice').directoryLookups['bob'] ?? 0) > lookups,
        reason: 'the directory was not asked');

    // Meanwhile bob's device presents another key: held for review.
    final otherKey = alice.device.identity.identityPublicKey;
    expect(await alice.trust.admit(conversationId, 'user-bob', 'dev-bob', otherKey), isFalse);
    final change = alice.controller.pendingIdentityChangeFor(conversationId);
    expect(change, isNotNull);

    // The older answer lands. It may still use the pinned key, but the
    // change raised after it was read stays for the user to review.
    relay.clientFor('alice').directoryGate = null;
    gate.complete();
    await renewal;
    expect(alice.controller.pendingIdentityChangeFor(conversationId)?.presentedKey, change!.presentedKey,
        reason: 'a late answer to an older question withdrew the change');

    // An answer read after the change, still with the pinned key, withdraws
    // it as before: the directory and the pins agree again.
    await alice.controller.renewSession(conversationId);
    expect(alice.controller.pendingIdentityChangeFor(conversationId), isNull);
  });
}
