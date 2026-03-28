import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../shared/presentation/veil_shell.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);

    return VeilShell(
      title: 'Settings',
      child: ListView(
        children: [
          Card(
            child: ListTile(
              title: Text(session.displayName ?? '@${session.handle ?? 'unbound'}'),
              subtitle: Text(session.deviceId ?? 'No active device'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('App lock'),
              subtitle: const Text('Biometric and PIN scaffold'),
              onTap: () => context.push('/lock'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Device transfer'),
              subtitle: const Text('Old device must approve'),
              onTap: () => context.push('/device-transfer'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Security status'),
              subtitle: const Text('Mock crypto adapter visibility'),
              onTap: () => context.push('/security-status'),
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Lock now'),
              onTap: () {
                ref.read(appSessionProvider.notifier).lock();
                context.go('/lock');
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Revoke this device'),
              subtitle: const Text('Destroys this bound session. No recovery exists.'),
              textColor: Theme.of(context).colorScheme.error,
              onTap: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Revoke this device?'),
                    content: const Text(
                      'This removes the active device binding for this account on this device. VEIL cannot restore it.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('Revoke'),
                      ),
                    ],
                  ),
                );

                if (confirmed != true) {
                  return;
                }

                await ref.read(appSessionProvider.notifier).revokeCurrentDevice();
                if (context.mounted) {
                  context.go('/create-account');
                }
              },
            ),
          ),
          Card(
            child: ListTile(
              title: const Text('Log out'),
              subtitle: const Text('Clears the local session only. No recovery exists.'),
              onTap: () async {
                await ref.read(appSessionProvider.notifier).logout();
                if (context.mounted) {
                  context.go('/create-account');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
