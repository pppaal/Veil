import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'app_lock_parts.dart';

/// The app's lock. With a PIN it is the lock screen: "Veil is locked", the
/// PIN and the ways to unlock. Without one (the app locked before a PIN
/// was ever chosen) it is where the PIN is chosen.
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
    // The PIN and biometrics are read on this phone in a moment: the page
    // stays empty until they are, rather than showing one state and then
    // the other.
    if (_loading) return const VeilShell(child: SizedBox.shrink());
    if (!_hasPin) {
      return VeilShell(
        title: l10n.appLockTitle,
        grouped: true,
        child: ListView(
          padding: const EdgeInsets.only(top: VeilSpace.xl, bottom: VeilSpace.xl),
          children: _setUp(context),
        ),
      );
    }
    return VeilShell(
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
          children: _locked(context, constraints.maxHeight),
        ),
      ),
    );
  }

  bool get _canSubmit {
    final appLock = ref.read(appLockServiceProvider);
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    return !_submitting &&
        !_integrityCompromised &&
        pin.isNotEmpty &&
        (_hasPin || confirmPin.isNotEmpty) &&
        appLock.isValidPinFormat(pin) &&
        !(_lockedOut && _hasPin);
  }

  // What went wrong with the last attempt, said under the PIN field.
  String? _attemptError(AppLocalizations l10n) {
    final status = _status;
    if (status == null || !status.isFieldError || _lockedOut) return null;
    return status.message(l10n);
  }

  // A device that looks rooted or jailbroken does not unlock: said once,
  // with why, and nothing to tap.
  Widget _compromisedNotice(AppLocalizations l10n, {EdgeInsetsGeometry? margin}) => VeilNotice(
        tone: VeilTone.danger,
        margin: margin,
        message: _integrityReasons.isEmpty
            ? l10n.appLockCompromisedBody
            : l10n.appLockCompromisedReasons(_integrityReasons.join(' | ')),
      );

  Widget? _biometricsButton(AppLocalizations l10n) => !_biometricsAvailable
      ? null
      : VeilButton(
          onPressed: _submitting || _integrityCompromised ? null : _unlockWithBiometrics,
          tone: VeilButtonTone.ghost,
          label: l10n.appLockUseBiometrics,
        );

  TextField _pinField({
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

  void _pinChanged(String _) => setState(() {
        _status = null;
        _lockout = null;
        _lockedOut = false;
      });

  // The app is locked and has a PIN: the headline a quarter of the way
  // down, the PIN, Unlock, and biometrics when the phone has them. Why the
  // PIN cannot be entered (a lockout, a compromised device) is said under
  // the field.
  List<Widget> _locked(BuildContext context, double height) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;
    final appLock = ref.read(appLockServiceProvider);
    final pin = _pinController.text.trim();
    final formatError = pin.isEmpty || appLock.isValidPinFormat(pin) ? null : l10n.appLockFieldPinError;
    final biometrics = _biometricsButton(l10n);
    return [
      SizedBox(height: (height * 0.25 - 40).clamp(VeilSpace.md, double.infinity)),
      Semantics(
        header: true,
        child: Text(l10n.appLockLockedTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineLarge),
      ),
      const SizedBox(height: VeilSpace.xl),
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _pinField(
                controller: _pinController,
                hint: l10n.appLockPinLabel,
                textAlign: TextAlign.center,
                dense: true,
                errorText: formatError ?? _attemptError(l10n),
                onChanged: _pinChanged,
              ),
              if (_lockedOut) ...[
                const SizedBox(height: VeilSpace.xs),
                Text(
                  l10n.appLockLockoutBody(formatAppLockRetry(l10n, _lockout)),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted),
                ),
              ],
              if (_integrityCompromised) ...[
                const SizedBox(height: VeilSpace.sm),
                _compromisedNotice(l10n, margin: EdgeInsets.zero),
              ],
              const SizedBox(height: VeilSpace.md),
              VeilButton(onPressed: _canSubmit ? _submitPin : null, label: l10n.appLockUnlock),
              if (biometrics != null) ...[const SizedBox(height: VeilSpace.xs), biometrics],
            ],
          ),
        ),
      ),
      const SizedBox(height: VeilSpace.xl),
    ];
  }

  // No PIN yet: choose one, enter it again, turn the lock on. What the PIN
  // is and what forgetting it means is the group's footer.
  List<Widget> _setUp(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final appLock = ref.read(appLockServiceProvider);
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    final formatError = pin.isEmpty || appLock.isValidPinFormat(pin) ? null : l10n.appLockFieldPinError;
    final mismatch = confirmPin.isEmpty || pin == confirmPin ? null : l10n.appLockConfirmMismatch;
    final biometrics = _biometricsButton(l10n);
    final pinError = formatError ?? _attemptError(l10n);
    // The two labels share one width, so the fields start in one column.
    // An error line under a field keeps the row's 11 below it, off the
    // hairline and the group's edge.
    final labelWidth = MediaQuery.textScalerOf(context).scale(112);
    Widget labelled(String label, Widget field, {required bool hasError}) => Padding(
          padding: EdgeInsets.only(bottom: hasError ? 11 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              SizedBox(width: labelWidth, child: Text(label, style: Theme.of(context).textTheme.titleMedium)),
              Expanded(child: field),
            ],
          ),
        );

    return [
      if (_integrityCompromised) ...[
        _compromisedNotice(l10n, margin: const EdgeInsets.symmetric(horizontal: VeilSpace.md)),
        const SizedBox(height: VeilSpace.md),
      ],
      VeilGroup(
        footer: l10n.appLockSetupFooter,
        children: [
          VeilRow.field(
            field: labelled(
              l10n.appLockPinLabel,
              _pinField(
                controller: _pinController,
                hint: l10n.appLockFieldPinHint,
                errorText: pinError,
                onChanged: _pinChanged,
              ),
              hasError: pinError != null,
            ),
          ),
          VeilRow.field(
            field: labelled(
              l10n.appLockFieldConfirm,
              _pinField(
                controller: _confirmPinController,
                hint: l10n.appLockFieldConfirmHint,
                errorText: mismatch,
                onChanged: (_) => setState(() => _status = null),
              ),
              hasError: mismatch != null,
            ),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: VeilSpace.xs),
            VeilButton(onPressed: _canSubmit ? _submitPin : null, label: l10n.appLockTurnOn),
            if (biometrics != null) ...[const SizedBox(height: VeilSpace.xs), biometrics],
          ],
        ),
      ),
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
