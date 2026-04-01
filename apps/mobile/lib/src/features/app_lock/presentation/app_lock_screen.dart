import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  final _pinController = TextEditingController();
  bool _hasPin = false;
  bool _loading = true;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hasPin = await ref.read(appLockServiceProvider).hasPin();
    if (!mounted) {
      return;
    }
    setState(() {
      _hasPin = hasPin;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  title: 'The server never unlocks VEIL.',
                  body:
                      'PIN and biometrics are strictly local controls. No remote reset. No recovery fallback. No server override.',
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const VeilSectionLabel('PIN'),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pinController,
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(labelText: _hasPin ? 'PIN' : 'Set PIN'),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            VeilStatusPill(
                              label: _hasPin ? 'PIN configured' : 'PIN not set',
                              tone: _hasPin ? VeilBannerTone.good : VeilBannerTone.warn,
                            ),
                            const VeilStatusPill(label: 'No reset flow'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 16),
                  VeilInlineBanner(
                    title: _status == 'Unlocked.' ? 'Unlocked' : 'Lock status',
                    message: _status!,
                    tone: _status == 'Unlocked.'
                        ? VeilBannerTone.good
                        : _status == 'PIN mismatch.' ||
                                _status == 'Enter a PIN first.' ||
                                _status == 'Biometric unlock failed.'
                            ? VeilBannerTone.danger
                            : VeilBannerTone.info,
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () async {
                    final appLock = ref.read(appLockServiceProvider);
                    final canUse = await appLock.canUseBiometrics();
                    if (!canUse) {
                      if (mounted) {
                        setState(() => _status = 'Biometrics unavailable on this device.');
                      }
                      return;
                    }

                    final authenticated = await appLock.authenticateBiometric();
                    if (!mounted) {
                      return;
                    }

                    if (authenticated) {
                      ref.read(appSessionProvider.notifier).unlock();
                      setState(() => _status = 'Unlocked.');
                      if (!context.mounted) {
                        return;
                      }
                      context.go('/conversations');
                      return;
                    }

                    setState(() => _status = 'Biometric unlock failed.');
                  },
                  child: const Text('Use biometrics'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _pinController.text.trim().isEmpty
                      ? null
                      : () async {
                          final pin = _pinController.text.trim();
                          if (pin.isEmpty) {
                            setState(() => _status = 'Enter a PIN first.');
                            return;
                          }

                          final appLock = ref.read(appLockServiceProvider);
                          if (!_hasPin) {
                            await appLock.setPin(pin);
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _hasPin = true;
                              _status = 'PIN set. Unlocking.';
                            });
                            ref.read(appSessionProvider.notifier).unlock();
                            if (!context.mounted) {
                              return;
                            }
                            context.go('/conversations');
                            return;
                          }

                          final valid = await appLock.validatePin(pin);
                          if (!mounted) {
                            return;
                          }

                          if (valid) {
                            ref.read(appSessionProvider.notifier).unlock();
                            setState(() => _status = 'Unlocked.');
                            if (!context.mounted) {
                              return;
                            }
                            context.go('/conversations');
                            return;
                          }

                          setState(() => _status = 'PIN mismatch.');
                        },
                  child: Text(_hasPin ? 'Unlock VEIL' : 'Set PIN and unlock'),
                ),
              ],
            ),
    );
  }
}
