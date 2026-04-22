import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

// Exercises manual session rekey: forceRekeyNextSend arms a fresh DH ratchet
// step on the next encrypt, drops stashed skipped keys, and the peer can
// still decrypt the post-rotation envelope.
void main() {
  const conversationId = 'conv-rekey';

  KeyBundle bundle(DeviceIdentityMaterial id, String user, String device) {
    return KeyBundle(
      userId: user,
      deviceId: device,
      handle: device,
      identityPublicKey: id.identityPublicKey,
      signedPrekeyBundle: id.signedPrekeyBundle,
    );
  }

  Future<CryptoEnvelope> send({
    required LibCryptoAdapter from,
    required String fromDeviceId,
    required KeyBundle recipientBundle,
    required String body,
  }) {
    return from.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: fromDeviceId,
      recipientUserId: recipientBundle.userId,
      body: body,
      messageKind: MessageKind.text,
      recipientBundle: recipientBundle,
    );
  }

  Future<void> bootstrapReceiver({
    required LibCryptoAdapter receiver,
    required DeviceIdentityMaterial receiverIdentity,
    required String receiverDevice,
    required String senderDevice,
    required CryptoEnvelope firstEnvelope,
  }) async {
    final inspector = receiver.envelopeCodec as InboundEnvelopeInspector;
    final pub = inspector.extractSenderEphemeralPublicKey(firstEnvelope)!;
    await receiver.sessions.bootstrapSessionFromInbound(
      InboundSessionBootstrapRequest(
        conversationId: conversationId,
        localDeviceId: receiverDevice,
        localUserId: receiverDevice,
        localIdentityPrivateRef: receiverIdentity.identityPrivateKeyRef,
        remoteUserId: senderDevice,
        remoteDeviceId: senderDevice,
        remoteEphemeralPublicKey: pub,
      ),
    );
  }

  List<int> ratchetPubFrom(CryptoEnvelope envelope) {
    final padded = envelope.ciphertext.padRight(
      envelope.ciphertext.length +
          ((4 - envelope.ciphertext.length % 4) % 4),
      '=',
    );
    return Uint8List.fromList(base64Url.decode(padded)).sublist(0, 32);
  }

  group('forceRekeyNextSend', () {
    test('returns false when no session exists', () async {
      final alice = LibCryptoAdapter();
      final armed = await alice.forceRekeyNextSend(conversationId);
      expect(armed, isFalse);
    });

    test('arms a fresh DH ratchet step on the next send', () async {
      final alice = LibCryptoAdapter();
      final bob = LibCryptoAdapter();
      final bobId = await bob.identity.generateDeviceIdentity('device-bob');
      final bobBundle = bundle(bobId, 'device-bob', 'device-bob');

      await alice.sessions.bootstrapSession(
        SessionBootstrapRequest(
          conversationId: conversationId,
          localDeviceId: 'device-alice',
          localUserId: 'device-alice',
          remoteUserId: 'device-bob',
          remoteDeviceId: 'device-bob',
          remoteIdentityPublicKey: bobId.identityPublicKey,
          remoteSignedPrekeyBundle: bobId.signedPrekeyBundle,
        ),
      );

      // Two sends without an intervening receive share the same ratchet pub.
      final a0 = await send(
        from: alice,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'a0',
      );
      final a1 = await send(
        from: alice,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'a1',
      );
      expect(ratchetPubFrom(a1), ratchetPubFrom(a0));

      // Force a rekey — the next send MUST rotate the ratchet pub even
      // without a receive in between.
      final armed = await alice.forceRekeyNextSend(conversationId);
      expect(armed, isTrue);

      final a2 = await send(
        from: alice,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'a2',
      );
      expect(ratchetPubFrom(a2), isNot(equals(ratchetPubFrom(a0))));

      // A subsequent send without another rekey reuses a2's ratchet pub.
      final a3 = await send(
        from: alice,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'a3',
      );
      expect(ratchetPubFrom(a3), equals(ratchetPubFrom(a2)));
    });

    test('peer decrypts post-rotation envelope end-to-end', () async {
      final alice = LibCryptoAdapter();
      final bob = LibCryptoAdapter();
      final bobId = await bob.identity.generateDeviceIdentity('device-bob');
      final aliceId =
          await alice.identity.generateDeviceIdentity('device-alice');
      final bobBundle = bundle(bobId, 'device-bob', 'device-bob');
      final aliceBundle = bundle(aliceId, 'device-alice', 'device-alice');

      await alice.sessions.bootstrapSession(
        SessionBootstrapRequest(
          conversationId: conversationId,
          localDeviceId: 'device-alice',
          localUserId: 'device-alice',
          remoteUserId: 'device-bob',
          remoteDeviceId: 'device-bob',
          remoteIdentityPublicKey: bobId.identityPublicKey,
          remoteSignedPrekeyBundle: bobId.signedPrekeyBundle,
        ),
      );

      final first = await send(
        from: alice,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'pre-rekey',
      );
      await bootstrapReceiver(
        receiver: bob,
        receiverIdentity: bobId,
        receiverDevice: 'device-bob',
        senderDevice: 'device-alice',
        firstEnvelope: first,
      );
      expect((await bob.messaging.decryptMessage(first)).body, 'pre-rekey');

      // Alice rekeys. Next send must rotate and still decrypt on Bob's side.
      expect(await alice.forceRekeyNextSend(conversationId), isTrue);
      final rotated = await send(
        from: alice,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'post-rekey',
      );
      expect(ratchetPubFrom(rotated), isNot(equals(ratchetPubFrom(first))));
      expect(
        (await bob.messaging.decryptMessage(rotated)).body,
        'post-rekey',
      );

      // Bob replies → Alice decrypts → conversation continues normally.
      final reply = await send(
        from: bob,
        fromDeviceId: 'device-bob',
        recipientBundle: aliceBundle,
        body: 'ack',
      );
      expect((await alice.messaging.decryptMessage(reply)).body, 'ack');
    });

    test('rekey clears skipped-key stash and persists immediately', () async {
      final alice = LibCryptoAdapter();
      final bob = LibCryptoAdapter();
      final bobId = await bob.identity.generateDeviceIdentity('device-bob');
      final bobBundle = bundle(bobId, 'device-bob', 'device-bob');

      final snapshots = <String, Map<String, dynamic>>{};
      var writeCount = 0;
      alice.setSessionPersistence(
        persister: (id, snap) async {
          snapshots[id] = snap;
          writeCount += 1;
        },
      );

      await alice.sessions.bootstrapSession(
        SessionBootstrapRequest(
          conversationId: conversationId,
          localDeviceId: 'device-alice',
          localUserId: 'device-alice',
          remoteUserId: 'device-bob',
          remoteDeviceId: 'device-bob',
          remoteIdentityPublicKey: bobId.identityPublicKey,
          remoteSignedPrekeyBundle: bobId.signedPrekeyBundle,
        ),
      );
      // Bootstrap persists synchronously.
      final baselineWrites = writeCount;
      expect(baselineWrites, greaterThanOrEqualTo(1));

      // Encrypt a message to seed session state (no skipped keys yet, but
      // this exercises the write-through path).
      await send(
        from: alice,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'seed',
      );

      expect(await alice.forceRekeyNextSend(conversationId), isTrue);
      // Rekey persists synchronously (not through the debounce window).
      expect(writeCount, greaterThan(baselineWrites));

      final snap = snapshots[conversationId]!;
      // Skipped keys dropped; v3 shape retained.
      expect(snap['v'], 3);
      expect((snap['skippedKeys'] as Map).isEmpty, isTrue);
    });
  });
}
