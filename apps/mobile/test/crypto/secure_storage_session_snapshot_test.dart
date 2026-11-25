import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';

import 'support/crypto_harness.dart';

/// Key-value store whose every operation yields for a random moment, so
/// unserialized read-modify-write sequences would interleave and lose data.
class _SlowStore implements SecureKeyValueStore {
  _SlowStore(int seed) : _random = Random(seed);

  final Random _random;
  final Map<String, String> values = {};

  Future<void> _lag() => Future<void>.delayed(Duration(microseconds: _random.nextInt(300)));

  @override
  Future<String?> read({required String key}) async {
    await _lag();
    return values[key];
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    await _lag();
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({required String key}) async {
    await _lag();
    values.remove(key);
  }
}

Map<String, dynamic> _snapshot(int rev, String marker) => {'v': 4, 'rev': rev, 'marker': marker};

void main() {
  test('older rev dropped', () async {
    final store = _SlowStore(1);
    final service = SecureStorageService(store);
    await service.writeSessionSnapshot('conv-a', _snapshot(5, 'five'));
    // Refused loudly: the session store only publishes state once its write
    // completes, so a silent drop would leave memory ahead of disk.
    await expectLater(service.writeSessionSnapshot('conv-a', _snapshot(3, 'three')), throwsStateError);
    expect((await service.readAllSessionSnapshots())['conv-a']!['marker'], 'five');

    await service.writeSessionSnapshot('conv-a', _snapshot(6, 'six'));
    expect((await service.readAllSessionSnapshots())['conv-a']!['marker'], 'six');

    // The guard survives a restart: the stored rev is read back.
    final restarted = SecureStorageService(store);
    await expectLater(restarted.writeSessionSnapshot('conv-a', _snapshot(4, 'four')), throwsStateError);
    expect((await restarted.readAllSessionSnapshots())['conv-a']!['marker'], 'six');
  });

  test('a session re-created over an unreadable snapshot is still durable', () async {
    // Written while the clock ran ahead; it no longer parses, and the clock
    // has since gone back.
    final now = DateTime.utc(2026, 11, 1);
    final aheadRev = now.add(const Duration(days: 30)).microsecondsSinceEpoch;
    final storage = SecureStorageService(_SlowStore(5));
    await storage.writeSessionSnapshot('conv-r', {'v': 4, 'rev': aheadRev, 'current': 'unreadable'});
    final alice = await createParty('alice', clock: () => now);
    final bob = await createParty('bob', clock: () => now);
    alice.adapter.setSessionPersistence(persister: storage.writeSessionSnapshot);
    await alice.adapter.restoreSessionsFromSnapshots(await storage.readAllSessionSnapshots());
    expect(alice.adapter.sessions.hasSessionFor('conv-r'), isFalse);

    await bootstrap(alice, bob, conversationId: 'conv-r');
    final stored = (await storage.readAllSessionSnapshots())['conv-r']!;
    expect(stored['rev'] as int, greaterThan(aheadRev));
    expect(stored['current'], isA<Map<String, dynamic>>());
  });

  test('concurrent writes for two conversations survive slow storage', () async {
    final store = _SlowStore(7);
    final service = SecureStorageService(store);
    await Future.wait([
      for (var rev = 1; rev <= 6; rev++) ...[
        service.writeSessionSnapshot('conv-x', _snapshot(rev, 'x$rev')),
        service.writeSessionSnapshot('conv-y', _snapshot(rev, 'y$rev')),
        service.writeGroupSenderKeySnapshot('group-$rev', {'epoch': rev}),
      ],
    ]);

    final sessions = await service.readAllSessionSnapshots();
    expect(sessions['conv-x']!['marker'], 'x6');
    expect(sessions['conv-y']!['marker'], 'y6');
    expect((await service.readAllGroupSenderKeySnapshots()).keys, containsAll(['group-1', 'group-6']));
    expect(await service.readAllGroupSenderKeySnapshots(), hasLength(6));
    // Conversation ids never appear in key names.
    expect(store.values.keys.where((k) => k.contains('conv-x')), isEmpty);
  });

  test('legacy blob migrated once', () async {
    final store = _SlowStore(3)
      ..values['veil.crypto.session_snapshots'] = json.encode({
        'conv-a': {'v': 3, 'marker': 'legacy-a'},
        'conv-b': {'v': 3, 'marker': 'legacy-b'},
      });
    final service = SecureStorageService(store);

    final migrated = await service.readAllSessionSnapshots();
    expect(migrated.keys, unorderedEquals(['conv-a', 'conv-b']));
    expect(migrated['conv-a']!['marker'], 'legacy-a');
    expect(store.values.containsKey('veil.crypto.session_snapshots'), isFalse);
    expect(store.values.keys.where((k) => k.startsWith('veil.crypto.session.')), hasLength(2));

    await service.writeSessionSnapshot('conv-a', _snapshot(10, 'new-a'));
    final restarted = SecureStorageService(store);
    final afterRestart = await restarted.readAllSessionSnapshots();
    expect(afterRestart['conv-a']!['marker'], 'new-a');
    expect(afterRestart['conv-b']!['marker'], 'legacy-b');

    await restarted.clearSessionSnapshots();
    expect(await restarted.readAllSessionSnapshots(), isEmpty);
    expect(store.values.keys.where((k) => k.startsWith('veil.crypto.session')), isEmpty);
  });

  test('adapter state persisted through secure storage resumes after restart', () async {
    final store = _SlowStore(11);
    final storage = SecureStorageService(store);
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    alice.adapter.setSessionPersistence(persister: storage.writeSessionSnapshot);
    const conversationId = 'conv-durable';

    await bootstrap(alice, bob, conversationId: conversationId);
    expect((await receive(bob, await send(alice, bob, 'before restart', conversationId: conversationId))).isOk, isTrue);
    final reply = await send(bob, alice, 'reply', conversationId: conversationId);
    expect((await receive(alice, reply)).isOk, isTrue);

    final restarted = Party('alice', LibCryptoAdapter(), alice.identity);
    await restarted.adapter.restoreSessionsFromSnapshots(await SecureStorageService(store).readAllSessionSnapshots());
    final after = await send(restarted, bob, 'after restart', conversationId: conversationId);
    expect((await receive(bob, after)).body, 'after restart');
    expect((await receive(restarted, reply)).status, DecryptStatus.replayed);
  });
}
