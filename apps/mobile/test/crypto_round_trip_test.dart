import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

import 'crypto/support/crypto_harness.dart';

// End-to-end proof: two independent adapters (Alice, Bob) derive the same
// session without a handshake round-trip. Alice runs X3DH against Bob's
// published bundle; Bob's side of the session is established by decrypting
// Alice's first (PreKey) frame.
void main() {
  const conversationId = 'conv-round-trip';

  test('alice encrypt → bob decrypt; the PreKey frame establishes Bob', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);

    final envelope = await send(alice, bob, 'hello bob', conversationId: conversationId);
    expect(envelope.version, 'veil-envelope-v2');
    expect(bob.adapter.sessions.hasSessionFor(conversationId), isFalse);
    // The controller's legacy inbound hook stays inert for v2 frames.
    final inspector = bob.adapter.envelopeCodec as InboundEnvelopeInspector;
    expect(inspector.extractSenderEphemeralPublicKey(envelope), isNull);

    final decrypted = await receive(bob, envelope);
    expect(decrypted.status, DecryptStatus.ok);
    expect(decrypted.isOk, isTrue);
    expect(decrypted.body, 'hello bob');
    expect(decrypted.messageKind, MessageKind.text);
    expect(bob.adapter.sessions.hasSessionFor(conversationId), isTrue);
  });

  test('multi-message ratchet survives round-trip', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    for (var i = 0; i < 10; i++) {
      final out = await receive(bob, await send(alice, bob, 'msg $i', conversationId: conversationId));
      expect(out.body, 'msg $i');
    }
  });

  test('out-of-order delivery within the skipped-key window', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    final envelopes = [
      for (var i = 0; i < 5; i++) await send(alice, bob, 'body-$i', conversationId: conversationId),
    ];

    // Bob sees 2, then 0, then 4, then 1, then 3 — classic out-of-order delivery.
    final bodies = [
      for (final idx in [2, 0, 4, 1, 3]) (await receive(bob, envelopes[idx])).body
    ];
    expect(bodies, ['body-2', 'body-0', 'body-4', 'body-1', 'body-3']);
  });

  test('replayed counter rejected after first consume', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    final env = await send(alice, bob, 'replay me', conversationId: conversationId);

    expect((await receive(bob, env)).body, 'replay me');
    final replayed = await receive(bob, env);
    expect(replayed.status, DecryptStatus.replayed);
    expect(replayed.body, isNot('replay me'));
  });

  test('legacy v1 peers still interoperate, typed legacyUnauthenticated', () async {
    final alice = await createParty('alice');
    final bob = await createLegacyParty('bob');
    final material = await bootstrap(alice, bob, conversationId: conversationId);
    expect(material.sessionEnvelopeVersion, 'veil-envelope-v1');

    final first = await send(alice, bob, 'to a v1 peer', conversationId: conversationId);
    expect(first.version, 'veil-envelope-v1');
    await acceptLegacy(bob, alice, first, conversationId: conversationId);
    final atBob = await receive(bob, first);
    expect(atBob.status, DecryptStatus.legacyUnauthenticated);
    expect(atBob.isOk, isFalse);
    expect(atBob.body, 'to a v1 peer');

    final reply = await receive(alice, await send(bob, alice, 'from a v1 peer', conversationId: conversationId));
    expect(reply.status, DecryptStatus.legacyUnauthenticated);
    expect(reply.body, 'from a v1 peer');
  });

  test('corrupted identity bundle refuses to bootstrap', () async {
    final bob = LibCryptoAdapter();
    expect(
      () => bob.sessions.bootstrapSessionFromInbound(
        InboundSessionBootstrapRequest(
          conversationId: conversationId,
          localDeviceId: 'device-bob',
          localUserId: 'user-bob',
          localIdentityPrivateRef: base64Url.encode(utf8.encode('{"ed25519":"xx"}')).replaceAll('=', ''),
          remoteUserId: 'user-alice',
          remoteDeviceId: 'device-alice',
          remoteEphemeralPublicKey: List<int>.filled(32, 0),
        ),
      ),
      throwsStateError,
    );
  });
}
