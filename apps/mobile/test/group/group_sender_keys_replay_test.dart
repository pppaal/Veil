import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/group_sender_keys.dart';

import 'support/group_fixtures.dart';

// Regression tests for the distribution replay / rollback findings: the relay
// sees and can record every sealed distribution, so re-delivering one must
// never rewind a chain or bring back a chain the sender rotated away.

void main() {
  late TestIdentity aliceId;
  late TestIdentity bobId;
  late IdentityDirectory directory;
  late GroupSenderKeyEngine alice;
  late GroupSenderKeyEngine bob;

  setUp(() async {
    aliceId = await TestIdentity.generate(userId: 'user-alice', deviceId: 'dev-alice', handle: 'alice');
    bobId = await TestIdentity.generate(userId: 'user-bob', deviceId: 'dev-bob', handle: 'bob');
    directory = IdentityDirectory()
      ..add(aliceId)
      ..add(bobId);
    alice = GroupSenderKeyEngine();
    bob = GroupSenderKeyEngine();
  });

  Future<GroupSenderKey> aliceKey({bool rotate = false}) => alice.ensureOwnSenderKey(
        groupId: groupId,
        epoch: 0,
        localDeviceId: aliceId.deviceId,
        forceRotate: rotate,
      );

  Future<SealedGroupSenderKey> sealToBob(GroupSenderKey key, {DateTime Function()? clock}) =>
      directory.sealer(clock: clock).seal(
            key: key,
            recipientUserId: bobId.userId,
            recipientIdentityPublicKey: bobId.identityPublicKey,
            recipientSignedPrekeyBundle: bobId.signedPrekeyBundle,
            senderIdentityEd25519Seed: aliceId.ed25519Seed,
          );

  // What the coordinator does with a blob the relay hands bob.
  Future<bool> deliver(SealedGroupSenderKey sealed, {GroupSenderKeyEngine? to}) async {
    final distribution = await directory.sealer().unseal(
          groupId: groupId,
          epoch: 0,
          senderDeviceId: aliceId.deviceId,
          localUserId: bobId.userId,
          encryptedChainKey: sealed.encryptedChainKey,
          nonce: sealed.nonce,
          version: sealed.version,
          localIdentityX25519Private: bobId.x25519Private,
          senderIdentityPublicKey: aliceId.identityPublicKey,
        );
    return (to ?? bob).ingestDistribution(distribution);
  }

  Future<GroupCiphertext> send(String text) =>
      alice.encrypt(groupId: groupId, localDeviceId: aliceId.deviceId, plaintext: utf8.encode(text));

  Future<String> recv(GroupCiphertext ct, {GroupSenderKeyEngine? by}) async {
    final out = await (by ?? bob).decrypt(groupId: groupId, payload: ct.payload, nonce: ct.nonce);
    return utf8.decode(out.plaintext);
  }

  test('re-delivered distribution is a no-op and replayed frame stays replayed', () async {
    final distribution = await sealToBob(await aliceKey());
    expect(await deliver(distribution), isTrue);

    final f1 = await send('F1');
    expect(await recv(f1), 'F1');
    expect(await errorCode(() => recv(f1)), 'replayed');

    // The relay re-delivers the blob it recorded.
    expect(await deliver(distribution), isFalse);
    expect(await errorCode(() => recv(f1)), 'replayed');

    final f2 = await send('F2');
    expect(await recv(f2), 'F2');
  });

  test('pre-rotation distribution rejected after forceRotate', () async {
    final first = await sealToBob(await aliceKey());
    expect(await deliver(first), isTrue);
    final beforeRotation = await send('before');
    expect(await recv(beforeRotation), 'before');

    final rotated = await aliceKey(rotate: true);
    expect(rotated.generation, 2);
    expect(await deliver(await sealToBob(rotated)), isTrue);

    expect(await errorCode(() => deliver(first)), 'distribution_stale');
    // The retired chain and signing key stayed retired.
    expect(await errorCode(() => recv(beforeRotation)), 'signatureInvalid');
    expect(await recv(await send('after')), 'after');
  });

  test('v1 distribution cannot replace an installed chain', () async {
    final key = await aliceKey();
    final legacy = await sealLegacyV1(key: key, sender: aliceId, recipient: bobId);

    // Older clients still get a first chain installed from a v1 blob.
    expect(await deliver(legacy, to: GroupSenderKeyEngine()), isTrue);

    expect(await deliver(await sealToBob(key)), isTrue);
    final f1 = await send('F1');
    expect(await recv(f1), 'F1');

    expect(await errorCode(() => deliver(legacy)), 'distribution_stale');
    expect(await errorCode(() => recv(f1)), 'replayed');
  });

  test('distribution issued >30 min ago cannot replace chain', () async {
    expect(await deliver(await sealToBob(await aliceKey())), isTrue);
    final rotated = await aliceKey(rotate: true);
    final afterRotation = await send('after rotation');

    final stale = await sealToBob(
      rotated,
      clock: () => DateTime.now().subtract(const Duration(minutes: 31)),
    );
    expect(await errorCode(() => deliver(stale)), 'distribution_stale');
    expect(await errorCode(() => recv(afterRotation)), 'signatureInvalid');

    // The same chain re-issued now is accepted.
    expect(await deliver(await sealToBob(rotated)), isTrue);
    expect(await recv(afterRotation), 'after rotation');
  });

  test('distribution issued beyond the clock-skew allowance cannot replace chain', () async {
    expect(await deliver(await sealToBob(await aliceKey())), isTrue);
    final future = await sealToBob(
      await aliceKey(rotate: true),
      clock: () => DateTime.now().add(const Duration(minutes: 6)),
    );
    expect(await errorCode(() => deliver(future)), 'distribution_stale');
  });

  test('a different signing key at the same generation is rejected', () async {
    expect(await deliver(await sealToBob(await aliceKey())), isTrue);
    // alice lost her state and started over at generation 1 with a new key.
    alice = GroupSenderKeyEngine();
    final restarted = await aliceKey();
    expect(restarted.generation, 1);
    final conflicting = await sealToBob(restarted);
    expect(await errorCode(() => deliver(conflicting)), 'distribution_stale');
  });

  test('a dropped chain is not reinstalled below what was consumed', () async {
    final distribution = await sealToBob(await aliceKey());
    expect(await deliver(distribution), isTrue);
    final f1 = await send('F1');
    expect(await recv(f1), 'F1');

    await bob.dropPeer(groupId: groupId, senderDeviceId: aliceId.deviceId);
    expect(await deliver(distribution), isFalse);
    expect(await errorCode(() => recv(f1)), 'senderKeyMissing');

    // A redistribution that starts after the consumed frames is fine.
    expect(await deliver(await sealToBob(alice.exportOwnSenderKey(groupId)!)), isTrue);
    expect(await recv(await send('F2')), 'F2');
  });

  test('skipped group keys expire after 7 days (injected clock)', () async {
    var now = DateTime.utc(2026, 11, 1);
    final receiver = GroupSenderKeyEngine(clock: () => now);
    expect(await deliver(await sealToBob(await aliceKey()), to: receiver), isTrue);
    final frames = [for (var i = 0; i < 4; i++) await send('m$i')];

    // Receiving 1 and 3 first stashes the keys for 0 and 2.
    expect(await recv(frames[1], by: receiver), 'm1');
    expect(await recv(frames[3], by: receiver), 'm3');

    now = now.add(const Duration(days: 6));
    expect(await recv(frames[0], by: receiver), 'm0');

    now = now.add(const Duration(days: 1, minutes: 1));
    expect(await errorCode(() => recv(frames[2], by: receiver)), 'replayed');
  });

  test('restore purges skipped keys past the TTL', () async {
    var now = DateTime.utc(2026, 11, 1);
    final persisted = <String, Map<String, dynamic>?>{};
    final receiver = GroupSenderKeyEngine(
      clock: () => now,
      persister: (id, snapshot) async => persisted[id] = snapshot,
    );
    expect(await deliver(await sealToBob(await aliceKey()), to: receiver), isTrue);
    final f0 = await send('m0');
    final f1 = await send('m1');
    expect(await recv(f1, by: receiver), 'm1');

    now = now.add(const Duration(days: 8));
    final restored = GroupSenderKeyEngine(
      clock: () => now,
      persister: (id, snapshot) async => persisted[id] = snapshot,
    );
    await restored.restoreFromSnapshots({groupId: persisted[groupId]!});
    expect(await errorCode(() => recv(f0, by: restored)), 'replayed');
    final senders = persisted[groupId]!['senders'] as Map<String, dynamic>;
    final chain = (senders[aliceId.deviceId] as Map<String, dynamic>)['chain'] as Map<String, dynamic>;
    expect(chain['skipped'], isEmpty);
  });

  test('stashed keys are capped per sender chain', () async {
    expect(await deliver(await sealToBob(await aliceKey())), isTrue);
    final frames = [for (var i = 0; i <= kMaxSkippedKeysPerSender + 1; i++) await send('m$i')];

    // Jumping to the last frame stashes one key too many; the oldest goes.
    expect(await recv(frames.last), 'm${kMaxSkippedKeysPerSender + 1}');
    expect(await errorCode(() => recv(frames[0])), 'replayed');
    expect(await recv(frames[1]), 'm1');
  });

  test('stashed keys are capped across the group, oldest first', () async {
    var now = DateTime.utc(2026, 11, 1);
    final receiver = GroupSenderKeyEngine(clock: () => now);
    final lastFrames = <String, GroupCiphertext>{};
    final firstFrames = <String, GroupCiphertext>{};
    for (var s = 0; s < 6; s++) {
      final deviceId = 'dev-$s';
      final sender = GroupSenderKeyEngine();
      final key = await sender.ensureOwnSenderKey(groupId: groupId, epoch: 0, localDeviceId: deviceId);
      await receiver.ingestDistribution(
        GroupKeyDistribution(key: key, issuedAtMs: now.millisecondsSinceEpoch),
      );
      final frames = [
        for (var i = 0; i <= kMaxSkippedKeysPerSender; i++)
          await sender.encrypt(groupId: groupId, localDeviceId: deviceId, plaintext: utf8.encode('$s/$i')),
      ];
      firstFrames[deviceId] = frames.first;
      lastFrames[deviceId] = frames.last;
    }
    // Each sender's stash lands a minute after the previous one's: 6 x 200
    // keys exceed the group cap by 200, so the first sender's stash goes.
    for (final entry in lastFrames.entries) {
      await recv(entry.value, by: receiver);
      now = now.add(const Duration(minutes: 1));
    }
    expect(await errorCode(() => recv(firstFrames['dev-0']!, by: receiver)), 'replayed');
    expect(await recv(firstFrames['dev-1']!, by: receiver), '1/0');
  });

  test('concurrent decrypts on one group serialize', () async {
    var inFlight = 0;
    var maxInFlight = 0;
    final receiver = GroupSenderKeyEngine(
      persister: (_, __) async {
        inFlight++;
        if (inFlight > maxInFlight) maxInFlight = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        inFlight--;
      },
    );
    expect(await deliver(await sealToBob(await aliceKey()), to: receiver), isTrue);
    final frames = [for (var i = 0; i < 8; i++) await send('m$i')];

    final texts = await Future.wait([
      for (final frame in frames.reversed) recv(frame, by: receiver),
    ]);
    expect(texts, [for (var i = 7; i >= 0; i--) 'm$i']);
    expect(maxInFlight, 1);
    for (final frame in frames) {
      expect(await errorCode(() => recv(frame, by: receiver)), 'replayed');
    }
  });

  test('epochs never move backwards', () async {
    await bob.resetForEpoch(groupId: groupId, epoch: 3);
    await bob.resetForEpoch(groupId: groupId, epoch: 1);
    expect(bob.currentEpoch(groupId), 3);
    expect(
      await errorCode(() => bob.ensureOwnSenderKey(groupId: groupId, epoch: 2, localDeviceId: bobId.deviceId)),
      'epochMismatch',
    );
  });
}
