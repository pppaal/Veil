import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_screen_intro.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'onboarding_action_scaffold.dart';

// Above and below the consent row, inside what a tap on it reaches.
const double _consentRowPadding = 10;

/// The privacy notice and the consent to it. The notice scrolls; the box
/// that gives consent and the button that goes on stay under it, so they
/// are in reach from the first line to the last. The button does nothing
/// until the box is ticked.
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

    return OnboardingActionScaffold(
      title: l10n.privacyConsentTitle,
      actions: [
        // The box and its sentence are one thing to tap, 44 px tall or
        // more, and a screen reader reads one checkbox with its sentence.
        MergeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _consentChecked = !_consentChecked),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: _consentRowPadding),
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
                    child: VeilCopy(
                      l10n.privacyConsentAgree,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: palette.text,
                            height: 1.5,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: VeilSpace.xs),
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
      ],
      children: [
        VeilScreenIntro(
          title: l10n.privacyConsentSubtitle,
          body: l10n.privacyConsentHeroBody,
        ),
        const SizedBox(height: VeilSpace.lg),
        _PolicySection(
          title: l10n.privacyConsentCollectTitle,
          items: [
            l10n.privacyConsentCollectItem1,
            l10n.privacyConsentCollectItem2,
            l10n.privacyConsentCollectItem3,
            l10n.privacyConsentCollectItem4,
            l10n.privacyConsentCollectItem5,
            l10n.privacyConsentCollectItem6,
            l10n.privacyConsentCollectItem7,
          ],
        ),
        _PolicySection(
          title: l10n.privacyConsentPurposeTitle,
          items: [
            l10n.privacyConsentPurposeItem1,
            l10n.privacyConsentPurposeItem2,
            l10n.privacyConsentPurposeItem3,
          ],
        ),
        _PolicySection(
          title: l10n.privacyConsentRetentionTitle,
          items: [
            l10n.privacyConsentRetentionItem1,
            l10n.privacyConsentRetentionItem2,
            l10n.privacyConsentRetentionItem3,
          ],
        ),
        _PolicySection(
          title: l10n.privacyConsentRightsTitle,
          items: [
            l10n.privacyConsentRightsItem1,
            l10n.privacyConsentRightsItem2,
            l10n.privacyConsentRightsItem3,
          ],
        ),
        _PolicySection(
          title: l10n.privacyConsentNotCollectedTitle,
          items: [
            l10n.privacyConsentNotCollectedItem1,
            l10n.privacyConsentNotCollectedItem2,
            l10n.privacyConsentNotCollectedItem3,
          ],
        ),
        _PolicySection(
          title: l10n.privacyConsentThirdPartyTitle,
          paragraph: l10n.privacyConsentThirdPartyBody,
          last: true,
        ),
      ],
    );
  }
}

/// One heading of the notice with what stands under it: a list of items,
/// or a paragraph.
class _PolicySection extends StatelessWidget {
  const _PolicySection({
    required this.title,
    this.items = const [],
    this.paragraph,
    this.last = false,
  });

  final String title;
  final List<String> items;
  final String? paragraph;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(color: palette.textMuted);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : VeilSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VeilCopy(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: VeilSpace.xs),
          if (paragraph != null) VeilCopy(paragraph!, style: body),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: VeilSpace.xxs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: VeilSpace.md,
                    child: Text('•', style: body?.copyWith(color: palette.primary)),
                  ),
                  Expanded(child: VeilCopy(item, style: body)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
