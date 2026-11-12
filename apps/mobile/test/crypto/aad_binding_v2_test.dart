import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';

import 'support/crypto_harness.dart';

// AAD v4 binds every routing field the server relays in clear (version,
// conversation, sender, kind) to the frame. expiresAt is deliberately not
// bound (contract C4): the server may clamp it, and the authenticated value
// rides inside the payload.
void main() {
  const conversationId = 'conv-aad';

  test('tampered kind, conversationId or version fails AEAD', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    await bootstrap(alice, bob, conversationId: 'conv-other');
    expect((await receive(bob, await send(alice, bob, 'other', conversationId: 'conv-other'))).isOk, isTrue);
    final envelope = await send(alice, bob, 'bound', conversationId: conversationId);

    Future<void> expectAeadFailure(CryptoEnvelope tampered) async {
      final result = await receive(bob, tampered);
      expect(result.status, DecryptStatus.failed);
      expect(result.failureReason, 'aead_failed');
    }

    await expectAeadFailure(copyEnvelope(envelope, messageKind: MessageKind.system));
    await expectAeadFailure(copyEnvelope(envelope, version: 'veil-envelope-v3'));
    await expectAeadFailure(copyEnvelope(envelope, senderDeviceId: 'device-mallory'));
    // Replayed into a conversation where Bob holds a session with Alice.
    expect((await receive(bob, copyEnvelope(envelope, conversationId: 'conv-other'))).isOk, isFalse);
    // Replayed into a fresh conversation, the PreKey frame cannot open one.
    await expectAeadFailure(copyEnvelope(envelope, conversationId: 'conv-fresh'));
    expect(bob.adapter.sessions.hasSessionFor('conv-fresh'), isFalse);
    // Downgrade relabel takes the legacy path, which has no such session.
    expect((await receive(bob, copyEnvelope(envelope, version: 'veil-envelope-v1'))).isOk, isFalse);

    final genuine = await receive(bob, envelope);
    expect(genuine.status, DecryptStatus.ok);
    expect(genuine.body, 'bound');
    expect(genuine.messageKind, MessageKind.text);
  });

  test('a messageType the relay relabels to a value this build cannot parse, or drops, fails AEAD', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    final codec = bob.adapter.envelopeCodec;
    final relayed = codec.encodeApiEnvelope(await send(alice, bob, 'text frame', conversationId: conversationId));

    for (final relabel in ['bogus', 'TEXT', null]) {
      final json = Map<String, dynamic>.of(relayed);
      if (relabel == null) {
        json.remove('messageType');
      } else {
        json['messageType'] = relabel;
      }
      final result = await receive(bob, codec.decodeApiEnvelope(json));
      expect(result.isOk, isFalse, reason: 'messageType $relabel');
      expect(result.failureReason, 'aead_failed');
    }
    expect((await receive(bob, codec.decodeApiEnvelope(relayed))).body, 'text frame');
  });

  test('outer expiresAt change does not fail and inner expiresAt returned', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    final innerExpiry = DateTime.utc(2030, 1, 1, 12);
    final envelope = await send(alice, bob, 'ephemeral', conversationId: conversationId, expiresAt: innerExpiry);

    final clamped = copyEnvelope(envelope, expiresAt: DateTime.utc(2029, 12, 31));
    final result = await receive(bob, clamped);
    expect(result.status, DecryptStatus.ok);
    expect(result.body, 'ephemeral');
    expect(result.expiresAt!.isAtSameMomentAs(innerExpiry), isTrue);
  });
}
