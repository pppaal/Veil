import 'dart:math';

import 'package:flutter/services.dart';
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
  Future<bool> canUseBiometrics() async {
    try {
      final available = await _localAuth.getAvailableBiometrics();
      if (available.isNotEmpty) {
        return true;
      }
      return await _localAuth.canCheckBiometrics &&
          await _localAuth.isDeviceSupported();
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> authenticateBiometric() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock VEIL',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: false,
          sensitiveTransaction: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}

class AppLockService {
  AppLockService(this._authenticator, this._secureStorage);

  static final _pinPattern = RegExp(r'^\d{6,12}$');
  static const int maxFailedPinAttempts = 5;
  static const Duration pinLockoutDuration = Duration(seconds: 30);

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

  Future<bool> authenticateBiometric() =>
      _authenticator.authenticateBiometric();

  bool isValidPinFormat(String pin) => _pinPattern.hasMatch(pin);

  Future<void> setPin(String pin) async {
    if (!isValidPinFormat(pin)) {
      throw StateError('PIN must be 6 to 12 digits.');
    }

    await _secureStorage.persistPin(pin);
  }

  Future<bool> validatePin(String pin) async {
    final result = await validatePinAttempt(pin);
    return result.isSuccess;
  }

  Future<PinValidationResult> validatePinAttempt(String pin) async {
    if (!isValidPinFormat(pin)) {
      return PinValidationResult.invalidFormat;
    }

    final throttleState = await _secureStorage.readPinThrottleState();
    final now = DateTime.now().toUtc();
    if (throttleState.lockoutUntil?.isAfter(now) ?? false) {
      return PinValidationResult.lockedOut(
        remaining: throttleState.lockoutUntil!.difference(now),
      );
    }

    final valid = await _secureStorage.verifyPin(pin);
    if (valid) {
      await _secureStorage.clearPinThrottleState();
      return PinValidationResult.success;
    }

    final nextFailures = throttleState.failedAttempts + 1;
    if (nextFailures >= maxFailedPinAttempts) {
      final lockoutUntil = now.add(pinLockoutDuration);
      await _secureStorage.persistPinThrottleState(
        PinThrottleState(
          failedAttempts: 0,
          lockoutUntil: lockoutUntil,
        ),
      );
      return PinValidationResult.lockedOut(
        remaining: lockoutUntil.difference(now),
      );
    }

    await _secureStorage.persistPinThrottleState(
      PinThrottleState(failedAttempts: nextFailures),
    );
    return PinValidationResult.mismatch(
      remainingAttempts: max(0, maxFailedPinAttempts - nextFailures),
    );
  }

  Future<void> clearPin() => _secureStorage.clearPin();

  Future<Duration?> remainingPinLockout() async {
    final state = await _secureStorage.readPinThrottleState();
    if (!state.isLockedOut || state.lockoutUntil == null) {
      return null;
    }

    final remaining = state.lockoutUntil!.difference(DateTime.now().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }
}

class PinValidationResult {
  const PinValidationResult._(
    this._state, {
    this.remainingAttempts,
    this.remainingLockout,
  });

  const PinValidationResult._success() : this._(_PinValidationState.success);

  const PinValidationResult._invalidFormat()
      : this._(_PinValidationState.invalidFormat);

  const PinValidationResult._mismatch({required int remainingAttempts})
      : this._(
          _PinValidationState.mismatch,
          remainingAttempts: remainingAttempts,
        );

  const PinValidationResult._lockedOut({required Duration remaining})
      : this._(
          _PinValidationState.lockedOut,
          remainingLockout: remaining,
        );

  final _PinValidationState _state;
  final int? remainingAttempts;
  final Duration? remainingLockout;

  bool get isSuccess => _state == _PinValidationState.success;
  bool get isLockedOut => _state == _PinValidationState.lockedOut;

  static const success = PinValidationResult._success();
  static const invalidFormat = PinValidationResult._invalidFormat();

  static PinValidationResult mismatch({required int remainingAttempts}) =>
      PinValidationResult._mismatch(remainingAttempts: remainingAttempts);

  static PinValidationResult lockedOut({required Duration remaining}) =>
      PinValidationResult._lockedOut(remaining: remaining);
}

enum _PinValidationState {
  success,
  invalidFormat,
  mismatch,
  lockedOut,
}
