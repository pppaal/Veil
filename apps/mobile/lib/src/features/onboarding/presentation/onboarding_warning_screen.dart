import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../shared/presentation/veil_shell.dart';

class OnboardingWarningScreen extends ConsumerWidget {
  const OnboardingWarningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return VeilShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No backup.\nNo recovery.\nNo leaks.', style: theme.textTheme.displayLarge),
          const SizedBox(height: 24),
          const _WarningCard(
            lines: [
              'If you lose your device, your account and messages are gone.',
              'This is intentional.',
              'VEIL cannot restore your access.',
            ],
          ),
          const SizedBox(height: 16),
          const _WarningCard(
            lines: [
              'Identity is bound to this device.',
              'Transfer only works when the old device still exists.',
              'There is no password reset path.',
            ],
          ),
          const Spacer(),
          FilledButton(
            onPressed: () async {
              await ref.read(appSessionProvider.notifier).acceptOnboarding();
              if (!context.mounted) {
                return;
              }
              context.go('/create-account');
            },
            child: const SizedBox(width: double.infinity, child: Center(child: Text('I understand'))),
          ),
        ],
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines) ...[
              Text(line),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}
