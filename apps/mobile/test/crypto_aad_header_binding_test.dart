import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';

import 'crypto/support/crypto_harness.dart';

// Regression test for AEAD associated-data (AAD) header binding.
//
// The per-message AES-GCM tag authenticates the unencrypted frame header
// (handshake fields, ratchet key, PN, counter) and the routing fields the
// server relays (senderDeviceId among them). These tests prove:
//   (a) a normal encrypt -> decrypt round-trip still succeeds;
//   (b) flipping the transmitted senderDeviceId — which affects neither
//       frame parsing nor key derivation — fails to decrypt;
//   (c) flipping a counter byte while leaving ciphertext and tag untouched
//       fails to decrypt;
// and that a rejected forgery leaves the session able to decrypt the
// genuine frame (commit-after-verify).
void main() {
  const conversationId = 'conv-aad-header-binding';

  Future<(Party, Party)> establish() async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    expect((await receive(bob, await send(alice, bob, 'bootstrap', conversationId: conversationId))).body, 'bootstrap');
    return (alice, bob);
  }

  test('(a) untampered round-trip still decrypts under AAD binding', () async {
    final (alice, bob) = await establish();
    final env = await send(alice, bob, 'hello aad', conversationId: conversationId);
    expect((await receive(bob, env)).body, 'hello aad');
  });

  test('(b) tampering senderDeviceId in the envelope fails to decrypt', () async {
    final (alice, bob) = await establish();
    final env = await send(alice, bob, 'authentic sender', conversationId: conversationId);

    final result = await receive(bob, copyEnvelope(env, senderDeviceId: 'device-mallory'));
    expect(result.status, DecryptStatus.failed, reason: 'altered senderDeviceId must invalidate the GCM tag');
    expect(result.body, startsWith('['));

    expect((await receive(bob, env)).body, 'authentic sender');
  });

  test('(c) flipping a counter-header byte (ciphertext/tag intact) fails', () async {
    final (alice, bob) = await establish();
    final env = await send(alice, bob, 'counter bound', conversationId: conversationId);

    // The counter is the header's last 4 bytes (BE); flip its low byte.
    final frame = b64uDecode(env.ciphertext);
    frame[frameOf(env).header.length - 1] ^= 0x01;
    final result = await receive(bob, copyEnvelope(env, ciphertext: b64uEncode(frame)));
    expect(result.isOk, isFalse, reason: 'altered counter header must invalidate the GCM tag');

    expect((await receive(bob, env)).body, 'counter bound');
  });
}
