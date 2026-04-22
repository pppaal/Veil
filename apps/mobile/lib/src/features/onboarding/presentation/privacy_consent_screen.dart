import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class PrivacyConsentScreen extends ConsumerStatefulWidget {
  const PrivacyConsentScreen({super.key});

  @override
  ConsumerState<PrivacyConsentScreen> createState() =>
      _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends ConsumerState<PrivacyConsentScreen> {
  bool _consentChecked = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);

    return VeilShell(
      child: ListView(
        children: [
          VeilHeroPanel(
            eyebrow: l10n.privacyConsentEyebrow,
            title: l10n.privacyConsentHeroTitle,
            body: l10n.privacyConsentHeroBody,
          ),
          const SizedBox(height: VeilSpace.lg),
          VeilSurfaceCard(
            toned: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PolicySection(
                  title: l10n.privacyConsentCollectTitle,
                  items: [
                    l10n.privacyConsentCollectItem1,
                    l10n.privacyConsentCollectItem2,
                    l10n.privacyConsentCollectItem3,
                  ],
                ),
                const SizedBox(height: VeilSpace.md),
                _PolicySection(
                  title: l10n.privacyConsentPurposeTitle,
                  items: [
                    l10n.privacyConsentPurposeItem1,
                    l10n.privacyConsentPurposeItem2,
                    l10n.privacyConsentPurposeItem3,
                  ],
                ),
                const SizedBox(height: VeilSpace.md),
                _PolicySection(
                  title: l10n.privacyConsentRetentionTitle,
                  items: [
                    l10n.privacyConsentRetentionItem1,
                    l10n.privacyConsentRetentionItem2,
                    l10n.privacyConsentRetentionItem3,
                  ],
                ),
                const SizedBox(height: VeilSpace.md),
                _PolicySection(
                  title: l10n.privacyConsentRightsTitle,
                  items: [
                    l10n.privacyConsentRightsItem1,
                    l10n.privacyConsentRightsItem2,
                    l10n.privacyConsentRightsItem3,
                  ],
                ),
                const SizedBox(height: VeilSpace.md),
                _PolicySection(
                  title: l10n.privacyConsentNotCollectedTitle,
                  items: [
                    l10n.privacyConsentNotCollectedItem1,
                    l10n.privacyConsentNotCollectedItem2,
                    l10n.privacyConsentNotCollectedItem3,
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.md),
          VeilInlineBanner(
            title: l10n.privacyConsentThirdPartyTitle,
            message: l10n.privacyConsentThirdPartyBody,
          ),
          const SizedBox(height: VeilSpace.lg),
          GestureDetector(
            onTap: () => setState(() => _consentChecked = !_consentChecked),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: _consentChecked,
                    onChanged: (value) =>
                        setState(() => _consentChecked = value ?? false),
                  ),
                ),
                const SizedBox(width: VeilSpace.sm),
                Expanded(
                  child: Text(
                    l10n.privacyConsentAgree,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                          height: 1.5,
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VeilSpace.xl),
          VeilButton(
            onPressed: _consentChecked
                ? () async {
                    await ref
                        .read(appSessionProvider.notifier)
                        .acceptPrivacyConsent();
                    if (!context.mounted) return;
                    context.go('/onboarding');
                  }
                : null,
            label: l10n.privacyConsentAccept,
            icon: Icons.arrow_forward_rounded,
          ),
          const SizedBox(height: VeilSpace.md),
        ],
      ),
    );
  }
}

class _PolicySection extends StatelessWidget {
  const _PolicySection({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: VeilSpace.xs),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('  •  ', style: TextStyle(color: palette.primary)),
                Expanded(
                  child: Text(
                    item,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: palette.textMuted,
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
