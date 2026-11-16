import 'package:flutter/material.dart';

import '../../../core/security/app_lock_service.dart';
import '../../../l10n/generated/app_localizations.dart';

// What the lock screen says about itself: the outcome of the last attempt
// and how long a lockout lasts.

/// How the last unlock attempt ended.
enum AppLockOutcome {
  unlocked,
  biometricFailed,
  enterPin,
  pinFormat,
  confirmMismatch,
  pinMismatch,
  lockedTemporarily,
  blockedCompromised,
}

class AppLockStatus {
  const AppLockStatus(this.outcome, {this.remainingAttempts});

  final AppLockOutcome outcome;

  /// Attempts left before the PIN locks, after a mismatch that says so.
  final int? remainingAttempts;

  String message(AppLocalizations l10n) => switch (outcome) {
        AppLockOutcome.unlocked => l10n.appLockStatusUnlocked,
        AppLockOutcome.biometricFailed => l10n.appLockStatusBiometricFailed,
        AppLockOutcome.enterPin => l10n.appLockStatusEnterPin,
        AppLockOutcome.pinFormat => l10n.appLockStatusPinFormat,
        AppLockOutcome.confirmMismatch => l10n.appLockConfirmMismatch,
        AppLockOutcome.pinMismatch => remainingAttempts == null
            ? l10n.appLockStatusPinMismatch
            : l10n.appLockStatusPinMismatchAttempts(remainingAttempts!),
        AppLockOutcome.lockedTemporarily => l10n.appLockStatusLocked,
        AppLockOutcome.blockedCompromised => l10n.appLockStatusCompromised,
      };

  /// Whether the attempt failed in a way the field says under it: a wrong
  /// or missing PIN, biometrics that did not work. An unlock says nothing
  /// (the screen goes away) and a lockout has its own line.
  bool get isFieldError => outcome != AppLockOutcome.unlocked && outcome != AppLockOutcome.lockedTemporarily;
}

/// "Try again in 40s." for what is left of a PIN lockout.
String formatAppLockRetry(AppLocalizations l10n, Duration? remaining) {
  final seconds = remaining == null || remaining.isNegative ? 0 : remaining.inSeconds;
  if (seconds <= 0) return l10n.appLockRetryNow;
  if (seconds < 60) return l10n.appLockRetrySeconds(seconds);
  return l10n.appLockRetryMinutes((seconds / 60).ceil());
}

/// The button that unlocks with the phone's biometrics, named after the
/// method it has ("Use Face ID").
String biometricUnlockLabel(AppLocalizations l10n, BiometricKind kind) => switch (kind) {
      BiometricKind.faceId => l10n.appLockUseFaceId,
      BiometricKind.touchId => l10n.appLockUseTouchId,
      BiometricKind.fingerprint => l10n.appLockUseFingerprint,
      BiometricKind.unknown => l10n.appLockUseBiometrics,
    };

/// A PIN field of the lock screen and of its setup: digits, obscured, no
/// suggestions, no selection.
TextField appLockPinField({
  required TextEditingController controller,
  required String hint,
  String? label,
  String? errorText,
  ValueChanged<String>? onChanged,
  TextAlign textAlign = TextAlign.start,
  bool dense = false,
}) {
  return TextField(
    controller: controller,
    obscureText: true,
    keyboardType: TextInputType.number,
    enableSuggestions: false,
    autocorrect: false,
    enableInteractiveSelection: false,
    textAlign: textAlign,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      errorMaxLines: 3,
      // The lock screen's field is the design system's 44.
      isDense: dense ? true : null,
    ),
  );
}
