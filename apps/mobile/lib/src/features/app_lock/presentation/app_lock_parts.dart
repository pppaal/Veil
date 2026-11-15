import 'package:flutter/material.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_screen_intro.dart';
import '../../../shared/presentation/veil_ui.dart';

// What the lock screen says about itself: the outcome of the last attempt,
// how long a lockout lasts, and the facts about the local barrier.

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

  String title(AppLocalizations l10n) =>
      outcome == AppLockOutcome.unlocked ? l10n.appLockStatusUnlockedTitle : l10n.appLockStatusTitle;

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

  VeilBannerTone get tone => switch (outcome) {
        AppLockOutcome.unlocked => VeilBannerTone.good,
        AppLockOutcome.lockedTemporarily => VeilBannerTone.info,
        _ => VeilBannerTone.danger,
      };
}

/// "Try again in 40s." for what is left of a PIN lockout.
String formatAppLockRetry(AppLocalizations l10n, Duration? remaining) {
  final seconds = remaining == null || remaining.isNegative ? 0 : remaining.inSeconds;
  if (seconds <= 0) return l10n.appLockRetryNow;
  if (seconds < 60) return l10n.appLockRetrySeconds(seconds);
  return l10n.appLockRetryMinutes((seconds / 60).ceil());
}

/// What the device offers for the local barrier.
class AppLockFacts {
  const AppLockFacts({
    required this.hasPin,
    required this.biometricsAvailable,
    required this.captureBlocked,
  });

  final bool hasPin;
  final bool biometricsAvailable;
  final bool captureBlocked;

  /// The state of the PIN, biometrics and screen capture, as pills.
  List<Widget> statePills(AppLocalizations l10n) => [
        VeilStatusPill(
          label: hasPin ? l10n.appLockPillPinConfigured : l10n.appLockPillPinRequired,
          tone: hasPin ? VeilBannerTone.good : VeilBannerTone.warn,
        ),
        VeilStatusPill(
          label:
              biometricsAvailable ? l10n.appLockPillBiometricsAvailable : l10n.appLockPillBiometricsUnavailable,
          tone: biometricsAvailable ? VeilBannerTone.good : VeilBannerTone.info,
        ),
        VeilStatusPill(
          label: captureBlocked ? l10n.appLockPillCaptureBlocked : l10n.appLockPillPreviewShield,
          tone: captureBlocked ? VeilBannerTone.good : VeilBannerTone.warn,
        ),
      ];

  /// What never changes about the barrier, as pills: the wide layout's.
  static List<Widget> principlePills(AppLocalizations l10n) => [
        VeilStatusPill(label: l10n.appLockPillLocalOnly),
        VeilStatusPill(label: l10n.appLockPillNoRemoteReset),
        VeilStatusPill(label: l10n.pillNoRecovery),
      ];

  List<VeilMetricItem> metrics(AppLocalizations l10n) => [
        VeilMetricItem(
          label: l10n.appLockPinLabel,
          value: hasPin ? l10n.appLockMetricConfigured : l10n.appLockMetricRequired,
        ),
        VeilMetricItem(
          label: l10n.appLockMetricBiometrics,
          value: biometricsAvailable ? l10n.appLockMetricAvailable : l10n.appLockMetricUnavailable,
        ),
        VeilMetricItem(
          label: l10n.appLockMetricPreview,
          value: captureBlocked ? l10n.appLockMetricProtected : l10n.appLockMetricShielded,
        ),
      ];
}

/// The lock screen's opening words on a phone: what the wide layout says in
/// its hero panel, without the panel, so the PIN field stays on the first
/// screenful.
class AppLockCompactIntro extends StatelessWidget {
  const AppLockCompactIntro({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VeilScreenIntro(
      eyebrow: l10n.appLockHeroEyebrow,
      title: l10n.appLockHeroTitle,
      body: l10n.appLockHeroBody,
    );
  }
}
