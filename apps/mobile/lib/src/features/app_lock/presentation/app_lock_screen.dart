import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'app_lock_parts.dart';

/// Under this width the lock screen is laid out for a phone: the PIN field
/// and its buttons first, what stands around them after.
const double _compactWidth = 600;

class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();

  bool _hasPin = false;
  bool _biometricsAvailable = false;
  bool _loading = true;
  bool _submitting = false;
  bool _integrityCompromised = false;
  bool _screenCaptureProtectionEnabled = false;
  AppLockStatus? _status;
  // What is left of a PIN lockout when it was last asked; null without one.
  Duration? _lockout;
  bool _lockedOut = false;
  List<String> _integrityReasons = const <String>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final appLock = ref.read(appLockServiceProvider);
    final values = await Future.wait<bool>([
      appLock.hasPin(),
      appLock.canUseBiometrics(),
    ]);
    final lockout = await appLock.remainingPinLockout();
    final platformSecurityService = ref.read(platformSecurityServiceProvider);
    await platformSecurityService.applyPrivacyProtections();
    final platformSecurity = await platformSecurityService.getStatus();
    if (!mounted) {
      return;
    }
    setState(() {
      _hasPin = values[0];
      _biometricsAvailable = values[1];
      _lockout = lockout;
      _lockedOut = lockout != null;
      _integrityCompromised = platformSecurity.integrityCompromised;
      _screenCaptureProtectionEnabled =
          platformSecurity.screenCaptureProtectionEnabled;
      _integrityReasons = platformSecurity.integrityReasons;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return VeilShell(
      title: l10n.appLockTitle,
      padding: VeilShell.formPadding,
      child: _loading
          ? VeilLoadingBlock(
              title: l10n.appLockLoadingTitle,
              body: l10n.appLockLoadingBody,
            )
          : LayoutBuilder(
              builder: (context, constraints) => ListView(
                children: _sections(context, compact: constraints.maxWidth < _compactWidth),
              ),
            ),
    );
  }

  List<Widget> _sections(BuildContext context, {required bool compact}) {
    final l10n = AppLocalizations.of(context);
    final appLock = ref.read(appLockServiceProvider);
    final isSettingPin = !_hasPin;
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    final pinFormatValid = pin.isEmpty || appLock.isValidPinFormat(pin);
    final pinLockedOut = _lockedOut && _hasPin;
    final canSubmit = !_submitting &&
        !_integrityCompromised &&
        pin.isNotEmpty &&
        (!isSettingPin || confirmPin.isNotEmpty) &&
        pinFormatValid &&
        !pinLockedOut;
    final facts = AppLockFacts(
      hasPin: _hasPin,
      biometricsAvailable: _biometricsAvailable,
      captureBlocked: _screenCaptureProtectionEnabled,
    );
    final status = _status;

    final noRecovery = VeilDestructiveNotice(
      title: l10n.pillNoRecovery,
      body: l10n.appLockNoRecoveryBody,
    );
    final warnings = <Widget>[
      if (_integrityCompromised) ...[
        const SizedBox(height: VeilSpace.md),
        VeilInlineBanner(
          title: l10n.appLockCompromisedTitle,
          message: _integrityReasons.isEmpty
              ? l10n.appLockCompromisedBody
              : l10n.appLockCompromisedReasons(_integrityReasons.join(' | ')),
          tone: VeilBannerTone.danger,
        ),
      ],
      if (_lockedOut) ...[
        const SizedBox(height: VeilSpace.md),
        VeilInlineBanner(
          title: l10n.appLockLockoutTitle,
          message: l10n.appLockLockoutBody(formatAppLockRetry(l10n, _lockout)),
          tone: VeilBannerTone.warn,
        ),
      ],
    ];
    final pinBlock = VeilFieldBlock(
      label: l10n.appLockPinLabel,
      // On a phone the pills do not fit beside the label: they follow the
      // buttons instead.
      trailing: compact ? null : Wrap(spacing: 8, runSpacing: 8, children: facts.statePills(l10n)),
      caption: isSettingPin ? l10n.appLockCaptionSet : l10n.appLockCaptionUnlock,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _pinController,
            obscureText: true,
            keyboardType: TextInputType.number,
            enableSuggestions: false,
            autocorrect: false,
            enableInteractiveSelection: false,
            onChanged: (_) => setState(() {
              _status = null;
              _lockout = null;
              _lockedOut = false;
            }),
            decoration: InputDecoration(
              labelText: isSettingPin ? l10n.appLockFieldSetPin : l10n.appLockPinLabel,
              hintText: l10n.appLockFieldPinHint,
              errorText: pin.isEmpty || pinFormatValid ? null : l10n.appLockFieldPinError,
            ),
          ),
          if (isSettingPin) ...[
            const SizedBox(height: VeilSpace.sm),
            TextField(
              controller: _confirmPinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              enableSuggestions: false,
              autocorrect: false,
              enableInteractiveSelection: false,
              onChanged: (_) => setState(() => _status = null),
              decoration: InputDecoration(
                labelText: l10n.appLockFieldConfirm,
                hintText: l10n.appLockFieldConfirmHint,
                errorText: confirmPin.isEmpty || pin == confirmPin ? null : l10n.appLockConfirmMismatch,
              ),
            ),
          ],
        ],
      ),
    );
    final statusBanner = <Widget>[
      if (status != null) ...[
        const SizedBox(height: VeilSpace.md),
        VeilInlineBanner(
          title: status.title(l10n),
          message: status.message(l10n),
          tone: status.tone,
        ),
      ],
    ];
    final biometrics = VeilButton(
      onPressed: _submitting || _integrityCompromised ? null : _unlockWithBiometrics,
      tone: VeilButtonTone.secondary,
      label: l10n.appLockUseBiometrics,
      icon: Icons.fingerprint_rounded,
    );
    final submit = VeilButton(
      onPressed: canSubmit ? _submitPin : null,
      label: isSettingPin ? l10n.appLockSetAndUnlock : l10n.appLockUnlock,
      icon: Icons.lock_open_rounded,
    );

    if (compact) {
      return [
        const AppLockCompactIntro(),
        // Choosing a PIN is the moment to know it cannot be recovered;
        // afterwards the reminder follows the unlock buttons.
        if (isSettingPin) ...[const SizedBox(height: VeilSpace.md), noRecovery],
        ...warnings,
        const SizedBox(height: VeilSpace.md),
        pinBlock,
        ...statusBanner,
        const SizedBox(height: VeilSpace.md),
        VeilActionCluster(children: [submit, if (_biometricsAvailable) biometrics]),
        if (!isSettingPin) ...[const SizedBox(height: VeilSpace.lg), noRecovery],
        // What this device offers. The rules that never change are in the
        // words above and in the notice; they are not repeated as pills.
        const SizedBox(height: VeilSpace.md),
        Wrap(spacing: 8, runSpacing: 8, children: facts.statePills(l10n)),
      ];
    }

    return [
      VeilHeroPanel(
        eyebrow: l10n.appLockHeroEyebrow,
        title: l10n.appLockHeroTitle,
        body: l10n.appLockHeroBody,
        bottom: Wrap(spacing: 8, runSpacing: 8, children: AppLockFacts.principlePills(l10n)),
      ),
      const SizedBox(height: VeilSpace.md),
      noRecovery,
      ...warnings,
      const SizedBox(height: VeilSpace.md),
      VeilMetricStrip(items: facts.metrics(l10n)),
      const SizedBox(height: VeilSpace.md),
      pinBlock,
      ...statusBanner,
      const SizedBox(height: VeilSpace.md),
      VeilActionCluster(children: [if (_biometricsAvailable) biometrics, submit]),
    ];
  }

  Future<void> _unlockWithBiometrics() async {
    if (_integrityCompromised) {
      setState(() => _status = const AppLockStatus(AppLockOutcome.blockedCompromised));
      return;
    }

    final appLock = ref.read(appLockServiceProvider);
    setState(() {
      _submitting = true;
      _status = null;
    });

    try {
      final authenticated = await appLock.authenticateBiometric();
      if (!mounted) {
        return;
      }

      if (authenticated) {
        // The router's lock guard navigates back to the interrupted screen.
        ref.read(appSessionProvider.notifier).unlock();
        setState(() {
          _status = const AppLockStatus(AppLockOutcome.unlocked);
          _lockout = null;
          _lockedOut = false;
        });
        return;
      }

      setState(() => _status = const AppLockStatus(AppLockOutcome.biometricFailed));
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _submitPin() async {
    if (_integrityCompromised) {
      setState(() => _status = const AppLockStatus(AppLockOutcome.blockedCompromised));
      return;
    }

    final appLock = ref.read(appLockServiceProvider);
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (pin.isEmpty) {
      setState(() => _status = const AppLockStatus(AppLockOutcome.enterPin));
      return;
    }
    if (!appLock.isValidPinFormat(pin)) {
      setState(() => _status = const AppLockStatus(AppLockOutcome.pinFormat));
      return;
    }

    setState(() {
      _submitting = true;
      _status = null;
    });

    try {
      if (!_hasPin) {
        if (pin != confirmPin) {
          setState(() => _status = const AppLockStatus(AppLockOutcome.confirmMismatch));
          return;
        }

        await appLock.setPin(pin);
        if (!mounted) {
          return;
        }
        setState(() {
          _hasPin = true;
          _status = const AppLockStatus(AppLockOutcome.unlocked);
          _lockout = null;
          _lockedOut = false;
        });
      } else {
        final result = await appLock.validatePinAttempt(pin);
        if (!mounted) {
          return;
        }
        if (result.isLockedOut) {
          setState(() {
            _lockout = result.remainingLockout;
            _lockedOut = true;
            _status = const AppLockStatus(AppLockOutcome.lockedTemporarily);
          });
          return;
        }
        if (!result.isSuccess) {
          setState(() {
            _status = AppLockStatus(AppLockOutcome.pinMismatch, remainingAttempts: result.remainingAttempts);
          });
          return;
        }
        setState(() {
          _status = const AppLockStatus(AppLockOutcome.unlocked);
          _lockout = null;
          _lockedOut = false;
        });
      }

      // The router's lock guard navigates back to the interrupted screen.
      ref.read(appSessionProvider.notifier).unlock();
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}
