import 'package:local_auth/local_auth.dart';

import '../storage/secure_storage_service.dart';

class AppLockService {
  AppLockService(this._localAuth, this._secureStorage);

  final LocalAuthentication _localAuth;
  final SecureStorageService _secureStorage;

  Future<bool> canUseBiometrics() => _localAuth.canCheckBiometrics;

  Future<bool> hasPin() => _secureStorage.hasPin();

  Future<bool> authenticateBiometric() {
    return _localAuth.authenticate(
      localizedReason: 'Unlock VEIL',
      options: const AuthenticationOptions(
        biometricOnly: true,
      ),
    );
  }

  Future<void> setPin(String pin) => _secureStorage.persistPin(pin);

  Future<bool> validatePin(String pin) => _secureStorage.verifyPin(pin);
}
