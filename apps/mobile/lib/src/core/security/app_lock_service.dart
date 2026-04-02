import 'package:local_auth/local_auth.dart';

import '../storage/secure_storage_service.dart';

abstract class LocalUnlockAuthenticator {
  Future<bool> canUseBiometrics();

  Future<bool> authenticateBiometric();
}

class DeviceLocalUnlockAuthenticator implements LocalUnlockAuthenticator {
  DeviceLocalUnlockAuthenticator(this._localAuth);

  final LocalAuthentication _localAuth;

  @override
  Future<bool> canUseBiometrics() => _localAuth.canCheckBiometrics;

  @override
  Future<bool> authenticateBiometric() {
    return _localAuth.authenticate(
      localizedReason: 'Unlock VEIL',
      options: const AuthenticationOptions(
        biometricOnly: true,
        stickyAuth: true,
        useErrorDialogs: false,
        sensitiveTransaction: true,
      ),
    );
  }
}

class AppLockService {
  AppLockService(this._authenticator, this._secureStorage);

  static final _pinPattern = RegExp(r'^\d{6,12}$');

  final LocalUnlockAuthenticator _authenticator;
  final SecureStorageService _secureStorage;

  Future<bool> canUseBiometrics() => _authenticator.canUseBiometrics();

  Future<bool> hasPin() => _secureStorage.hasPin();

  Future<bool> hasLocalUnlockMethod() async {
    final values = await Future.wait<bool>([
      hasPin(),
      canUseBiometrics(),
    ]);
    return values.any((value) => value);
  }

  Future<bool> authenticateBiometric() => _authenticator.authenticateBiometric();

  bool isValidPinFormat(String pin) => _pinPattern.hasMatch(pin);

  Future<void> setPin(String pin) async {
    if (!isValidPinFormat(pin)) {
      throw StateError('PIN must be 6 to 12 digits.');
    }

    await _secureStorage.persistPin(pin);
  }

  Future<bool> validatePin(String pin) async {
    if (!isValidPinFormat(pin)) {
      return false;
    }

    return _secureStorage.verifyPin(pin);
  }

  Future<void> clearPin() => _secureStorage.clearPin();
}
