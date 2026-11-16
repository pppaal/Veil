import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'onboarding_action_scaffold.dart';

/// The privacy notice and the consent to it. The notice reads as a
/// document: a small bold heading, then its items as plain paragraphs. The
/// box that gives consent and the button that goes on stay under it, so
/// they are in reach from the first line to the last. The button does
/// nothing until the box is ticked.
class PrivacyConsentScreen extends ConsumerStatefulWidget {
  const PrivacyConsentScreen({super.key});

  @override
  ConsumerState<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends ConsumerState<PrivacyConsentScreen> {
  bool _consentChecked = false;

  Future<void> _accept() async {
    await ref.read(appSessionProvider.notifier).acceptPrivacyConsent();
    if (!mounted) return;
    context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return OnboardingActionScaffold(
      title: l10n.privacyConsentTitle,
      listPadding: const EdgeInsets.fromLTRB(VeilSpace.md, 0, VeilSpace.md, VeilSpace.md),
      actions: [
        // The box and its sentence are one row to tap, and one checkbox
        // with its sentence to a screen reader.
        CheckboxListTile(
          value: _consentChecked,
          onChanged: (value) => setState(() => _consentChecked = value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          // The box, not its tap area, lines up with the text above.
          contentPadding: const EdgeInsetsDirectional.only(start: VeilSpace.xxs, end: VeilSpace.md),
          title: Text(l10n.privacyConsentAgree, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(height: VeilSpace.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
          child: VeilButton(label: l10n.privacyConsentAccept, onPressed: _consentChecked ? _accept : null),
        ),
      ],
      children: [
        _NoticeGroup(
          header: l10n.privacyConsentCollectTitle,
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
        _NoticeGroup(
          header: l10n.privacyConsentPurposeTitle,
          items: [
            l10n.privacyConsentPurposeItem1,
            l10n.privacyConsentPurposeItem2,
            l10n.privacyConsentPurposeItem3,
          ],
        ),
        _NoticeGroup(
          header: l10n.privacyConsentRetentionTitle,
          items: [
            l10n.privacyConsentRetentionItem1,
            l10n.privacyConsentRetentionItem2,
            l10n.privacyConsentRetentionItem3,
          ],
        ),
        _NoticeGroup(
          header: l10n.privacyConsentRightsTitle,
          items: [
            l10n.privacyConsentRightsItem1,
            l10n.privacyConsentRightsItem2,
            l10n.privacyConsentRightsItem3,
          ],
        ),
        _NoticeGroup(
          header: l10n.privacyConsentNotCollectedTitle,
          items: [
            l10n.privacyConsentNotCollectedItem1,
            l10n.privacyConsentNotCollectedItem2,
            l10n.privacyConsentNotCollectedItem3,
          ],
        ),
        _NoticeGroup(
          header: l10n.privacyConsentThirdPartyTitle,
          items: [l10n.privacyConsentThirdPartyBody],
        ),
      ],
    );
  }
}

/// One heading of the notice and its items, a plain paragraph each.
class _NoticeGroup extends StatelessWidget {
  const _NoticeGroup({required this.header, required this.items});

  final String header;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: VeilSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(header, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: VeilSpace.xs),
              child: Text(item, style: theme.textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}
