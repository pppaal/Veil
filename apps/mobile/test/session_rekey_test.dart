import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

import 'crypto/support/crypto_harness.dart';

// "Rotate keys" UX: forceRekeyNextSend arms a DH ratchet step on the next
// send even without an intervening receive, and drops skipped keys so
// pre-rotation stragglers stop decrypting.
void main() {
  const conversationId = 'conv-rekey';

  List<int> ratchetPubFrom(CryptoEnvelope envelope) => frameOf(envelope).ratchetPublic;

  group('forceRekeyNextSend', () {
    test('returns false when no session exists', () async {
      expect(await LibCryptoAdapter().forceRekeyNextSend(conversationId), isFalse);
    });

    test('arms a fresh DH ratchet step on the next send', () async {
      final alice = await createParty('alice');
      final bob = await createParty('bob');
      await bootstrap(alice, bob, conversationId: conversationId);

      final a0 = await send(alice, bob, 'a0', conversationId: conversationId);
      final a1 = await send(alice, bob, 'a1', conversationId: conversationId);
      expect(ratchetPubFrom(a1), ratchetPubFrom(a0));

      expect(await alice.adapter.forceRekeyNextSend(conversationId), isTrue);
      final a2 = await send(alice, bob, 'a2', conversationId: conversationId);
      expect(ratchetPubFrom(a2), isNot(equals(ratchetPubFrom(a0))));
      expect(frameOf(a2).previousCounter, 2);

      // A subsequent send without another rekey reuses a2's ratchet pub.
      final a3 = await send(alice, bob, 'a3', conversationId: conversationId);
      expect(ratchetPubFrom(a3), equals(ratchetPubFrom(a2)));
    });

    test('peer decrypts post-rotation envelope end-to-end', () async {
      final alice = await createParty('alice');
      final bob = await createParty('bob');
      await bootstrap(alice, bob, conversationId: conversationId);

      final first = await send(alice, bob, 'pre-rekey', conversationId: conversationId);
      expect((await receive(bob, first)).body, 'pre-rekey');

      expect(await alice.adapter.forceRekeyNextSend(conversationId), isTrue);
      final rotated = await send(alice, bob, 'post-rekey', conversationId: conversationId);
      expect(ratchetPubFrom(rotated), isNot(equals(ratchetPubFrom(first))));
      expect((await receive(bob, rotated)).body, 'post-rekey');

      final reply = await send(bob, alice, 'ack', conversationId: conversationId);
      expect((await receive(alice, reply)).body, 'ack');
    });

    test('rekey clears skipped-key stash and persists immediately', () async {
      final alice = await createParty('alice');
      final bob = await createParty('bob');
      final snapshots = SnapshotRecorder();
      bob.adapter.setSessionPersistence(persister: snapshots.call);
      await bootstrap(alice, bob, conversationId: conversationId);

      final a0 = await send(alice, bob, 'a0', conversationId: conversationId);
      final straggler = await send(alice, bob, 'a1', conversationId: conversationId);
      final a2 = await send(alice, bob, 'a2', conversationId: conversationId);
      expect((await receive(bob, a0)).isOk, isTrue);
      expect((await receive(bob, a2)).isOk, isTrue);
      Map<String, dynamic> current() => snapshots.latest[conversationId]!['current'] as Map<String, dynamic>;
      expect((current()['skippedKeys'] as Map).length, 1);
      final writesBefore = snapshots.writes.length;

      expect(await bob.adapter.forceRekeyNextSend(conversationId), isTrue);
      expect(snapshots.writes.length, writesBefore + 1);
      expect(snapshots.latest[conversationId]!['v'], 4);
      expect((current()['skippedKeys'] as Map), isEmpty);
      expect(current()['hasReceivedSinceLastSend'], isTrue);
      // The user asked for pre-rotation stragglers to stop decrypting.
      expect((await receive(bob, straggler)).isOk, isFalse);
    });
  });
}
