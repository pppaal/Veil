import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'onboarding_action_scaffold.dart';

/// What the user takes on before there is an account: that it lives on
/// this phone, that losing the phone loses it, and that moving needs this
/// phone. Plain sentences, no list. "Continue" waits for the box that says
/// so to be ticked; both stay at the foot of the screen, in reach on any
/// height.
class OnboardingWarningScreen extends ConsumerStatefulWidget {
  const OnboardingWarningScreen({super.key});

  @override
  ConsumerState<OnboardingWarningScreen> createState() => _OnboardingWarningScreenState();
}

class _OnboardingWarningScreenState extends ConsumerState<OnboardingWarningScreen> {
  bool _understood = false;

  Future<void> _continue() async {
    await ref.read(appSessionProvider.notifier).acceptOnboarding();
    if (!mounted) return;
    context.go('/choose-handle');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return OnboardingActionScaffold(
      actions: [
        CheckboxListTile(
          value: _understood,
          onChanged: (value) => setState(() => _understood = value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          // The box, not its tap area, lines up with the text above.
          contentPadding: const EdgeInsetsDirectional.only(start: VeilSpace.xxs, end: VeilSpace.md),
          title: Text(l10n.onboardingWarnAgreeCheckbox, style: theme.textTheme.bodyLarge),
        ),
        const SizedBox(height: VeilSpace.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: VeilSpace.md),
          child: VeilButton(label: l10n.commonContinue, onPressed: _understood ? _continue : null),
        ),
      ],
      children: [
        Semantics(header: true, child: Text(l10n.onboardingWarnTitle, style: theme.textTheme.headlineLarge)),
        const SizedBox(height: VeilSpace.lg),
        for (final line in [l10n.onboardingWarnLine1, l10n.onboardingWarnLine2, l10n.onboardingWarnLine3])
          Padding(
            padding: const EdgeInsets.only(bottom: VeilSpace.md),
            child: Text(line, style: theme.textTheme.bodyLarge),
          ),
      ],
    );
  }
}
