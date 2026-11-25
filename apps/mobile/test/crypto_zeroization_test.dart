import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'crypto/support/crypto_harness.dart';

// Best-effort zeroization. Dart cannot guarantee secrets were never copied,
// but buffers the adapter owns must be overwritten once superseded: every
// commit replaces the live ratchet state with an updated copy and wipes the
// old one (root key, chain keys, ratchet private key).
void main() {
  test('destroy() makes a SecretKey unusable (best-effort wipe)', () async {
    final key = SecretKey(List<int>.filled(32, 0x5A));

    final before = await key.extractBytes();
    expect(before, hasLength(32));
    expect(before.every((b) => b == 0x5A), isTrue);

    key.destroy();

    var threw = false;
    try {
      await key.extractBytes();
    } catch (_) {
      threw = true;
    }
    expect(threw, isTrue, reason: 'destroyed key must not extract bytes');
  });

  test('superseded buffers zeroed after encrypt, decrypt and DH step', () async {
    const conversationId = 'conv-zeroize';
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);

    bool zeroed(Uint8List buffer) => buffer.every((b) => b == 0);
    void expectWiped(List<Uint8List> buffers, String step) {
      expect(buffers, isNotEmpty);
      for (final buffer in buffers) {
        expect(zeroed(buffer), isTrue, reason: '$step left a superseded secret in memory');
      }
    }

    void expectLive(List<Uint8List> buffers) {
      for (final buffer in buffers) {
        expect(zeroed(buffer), isFalse);
      }
    }

    // Encrypt: advances Alice's sending chain.
    final beforeEncrypt = alice.adapter.debugLiveSecretBuffers(conversationId);
    final a0 = await send(alice, bob, 'a0', conversationId: conversationId);
    expectWiped(beforeEncrypt, 'encrypt');
    expectLive(alice.adapter.debugLiveSecretBuffers(conversationId));

    // Decrypt on the same chain.
    expect((await receive(bob, a0)).isOk, isTrue);
    final a1 = await send(alice, bob, 'a1', conversationId: conversationId);
    final beforeDecrypt = bob.adapter.debugLiveSecretBuffers(conversationId);
    expect((await receive(bob, a1)).isOk, isTrue);
    expectWiped(beforeDecrypt, 'decrypt');

    // DH step: Bob's reply makes Alice step her receiving ratchet.
    final b0 = await send(bob, alice, 'b0', conversationId: conversationId);
    final beforeDhStep = alice.adapter.debugLiveSecretBuffers(conversationId);
    expect((await receive(alice, b0)).isOk, isTrue);
    expectWiped(beforeDhStep, 'DH step');
    expectLive(alice.adapter.debugLiveSecretBuffers(conversationId));
  });
}
