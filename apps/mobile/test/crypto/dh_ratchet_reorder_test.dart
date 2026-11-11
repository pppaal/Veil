import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';

import 'support/crypto_harness.dart';

// Reordering across DH ratchet steps (audit PoC S1/S2): with PN in the
// header the receiver stashes the previous chain's remaining keys before
// stepping, and a stashed straggler never triggers a DH step.
void main() {
  const conversationId = 'conv-reorder';

  Future<(Party, Party)> establish() async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    return (alice, bob);
  }

  Future<String> body(Party to, CryptoEnvelope envelope) async {
    final result = await receive(to, envelope);
    expect(result.status, DecryptStatus.ok, reason: 'expected to decrypt: ${result.failureReason}');
    return result.body;
  }

  test('S1 late message from previous chain decrypts', () async {
    final (alice, bob) = await establish();
    expect(await body(bob, await send(alice, bob, 'A0', conversationId: conversationId)), 'A0');
    final a1Late = await send(alice, bob, 'A1-late', conversationId: conversationId);
    expect(await body(alice, await send(bob, alice, 'B1', conversationId: conversationId)), 'B1');
    final a2 = await send(alice, bob, 'A2', conversationId: conversationId);
    expect(frameOf(a2).previousCounter, 2);
    expect(await body(bob, a2), 'A2');
    expect(await body(bob, a1Late), 'A1-late');
  });

  test('S2 straggler does not corrupt; A4 and B2 decrypt', () async {
    final (alice, bob) = await establish();
    final a0 = await send(alice, bob, 'A0', conversationId: conversationId);
    final a1 = await send(alice, bob, 'A1', conversationId: conversationId);
    final a2 = await send(alice, bob, 'A2', conversationId: conversationId);
    expect(await body(bob, a0), 'A0');
    expect(await body(bob, a2), 'A2');
    expect(await body(alice, await send(bob, alice, 'B1', conversationId: conversationId)), 'B1');
    expect(await body(bob, await send(alice, bob, 'A3', conversationId: conversationId)), 'A3');
    expect(await body(bob, a1), 'A1');
    expect(await body(bob, await send(alice, bob, 'A4', conversationId: conversationId)), 'A4');
    expect(await body(alice, await send(bob, alice, 'B2', conversationId: conversationId)), 'B2');
  });

  test('20 seeded shuffles of 10 turn flips x 1-5 msgs with <=3 delays decrypt exactly once', () async {
    for (var seed = 0; seed < 20; seed++) {
      final rng = Random(seed);
      final (alice, bob) = await establish();
      final delayed = <({int releaseTurn, CryptoEnvelope envelope, Party to, String body})>[];
      final delivered = <({CryptoEnvelope envelope, Party to})>[];
      var delaysLeft = 3;

      Future<void> deliver(CryptoEnvelope envelope, Party to, String expected) async {
        expect(await body(to, envelope), expected, reason: 'seed $seed');
        delivered.add((envelope: envelope, to: to));
      }

      Future<void> release(bool Function(int releaseTurn) due) async {
        final ready = delayed.where((d) => due(d.releaseTurn)).toList()..shuffle(rng);
        for (final d in ready) {
          delayed.remove(d);
          await deliver(d.envelope, d.to, d.body);
        }
      }

      for (var turn = 0; turn < 10; turn++) {
        await release((releaseTurn) => releaseTurn <= turn);
        final aliceSends = turn.isEven;
        final from = aliceSends ? alice : bob;
        final to = aliceSends ? bob : alice;
        final count = 1 + rng.nextInt(5);
        for (var i = 0; i < count; i++) {
          final text = 'seed $seed turn $turn msg $i';
          final envelope = await send(from, to, text, conversationId: conversationId);
          // The very first frame is never held back, so Bob has a session
          // before his first turn (simultaneous initiation is covered by the
          // glare tests).
          final isFirst = turn == 0 && i == 0;
          if (!isFirst && delaysLeft > 0 && rng.nextInt(4) == 0) {
            delaysLeft -= 1;
            delayed.add((releaseTurn: turn + 1 + rng.nextInt(10 - turn), envelope: envelope, to: to, body: text));
          } else {
            await deliver(envelope, to, text);
          }
        }
      }
      await release((_) => true);

      final sample = List.of(delivered)..shuffle(rng);
      for (final replay in sample.take(3)) {
        expect((await receive(replay.to, replay.envelope)).status, DecryptStatus.replayed, reason: 'seed $seed');
      }
      expect(await body(bob, await send(alice, bob, 'after A', conversationId: conversationId)), 'after A');
      expect(await body(alice, await send(bob, alice, 'after B', conversationId: conversationId)), 'after B');
    }
  });

  test('consumed message returns replayed', () async {
    final (alice, bob) = await establish();
    final a0 = await send(alice, bob, 'A0', conversationId: conversationId);
    final a1 = await send(alice, bob, 'A1', conversationId: conversationId);
    final a2 = await send(alice, bob, 'A2', conversationId: conversationId);
    expect(await body(bob, a0), 'A0');
    expect(await body(bob, a2), 'A2');
    expect(await body(bob, a1), 'A1');

    for (final envelope in [a0, a1, a2]) {
      final again = await receive(bob, envelope);
      expect(again.status, DecryptStatus.replayed);
      expect(again.body, '[Replayed or out-of-window message]');
    }

    // Across a turn: Alice's first-chain frames stay replays after Bob's
    // DH step moved past that chain.
    expect(await body(alice, await send(bob, alice, 'B0', conversationId: conversationId)), 'B0');
    expect(await body(bob, await send(alice, bob, 'A3', conversationId: conversationId)), 'A3');
    expect((await receive(bob, a1)).status, DecryptStatus.replayed);
  });
}
