import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

// Regression test for AEAD associated-data (AAD) header binding (adapter v3).
//
// The per-message AES-GCM tag now authenticates the unencrypted frame
// header / routing fields — the sender's ratchet public key, the message
// counter, and senderDeviceId — by binding them as associated data. Before
// v3 those fields rode alongside the ciphertext unauthenticated, so an
// attacker could alter them without invalidating the GCM tag.
//
// These tests prove:
//   (a) a normal encrypt -> decrypt round-trip still succeeds (AAD matches);
//   (b) flipping the transmitted senderDeviceId (which does NOT affect frame
//       parsing or message-key derivation — the AAD is the ONLY thing binding
//       it) now fails to decrypt;
//   (c) flipping a byte in the counter region of the frame, while leaving the
//       AES-GCM ciphertext and tag bytes untouched, now fails to decrypt.
void main() {
  const conversationId = 'conv-aad-header-binding';

  List<int> unb64(String s) =>
      base64Url.decode(s.padRight((s.length + 3) & ~3, '='));
  String b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  // Stands up Alice (initiator) and Bob (responder) and returns Alice's first
  // envelope already decryptable by Bob, leaving both sessions live.
  Future<({LibCryptoAdapter alice, LibCryptoAdapter bob, KeyBundle bobBundle})>
      establish() async {
    final alice = LibCryptoAdapter();
    final bob = LibCryptoAdapter();

    final bobIdentity = await bob.identity.generateDeviceIdentity('device-bob');
    await alice.identity.generateDeviceIdentity('device-alice');

    await alice.sessions.bootstrapSession(
      SessionBootstrapRequest(
        conversationId: conversationId,
        localDeviceId: 'device-alice',
        localUserId: 'user-alice',
        remoteUserId: 'user-bob',
        remoteDeviceId: 'device-bob',
        remoteIdentityPublicKey: bobIdentity.identityPublicKey,
        remoteSignedPrekeyBundle: bobIdentity.signedPrekeyBundle,
      ),
    );

    final bobBundle = KeyBundle(
      userId: 'user-bob',
      deviceId: 'device-bob',
      handle: 'bob',
      identityPublicKey: bobIdentity.identityPublicKey,
      signedPrekeyBundle: bobIdentity.signedPrekeyBundle,
    );

    final env1 = await alice.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'device-alice',
      recipientUserId: 'user-bob',
      body: 'bootstrap',
      messageKind: MessageKind.text,
      recipientBundle: bobBundle,
    );

    final inspector = bob.envelopeCodec as InboundEnvelopeInspector;
    final ephemeralPub = inspector.extractSenderEphemeralPublicKey(env1)!;
    await bob.sessions.bootstrapSessionFromInbound(
      InboundSessionBootstrapRequest(
        conversationId: conversationId,
        localDeviceId: 'device-bob',
        localUserId: 'user-bob',
        localIdentityPrivateRef: bobIdentity.identityPrivateKeyRef,
        remoteUserId: 'user-alice',
        remoteDeviceId: 'device-alice',
        remoteEphemeralPublicKey: ephemeralPub,
      ),
    );
    expect((await bob.messaging.decryptMessage(env1)).body, 'bootstrap');

    return (alice: alice, bob: bob, bobBundle: bobBundle);
  }

  test('(a) untampered round-trip still decrypts under AAD binding', () async {
    final ctx = await establish();
    final env = await ctx.alice.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'device-alice',
      recipientUserId: 'user-bob',
      body: 'hello aad',
      messageKind: MessageKind.text,
      recipientBundle: ctx.bobBundle,
    );
    final result = await ctx.bob.messaging.decryptMessage(env);
    expect(result.body, 'hello aad');
  });

  test('(b) tampering senderDeviceId in the envelope fails to decrypt',
      () async {
    final ctx = await establish();
    final env = await ctx.alice.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'device-alice',
      recipientUserId: 'user-bob',
      body: 'authentic sender',
      messageKind: MessageKind.text,
      recipientBundle: ctx.bobBundle,
    );

    // Ciphertext frame is byte-for-byte intact; only the routing senderDeviceId
    // is altered. senderDeviceId never enters frame parsing or message-key
    // derivation, so the ONLY thing that can reject this is the AAD binding.
    final tampered = CryptoEnvelope(
      version: env.version,
      conversationId: env.conversationId,
      senderDeviceId: 'device-mallory',
      recipientUserId: env.recipientUserId,
      ciphertext: env.ciphertext,
      nonce: env.nonce,
      messageKind: env.messageKind,
    );

    final result = await ctx.bob.messaging.decryptMessage(tampered);
    expect(result.body, startsWith('['),
        reason: 'altered senderDeviceId must invalidate the GCM tag');

    // And the original, untampered envelope must still decrypt (the forged
    // attempt did not wedge the receive ratchet — commit-after-verify).
    expect((await ctx.bob.messaging.decryptMessage(env)).body,
        'authentic sender');
  });

  test('(c) flipping a counter-header byte (ciphertext/tag intact) fails',
      () async {
    final ctx = await establish();
    final env = await ctx.alice.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'device-alice',
      recipientUserId: 'user-bob',
      body: 'counter bound',
      messageKind: MessageKind.text,
      recipientBundle: ctx.bobBundle,
    );

    // Frame layout: [ratchetPub(32)][counter(4 BE)][ct(var)][mac(16)].
    // Flip the low byte of the counter (index 35). This leaves the AES-GCM
    // ciphertext and tag bytes (index 36..end) untouched, so the only signal
    // that the header changed is the AAD binding the counter.
    final frame = List<int>.of(unb64(env.ciphertext));
    frame[35] ^= 0x01;

    final tampered = CryptoEnvelope(
      version: env.version,
      conversationId: env.conversationId,
      senderDeviceId: env.senderDeviceId,
      recipientUserId: env.recipientUserId,
      ciphertext: b64(frame),
      nonce: env.nonce,
      messageKind: env.messageKind,
    );

    final result = await ctx.bob.messaging.decryptMessage(tampered);
    expect(result.body, startsWith('['),
        reason: 'altered counter header must invalidate the GCM tag');

    // Original still decrypts — the forged frame did not advance the ratchet.
    expect((await ctx.bob.messaging.decryptMessage(env)).body, 'counter bound');
  });
}
