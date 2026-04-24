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
  // Base lockout kicks in after the first full batch of failed attempts.
  // Each subsequent batch doubles the lockout up to [maxLockoutDuration],
  // which slows a brute-force attacker from 12 guesses/minute down to a
  // handful per hour after a few rounds without permanently bricking the
  // user out from a legitimate memory slip.
  static const Duration baseLockoutDuration = Duration(seconds: 30);
  static const Duration maxLockoutDuration = Duration(hours: 1);
  // Retained for API compatibility — callers that used to reference the
  // fixed-duration constant now see the base tier; actual lockout length
  // for a given state is [lockoutDurationForTier].
  static const Duration pinLockoutDuration = baseLockoutDuration;

  /// Returns the lockout duration for a 1-based [tier]. Tier 0 means "no
  /// lockout scheduled"; tier 1 is the first lockout (==base), tier 2 is
  /// twice as long, and so on — capped at [maxLockoutDuration].
  static Duration lockoutDurationForTier(int tier) {
    if (tier <= 0) {
      return Duration.zero;
    }
    // `1 << exponent` overflows silently at int64 boundary; clamp to a safe
    // exponent since we cap on the second line anyway.
    final exponent = (tier - 1).clamp(0, 30);
    final multiplier = 1 << exponent;
    final scaledSeconds = baseLockoutDuration.inSeconds * multiplier;
    final cappedSeconds = scaledSeconds > maxLockoutDuration.inSeconds
        ? maxLockoutDuration.inSeconds
        : scaledSeconds;
    return Duration(seconds: cappedSeconds);
  }

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
      // Advance the tier so successive lockout rounds grow exponentially.
      // failedAttempts resets so the user can try again after the window.
      final nextTier = throttleState.lockoutTier + 1;
      final lockoutUntil = now.add(lockoutDurationForTier(nextTier));
      await _secureStorage.persistPinThrottleState(
        PinThrottleState(
          failedAttempts: 0,
          lockoutUntil: lockoutUntil,
          lockoutTier: nextTier,
        ),
      );
      return PinValidationResult.lockedOut(
        remaining: lockoutUntil.difference(now),
      );
    }

    await _secureStorage.persistPinThrottleState(
      PinThrottleState(
        failedAttempts: nextFailures,
        // Carry tier forward — it only resets on a successful unlock, which
        // hit `clearPinThrottleState` above.
        lockoutTier: throttleState.lockoutTier,
      ),
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
