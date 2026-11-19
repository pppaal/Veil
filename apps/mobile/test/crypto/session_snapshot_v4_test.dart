import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

import 'support/crypto_harness.dart';

// Snapshot schema v4 = {v: 4, rev, current, archived[]}; v2/v3 snapshots
// (one legacy-protocol state each) restore as the current state of a record.
void main() {
  const conversationId = 'conv-snapshot';

  // Keys that only exist in v4 state maps; stripping them (and stamping
  // v: 3) reproduces the flat v3 snapshot shape.
  const v4OnlyStateKeys = [
    'protocol',
    'initiatedLocally',
    'createdAt',
    'localIdentityKey',
    'remoteIdentityKey',
    'associatedData',
    'baseKey',
    'pendingPreKey',
    'previousSendCounter',
    'previousPeerPubs',
  ];

  Map<String, dynamic> roundTripJson(Map<String, dynamic> map) => json.decode(json.encode(map)) as Map<String, dynamic>;

  Future<(Party, Party, SnapshotRecorder)> legacySession() async {
    final alice = await createParty('alice');
    final bob = await createLegacyParty('bob');
    final recorder = SnapshotRecorder();
    alice.adapter.setSessionPersistence(persister: recorder.call);
    await bootstrap(alice, bob, conversationId: conversationId);
    final first = await send(alice, bob, 'legacy hello', conversationId: conversationId);
    await acceptLegacy(bob, alice, first, conversationId: conversationId);
    expect((await receive(bob, first)).status, DecryptStatus.legacyUnauthenticated);
    return (alice, bob, recorder);
  }

  test('fresh snapshot carries v4, a rev and epoch metadata', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final recorder = SnapshotRecorder();
    alice.adapter.setSessionPersistence(persister: recorder.call);
    await bootstrap(alice, bob, conversationId: conversationId);

    final snapshot = recorder.latest[conversationId]!;
    expect(snapshot['v'], 4);
    expect(snapshot['rev'], isA<int>());
    expect(snapshot['archived'], isEmpty);
    final current = snapshot['current'] as Map<String, dynamic>;
    expect(current['protocol'], 2);
    expect(current['ratchetRotationCount'], 0);
    expect(current['lastRatchetRotationAt'], isNull);
    expect(current['pendingPreKey'], isA<String>());
  });

  test('rev grows with every commit and DH rotation is counted', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final revs = <int>[];
    Map<String, dynamic>? latest;
    alice.adapter.setSessionPersistence(persister: (_, snapshot) async {
      revs.add(snapshot['rev'] as int);
      latest = snapshot;
    });
    await bootstrap(alice, bob, conversationId: conversationId);
    expect((await receive(bob, await send(alice, bob, 'hi', conversationId: conversationId))).isOk, isTrue);
    expect((await receive(alice, await send(bob, alice, 'hello', conversationId: conversationId))).isOk, isTrue);
    await send(alice, bob, 'rotating-now', conversationId: conversationId);

    expect(revs, hasLength(4));
    for (var i = 1; i < revs.length; i++) {
      expect(revs[i], greaterThan(revs[i - 1]));
    }
    final current = latest!['current'] as Map<String, dynamic>;
    // Receive step on Bob's reply, then the send step.
    expect(current['ratchetRotationCount'], 2);
    expect(current['lastRatchetRotationAt'], isA<String>());
  });

  test('v4 round-trips current and archived states', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final recorder = SnapshotRecorder();
    alice.adapter.setSessionPersistence(persister: recorder.call);
    await bootstrap(alice, bob, conversationId: conversationId);
    expect((await receive(bob, await send(alice, bob, 'A0', conversationId: conversationId))).isOk, isTrue);
    final inFlight = await send(bob, alice, 'on the first session', conversationId: conversationId);
    await bootstrap(alice, bob, conversationId: conversationId);
    expect((recorder.latest[conversationId]!['archived'] as List<dynamic>), hasLength(1));

    final restarted = Party('alice', LibCryptoAdapter(), alice.identity);
    await restarted.adapter.restoreSessionsFromSnapshots(recorder.latest);
    expect((await receive(restarted, inFlight)).body, 'on the first session');
    expect((await receive(bob, await send(restarted, bob, 'second session', conversationId: conversationId))).body,
        'second session');
  });

  test('v3 restores into record', () async {
    final (alice, bob, recorder) = await legacySession();
    final v3 = <String, dynamic>{...recorder.latest[conversationId]!['current'] as Map<String, dynamic>, 'v': 3};
    v4OnlyStateKeys.forEach(v3.remove);

    final restarted = Party('alice', LibCryptoAdapter(), alice.identity);
    await restarted.adapter.restoreSessionsFromSnapshots({conversationId: roundTripJson(v3)});
    expect(restarted.adapter.sessions.hasSessionFor(conversationId), isTrue);

    final next = await send(restarted, bob, 'after v3 restore', conversationId: conversationId);
    expect(next.version, 'veil-envelope-v1');
    final result = await receive(bob, next);
    expect(result.status, DecryptStatus.legacyUnauthenticated);
    expect(result.body, 'after v3 restore');
    expect(
        (await receive(restarted, await send(bob, restarted, 'reply', conversationId: conversationId))).body, 'reply');
  });

  test('v2 restores into record', () async {
    final (alice, bob, recorder) = await legacySession();
    final v2 = <String, dynamic>{...recorder.latest[conversationId]!['current'] as Map<String, dynamic>, 'v': 2};
    v4OnlyStateKeys.forEach(v2.remove);
    v2
      ..remove('ratchetRotationCount')
      ..remove('lastRatchetRotationAt')
      ..['skippedKeys'] = <String, String>{};

    final restarted = Party('alice', LibCryptoAdapter(), alice.identity);
    await restarted.adapter.restoreSessionsFromSnapshots({conversationId: roundTripJson(v2)});
    final result = await receive(bob, await send(restarted, bob, 'migrated', conversationId: conversationId));
    expect(result.body, 'migrated');
  });

  test('restore keeps a newer in-memory record and skips unreadable snapshots', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final recorder = SnapshotRecorder();
    alice.adapter.setSessionPersistence(persister: recorder.call);
    await bootstrap(alice, bob, conversationId: conversationId);
    final stale = roundTripJson(recorder.latest[conversationId]!);
    expect((await receive(bob, await send(alice, bob, 'A0', conversationId: conversationId))).isOk, isTrue);

    await alice.adapter.restoreSessionsFromSnapshots({
      conversationId: stale,
      'conv-garbage': {'v': 4, 'rev': 'not-a-number'},
    });
    expect(alice.adapter.sessions.hasSessionFor('conv-garbage'), isFalse);
    final next = await send(alice, bob, 'A1', conversationId: conversationId);
    expect(frameOf(next).counter, 1, reason: 'the stale snapshot must not roll the chain back');
    expect((await receive(bob, next)).body, 'A1');
  });
}
