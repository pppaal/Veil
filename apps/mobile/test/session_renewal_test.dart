import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';

import 'crypto/support/crypto_harness.dart';
import 'support/async_wait.dart';
import 'support/fake_relay.dart';
import 'support/messenger_party.dart';

// "Start a new session" replaces a 1:1 session with a fresh X3DH handshake
// and archives the old state. It replaced a forced ratchet step on the live
// session, which desynchronised the conversation for good whenever the peer
// had a reply in flight: the step was taken from a ratchet key the peer had
// already moved past.
void main() {
  const conversationId = 'conv-renew';

  group('a fresh handshake over an established session', () {
    test('still opens the reply the peer had in flight, and both directions keep working', () async {
      final alice = await createParty('alice');
      final bob = await createParty('bob');
      await bootstrap(alice, bob, conversationId: conversationId);
      for (final turn in ['1', '2']) {
        expect((await receive(bob, await send(alice, bob, 'a$turn', conversationId: conversationId))).isOk, isTrue);
        expect((await receive(alice, await send(bob, alice, 'b$turn', conversationId: conversationId))).isOk, isTrue);
      }
      // The reported race: bob's reply is on its way while alice renews.
      final inFlight = await send(bob, alice, 'in flight', conversationId: conversationId);

      await bootstrap(alice, bob, conversationId: conversationId);
      final fresh = await send(alice, bob, 'on the new session', conversationId: conversationId);
      expect(frameOf(fresh).preKey, isNotNull);

      expect((await receive(bob, fresh)).body, 'on the new session');
      expect((await receive(alice, inFlight)).body, 'in flight');
      for (final turn in ['3', '4']) {
        expect((await receive(alice, await send(bob, alice, 'b$turn', conversationId: conversationId))).body, 'b$turn');
        expect((await receive(bob, await send(alice, bob, 'a$turn', conversationId: conversationId))).body, 'a$turn');
      }
    });
  });

  group('VeilMessengerController.renewSession', () {
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
      await waitFor(
        () async => (await to.bodies(conversationId)).contains(body),
        reason: '"$body" is not readable by ${to.device.handle}',
      );
    }

    test('needs a session to replace', () async {
      expect(await alice.controller.renewSession(conversationId), isFalse);
      expect(await alice.controller.renewSession('conv-unknown'), isFalse);
    });

    test('keeps the conversation readable both ways when the peer has a reply in flight', () async {
      await deliver(alice, bob, 'hello');
      await deliver(bob, alice, 'hi');
      await deliver(alice, bob, 'how are you');
      await deliver(bob, alice, 'fine');
      // bob's next reply is sealed but the relay has not delivered it yet.
      final inFlight = bob.lib.envelopeCodec.encodeApiEnvelope(await bob.lib.messaging.encryptMessage(
        conversationId: conversationId,
        senderDeviceId: bob.device.deviceId,
        recipientUserId: alice.device.userId,
        body: 'typed while you renewed',
        messageKind: MessageKind.text,
        recipientBundle: KeyBundle(
          userId: alice.device.userId,
          deviceId: alice.device.deviceId,
          handle: alice.device.handle,
          identityPublicKey: alice.device.identity.identityPublicKey,
          signedPrekeyBundle: alice.device.identity.signedPrekeyBundle,
        ),
      ));

      expect(await alice.controller.renewSession(conversationId), isTrue);
      relay.inject(senderHandle: 'bob', conversationId: conversationId, envelope: inFlight);
      await alice.controller.loadConversationMessages(conversationId);
      await waitFor(
        () async => (await alice.bodies(conversationId)).contains('typed while you renewed'),
        reason: 'the reply in flight was lost',
      );

      await deliver(alice, bob, 'on the new session');
      final carried = alice.lib.envelopeCodec.decodeApiEnvelope(relay.conversations[conversationId]!.messages.last);
      expect(frameOf(carried).preKey, isNotNull);
      await deliver(bob, alice, 'got it');
      await deliver(alice, bob, 'still flowing');
      await deliver(bob, alice, 'both ways');
    });
  });
}
