import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';

import 'support/crypto_harness.dart';

// Concurrency and durability (audit PoC S3): every state transition runs
// under a per-conversation lock on a private copy, and is published only
// after the persister finished, so nothing can roll the ratchet back.
void main() {
  const conversationId = 'conv-concurrency';

  Future<(Party, Party)> establish() async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    expect((await receive(bob, await send(alice, bob, 'A0', conversationId: conversationId))).status, DecryptStatus.ok);
    return (alice, bob);
  }

  test('S3 concurrent own-envelope decrypt and encrypt never reuse a counter', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    final a0 = await send(alice, bob, 'A0', conversationId: conversationId);
    expect((await receive(bob, a0)).body, 'A0');

    // The chat screen re-renders Alice's own bubble while she sends.
    final results = await Future.wait<Object>([
      receive(alice, a0),
      send(alice, bob, 'A1', conversationId: conversationId),
    ]);
    expect((results[0] as DecryptedMessage).isOk, isFalse);
    final a1 = results[1] as CryptoEnvelope;
    final a2 = await send(alice, bob, 'A2', conversationId: conversationId);

    expect(frameOf(a1).counter, 1);
    expect(frameOf(a2).counter, 2);
    expect((await receive(bob, a1)).body, 'A1');
    expect((await receive(bob, a2)).body, 'A2');
  });

  test('fuzzed interleaving stays in sync', () async {
    for (var seed = 0; seed < 5; seed++) {
      final rng = Random(seed);
      final (alice, bob) = await establish();
      // A persister with random latency widens every await window.
      Future<void> slowPersist(String _, Map<String, dynamic> __) =>
          Future<void>.delayed(Duration(microseconds: rng.nextInt(400)));
      alice.adapter.setSessionPersistence(persister: slowPersist);
      bob.adapter.setSessionPersistence(persister: slowPersist);

      final pending = <Future<void>>[];
      final sent = <({CryptoEnvelope envelope, Party to, String body})>[];
      for (var round = 0; round < 6; round++) {
        final ops = <Future<void>>[];
        for (var i = 0; i < 4; i++) {
          final aliceActs = rng.nextBool();
          final me = aliceActs ? alice : bob;
          final peer = aliceActs ? bob : alice;
          final text = 'seed $seed round $round op $i';
          switch (rng.nextInt(3)) {
            case 0:
              ops.add(send(me, peer, text, conversationId: conversationId)
                  .then((e) => sent.add((envelope: e, to: peer, body: text))));
            case 1:
              // Re-decrypting something we sent ourselves must fail without
              // disturbing the sending chain.
              final own = sent.where((s) => s.to == peer).toList();
              if (own.isNotEmpty) {
                ops.add(receive(me, own[rng.nextInt(own.length)].envelope).then((r) => expect(r.isOk, isFalse)));
              }
            default:
              final forged = sent.where((s) => s.to == me).toList();
              if (forged.isNotEmpty) {
                final target = forged[rng.nextInt(forged.length)].envelope;
                final bytes = b64uDecode(target.ciphertext)..[target.ciphertext.length ~/ 2] ^= 0x40;
                ops.add(receive(me, copyEnvelope(target, ciphertext: b64uEncode(bytes)))
                    .then((r) => expect(r.isOk, isFalse)));
              }
          }
        }
        pending.addAll(ops);
        await Future.wait(ops);
        // Deliver everything sent this round, concurrently and shuffled.
        final batch = List.of(sent.where((s) => !s.body.endsWith('#done')))..shuffle(rng);
        await Future.wait([
          for (final item in batch)
            receive(item.to, item.envelope).then((r) {
              expect(r.status, DecryptStatus.ok, reason: 'seed $seed: ${item.body} (${r.failureReason})');
              expect(r.body, item.body);
            }),
        ]);
        for (final item in batch) {
          sent[sent.indexOf(item)] = (envelope: item.envelope, to: item.to, body: '${item.body}#done');
        }
      }
      await Future.wait(pending);

      final headers = sent.map((s) {
        final frame = frameOf(s.envelope);
        return '${s.to.name}|${b64uEncode(frame.ratchetPublic)}|${frame.counter}';
      }).toList();
      expect(headers.toSet().length, headers.length, reason: 'seed $seed reused a (ratchet key, counter)');
      expect((await receive(bob, await send(alice, bob, 'final A', conversationId: conversationId))).body, 'final A');
      expect((await receive(alice, await send(bob, alice, 'final B', conversationId: conversationId))).body, 'final B');
    }
  });

  test('encrypt completes only after persister completes', () async {
    final (alice, bob) = await establish();
    final gate = Completer<void>();
    Map<String, dynamic>? persisted;
    alice.adapter.setSessionPersistence(persister: (_, snapshot) async {
      persisted = snapshot;
      await gate.future;
    });

    var completed = false;
    final sending =
        send(alice, bob, 'durable first', conversationId: conversationId).whenComplete(() => completed = true);
    await pumpEventQueue();
    expect(persisted, isNotNull, reason: 'the persister must be invoked');
    expect((persisted!['current'] as Map<String, dynamic>)['sendCounter'], 2);
    expect(completed, isFalse, reason: 'ciphertext must not escape before the state is durable');

    // A flush waits for the in-flight write too.
    var flushed = false;
    final flushing = alice.adapter.flushPendingSnapshotWrites().whenComplete(() => flushed = true);
    await pumpEventQueue();
    expect(flushed, isFalse);

    gate.complete();
    final envelope = await sending;
    await flushing;
    expect(completed && flushed, isTrue);
    expect((await receive(bob, envelope)).body, 'durable first');

    // A failed write publishes nothing: the counter is not consumed.
    alice.adapter.setSessionPersistence(persister: (_, __) async => throw StateError('disk full'));
    await expectLater(send(alice, bob, 'lost', conversationId: conversationId), throwsStateError);
    alice.adapter.setSessionPersistence(persister: null);
    final next = await send(alice, bob, 'after failure', conversationId: conversationId);
    expect(frameOf(next).counter, frameOf(envelope).counter + 1);
    expect((await receive(bob, next)).body, 'after failure');
  });
}
