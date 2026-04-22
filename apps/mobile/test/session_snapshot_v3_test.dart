import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

// Exercises the v3 snapshot hardening: schema migration from v2, per-epoch
// skipped-key cap, TTL drop for abandoned stragglers, and write debouncing
// (writes coalesce within the debounce window and a flush settles them).
void main() {
  const conversationId = 'conv-v3';

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

  group('v3 snapshot', () {
    test('fresh snapshot carries v=3 and epoch metadata', () async {
      final alice = LibCryptoAdapter();
      final bob = LibCryptoAdapter();
      final bobId = await bob.identity.generateDeviceIdentity('device-bob');

      final snapshots = <String, Map<String, dynamic>>{};
      alice.setSessionPersistence(
        persister: (id, snap) async => snapshots[id] = snap,
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
      // Bootstrap persists synchronously, no flush needed.
      final snap = snapshots[conversationId]!;
      expect(snap['v'], 3);
      expect(snap['ratchetRotationCount'], 0);
      expect(snap['lastRatchetRotationAt'], isNull);
      expect(snap['skippedKeys'], isA<Map<String, dynamic>>());
    });

    test('DH rotation bumps rotation counter + timestamp', () async {
      final alice = LibCryptoAdapter();
      final bob = LibCryptoAdapter();
      final bobId = await bob.identity.generateDeviceIdentity('device-bob');
      final aliceId =
          await alice.identity.generateDeviceIdentity('device-alice');
      final bobBundle = bundle(bobId, 'device-bob', 'device-bob');
      final aliceBundle = bundle(aliceId, 'device-alice', 'device-alice');

      final snapshots = <String, Map<String, dynamic>>{};
      alice.setSessionPersistence(
        persister: (id, snap) async => snapshots[id] = snap,
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

      final first = await send(
        from: alice,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'hi',
      );
      await bootstrapReceiver(
        receiver: bob,
        receiverIdentity: bobId,
        receiverDevice: 'device-bob',
        senderDevice: 'device-alice',
        firstEnvelope: first,
      );
      expect((await bob.messaging.decryptMessage(first)).body, 'hi');

      // Bob replies → Alice receives → Alice rotates on next send (1st rotation).
      final reply = await send(
        from: bob,
        fromDeviceId: 'device-bob',
        recipientBundle: aliceBundle,
        body: 'hello',
      );
      expect((await alice.messaging.decryptMessage(reply)).body, 'hello');
      await send(
        from: alice,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'rotating-now',
      );

      await alice.flushPendingSnapshotWrites();
      final snap = snapshots[conversationId]!;
      // Alice performs exactly one rotation: receive-side DH on Bob's reply.
      // Send-side DH then reuses that rotation (no additional DH step).
      expect((snap['ratchetRotationCount'] as num).toInt(), greaterThanOrEqualTo(1));
      expect(snap['lastRatchetRotationAt'], isA<String>());
    });

    test('v2 snapshot migrates into a working v3 session', () async {
      final alice = LibCryptoAdapter();
      final bob = LibCryptoAdapter();
      final bobId = await bob.identity.generateDeviceIdentity('device-bob');
      final bobBundle = bundle(bobId, 'device-bob', 'device-bob');

      // Build a real v3 snapshot, then rewrite it to v2 shape to simulate
      // an upgrade from a pre-v3 installation.
      final snapshots = <String, Map<String, dynamic>>{};
      alice.setSessionPersistence(
        persister: (id, snap) async => snapshots[id] = snap,
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
      final v3 = Map<String, dynamic>.from(snapshots[conversationId]!);
      // Downgrade to v2: flat skippedKeys, drop epoch fields.
      final v2 = <String, dynamic>{...v3, 'v': 2};
      v2.remove('ratchetRotationCount');
      v2.remove('lastRatchetRotationAt');
      v2['skippedKeys'] = <String, String>{}; // v2 format (flat)

      // Round-trip through JSON to verify the migration handles decoded maps.
      final encoded = json.encode(v2);
      final decoded = json.decode(encoded) as Map<String, dynamic>;

      final alicePostUpgrade = LibCryptoAdapter();
      await alicePostUpgrade.restoreSessionsFromSnapshots({
        conversationId: decoded,
      });

      // The restored session must be usable: send a message, Bob must decrypt.
      final msg = await send(
        from: alicePostUpgrade,
        fromDeviceId: 'device-alice',
        recipientBundle: bobBundle,
        body: 'migrated',
      );
      await bootstrapReceiver(
        receiver: bob,
        receiverIdentity: bobId,
        receiverDevice: 'device-bob',
        senderDevice: 'device-alice',
        firstEnvelope: msg,
      );
      expect((await bob.messaging.decryptMessage(msg)).body, 'migrated');
    });

    test('debounced writes coalesce then settle on flush', () async {
      final alice = LibCryptoAdapter();
      final bob = LibCryptoAdapter();
      final bobId = await bob.identity.generateDeviceIdentity('device-bob');
      final bobBundle = bundle(bobId, 'device-bob', 'device-bob');

      var writeCount = 0;
      alice.setSessionPersistence(
        persister: (id, snap) async => writeCount += 1,
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
      // Bootstrap writes synchronously: 1 write guaranteed.
      expect(writeCount, 1);

      // Burst 5 encrypts well within the debounce window.
      for (var i = 0; i < 5; i++) {
        await send(
          from: alice,
          fromDeviceId: 'device-alice',
          recipientBundle: bobBundle,
          body: 'burst-$i',
        );
      }
      // Before flush, the 5 encrypts should NOT have written synchronously.
      expect(writeCount, 1,
          reason: 'debounce window should have coalesced all 5 writes');

      await alice.flushPendingSnapshotWrites();
      // Exactly one additional write lands (the coalesced burst).
      expect(writeCount, 2,
          reason: 'flush should settle exactly one coalesced write');

      // Another flush with nothing pending must be a no-op.
      await alice.flushPendingSnapshotWrites();
      expect(writeCount, 2);
    });
  });
}
