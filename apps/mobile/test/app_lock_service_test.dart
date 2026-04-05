import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/security/app_lock_service.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';

void main() {
  test('requires numeric PIN between 6 and 12 digits', () {
    final service = AppLockService(
      _FakeAuthenticator(),
      SecureStorageService(_MemorySecureKeyValueStore()),
    );

    expect(service.isValidPinFormat('12345'), isFalse);
    expect(service.isValidPinFormat('123456'), isTrue);
    expect(service.isValidPinFormat('123456789012'), isTrue);
    expect(service.isValidPinFormat('1234567890123'), isFalse);
    expect(service.isValidPinFormat('12ab56'), isFalse);
  });

  test(
      'setPin persists verifier and validatePin succeeds only for the same PIN',
      () async {
    final service = AppLockService(
      _FakeAuthenticator(),
      SecureStorageService(_MemorySecureKeyValueStore()),
    );

    await service.setPin('123456');

    expect(await service.hasPin(), isTrue);
    expect(await service.validatePin('123456'), isTrue);
    expect(await service.validatePin('654321'), isFalse);
  });

  test('hasLocalUnlockMethod becomes true when biometrics or PIN is available',
      () async {
    final noUnlock = AppLockService(
      _FakeAuthenticator(biometricsAvailable: false),
      SecureStorageService(_MemorySecureKeyValueStore()),
    );
    expect(await noUnlock.hasLocalUnlockMethod(), isFalse);

    final biometricOnly = AppLockService(
      _FakeAuthenticator(biometricsAvailable: true),
      SecureStorageService(_MemorySecureKeyValueStore()),
    );
    expect(await biometricOnly.hasLocalUnlockMethod(), isTrue);

    final pinOnly = AppLockService(
      _FakeAuthenticator(biometricsAvailable: false),
      SecureStorageService(_MemorySecureKeyValueStore()),
    );
    await pinOnly.setPin('123456');
    expect(await pinOnly.hasLocalUnlockMethod(), isTrue);
  });

  test('authenticateBiometric returns the authenticator result', () async {
    final success = AppLockService(
      _FakeAuthenticator(biometricsAvailable: true, authenticateResult: true),
      SecureStorageService(_MemorySecureKeyValueStore()),
    );
    final failure = AppLockService(
      _FakeAuthenticator(biometricsAvailable: true, authenticateResult: false),
      SecureStorageService(_MemorySecureKeyValueStore()),
    );

    expect(await success.authenticateBiometric(), isTrue);
    expect(await failure.authenticateBiometric(), isFalse);
  });

  test('temporary PIN lockout engages after repeated failed attempts',
      () async {
    final service = AppLockService(
      _FakeAuthenticator(),
      SecureStorageService(_MemorySecureKeyValueStore()),
    );

    await service.setPin('123456');

    for (var attempt = 0;
        attempt < AppLockService.maxFailedPinAttempts - 1;
        attempt++) {
      final result = await service.validatePinAttempt('654321');
      expect(result.isLockedOut, isFalse);
    }

    final lockedOut = await service.validatePinAttempt('654321');
    expect(lockedOut.isLockedOut, isTrue);
    expect(await service.remainingPinLockout(), isNotNull);
    expect(await service.validatePin('123456'), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
}

class _FakeAuthenticator implements LocalUnlockAuthenticator {
  _FakeAuthenticator({
    this.biometricsAvailable = false,
    this.authenticateResult = false,
  });

  final bool biometricsAvailable;
  final bool authenticateResult;

  @override
  Future<bool> authenticateBiometric() async => authenticateResult;

  @override
  Future<bool> canUseBiometrics() async => biometricsAvailable;
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String?> values = <String, String?>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      values.remove(key);
      return;
    }
    values[key] = value;
  }
}
