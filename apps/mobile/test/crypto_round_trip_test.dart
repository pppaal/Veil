import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

// End-to-end proof: two independent adapters (Alice, Bob) can derive the same
// symmetric session state without a handshake round-trip. Alice bootstraps
// from Bob's published identity; Bob bootstraps on-receive using his own
// x25519 private key and the sender-ephemeral bytes from the first envelope.
void main() {
  const conversationId = 'conv-round-trip';

  test('alice encrypt → bob decrypt via inbound-bootstrap', () async {
    final alice = LibCryptoAdapter();
    final bob = LibCryptoAdapter();

    final bobIdentity =
        await bob.identity.generateDeviceIdentity('device-bob');
    final aliceIdentity =
        await alice.identity.generateDeviceIdentity('device-alice');

    // Alice bootstraps using Bob's published identity + signed prekey.
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

    final envelope = await alice.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'device-alice',
      recipientUserId: 'user-bob',
      body: 'hello bob',
      messageKind: MessageKind.text,
      recipientBundle: KeyBundle(
        userId: 'user-bob',
        deviceId: 'device-bob',
        handle: 'bob',
        identityPublicKey: bobIdentity.identityPublicKey,
        signedPrekeyBundle: bobIdentity.signedPrekeyBundle,
      ),
    );

    // Bob has never seen this conversation. Controller-style path: use the
    // envelope inspector to lift Alice's ephemeral pub, then bootstrap-on-receive.
    final inspector = bob.envelopeCodec as InboundEnvelopeInspector;
    final ephemeralPub = inspector.extractSenderEphemeralPublicKey(envelope);
    expect(ephemeralPub, isNotNull);
    expect(ephemeralPub!.length, 32);

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

    final decrypted = await bob.messaging.decryptMessage(envelope);
    expect(decrypted.body, 'hello bob');
    expect(decrypted.messageKind, MessageKind.text);

    // Unused variable guard so the analyzer doesn't complain on CI.
    expect(aliceIdentity.identityPublicKey, isNotEmpty);
  });

  test('multi-message ratchet survives round-trip', () async {
    final alice = LibCryptoAdapter();
    final bob = LibCryptoAdapter();

    final bobIdentity =
        await bob.identity.generateDeviceIdentity('device-bob');

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

    final firstEnvelope = await alice.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'device-alice',
      recipientUserId: 'user-bob',
      body: 'msg 0',
      messageKind: MessageKind.text,
      recipientBundle: KeyBundle(
        userId: 'user-bob',
        deviceId: 'device-bob',
        handle: 'bob',
        identityPublicKey: bobIdentity.identityPublicKey,
        signedPrekeyBundle: bobIdentity.signedPrekeyBundle,
      ),
    );

    final inspector = bob.envelopeCodec as InboundEnvelopeInspector;
    final ephemeralPub =
        inspector.extractSenderEphemeralPublicKey(firstEnvelope)!;

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

    final first = await bob.messaging.decryptMessage(firstEnvelope);
    expect(first.body, 'msg 0');

    for (var i = 1; i < 10; i++) {
      final env = await alice.messaging.encryptMessage(
        conversationId: conversationId,
        senderDeviceId: 'device-alice',
        recipientUserId: 'user-bob',
        body: 'msg $i',
        messageKind: MessageKind.text,
        recipientBundle: KeyBundle(
          userId: 'user-bob',
          deviceId: 'device-bob',
          handle: 'bob',
          identityPublicKey: bobIdentity.identityPublicKey,
          signedPrekeyBundle: bobIdentity.signedPrekeyBundle,
        ),
      );
      final out = await bob.messaging.decryptMessage(env);
      expect(out.body, 'msg $i');
    }
  });

  test('out-of-order delivery within the skipped-key window', () async {
    final alice = LibCryptoAdapter();
    final bob = LibCryptoAdapter();

    final bobIdentity =
        await bob.identity.generateDeviceIdentity('device-bob');

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

    final envelopes = <CryptoEnvelope>[];
    for (var i = 0; i < 5; i++) {
      envelopes.add(
        await alice.messaging.encryptMessage(
          conversationId: conversationId,
          senderDeviceId: 'device-alice',
          recipientUserId: 'user-bob',
          body: 'body-$i',
          messageKind: MessageKind.text,
          recipientBundle: KeyBundle(
            userId: 'user-bob',
            deviceId: 'device-bob',
            handle: 'bob',
            identityPublicKey: bobIdentity.identityPublicKey,
            signedPrekeyBundle: bobIdentity.signedPrekeyBundle,
          ),
        ),
      );
    }

    final inspector = bob.envelopeCodec as InboundEnvelopeInspector;
    final ephemeralPub =
        inspector.extractSenderEphemeralPublicKey(envelopes.first)!;
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

    // Bob sees 2, then 0, then 4, then 1, then 3 — classic out-of-order delivery.
    final order = [2, 0, 4, 1, 3];
    final bodies = <String>[];
    for (final idx in order) {
      final decoded = await bob.messaging.decryptMessage(envelopes[idx]);
      bodies.add(decoded.body);
    }
    expect(bodies, ['body-2', 'body-0', 'body-4', 'body-1', 'body-3']);
  });

  test('replayed counter rejected after first consume', () async {
    final alice = LibCryptoAdapter();
    final bob = LibCryptoAdapter();

    final bobIdentity =
        await bob.identity.generateDeviceIdentity('device-bob');

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

    final env = await alice.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'device-alice',
      recipientUserId: 'user-bob',
      body: 'replay me',
      messageKind: MessageKind.text,
      recipientBundle: KeyBundle(
        userId: 'user-bob',
        deviceId: 'device-bob',
        handle: 'bob',
        identityPublicKey: bobIdentity.identityPublicKey,
        signedPrekeyBundle: bobIdentity.signedPrekeyBundle,
      ),
    );

    final inspector = bob.envelopeCodec as InboundEnvelopeInspector;
    final ephemeralPub = inspector.extractSenderEphemeralPublicKey(env)!;
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

    final first = await bob.messaging.decryptMessage(env);
    expect(first.body, 'replay me');

    final replayed = await bob.messaging.decryptMessage(env);
    // Replay produces a placeholder body, not the original cleartext.
    expect(replayed.body, isNot('replay me'));
  });

  test('corrupted identity bundle refuses to bootstrap', () async {
    final bob = LibCryptoAdapter();
    expect(
      () => bob.sessions.bootstrapSessionFromInbound(
        InboundSessionBootstrapRequest(
          conversationId: conversationId,
          localDeviceId: 'device-bob',
          localUserId: 'user-bob',
          localIdentityPrivateRef:
              base64Url.encode(utf8.encode('{"ed25519":"xx"}')).replaceAll('=', ''),
          remoteUserId: 'user-alice',
          remoteDeviceId: 'device-alice',
          remoteEphemeralPublicKey: List<int>.filled(32, 0),
        ),
      ),
      throwsStateError,
    );
  });
}
