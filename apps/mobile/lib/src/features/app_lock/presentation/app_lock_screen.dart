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
  String? _status;

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
    if (!mounted) {
      return;
    }
    setState(() {
      _hasPin = values[0];
      _biometricsAvailable = values[1];
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
    final canSubmit = !_submitting &&
        pin.isNotEmpty &&
        (!isSettingPin || confirmPin.isNotEmpty) &&
        pinFormatValid;

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
                ),
                const SizedBox(height: VeilSpace.md),
                const VeilInlineBanner(
                  title: 'No recovery',
                  message:
                      'If you forget the local barrier and lose the active device, VEIL cannot restore access.',
                  tone: VeilBannerTone.warn,
                ),
                const SizedBox(height: VeilSpace.md),
                VeilSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      VeilSectionLabel(
                        'PIN',
                        trailing: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            VeilStatusPill(
                              label: _hasPin ? 'PIN configured' : 'PIN required',
                              tone: _hasPin ? VeilBannerTone.good : VeilBannerTone.warn,
                            ),
                            VeilStatusPill(
                              label: _biometricsAvailable
                                  ? 'Biometrics available'
                                  : 'Biometrics unavailable',
                              tone: _biometricsAvailable
                                  ? VeilBannerTone.good
                                  : VeilBannerTone.info,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: VeilSpace.sm),
                      TextField(
                        controller: _pinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() => _status = null),
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
                      const SizedBox(height: VeilSpace.sm),
                      Text(
                        isSettingPin
                            ? 'Set a local numeric barrier before continuing. VEIL cannot reset it for you.'
                            : 'Unlock with your local PIN or biometrics. This never contacts the server.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
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
                      OutlinedButton(
                        onPressed: _submitting ? null : _unlockWithBiometrics,
                        child: const Text('Use biometrics'),
                      ),
                    FilledButton(
                      onPressed: canSubmit ? _submitPin : null,
                      child: Text(isSettingPin ? 'Set PIN and unlock' : 'Unlock VEIL'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Future<void> _unlockWithBiometrics() async {
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
        setState(() => _status = 'Unlocked.');
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
        });
      } else {
        final valid = await appLock.validatePin(pin);
        if (!mounted) {
          return;
        }
        if (!valid) {
          setState(() => _status = 'PIN mismatch.');
          return;
        }
        setState(() => _status = 'Unlocked.');
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
}
