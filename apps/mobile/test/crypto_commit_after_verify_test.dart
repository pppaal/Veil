import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

// Regression test for the pre-auth Double Ratchet state mutation
// (improvement-audit Top-10 #1): a frame that fails AEAD authentication must
// NOT advance or wedge the receive ratchet. Before the commit-after-verify
// fix, one forged frame whose 32-byte header forces a DH step permanently
// corrupted rootKey/receiveChainKey, so the next *legitimate* message could
// never decrypt.
void main() {
  const conversationId = 'conv-commit-after-verify';

  List<int> unb64(String s) =>
      base64Url.decode(s.padRight((s.length + 3) & ~3, '='));
  String b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

  test('a forged frame does not wedge the session', () async {
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

    Future<CryptoEnvelope> aliceSend(String body) => alice.messaging.encryptMessage(
          conversationId: conversationId,
          senderDeviceId: 'device-alice',
          recipientUserId: 'user-bob',
          body: body,
          messageKind: MessageKind.text,
          recipientBundle: bobBundle,
        );

    final env1 = await aliceSend('first message');

    // Bob bootstraps on-receive from Alice's ephemeral, then decrypts msg 1.
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
    expect((await bob.messaging.decryptMessage(env1)).body, 'first message');

    // Alice sends a real second message.
    final env2 = await aliceSend('second message');

    // Forge a frame: random 32-byte ratchet header (forces a DH step) and a
    // corrupted MAC (fails GCM). Same envelope shell as env2.
    final real = unb64(env2.ciphertext);
    final forged = List<int>.of(real);
    final rng = Random(1234);
    for (var i = 0; i < 32; i++) {
      forged[i] = rng.nextInt(256);
    }
    for (var i = forged.length - 16; i < forged.length; i++) {
      forged[i] ^= 0xFF;
    }
    final forgedEnv = CryptoEnvelope(
      version: env2.version,
      conversationId: conversationId,
      senderDeviceId: env2.senderDeviceId,
      recipientUserId: env2.recipientUserId,
      ciphertext: b64(forged),
      nonce: env2.nonce,
      messageKind: env2.messageKind,
    );

    final forgedResult = await bob.messaging.decryptMessage(forgedEnv);
    expect(forgedResult.body, startsWith('['), reason: 'forged frame must not decrypt');

    // The legitimate second message must STILL decrypt — the session was not
    // wedged by the forged frame.
    expect((await bob.messaging.decryptMessage(env2)).body, 'second message');
  });
}
