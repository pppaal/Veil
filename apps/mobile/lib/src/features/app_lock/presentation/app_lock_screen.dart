import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../shared/presentation/veil_shell.dart';

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
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Local barrier only.', style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: 12),
                const Text('Biometric and PIN hooks belong on the device. The server never helps.'),
                const SizedBox(height: 24),
                TextField(
                  controller: _pinController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: _hasPin ? 'PIN' : 'Set PIN'),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _status!,
                    style: TextStyle(
                      color: _status == 'Unlocked.'
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
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
                const Spacer(),
                FilledButton(
                  onPressed: () async {
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
                  child: SizedBox(
                    width: double.infinity,
                    child: Center(child: Text(_hasPin ? 'Unlock' : 'Set PIN and unlock')),
                  ),
                ),
              ],
            ),
    );
  }
}
