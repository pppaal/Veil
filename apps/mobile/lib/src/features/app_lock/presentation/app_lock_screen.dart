import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

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
  String? _status;
  String? _lockoutStatus;
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
      _lockoutStatus = lockout == null ? null : _formatLockout(lockout);
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
    final appLock = ref.read(appLockServiceProvider);
    final isSettingPin = !_hasPin;
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    final pinFormatValid = pin.isEmpty || appLock.isValidPinFormat(pin);
    final pinLockedOut = _lockoutStatus != null && _hasPin;
    final canSubmit = !_submitting &&
        !_integrityCompromised &&
        pin.isNotEmpty &&
        (!isSettingPin || confirmPin.isNotEmpty) &&
        pinFormatValid &&
        !pinLockedOut;

    return VeilShell(
      title: 'App Lock',
      child: _loading
          ? const VeilLoadingBlock(
              title: 'Checking local barrier',
              body: 'Looking for a stored PIN and biometric availability.',
            )
          : ListView(
              children: [
                const VeilHeroPanel(
                  eyebrow: 'LOCAL BARRIER',
                  title: 'VEIL never unlocks itself remotely.',
                  body:
                      'PIN and biometrics are local only. No remote reset. No recovery fallback. No server override.',
                  bottom: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      VeilStatusPill(label: 'Local only'),
                      VeilStatusPill(label: 'No remote reset'),
                      VeilStatusPill(label: 'No recovery'),
                    ],
                  ),
                ),
                const SizedBox(height: VeilSpace.md),
                const VeilDestructiveNotice(
                  title: 'No recovery',
                  body:
                      'If you forget the local barrier and lose the active device, VEIL cannot restore access.',
                ),
                if (_integrityCompromised) ...[
                  const SizedBox(height: VeilSpace.md),
                  VeilInlineBanner(
                    title: 'Compromised device blocked',
                    message: _integrityReasons.isEmpty
                        ? 'This device appears rooted or jailbroken. VEIL blocks local unlock on compromised devices.'
                        : 'This device appears rooted or jailbroken. ${_integrityReasons.join(' | ')}',
                    tone: VeilBannerTone.danger,
                  ),
                ],
                if (_lockoutStatus != null) ...[
                  const SizedBox(height: VeilSpace.md),
                  VeilInlineBanner(
                    title: 'PIN temporarily locked',
                    message:
                        'Too many failed PIN attempts on this device. $_lockoutStatus',
                    tone: VeilBannerTone.warn,
                  ),
                ],
                const SizedBox(height: VeilSpace.md),
                VeilMetricStrip(
                  items: [
                    VeilMetricItem(
                      label: 'PIN',
                      value: _hasPin ? 'Configured' : 'Required',
                    ),
                    VeilMetricItem(
                      label: 'Biometrics',
                      value: _biometricsAvailable ? 'Available' : 'Unavailable',
                    ),
                    VeilMetricItem(
                      label: 'Preview',
                      value: _screenCaptureProtectionEnabled ? 'Protected' : 'Shielded',
                    ),
                  ],
                ),
                const SizedBox(height: VeilSpace.md),
                VeilFieldBlock(
                  label: 'PIN',
                  trailing: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      VeilStatusPill(
                        label: _hasPin ? 'PIN configured' : 'PIN required',
                        tone:
                            _hasPin ? VeilBannerTone.good : VeilBannerTone.warn,
                      ),
                      VeilStatusPill(
                        label: _biometricsAvailable
                            ? 'Biometrics available'
                            : 'Biometrics unavailable',
                        tone: _biometricsAvailable
                            ? VeilBannerTone.good
                            : VeilBannerTone.info,
                      ),
                      VeilStatusPill(
                        label: _screenCaptureProtectionEnabled
                            ? 'Capture blocked'
                            : 'Preview shield only',
                        tone: _screenCaptureProtectionEnabled
                            ? VeilBannerTone.good
                            : VeilBannerTone.warn,
                      ),
                    ],
                  ),
                  caption: isSettingPin
                      ? 'Set a local numeric barrier before continuing. VEIL cannot reset it for you.'
                      : 'Unlock with your local PIN or biometrics. This never contacts the server.',
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
                          _lockoutStatus = null;
                        }),
                        decoration: InputDecoration(
                          labelText: isSettingPin ? 'Set PIN' : 'PIN',
                          hintText: '6 to 12 digits',
                          errorText: pin.isEmpty || pinFormatValid
                              ? null
                              : 'Use 6 to 12 digits only.',
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
                            labelText: 'Confirm PIN',
                            hintText: 'Repeat the same PIN',
                            errorText: confirmPin.isEmpty || pin == confirmPin
                                ? null
                                : 'PIN confirmation does not match.',
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: VeilSpace.md),
                  VeilInlineBanner(
                    title: _status == 'Unlocked.' ? 'Unlocked' : 'Lock status',
                    message: _status!,
                    tone: _status == 'Unlocked.'
                        ? VeilBannerTone.good
                        : _status == 'Biometric unlock failed.' ||
                                _status == 'Enter a PIN first.' ||
                                _status == 'PIN mismatch.' ||
                                _status ==
                                    'Unlock blocked on compromised device.' ||
                                _status == 'PIN confirmation does not match.' ||
                                _status == 'PIN must be 6 to 12 digits.'
                            ? VeilBannerTone.danger
                            : VeilBannerTone.info,
                  ),
                ],
                const SizedBox(height: VeilSpace.md),
                VeilActionCluster(
                  children: [
                    if (_biometricsAvailable)
                      VeilButton(
                        onPressed: _submitting || _integrityCompromised
                            ? null
                            : _unlockWithBiometrics,
                        tone: VeilButtonTone.secondary,
                        label: 'Use biometrics',
                        icon: Icons.fingerprint_rounded,
                      ),
                    VeilButton(
                      onPressed: canSubmit ? _submitPin : null,
                      label:
                          isSettingPin ? 'Set PIN and unlock' : 'Unlock VEIL',
                      icon: Icons.lock_open_rounded,
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Future<void> _unlockWithBiometrics() async {
    if (_integrityCompromised) {
      setState(() {
        _status = 'Unlock blocked on compromised device.';
      });
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
        ref.read(appSessionProvider.notifier).unlock();
        setState(() {
          _status = 'Unlocked.';
          _lockoutStatus = null;
        });
        if (context.mounted) {
          context.go('/conversations');
        }
        return;
      }

      setState(() => _status = 'Biometric unlock failed.');
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
      setState(() {
        _status = 'Unlock blocked on compromised device.';
      });
      return;
    }

    final appLock = ref.read(appLockServiceProvider);
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();

    if (pin.isEmpty) {
      setState(() => _status = 'Enter a PIN first.');
      return;
    }
    if (!appLock.isValidPinFormat(pin)) {
      setState(() => _status = 'PIN must be 6 to 12 digits.');
      return;
    }

    setState(() {
      _submitting = true;
      _status = null;
    });

    try {
      if (!_hasPin) {
        if (pin != confirmPin) {
          setState(() => _status = 'PIN confirmation does not match.');
          return;
        }

        await appLock.setPin(pin);
        if (!mounted) {
          return;
        }
        setState(() {
          _hasPin = true;
          _status = 'Unlocked.';
          _lockoutStatus = null;
        });
      } else {
        final result = await appLock.validatePinAttempt(pin);
        if (!mounted) {
          return;
        }
        if (result.isLockedOut) {
          setState(() {
            _lockoutStatus = _formatLockout(result.remainingLockout);
            _status = 'PIN locked temporarily.';
          });
          return;
        }
        if (!result.isSuccess) {
          setState(() {
            _status = result.remainingAttempts == null
                ? 'PIN mismatch.'
                : 'PIN mismatch. ${result.remainingAttempts} attempt(s) left before temporary lock.';
          });
          return;
        }
        setState(() {
          _status = 'Unlocked.';
          _lockoutStatus = null;
        });
      }

      ref.read(appSessionProvider.notifier).unlock();
      if (context.mounted) {
        context.go('/conversations');
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  String _formatLockout(Duration? remaining) {
    final safeRemaining =
        remaining == null || remaining.isNegative ? Duration.zero : remaining;
    final seconds = safeRemaining.inSeconds;
    if (seconds <= 0) {
      return 'Try again now.';
    }
    if (seconds < 60) {
      return 'Try again in ${seconds}s.';
    }
    final minutes = (seconds / 60).ceil();
    return 'Try again in ${minutes}m.';
  }
}
