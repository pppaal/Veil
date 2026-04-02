import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(appSessionProvider);

    return VeilShell(
      title: 'Settings',
      child: ListView(
        children: [
          VeilHeroPanel(
            eyebrow: 'LOCAL DEVICE',
            title: session.displayName ?? '@${session.handle ?? 'unbound'}',
            body: session.deviceId == null
                ? 'No active device session is bound.'
                : 'Current device session: ${session.deviceId}',
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                VeilStatusPill(label: 'No recovery'),
                VeilStatusPill(label: 'Device-bound'),
                VeilStatusPill(label: 'Private by design'),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          const VeilSectionLabel('SECURITY'),
          const SizedBox(height: VeilSpace.sm),
          VeilActionCluster(
            children: [
              VeilListTileCard(
                title: 'App lock',
                subtitle: 'Biometric and PIN barrier on this device only',
                leading: const Icon(Icons.lock_outline),
                onTap: () => context.push('/lock'),
              ),
              VeilListTileCard(
                title: 'Device transfer',
                subtitle: 'Old device must initiate and approve',
                leading: const Icon(Icons.phonelink_lock_outlined),
                onTap: () => context.push('/device-transfer'),
              ),
              VeilListTileCard(
                title: 'Security status',
                subtitle: 'Review local guardrails and runtime state',
                leading: const Icon(Icons.verified_user_outlined),
                onTap: () => context.push('/security-status'),
              ),
            ],
          ),
          const SizedBox(height: VeilSpace.md),
          const VeilSectionLabel('SESSION'),
          const SizedBox(height: VeilSpace.sm),
          VeilActionCluster(
            children: [
              VeilListTileCard(
                title: 'Lock now',
                subtitle: 'Hide the current session behind the local barrier immediately',
                leading: const Icon(Icons.visibility_off_outlined),
                onTap: () {
                  ref.read(appSessionProvider.notifier).lock();
                  context.go('/lock');
                },
              ),
              VeilListTileCard(
                title: 'Wipe local device state',
                subtitle:
                    'Deletes local session state, local secrets, encrypted cache, PIN, and onboarding state on this device only.',
                leading: Icon(
                  Icons.layers_clear_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                destructive: true,
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Wipe this device locally?'),
                      content: const Text(
                        'This erases local VEIL state on this device. It does not create a recovery path. If this is your only active device, access is gone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(dialogContext).pop(true),
                          child: const Text('Wipe local state'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed != true) {
                    return;
                  }

                  await ref.read(appSessionProvider.notifier).wipeLocalDeviceState();
                  if (context.mounted) {
                    context.go('/splash');
                  }
                },
              ),
              VeilListTileCard(
                title: 'Revoke this device',
                subtitle:
                    'Destroys this bound device session and wipes local state on this device. No recovery exists.',
                leading: Icon(
                  Icons.phonelink_erase_outlined,
                  color: Theme.of(context).colorScheme.error,
                ),
                destructive: true,
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('Revoke this device?'),
                      content: const Text(
                        'This removes the active device binding for this account on this device and wipes local state here. VEIL cannot restore it.',
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
              VeilListTileCard(
                title: 'Log out',
                subtitle:
                    'Clears this local session while leaving the onboarding acknowledgment and local barrier intact.',
                leading: const Icon(Icons.logout),
                onTap: () async {
                  await ref.read(appSessionProvider.notifier).logout();
                  if (context.mounted) {
                    context.go('/create-account');
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
