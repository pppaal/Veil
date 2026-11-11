import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';

import 'support/crypto_harness.dart';

// Session records keep superseded states for in-flight messages, glare
// (both peers initiating at once) converges on one sending state, and an
// established conversation stays bound to its peer's identity.
void main() {
  const conversationId = 'conv-glare';

  Future<String> body(Party to, CryptoEnvelope envelope) async {
    final result = await receive(to, envelope);
    expect(result.status, DecryptStatus.ok, reason: result.failureReason);
    return result.body;
  }

  test('simultaneous initiation converges', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final aliceSnapshots = SnapshotRecorder();
    final bobSnapshots = SnapshotRecorder();
    alice.adapter.setSessionPersistence(persister: aliceSnapshots.call);
    bob.adapter.setSessionPersistence(persister: bobSnapshots.call);

    // Both open the chat and send before seeing the other's message.
    await bootstrap(alice, bob, conversationId: conversationId);
    await bootstrap(bob, alice, conversationId: conversationId);
    final a1 = await send(alice, bob, 'hi from alice', conversationId: conversationId);
    final b1 = await send(bob, alice, 'hi from bob', conversationId: conversationId);
    expect(await body(bob, a1), 'hi from alice');
    expect(await body(alice, b1), 'hi from bob');

    // The state initiated by the lower identity key wins on both sides.
    final aliceWins = compareBytes(
          b64uDecode(alice.identity.identityPublicKey),
          b64uDecode(bob.identity.identityPublicKey),
        ) <
        0;
    final winningBaseKey = b64uEncode(frameOf(aliceWins ? a1 : b1).preKey!.baseKey);
    String currentBaseKey(SnapshotRecorder recorder) =>
        (recorder.latest[conversationId]!['current'] as Map<String, dynamic>)['baseKey'] as String;
    expect(currentBaseKey(aliceSnapshots), winningBaseKey);
    expect(currentBaseKey(bobSnapshots), winningBaseKey);

    expect(await body(bob, await send(alice, bob, 'second from alice', conversationId: conversationId)),
        'second from alice');
    expect(await body(alice, await send(bob, alice, 'second from bob', conversationId: conversationId)),
        'second from bob');
    // One round trip later neither side repeats a handshake header.
    final a3 = await send(alice, bob, 'third from alice', conversationId: conversationId);
    final b3 = await send(bob, alice, 'third from bob', conversationId: conversationId);
    expect(frameOf(a3).preKey, isNull);
    expect(frameOf(b3).preKey, isNull);
    expect(await body(bob, a3), 'third from alice');
    expect(await body(alice, b3), 'third from bob');
    expect(currentBaseKey(aliceSnapshots), currentBaseKey(bobSnapshots));
  });

  test('rebootstrap keeps old state for in-flight messages', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    expect(await body(bob, await send(alice, bob, 'A0', conversationId: conversationId)), 'A0');
    expect(await body(alice, await send(bob, alice, 'B0', conversationId: conversationId)), 'B0');

    // In flight on the old session when Alice re-bootstraps.
    final oldFromAlice = await send(alice, bob, 'old from alice', conversationId: conversationId);
    final oldFromBob = await send(bob, alice, 'old from bob', conversationId: conversationId);
    await bootstrap(alice, bob, conversationId: conversationId);

    expect(await body(alice, oldFromBob), 'old from bob');
    final fresh = await send(alice, bob, 'new session', conversationId: conversationId);
    expect(frameOf(fresh).preKey, isNotNull);
    expect(await body(bob, fresh), 'new session');
    expect(await body(bob, oldFromAlice), 'old from alice');

    final reply = await send(bob, alice, 'reply on new session', conversationId: conversationId);
    expect(await body(alice, reply), 'reply on new session');
    expect(frameOf(await send(alice, bob, 'settled', conversationId: conversationId)).preKey, isNull);
  });

  test('a PreKey frame from another identity cannot take over an established conversation', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final mallory = await createParty('mallory');
    final bobSnapshots = SnapshotRecorder();
    bob.adapter.setSessionPersistence(persister: bobSnapshots.call);
    final prekey = (await bob.adapter.generateOneTimePrekeys(count: 1)).single;
    await bootstrap(alice, bob, conversationId: conversationId);
    expect(await body(bob, await send(alice, bob, 'a0', conversationId: conversationId)), 'a0');
    expect(await body(alice, await send(bob, alice, 'b0', conversationId: conversationId)), 'b0');
    final committed = bobSnapshots.latest[conversationId];
    final writes = bobSnapshots.writes.length;

    // No verifier is configured. A hostile server routes Mallory, who holds
    // a genuine identity of her own, into the conversation.
    await bootstrap(mallory, bob, conversationId: conversationId, oneTimePrekey: prekey);
    final injected = await receive(bob, await send(mallory, bob, 'hi', conversationId: conversationId));
    expect(injected.status, DecryptStatus.identityRejected);
    expect(injected.body, isNot('hi'));
    expect(bobSnapshots.writes, hasLength(writes));
    expect(bobSnapshots.latest[conversationId], committed);

    final reply = await send(bob, alice, 'secret for alice', conversationId: conversationId);
    expect(await body(alice, reply), 'secret for alice');
    expect((await receive(mallory, reply)).isOk, isFalse);

    // The rejected frame consumed nothing: its one-time prekey still opens
    // an unrelated conversation.
    final carol = await createParty('carol');
    await bootstrap(carol, bob, conversationId: 'conv-carol', oneTimePrekey: prekey);
    expect(await body(bob, await send(carol, bob, 'hi bob', conversationId: 'conv-carol')), 'hi bob');
  });

  test('legacy states pin no identity: a v2 handshake upgrades a v1 conversation', () async {
    final alice = await createParty('alice');
    final bob = await createLegacyParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    final first = await send(alice, bob, 'over v1', conversationId: conversationId);
    await acceptLegacy(bob, alice, first, conversationId: conversationId);
    expect((await receive(bob, first)).status, DecryptStatus.legacyUnauthenticated);

    final rotation = await bob.adapter.rotateSignedPrekey();
    await bootstrap(alice, bob, conversationId: conversationId, signedPrekeyBundle: rotation.signedPrekeyBundle);
    final upgraded = await send(alice, bob, 'over v2', conversationId: conversationId);
    expect(frameOf(upgraded).preKey, isNotNull);
    expect(await body(bob, upgraded), 'over v2');
  });
}
