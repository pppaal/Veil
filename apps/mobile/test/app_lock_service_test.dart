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

  test('lockoutDurationForTier schedules exponential backoff up to the cap',
      () {
    // Schedule must double each tier until it hits the configured cap.
    expect(AppLockService.lockoutDurationForTier(0), Duration.zero);
    expect(AppLockService.lockoutDurationForTier(1),
        AppLockService.baseLockoutDuration);
    expect(
      AppLockService.lockoutDurationForTier(2),
      AppLockService.baseLockoutDuration * 2,
    );
    expect(
      AppLockService.lockoutDurationForTier(3),
      AppLockService.baseLockoutDuration * 4,
    );
    expect(
      AppLockService.lockoutDurationForTier(4),
      AppLockService.baseLockoutDuration * 8,
    );
    // Well past the cap — must not exceed maxLockoutDuration.
    expect(
      AppLockService.lockoutDurationForTier(20),
      AppLockService.maxLockoutDuration,
    );
    expect(
      AppLockService.lockoutDurationForTier(1000),
      AppLockService.maxLockoutDuration,
    );
  });

  test('successive lockout rounds escalate the stored tier', () async {
    final store = _MemorySecureKeyValueStore();
    final storage = SecureStorageService(store);
    final service = AppLockService(_FakeAuthenticator(), storage);
    await service.setPin('123456');

    Future<void> burnAttemptsUntilLocked() async {
      for (var i = 0; i < AppLockService.maxFailedPinAttempts; i++) {
        await service.validatePinAttempt('654321');
      }
    }

    await burnAttemptsUntilLocked();
    var state = await storage.readPinThrottleState();
    expect(state.lockoutTier, 1);
    final firstLockoutRemaining = state.lockoutUntil!
        .difference(DateTime.now().toUtc())
        .inMilliseconds;

    // Simulate the first lockout elapsing, then burn another round.
    await storage.persistPinThrottleState(
      PinThrottleState(
        failedAttempts: 0,
        lockoutUntil: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
        lockoutTier: state.lockoutTier,
      ),
    );
    await burnAttemptsUntilLocked();
    state = await storage.readPinThrottleState();
    expect(state.lockoutTier, 2);
    final secondLockoutRemaining = state.lockoutUntil!
        .difference(DateTime.now().toUtc())
        .inMilliseconds;
    // Second lockout window must be strictly longer than the first.
    expect(secondLockoutRemaining, greaterThan(firstLockoutRemaining));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('successful PIN entry resets the lockout tier', () async {
    final store = _MemorySecureKeyValueStore();
    final storage = SecureStorageService(store);
    final service = AppLockService(_FakeAuthenticator(), storage);
    await service.setPin('123456');

    // Manually plant a high-tier state as though the user had already
    // served multiple lockout rounds — then simulate the lockout window
    // having already elapsed so the next attempt isn't rejected as locked.
    await storage.persistPinThrottleState(
      PinThrottleState(
        failedAttempts: 2,
        lockoutUntil:
            DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
        lockoutTier: 4,
      ),
    );

    final ok = await service.validatePin('123456');
    expect(ok, isTrue);

    final state = await storage.readPinThrottleState();
    expect(state.failedAttempts, 0);
    expect(state.lockoutTier, 0);
    expect(state.lockoutUntil, isNull);
  });
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
