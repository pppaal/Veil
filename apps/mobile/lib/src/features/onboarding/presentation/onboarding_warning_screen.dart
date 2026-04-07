import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class OnboardingWarningScreen extends ConsumerWidget {
  const OnboardingWarningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return VeilShell(
      child: ListView(
        children: [
          VeilHeroPanel(
            eyebrow: 'PRODUCT RULES',
            title: 'No backup.\nNo recovery.\nNo leaks.',
            body:
                'VEIL is device-bound by design. Loss is final. Restore is unavailable. This is not a cloud inbox.',
            trailing: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outline),
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
              ),
              child: Icon(Icons.shield_outlined, color: theme.colorScheme.primary),
            ),
            bottom: const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: 'Device-bound'),
                VeilStatusPill(label: 'No password reset'),
                VeilStatusPill(label: 'Old device required'),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.lg),
          const VeilDestructiveNotice(
            title: 'Unrecoverable by design',
            body:
                'If you lose your device, your account and messages are gone. VEIL cannot restore your access.',
          ),
          const SizedBox(height: VeilSpace.md),
          const _WarningCard(
            title: 'Identity',
            lines: [
              'This device becomes your identity.',
              'Your private material stays on the device.',
              'There is no password reset path.',
            ],
          ),
          const SizedBox(height: VeilSpace.sm),
          const _WarningCard(
            title: 'Transfer',
            lines: [
              'Transfer works only while the old device still exists.',
              'The old device must approve the move.',
              'No old device means no transfer.',
            ],
          ),
          const SizedBox(height: VeilSpace.xl),
          VeilButton(
            onPressed: () async {
              await ref.read(appSessionProvider.notifier).acceptOnboarding();
              if (!context.mounted) {
                return;
              }
              context.go('/create-account');
            },
            label: 'I understand',
            icon: Icons.arrow_forward_rounded,
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return VeilSurfaceCard(
      toned: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: VeilSpace.sm),
          for (final line in lines) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.remove,
                  size: VeilIconSize.sm,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: VeilSpace.xs),
                Expanded(child: Text(line)),
              ],
            ),
            const SizedBox(height: VeilSpace.sm),
          ],
        ],
      ),
    );
  }
}
