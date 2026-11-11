import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';

import 'support/crypto_harness.dart';

// Session records keep superseded states for in-flight messages, and glare
// (both peers initiating at once) converges on one sending state.
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
}
