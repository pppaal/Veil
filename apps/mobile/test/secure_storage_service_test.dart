import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';

void main() {
  test('database key is device-local, deterministic, and hex-encoded',
      () async {
    final store = _InMemorySecureStore();
    final service = SecureStorageService(store);

    final first = await service.readOrCreateDatabaseKeyHex();
    final second = await service.readOrCreateDatabaseKeyHex();
    final cacheKey = await service.readOrCreateCacheKey();

    expect(first, equals(second));
    expect(first, isNot(equals(cacheKey)));
    expect(first, hasLength(64));
    expect(RegExp(r'^[0-9a-f]+$').hasMatch(first), isTrue);
  });

  group('SecureStorageLocalPrekeyStore', () {
    test('one-time prekey ids never repeat, even across restarts', () async {
      final store = _InMemorySecureStore();
      final first = await SecureStorageLocalPrekeyStore(SecureStorageService(store)).reserveOneTimePrekeyIds(3);
      final second = await SecureStorageLocalPrekeyStore(SecureStorageService(store)).reserveOneTimePrekeyIds(2);
      expect(first, 1);
      expect(second, 4);
    });

    test('stores, loads and deletes prekey private halves', () async {
      final prekeys = SecureStorageLocalPrekeyStore(SecureStorageService(_InMemorySecureStore()));
      await prekeys.saveOneTimePrekey(7, List<int>.filled(32, 7));
      expect(await prekeys.loadOneTimePrekey(7), List<int>.filled(32, 7));
      await prekeys.deleteOneTimePrekey(7);
      expect(await prekeys.loadOneTimePrekey(7), isNull);

      final createdAt = DateTime.utc(2026, 11, 1);
      await prekeys.saveSignedPrekey(StoredSignedPrekey(keyId: 2, privateKey: List<int>.filled(32, 2), createdAt: createdAt));
      final loaded = (await prekeys.loadSignedPrekeys()).single;
      expect(loaded.keyId, 2);
      expect(loaded.privateKey, List<int>.filled(32, 2));
      expect(loaded.createdAt, createdAt);
      await prekeys.deleteSignedPrekey(2);
      expect(await prekeys.loadSignedPrekeys(), isEmpty);
    });

    test('wiping the device clears prekeys and session snapshots', () async {
      final store = _InMemorySecureStore();
      final service = SecureStorageService(store);
      final prekeys = SecureStorageLocalPrekeyStore(service);
      await prekeys.saveOneTimePrekey(1, List<int>.filled(32, 1));
      await prekeys.saveSignedPrekey(StoredSignedPrekey(keyId: 1, privateKey: List<int>.filled(32, 1), createdAt: DateTime.utc(2026)));
      await service.writeSessionSnapshot('conv', {'v': 4, 'rev': 1});

      await service.wipeLocalDeviceState();

      expect(await prekeys.loadOneTimePrekey(1), isNull);
      expect(await prekeys.loadSignedPrekeys(), isEmpty);
      expect(await service.readAllSessionSnapshots(), isEmpty);
      expect(store.keys.where((key) => key.startsWith('veil.crypto.')), isEmpty);
    });
  });
}

class _InMemorySecureStore implements SecureKeyValueStore {
  final Map<String, String?> _values = <String, String?>{};

  Iterable<String> get keys => _values.keys;

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async {
    return _values[key];
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      _values.remove(key);
      return;
    }
    _values[key] = value;
  }
}
