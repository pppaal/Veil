import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class OnboardingWarningScreen extends ConsumerWidget {
  const OnboardingWarningScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return VeilShell(
      child: ListView(
        children: [
          VeilHeroPanel(
            eyebrow: l10n.onboardingWarnEyebrow,
            title: l10n.onboardingWarnTitle,
            body: l10n.onboardingWarnBody,
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
            bottom: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                VeilStatusPill(label: l10n.pillDeviceBound),
                VeilStatusPill(label: l10n.pillNoPasswordReset),
                VeilStatusPill(label: l10n.pillOldDeviceRequired),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.lg),
          VeilDestructiveNotice(
            title: l10n.onboardingWarnDestructiveTitle,
            body: l10n.onboardingWarnDestructiveBody,
          ),
          const SizedBox(height: VeilSpace.md),
          _WarningCard(
            title: l10n.onboardingWarnIdentityTitle,
            lines: [
              l10n.onboardingWarnIdentityLine1,
              l10n.onboardingWarnIdentityLine2,
              l10n.onboardingWarnIdentityLine3,
            ],
          ),
          const SizedBox(height: VeilSpace.sm),
          _WarningCard(
            title: l10n.onboardingWarnTransferTitle,
            lines: [
              l10n.onboardingWarnTransferLine1,
              l10n.onboardingWarnTransferLine2,
              l10n.onboardingWarnTransferLine3,
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
            label: l10n.commonIUnderstand,
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
