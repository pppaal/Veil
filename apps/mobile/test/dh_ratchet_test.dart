import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

import 'crypto/support/crypto_harness.dart';

// Exercises the DH ratchet on top of the symmetric hash ratchet:
//   - conversational turn-flips rotate the sender's ratchet pub on the wire
//   - the peer performs a receive DH step, producing a fresh chain
//   - persisted session snapshots restore into a fresh adapter that
//     continues the same chain without re-bootstrap.
void main() {
  const conversationId = 'conv-dh';

  List<int> ratchetPubFrom(CryptoEnvelope envelope) => frameOf(envelope).ratchetPublic;

  test('sender rotates its ratchet pub once per turn-flip, not per message', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);

    // Alice sends 3 messages in a row without receiving: same ratchet pub.
    final a0 = await send(alice, bob, 'a0', conversationId: conversationId);
    final a1 = await send(alice, bob, 'a1', conversationId: conversationId);
    final a2 = await send(alice, bob, 'a2', conversationId: conversationId);
    expect(ratchetPubFrom(a1), ratchetPubFrom(a0));
    expect(ratchetPubFrom(a2), ratchetPubFrom(a0));

    expect((await receive(bob, a0)).body, 'a0');
    expect((await receive(bob, a1)).body, 'a1');
    expect((await receive(bob, a2)).body, 'a2');

    // Bob's first reply MUST rotate his ratchet pub. Second reply without an
    // intervening receive must NOT rotate.
    final b0 = await send(bob, alice, 'b0', conversationId: conversationId);
    final b1 = await send(bob, alice, 'b1', conversationId: conversationId);
    expect(ratchetPubFrom(b0), isNot(ratchetPubFrom(a0)), reason: 'first send after receive should rotate DH');
    expect(ratchetPubFrom(b1), ratchetPubFrom(b0), reason: 'no new receive since last send, no rotation');

    // Alice must agree on the chain Bob's DH step produced.
    expect((await receive(alice, b0)).body, 'b0');
    expect((await receive(alice, b1)).body, 'b1');
  });

  test('ping-pong across many turns advances DH every turn-flip', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);

    final first = await send(alice, bob, 'alice-0', conversationId: conversationId);
    expect((await receive(bob, first)).body, 'alice-0');
    final ratchetHistory = <String>{base64Url.encode(ratchetPubFrom(first))};

    var aliceTurn = false;
    for (var turn = 1; turn <= 12; turn++) {
      final sender = aliceTurn ? alice : bob;
      final receiver = aliceTurn ? bob : alice;
      final env = await send(sender, receiver, 'turn-$turn', conversationId: conversationId);
      final key = base64Url.encode(ratchetPubFrom(env));
      expect(ratchetHistory.contains(key), isFalse, reason: 'turn $turn should use a fresh ratchet pub');
      ratchetHistory.add(key);
      expect((await receive(receiver, env)).body, 'turn-$turn');
      aliceTurn = !aliceTurn;
    }
  });

  test('session snapshot round-trips: restored state decrypts next message', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final snapshots = SnapshotRecorder();
    alice.adapter.setSessionPersistence(persister: snapshots.call);
    await bootstrap(alice, bob, conversationId: conversationId);

    for (var i = 0; i < 4; i++) {
      expect((await receive(bob, await send(alice, bob, 'pre-$i', conversationId: conversationId))).body, 'pre-$i');
    }
    // Every commit is persisted before the operation returns: no flush.
    final aliceRestarted = Party('alice', LibCryptoAdapter(), alice.identity);
    await aliceRestarted.adapter.restoreSessionsFromSnapshots(snapshots.latest);

    final afterRestart = await send(aliceRestarted, bob, 'post-restart', conversationId: conversationId);
    expect(frameOf(afterRestart).counter, 4);
    expect((await receive(bob, afterRestart)).body, 'post-restart');
  });

  test('restored alice can still rotate DH after receiving from bob', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final snapshots = SnapshotRecorder();
    alice.adapter.setSessionPersistence(persister: snapshots.call);
    await bootstrap(alice, bob, conversationId: conversationId);

    final first = await send(alice, bob, 'a0', conversationId: conversationId);
    expect((await receive(bob, first)).body, 'a0');
    expect((await receive(alice, await send(bob, alice, 'b0', conversationId: conversationId))).body, 'b0');

    // The snapshot captured after Alice processed Bob's reply carries the
    // pending send step.
    final aliceRestarted = Party('alice', LibCryptoAdapter(), alice.identity);
    await aliceRestarted.adapter.restoreSessionsFromSnapshots(snapshots.latest);

    final afterRestart = await send(aliceRestarted, bob, 'post-restart', conversationId: conversationId);
    expect(ratchetPubFrom(afterRestart), isNot(ratchetPubFrom(first)),
        reason: 'restart + queued turn-flip must rotate DH on next send');
    expect(frameOf(afterRestart).preKey, isNull, reason: 'Bob replied, so the handshake header is dropped');
    expect((await receive(bob, afterRestart)).body, 'post-restart');
  });
}
