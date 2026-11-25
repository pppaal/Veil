import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/safety/application/relationship.dart';
import 'package:veil_mobile/src/features/safety/data/contact_trust_store.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/messenger_party.dart';
import 'trust_support.dart';

// Which chats are message requests (ContactTrust), on real messengers over
// the fake relay: what the baseline accepts, what accepts a chat for good
// and what does not, and how the trust document is kept.

void main() {
  late FakeRelay relay;
  late MessengerParty alice;
  late MessengerParty bob;
  late MessengerParty carol;

  setUp(() async {
    relay = trustRelay();
    alice = await phone(relay, 'alice', requests: true);
    bob = await phone(relay, 'bob');
    carol = await phone(relay, 'carol');
    relay.addDirect('conv-bob', 'alice', 'bob');
  });

  tearDown(() async {
    await alice.dispose();
    await bob.dispose();
    await carol.dispose();
  });

  test('chats on the phone before the update are accepted, a new stranger\'s chat is a request', () async {
    // Before the document is read nothing is a request, but nothing that
    // tells the other side what was read or typed may go yet.
    expect(alice.contactTrust.isRequest('conv-bob'), isFalse);
    expect(alice.contactTrust.withholds('conv-bob'), isTrue);

    await alice.signIn();
    await bob.signIn();
    await carol.signIn();
    await trustReady(alice);
    expect(alice.contactTrust.isRequest('conv-bob'), isFalse, reason: 'a chat listed at the baseline is accepted');
    expect(alice.contactTrust.withholds('conv-bob'), isFalse);

    relay.addDirect('conv-carol', 'carol', 'alice');
    await deliver(carol, alice, 'conv-carol', 'hi, is this alice?');
    expect(alice.contactTrust.isRequest('conv-carol'), isTrue, reason: 'a stranger\'s chat after the baseline');
    expect(alice.contactTrust.withholds('conv-carol'), isTrue);
    // A chat this phone has no record of yet (a notification before the
    // list) is a request too.
    expect(alice.contactTrust.isRequest('conv-not-listed-yet'), isTrue);

    // Kept across a restart.
    await alice.restart();
    await trustReady(alice);
    expect(alice.contactTrust.isRequest('conv-bob'), isFalse);
    expect(alice.contactTrust.isRequest('conv-carol'), isTrue);
  });

  test('starting a chat, creating a group, verifying or sending a message accepts it for good', () async {
    final dave = await phone(relay, 'dave');
    final erin = await phone(relay, 'erin');
    addTearDown(dave.dispose);
    addTearDown(erin.dispose);
    for (final party in [alice, bob, carol, dave, erin]) {
      await party.signIn();
    }
    await trustReady(alice);

    // Started from a handle the user typed.
    final started = await alice.contactTrust.startDirect('dave');
    expect(started, isNotNull);
    expect(alice.contactTrust.isRequest(started!), isFalse);
    expect(alice.contactTrust.startedByMe(started), isTrue);

    // The group createGroup returned.
    final group = await alice.controller.createGroup(name: 'Trip', memberHandles: ['carol', 'erin']);
    expect(group, isNotNull, reason: 'createGroup returns the id the relay gave');
    await alice.contactTrust.acceptCreated(group!);
    expect(alice.contactTrust.isRequest(group), isFalse);

    // A text sent in a stranger's chat.
    relay.addDirect('conv-carol', 'carol', 'alice');
    await deliver(carol, alice, 'conv-carol', 'hello from carol');
    expect(alice.contactTrust.isRequest('conv-carol'), isTrue);
    await deliver(alice, carol, 'conv-carol', 'hi carol');
    expect(alice.contactTrust.isRequest('conv-carol'), isFalse);

    // A stranger the user then verifies.
    relay.addDirect('conv-erin', 'erin', 'alice');
    await deliver(erin, alice, 'conv-erin', 'hello from erin');
    expect(alice.contactTrust.isRequest('conv-erin'), isTrue);
    final pin = (await alice.pins.pinsForUser('user-erin')).single;
    await alice.trust.markVerified(pin.userId, pin.deviceId, pin.identityKey);
    await waitFor(() => !alice.contactTrust.isRequest('conv-erin'), reason: 'verifying the peer did not accept the chat');

    // For good: a restart reads every accept back.
    await alice.restart();
    await trustReady(alice);
    for (final id in [started, group, 'conv-carol', 'conv-erin']) {
      expect(alice.contactTrust.isRequest(id), isFalse, reason: '$id became a request again');
    }
    final stored = await storedTrust(alice);
    expect(stored!.chats[started]!.typed, isTrue);
    expect(stored.chats[group]!.created, isTrue);
    expect(stored.chats['conv-carol']!.sent, isNotNull);
  });

  test('a screenshot notice, a reaction or a nickname saved later does not accept a request', () async {
    for (final party in [alice, bob, carol]) {
      await party.signIn();
    }
    await trustReady(alice);
    relay.addDirect('conv-carol', 'carol', 'alice');
    await deliver(carol, alice, 'conv-carol', 'hello, remember me?');
    expect(alice.contactTrust.isRequest('conv-carol'), isTrue);

    // A line the app sends by itself.
    await alice.controller.sendSystemNotice(conversationId: 'conv-carol', body: 'screenshot');
    await waitFor(() => alice.controller.pendingCountFor('conv-carol') == 0, reason: 'the notice was not acked');
    expect(alice.contactTrust.isRequest('conv-carol'), isTrue, reason: 'a system notice accepted the chat');

    // A reaction.
    final theirs = alice.controller.messagesFor('conv-carol').firstWhere((message) => !message.isMine);
    await alice.controller.toggleReaction(theirs, '👍');
    await waitFor(() => alice.controller.pendingCountFor('conv-carol') == 0, reason: 'the reaction was not acked');
    expect(alice.contactTrust.isRequest('conv-carol'), isTrue, reason: 'a reaction accepted the chat');

    // A nickname saved after the chat appeared.
    await alice.saveNickname('carol', 'Mum', userId: 'user-carol');
    await settle();
    expect(alice.contactTrust.isRequest('conv-carol'), isTrue, reason: 'a nickname saved later accepted the chat');
    expect(alice.contactTrust.startedByMe('conv-carol'), isFalse);
    expect((await storedTrust(alice))!.chats['conv-carol']!.accepted, isNull);
  });

  test('a corrupt trust document counts as missing and the baseline runs again', () async {
    relay.addDirect('conv-carol', 'carol', 'alice');
    await alice.keystore.scoped(SecureScope.conversationPolicy).write(ContactTrustStore.documentKey, '{"v":1,"chats":[');
    await alice.signIn();
    await trustReady(alice);
    expect(alice.contactTrust.degraded, isFalse);
    expect(alice.contactTrust.isRequest('conv-bob'), isFalse);
    expect(alice.contactTrust.isRequest('conv-carol'), isFalse, reason: 'every listed chat is accepted again');
    final stored = await storedTrust(alice);
    expect(stored, isNotNull, reason: 'the document was written again');
    expect(stored!.baseline, isTrue);

    // After that baseline, a new chat is a request again.
    final dave = await phone(relay, 'dave');
    addTearDown(dave.dispose);
    await dave.signIn();
    relay.addDirect('conv-dave', 'dave', 'alice');
    await deliver(dave, alice, 'conv-dave', 'hi');
    expect(alice.contactTrust.isRequest('conv-dave'), isTrue);
  });

  test('a list without a chat keeps its record, so a chat that comes back is still accepted', () async {
    await alice.signIn();
    await trustReady(alice);
    expect(alice.contactTrust.isRequest('conv-bob'), isFalse);

    // One list leaves the chat out (a lying or broken relay).
    final kept = relay.conversations.remove('conv-bob')!;
    await alice.controller.refreshConversations();
    await waitFor(() => alice.controller.conversationById('conv-bob') == null, reason: 'the list still had the chat');
    await alice.contactTrust.flush();
    final gone = (await storedTrust(alice))!.chats['conv-bob'];
    expect(gone, isNotNull, reason: 'the record was dropped');
    expect(gone!.gone, isNotNull);
    expect(gone.accepted, isNotNull);

    // It comes back, after a restart too: still accepted.
    relay.conversations['conv-bob'] = kept;
    await alice.restart();
    await trustReady(alice);
    await waitFor(() => alice.controller.conversationById('conv-bob') != null, reason: 'the chat did not come back');
    expect(alice.contactTrust.isRequest('conv-bob'), isFalse);
    await alice.contactTrust.flush();
    expect((await storedTrust(alice))!.chats['conv-bob']!.gone, isNull);
  });

  test('a trust document that cannot be read is retried, then the app works as before', () async {
    var now = DateTime.utc(2026, 11, 20, 9);
    alice.clock = () => now;
    alice.failTrustReads = 4;
    relay.addDirect('conv-carol', 'carol', 'alice');
    await alice.signIn();
    await settle();
    expect(alice.failTrustReads, 3, reason: 'the first read was not made');
    expect(alice.contactTrust.degraded, isFalse);
    expect(alice.contactTrust.withholds('conv-bob'), isTrue, reason: 'receipts went before the document was read');

    // Not again before the wait is over.
    await alice.controller.refreshConversations();
    await settle();
    expect(alice.failTrustReads, 3);

    for (final (wait, left) in [(const Duration(seconds: 1), 2), (const Duration(seconds: 5), 1), (const Duration(seconds: 30), 0)]) {
      now = now.add(wait);
      await alice.controller.refreshConversations();
      await settle();
      expect(alice.failTrustReads, left, reason: 'no retry after $wait');
    }

    // The last retry failed: the app works as before message requests.
    expect(alice.contactTrust.degraded, isTrue);
    expect(alice.contactTrust.isRequest('conv-carol'), isFalse);
    expect(alice.contactTrust.withholds('conv-carol'), isFalse);
    expect(alice.contactTrust.withholds('conv-bob'), isFalse);
    expect(alice.trustLog, hasLength(1));
    expect(alice.trustLog.single, isNot(contains('conv-')));
    expect(alice.trustLog.single, isNot(contains('user-')));
    // Nothing is written over what the keystore may still hold.
    await alice.contactTrust.flush();
    expect(await alice.keystore.scoped(SecureScope.conversationPolicy).read(ContactTrustStore.documentKey), isNull);
  });

  test('a new device admitted while the trust document waits for a retry is recorded once it is read', () async {
    var now = DateTime.utc(2026, 11, 20, 9);
    alice.clock = () => now;
    await alice.signIn();
    await bob.signIn();
    await trustReady(alice);
    await deliver(bob, alice, 'conv-bob', 'hi from my phone');

    // The next start cannot read the document at first.
    alice.failTrustReads = 1;
    await alice.restart();
    await settle();
    expect(alice.failTrustReads, 0, reason: 'the first read was not made');
    expect(alice.contactTrust.ready, isFalse);

    // Meanwhile a device bob never had opens a message to alice: bob is
    // not verified, so it is admitted, and the trust layer hears of it once.
    final newPhone = await MessengerParty.join(relay, handle: 'bob', userId: 'user-bob', deviceId: 'dev-bob-2');
    addTearDown(newPhone.dispose);
    await newPhone.signIn();
    await newPhone.controller.refreshConversations();
    await newPhone.controller.sendText(conversationId: 'conv-bob', body: 'new phone, same bob');
    await waitFor(() => newPhone.controller.pendingCountFor('conv-bob') == 0, reason: 'the new phone did not send');
    await waitFor(() async => (await alice.bodies('conv-bob')).contains('new phone, same bob'),
        reason: 'the new phone\'s message did not open');
    final admittedAt = now;

    // The retry reads the document, and the admission is in it.
    now = now.add(const Duration(seconds: 1));
    await alice.controller.refreshConversations();
    await trustReady(alice);
    final stored = await storedTrust(alice);
    expect(stored!.changed['user-bob'], admittedAt.millisecondsSinceEpoch, reason: 'the new device was lost');
    expect(
      alice.contactTrust.relationshipAt('user-bob', 'bob', chat: alice.controller.conversationById('conv-bob')!, at: now),
      Relationship.changed,
    );
  });
}
