import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';

import 'crypto/support/crypto_harness.dart';

// Regression test for pre-auth Double Ratchet state mutation: a frame that
// fails AEAD authentication must NOT advance or wedge the receive ratchet.
// A forged frame whose ratchet key forces a DH step used to corrupt the
// root and chain keys permanently; now every attempt runs on a copy that is
// only committed after the tag verifies.
void main() {
  const conversationId = 'conv-commit-after-verify';

  test('a forged frame does not wedge the session', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    expect((await receive(bob, await send(alice, bob, 'first message', conversationId: conversationId))).body,
        'first message');

    final env2 = await send(alice, bob, 'second message', conversationId: conversationId);

    // Forge: random ratchet key in the header (forces a DH step) and a
    // corrupted tag.
    final forged = b64uDecode(env2.ciphertext);
    final ratchetOffset = frameOf(env2).header.length - 40;
    final rng = Random(1234);
    for (var i = ratchetOffset; i < ratchetOffset + 32; i++) {
      forged[i] = rng.nextInt(256);
    }
    for (var i = forged.length - 16; i < forged.length; i++) {
      forged[i] ^= 0xFF;
    }

    final forgedResult = await receive(bob, copyEnvelope(env2, ciphertext: b64uEncode(forged)));
    expect(forgedResult.status, DecryptStatus.failed, reason: 'forged frame must not decrypt');
    expect(forgedResult.body, startsWith('['));

    expect((await receive(bob, env2)).body, 'second message');
  });
}
