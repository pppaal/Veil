import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

// Exercises the DH ratchet on top of the symmetric hash ratchet:
//   - conversational turn-flips rotate the sender's ratchet pub on the wire
//   - the peer performs a receive DH step, producing a fresh chain
//   - persisted session snapshots round-trip through the snapshot API and
//     restored state continues the same chain without re-bootstrap.
void main() {
  const conversationId = 'conv-dh';

  KeyBundle _bundle(DeviceIdentityMaterial id, String user, String device) {
    return KeyBundle(
      userId: user,
      deviceId: device,
      handle: device,
      identityPublicKey: id.identityPublicKey,
      signedPrekeyBundle: id.signedPrekeyBundle,
    );
  }

  Future<CryptoEnvelope> _send({
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

  Future<void> _bootstrapReceiver({
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

  List<int> _ratchetPubFrom(CryptoEnvelope envelope) {
    final padded = envelope.ciphertext.padRight(
      envelope.ciphertext.length +
          ((4 - envelope.ciphertext.length % 4) % 4),
      '=',
    );
    return Uint8List.fromList(base64Url.decode(padded)).sublist(0, 32);
  }

  test('sender rotates its ratchet pub once per turn-flip, not per message',
      () async {
    final alice = LibCryptoAdapter();
    final bob = LibCryptoAdapter();
    final bobId = await bob.identity.generateDeviceIdentity('device-bob');
    final aliceId =
        await alice.identity.generateDeviceIdentity('device-alice');
    final bobBundle = _bundle(bobId, 'device-bob', 'device-bob');
    final aliceBundle = _bundle(aliceId, 'device-alice', 'device-alice');

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

    // Alice sends 3 messages in a row. She has not received anything — all
    // three must carry the same ratchet pub.
    final a0 = await _send(
        from: alice, fromDeviceId: 'device-alice', recipientBundle: bobBundle, body: 'a0');
    final a1 = await _send(
        from: alice, fromDeviceId: 'device-alice', recipientBundle: bobBundle, body: 'a1');
    final a2 = await _send(
        from: alice, fromDeviceId: 'device-alice', recipientBundle: bobBundle, body: 'a2');

    expect(_ratchetPubFrom(a1), _ratchetPubFrom(a0));
    expect(_ratchetPubFrom(a2), _ratchetPubFrom(a0));

    // Bob bootstraps + decrypts. That flips his turn-flag.
    await _bootstrapReceiver(
      receiver: bob,
      receiverIdentity: bobId,
      receiverDevice: 'device-bob',
      senderDevice: 'device-alice',
      firstEnvelope: a0,
    );
    expect((await bob.messaging.decryptMessage(a0)).body, 'a0');
    expect((await bob.messaging.decryptMessage(a1)).body, 'a1');
    expect((await bob.messaging.decryptMessage(a2)).body, 'a2');

    // Bob's first reply MUST rotate his ratchet pub. Second reply without an
    // intervening receive must NOT rotate.
    final b0 = await _send(
        from: bob, fromDeviceId: 'device-bob', recipientBundle: aliceBundle, body: 'b0');
    final b1 = await _send(
        from: bob, fromDeviceId: 'device-bob', recipientBundle: aliceBundle, body: 'b1');

    final aliceEphemeralPub = _ratchetPubFrom(a0);
    expect(_ratchetPubFrom(b0), isNot(aliceEphemeralPub),
        reason: 'first send after receive should rotate DH');
    expect(_ratchetPubFrom(b1), _ratchetPubFrom(b0),
        reason: 'no new receive since last send, no rotation');

    // Alice must be able to decrypt despite the rotation (proves the DH
    // receive-step on her side agreed on the same chain).
    expect((await alice.messaging.decryptMessage(b0)).body, 'b0');
    expect((await alice.messaging.decryptMessage(b1)).body, 'b1');
  });

  test('ping-pong across many turns advances DH every turn-flip', () async {
    final alice = LibCryptoAdapter();
    final bob = LibCryptoAdapter();
    final bobId = await bob.identity.generateDeviceIdentity('device-bob');
    final aliceId =
        await alice.identity.generateDeviceIdentity('device-alice');
    final bobBundle = _bundle(bobId, 'device-bob', 'device-bob');
    final aliceBundle = _bundle(aliceId, 'device-alice', 'device-alice');

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

    final first = await _send(
        from: alice,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'alice-0');
    await _bootstrapReceiver(
      receiver: bob,
      receiverIdentity: bobId,
      receiverDevice: 'device-bob',
      senderDevice: 'device-alice',
      firstEnvelope: first,
    );
    expect((await bob.messaging.decryptMessage(first)).body, 'alice-0');

    final ratchetHistory = <String>{};
    ratchetHistory.add(base64Url.encode(_ratchetPubFrom(first)));

    // 12 turn-flips back and forth.
    var aliceTurn = false;
    for (var turn = 1; turn <= 12; turn++) {
      final sender = aliceTurn ? alice : bob;
      final receiver = aliceTurn ? bob : alice;
      final recipientBundle = aliceTurn ? bobBundle : aliceBundle;
      final deviceId = aliceTurn ? 'device-alice' : 'device-bob';
      final body = 'turn-$turn';
      final env = await _send(
          from: sender,
          fromDeviceId: deviceId,
          recipientBundle: recipientBundle,
          body: body);
      final key = base64Url.encode(_ratchetPubFrom(env));
      expect(ratchetHistory.contains(key), isFalse,
          reason: 'turn $turn should use a fresh ratchet pub');
      ratchetHistory.add(key);
      expect((await receiver.messaging.decryptMessage(env)).body, body);
      aliceTurn = !aliceTurn;
    }
  });

  test('session snapshot round-trips: restored state decrypts next message',
      () async {
    final alice = LibCryptoAdapter();
    final bobOriginal = LibCryptoAdapter();
    final bobId =
        await bobOriginal.identity.generateDeviceIdentity('device-bob');
    final bobBundle = _bundle(bobId, 'device-bob', 'device-bob');

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

    // Snapshot capture: use the persister hook to record Alice's state.
    final snapshots = <String, Map<String, dynamic>>{};
    alice.setSessionPersistence(
      persister: (id, snap) async {
        snapshots[id] = snap;
      },
    );

    final bootstrapMsg =
        await _send(from: alice, fromDeviceId: 'device-alice', recipientBundle: bobBundle, body: 'bootstrap');
    await _bootstrapReceiver(
      receiver: bobOriginal,
      receiverIdentity: bobId,
      receiverDevice: 'device-bob',
      senderDevice: 'device-alice',
      firstEnvelope: bootstrapMsg,
    );
    expect((await bobOriginal.messaging.decryptMessage(bootstrapMsg)).body,
        'bootstrap');

    // Send a few more to advance Alice's send chain beyond counter 0.
    for (var i = 0; i < 3; i++) {
      final env = await _send(
          from: alice,
          fromDeviceId: 'device-alice',
          recipientBundle: bobBundle,
          body: 'pre-$i');
      expect((await bobOriginal.messaging.decryptMessage(env)).body, 'pre-$i');
    }

    // Force a persister flush: Alice sends one more and we capture the
    // snapshot at counter=4 state.
    final afterAdvance =
        await _send(from: alice, fromDeviceId: 'device-alice', recipientBundle: bobBundle, body: 'snap-point');
    expect((await bobOriginal.messaging.decryptMessage(afterAdvance)).body,
        'snap-point');
    expect(snapshots.containsKey(conversationId), isTrue);

    // Simulate app restart: build a fresh Alice adapter and restore.
    final aliceRestarted = LibCryptoAdapter();
    await aliceRestarted.restoreSessionsFromSnapshots(snapshots);

    final afterRestart = await _send(
        from: aliceRestarted,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'post-restart');
    final decrypted = await bobOriginal.messaging.decryptMessage(afterRestart);
    expect(decrypted.body, 'post-restart');
  });

  test('restored alice can still rotate DH after receiving from bob',
      () async {
    final alice = LibCryptoAdapter();
    final bob = LibCryptoAdapter();
    final bobId = await bob.identity.generateDeviceIdentity('device-bob');
    final aliceId =
        await alice.identity.generateDeviceIdentity('device-alice');
    final bobBundle = _bundle(bobId, 'device-bob', 'device-bob');
    final aliceBundle = _bundle(aliceId, 'device-alice', 'device-alice');

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

    final snapshots = <String, Map<String, dynamic>>{};
    alice.setSessionPersistence(
      persister: (id, snap) async {
        snapshots[id] = snap;
      },
    );

    final first = await _send(
        from: alice,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'a0');
    await _bootstrapReceiver(
      receiver: bob,
      receiverIdentity: bobId,
      receiverDevice: 'device-bob',
      senderDevice: 'device-alice',
      firstEnvelope: first,
    );
    expect((await bob.messaging.decryptMessage(first)).body, 'a0');

    // Bob replies → Alice receives → Alice snapshot captures hasReceived=true.
    final reply = await _send(
        from: bob,
        fromDeviceId: 'device-bob',
        recipientBundle: aliceBundle,
        body: 'b0');
    expect((await alice.messaging.decryptMessage(reply)).body, 'b0');

    // Snapshot captured after Alice processed Bob's reply. Simulate restart.
    final aliceRestarted = LibCryptoAdapter();
    await aliceRestarted.restoreSessionsFromSnapshots(snapshots);

    // On restart, Alice's next send should rotate DH. Bob must agree.
    final afterRestart = await _send(
        from: aliceRestarted,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'post-restart');
    expect(_ratchetPubFrom(afterRestart), isNot(_ratchetPubFrom(first)),
        reason: 'restart + queued turn-flip must rotate DH on next send');
    expect((await bob.messaging.decryptMessage(afterRestart)).body,
        'post-restart');
  });
}
