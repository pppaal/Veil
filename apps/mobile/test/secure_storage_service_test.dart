import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';

void main() {
  test('stores PIN as verifier and validates without plaintext equality', () async {
    final store = _MemorySecureKeyValueStore();
    final storage = SecureStorageService(store);

    await storage.persistPin('123456');

    expect(store.values.values.any((value) => value == '123456'), isFalse);
    expect(await storage.verifyPin('123456'), isTrue);
    expect(await storage.verifyPin('654321'), isFalse);
  });

  test('wipeLocalDeviceState clears secrets but can preserve onboarding and PIN', () async {
    final storage = SecureStorageService(_MemorySecureKeyValueStore());

    await storage.persistOnboardingAccepted(true);
    await storage.persistPin('123456');
    await storage.persistDeviceSecretRefs(
      identityPrivateRef: 'secure-store://identity',
      authPrivateKey: 'private-key',
      authPublicKey: 'public-key',
    );
    await storage.persistSession(
      accessToken: 'token',
      userId: 'user-1',
      deviceId: 'device-1',
      handle: 'atlas',
      displayName: 'Atlas',
    );
    await storage.readOrCreateCacheKey();

    await storage.wipeLocalDeviceState(
      preserveOnboardingAccepted: true,
      preservePin: true,
    );

    expect(await storage.readSession(), isNull);
    expect(await storage.hasDeviceSecretRefs(), isFalse);
    expect(await storage.readOnboardingAccepted(), isTrue);
    expect(await storage.hasPin(), isTrue);
  });
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String?> values = <String, String?>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async {
    return values[key];
  }

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      values.remove(key);
      return;
    }
    values[key] = value;
  }
}
