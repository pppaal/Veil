import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
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
          ),
          const SizedBox(height: 20),
          const VeilInlineBanner(
            title: 'Unrecoverable by design',
            message:
                'If you lose your device, your account and messages are gone. VEIL cannot restore your access.',
            tone: VeilBannerTone.warn,
          ),
          const SizedBox(height: 16),
          const _WarningCard(
            title: 'Identity',
            lines: [
              'This device becomes your identity.',
              'Your private material stays on the device.',
              'There is no password reset path.',
            ],
          ),
          const SizedBox(height: 12),
          const _WarningCard(
            title: 'Transfer',
            lines: [
              'Transfer works only while the old device still exists.',
              'The old device must approve the move.',
              'No old device means no transfer.',
            ],
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: () async {
              await ref.read(appSessionProvider.notifier).acceptOnboarding();
              if (!context.mounted) {
                return;
              }
              context.go('/create-account');
            },
            child: const Text('I understand'),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            for (final line in lines) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.remove,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(line)),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}
