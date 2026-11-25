import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/safety/application/relationship.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';
import 'trust_support.dart';

// Who an account is to this phone (ContactTrust.relationshipAt), on real
// messengers over the fake relay, with the trust layer's clock moved by
// hand: none of these classes can be had in the minutes a scam takes.

void main() {
  late FakeRelay relay;
  late MessengerParty alice;
  late MessengerParty bob;
  late DateTime now;

  setUp(() async {
    relay = trustRelay();
    now = DateTime.utc(2026, 11, 2, 9);
    alice = await phone(relay, 'alice', requests: true);
    alice.clock = () => now;
    bob = await phone(relay, 'bob');
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
  });

  Relationship of(String handle, String conversationId, DateTime at) => alice.contactTrust.relationshipAt(
        'user-$handle',
        handle,
        chat: alice.controller.conversationById(conversationId)!,
        at: at,
      );

  Future<void> verify(String userId) async {
    for (final pin in await alice.pins.pinsForUser(userId)) {
      await alice.trust.markVerified(pin.userId, pin.deviceId, pin.identityKey);
    }
    await waitFor(() => alice.verifiedAccounts.isVerified(userId), reason: '$userId was not verified');
  }

  test('an account is changed, verified, saved, known or new in that order, and known needs a week since accept and a message I sent', () async {
    await alice.signIn();
    await bob.signIn();
    await trustReady(alice);
    relay.addDirect('conv-bob', 'bob', 'alice');
    await deliver(bob, alice, 'conv-bob', 'hi, it is bob');
    final t0 = now;
    expect(of('bob', 'conv-bob', t0), Relationship.newContact);

    // Accepting is not knowing: a week later, with nothing sent, still new.
    await alice.contactTrust.accept('conv-bob');
    expect(of('bob', 'conv-bob', t0.add(const Duration(days: 8))), Relationship.newContact);

    // A text this phone sent, and a week since the accept.
    now = t0.add(const Duration(hours: 1));
    await deliver(alice, bob, 'conv-bob', 'hi bob');
    expect(of('bob', 'conv-bob', t0.add(const Duration(days: 6))), Relationship.newContact);
    expect(of('bob', 'conv-bob', t0.add(const Duration(days: 7, minutes: 1))), Relationship.known);

    // A nickname, a week old, comes before known.
    await alice.saveNickname('bob', 'Bob', userId: 'user-bob');
    await settle();
    expect(of('bob', 'conv-bob', t0.add(const Duration(days: 7, minutes: 1))), Relationship.known);
    expect(of('bob', 'conv-bob', t0.add(const Duration(days: 8))), Relationship.saved);

    // Verified comes before saved, and holds from now on.
    await verify('user-bob');
    expect(of('bob', 'conv-bob', t0.add(const Duration(days: 8))), Relationship.verified);
    expect(of('bob', 'conv-bob', t0), Relationship.verified);

    // An identity change comes before everything: bob's new phone, which a
    // verified contact's new device is held for review.
    final newPhone = await MessengerParty.join(relay, handle: 'bob', userId: 'user-bob', deviceId: 'dev-bob-2');
    addTearDown(newPhone.dispose);
    await newPhone.signIn();
    await newPhone.controller.refreshConversations();
    await newPhone.controller.sendText(conversationId: 'conv-bob', body: 'new phone, same bob');
    await waitFor(() => newPhone.controller.pendingCountFor('conv-bob') == 0, reason: 'the new phone did not send');
    await waitFor(() async {
      await alice.bodies('conv-bob');
      return alice.controller.pendingIdentityChangeAbout('user-bob') != null;
    }, reason: 'the new device was not held');
    expect(of('bob', 'conv-bob', t0.add(const Duration(days: 8))), Relationship.changed);
  });

  test('a nickname counts as saved only after a week, and one saved before the first message marks the chat as started by me', () async {
    final carol = await phone(relay, 'carol');
    final dave = await phone(relay, 'dave');
    addTearDown(carol.dispose);
    addTearDown(dave.dispose);
    for (final party in [alice, carol, dave]) {
      await party.signIn();
    }
    await trustReady(alice);

    // Saved before carol's account ever wrote: as if alice had typed it.
    final t0 = now;
    await alice.saveNickname('carol', 'Mum', userId: 'user-carol');
    await settle();
    now = t0.add(const Duration(hours: 1));
    relay.addDirect('conv-carol', 'carol', 'alice');
    await deliver(carol, alice, 'conv-carol', 'hi love');
    expect(alice.contactTrust.startedByMe('conv-carol'), isTrue);
    expect(alice.contactTrust.isRequest('conv-carol'), isFalse);
    expect(of('carol', 'conv-carol', t0.add(const Duration(days: 1))), Relationship.newContact,
        reason: 'a nickname under a week old counted as saved');
    expect(of('carol', 'conv-carol', t0.add(const Duration(days: 7))), Relationship.saved);

    // Saved after dave's chat appeared: not started by me, still a request;
    // saved only a week after the nickname.
    now = t0.add(const Duration(hours: 2));
    relay.addDirect('conv-dave', 'dave', 'alice');
    await deliver(dave, alice, 'conv-dave', 'hi mum, new number');
    final named = now = t0.add(const Duration(hours: 3));
    await alice.saveNickname('dave', 'Mum 2', userId: 'user-dave');
    await settle();
    expect(alice.contactTrust.startedByMe('conv-dave'), isFalse);
    expect(alice.contactTrust.isRequest('conv-dave'), isTrue);
    expect(of('dave', 'conv-dave', named.add(const Duration(days: 6))), Relationship.newContact);
    expect(of('dave', 'conv-dave', named.add(const Duration(days: 7))), Relationship.saved);
  });

  test('a group member is known only through my own chat with them, a group I created, or a week after accept', () async {
    final dave = await phone(relay, 'dave');
    addTearDown(dave.dispose);
    relay.addDirect('conv-bob', 'alice', 'bob');
    for (final party in [alice, bob, dave]) {
      await party.signIn();
    }
    await trustReady(alice);
    // bob's 1:1 was on the phone before (the baseline) and alice writes in it.
    await deliver(alice, bob, 'conv-bob', 'see you saturday');
    final t0 = now;

    // dave, a stranger, puts alice in a group with bob.
    relay.addGroup('grp-dave', ['dave', 'alice', 'bob'], useSenderKeys: false, name: 'Saturday');
    await alice.controller.refreshConversations();
    final group = alice.controller.conversationById('grp-dave');
    expect(group, isNotNull);
    expect(group!.type, ConversationType.group);
    expect(alice.contactTrust.isRequest('grp-dave'), isTrue, reason: 'a stranger\'s group is a request');
    expect(of('bob', 'grp-dave', t0), Relationship.known, reason: 'bob is known through alice\'s own 1:1');
    expect(of('dave', 'grp-dave', t0), Relationship.newContact);

    // Accepting the group makes dave known there only a week later.
    await alice.contactTrust.accept('grp-dave');
    expect(of('dave', 'grp-dave', t0.add(const Duration(days: 6))), Relationship.newContact);
    expect(of('dave', 'grp-dave', t0.add(const Duration(days: 8))), Relationship.known);

    // In a group alice created, at once.
    final mine = await alice.controller.createGroup(name: 'Mine', memberHandles: ['dave']);
    await alice.contactTrust.acceptCreated(mine!);
    expect(of('dave', mine, t0), Relationship.known);
  });
}
