import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/ratchet/session_record.dart';

import 'support/crypto_harness.dart';

// Session records keep superseded states for in-flight messages, glare
// (both peers initiating at once) converges on one sending state whatever
// order frames arrive in, and an established conversation stays bound to
// its peer's identity.
void main() {
  const conversationId = 'conv-glare';
  final start = DateTime.utc(2026, 11, 1);
  var now = start;
  final snapshots = <Party, SnapshotRecorder>{};

  setUp(() {
    now = start;
    snapshots.clear();
  });

  Future<String> body(Party to, CryptoEnvelope envelope) async {
    final result = await receive(to, envelope);
    expect(result.status, DecryptStatus.ok, reason: result.failureReason);
    return result.body;
  }

  Future<Party> recordedParty(String name) async {
    final party = await createParty(name, clock: () => now);
    final recorder = SnapshotRecorder();
    party.adapter.setSessionPersistence(persister: recorder.call);
    snapshots[party] = recorder;
    return party;
  }

  /// Two fresh parties ordered by identity key: the glare tie-break favours
  /// the state initiated by the lower one.
  Future<(Party, Party)> lowAndHigh() async {
    final alice = await recordedParty('alice');
    final bob = await recordedParty('bob');
    final aliceIsLower = compareBytes(
          b64uDecode(alice.identity.identityPublicKey),
          b64uDecode(bob.identity.identityPublicKey),
        ) <
        0;
    return aliceIsLower ? (alice, bob) : (bob, alice);
  }

  String currentBaseKey(Party party, String conversationId) =>
      (snapshots[party]!.latest[conversationId]!['current'] as Map<String, dynamic>)['baseKey'] as String;

  /// Strictly alternating turns of two messages, [first] speaking first.
  /// After [settleTurns] turns the conversation must be healthy: both
  /// records share one current state, no frame repeats a handshake header,
  /// and every turn brings a fresh sending ratchet key (the DH ratchet still
  /// heals), including after the archive retention window has passed.
  Future<void> expectConvergesAndHeals(
    Party first,
    Party second, {
    required String conversationId,
    int settleTurns = 2,
  }) async {
    final previousKey = <Party, String>{};
    var index = 0;
    Future<void> turn({required bool settled}) async {
      final (from, to) = index.isEven ? (first, second) : (second, first);
      String? turnKey;
      for (var message = 0; message < 2; message++) {
        final text = '${from.name} turn $index.$message';
        final envelope = await send(from, to, text, conversationId: conversationId);
        final frame = frameOf(envelope);
        turnKey ??= b64uEncode(frame.ratchetPublic);
        expect(b64uEncode(frame.ratchetPublic), turnKey, reason: 'one sending chain per turn');
        if (settled) expect(frame.preKey, isNull, reason: 'turn $index still repeats the handshake');
        expect(await body(to, envelope), text);
      }
      expect(turnKey, isNot(previousKey[from]), reason: '${from.name} did not ratchet on turn $index');
      previousKey[from] = turnKey!;
      index++;
    }

    for (var i = 0; i < settleTurns; i++) {
      await turn(settled: false);
    }
    for (var i = 0; i < 4; i++) {
      await turn(settled: true);
    }
    expect(currentBaseKey(first, conversationId), currentBaseKey(second, conversationId));

    now = now.add(archivedStateRetention + const Duration(days: 1));
    for (var i = 0; i < 4; i++) {
      await turn(settled: true);
    }
    expect(currentBaseKey(first, conversationId), currentBaseKey(second, conversationId));
  }

  test('simultaneous initiation converges', () async {
    final alice = await recordedParty('alice');
    final bob = await recordedParty('bob');

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
    expect(currentBaseKey(alice, conversationId), winningBaseKey);
    expect(currentBaseKey(bob, conversationId), winningBaseKey);

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
    expect(currentBaseKey(alice, conversationId), currentBaseKey(bob, conversationId));
  });

  test('glare converges when the PreKey frame arrives after the reply', () async {
    for (final lowSpeaksFirst in [true, false]) {
      final conversationId = 'conv-late-prekey-$lowSpeaksFirst';
      final (low, high) = await lowAndHigh();
      await bootstrap(low, high, conversationId: conversationId);
      await bootstrap(high, low, conversationId: conversationId);
      final highPreKey = await send(high, low, 'high opens', conversationId: conversationId);
      final lowPreKey = await send(low, high, 'low opens', conversationId: conversationId);

      // High adopts low's handshake and answers on it; the server holds back
      // high's own PreKey frame until after that answer.
      expect(await body(high, lowPreKey), 'low opens');
      final highReply = await send(high, low, 'high answers', conversationId: conversationId);
      expect(frameOf(highReply).preKey, isNull);
      expect(await body(low, highReply), 'high answers');
      expect(await body(low, highPreKey), 'high opens');

      await expectConvergesAndHeals(
        lowSpeaksFirst ? low : high,
        lowSpeaksFirst ? high : low,
        conversationId: conversationId,
      );
    }
  });

  test('bootstrapping over an unanswered responder state converges', () async {
    for (final responderIsLow in [true, false]) {
      final conversationId = 'conv-unanswered-$responderIsLow';
      final (low, high) = await lowAndHigh();
      final (initiator, responder) = responderIsLow ? (high, low) : (low, high);
      await bootstrap(initiator, responder, conversationId: conversationId);
      expect(await body(responder, await send(initiator, responder, 'first', conversationId: conversationId)),
          'first');

      // The responder opens its own handshake before ever replying.
      await bootstrap(responder, initiator, conversationId: conversationId);
      final second = await send(responder, initiator, 'second', conversationId: conversationId);
      expect(frameOf(second).preKey, isNotNull);
      expect(await body(initiator, second), 'second');

      await expectConvergesAndHeals(initiator, responder, conversationId: conversationId);
    }
  });

  test('glare converges under any delivery order', () async {
    for (var seed = 0; seed < 20; seed++) {
      final random = Random(seed);
      final conversationId = 'conv-glare-fuzz-$seed';
      final (low, high) = await lowAndHigh();
      final parties = [low, high];
      Party peerOf(Party party) => identical(party, low) ? high : low;
      final bootstrapped = <Party>{};
      final quota = {for (final party in parties) party: 1 + random.nextInt(3)};
      final sent = {for (final party in parties) party: 0};
      final inFlight = <(Party, CryptoEnvelope, String)>[];

      Future<void> deliverAny() async {
        final (to, envelope, text) = inFlight.removeAt(random.nextInt(inFlight.length));
        expect(await body(to, envelope), text, reason: 'seed $seed');
      }

      Future<void> sendNext(Party from) async {
        final text = '${from.name} #${sent[from]}';
        sent[from] = sent[from]! + 1;
        inFlight.add((peerOf(from), await send(from, peerOf(from), text, conversationId: conversationId), text));
      }

      // Each party bootstraps once and sends its quota, possibly before its
      // own bootstrap on a state the peer opened; delivery order is random.
      while (bootstrapped.length < parties.length || parties.any((party) => sent[party]! < quota[party]!)) {
        final actions = <Future<void> Function()>[
          for (final party in parties)
            if (!bootstrapped.contains(party))
              () async {
                await bootstrap(party, peerOf(party), conversationId: conversationId);
                bootstrapped.add(party);
              },
          for (final party in parties)
            if (sent[party]! < quota[party]! && party.adapter.sessions.hasSessionFor(conversationId))
              () => sendNext(party),
          if (inFlight.isNotEmpty) deliverAny,
        ];
        await actions[random.nextInt(actions.length)]();
      }
      while (inFlight.isNotEmpty) {
        await deliverAny();
      }

      final first = random.nextBool() ? low : high;
      await expectConvergesAndHeals(first, peerOf(first), conversationId: conversationId, settleTurns: 4);
    }
  });

  test('an archived state that keeps receiving is not pruned', () async {
    final alice = await recordedParty('alice');
    final bob = await recordedParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    expect(await body(bob, await send(alice, bob, 'a0', conversationId: conversationId)), 'a0');
    expect(await body(alice, await send(bob, alice, 'b0', conversationId: conversationId)), 'b0');

    // Alice re-bootstraps but sends nothing, so Bob never learns of the new
    // state and keeps sending on the old one, which Alice holds archived.
    await bootstrap(alice, bob, conversationId: conversationId);
    for (final day in [20, 40, 41]) {
      now = start.add(Duration(days: day));
      expect(await body(alice, await send(bob, alice, 'day $day', conversationId: conversationId)), 'day $day');
    }
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
