import 'package:flutter_test/flutter_test.dart';

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
}

class _InMemorySecureStore implements SecureKeyValueStore {
  final Map<String, String?> _values = <String, String?>{};

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
