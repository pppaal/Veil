import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'onboarding_action_scaffold.dart';

/// What the user takes on before there is an account: that it lives on
/// this phone, that losing the phone loses it, and that moving needs the
/// old phone. "Continue" waits for the box that says so to be ticked; both
/// stay at the foot of the screen, in reach on any height.
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
    context.go('/create-account');
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
        const SizedBox(height: VeilSpace.xl),
        _Line(icon: Icons.phone_iphone_outlined, text: l10n.onboardingWarnLine1),
        _Line(icon: Icons.cloud_off_outlined, text: l10n.onboardingWarnLine2),
        _Line(icon: Icons.swap_horiz_outlined, text: l10n.onboardingWarnLine3),
      ],
    );
  }
}

/// One of the three things to know, after a plain glyph.
class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VeilSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: VeilIconSize.md, color: context.veilPalette.textMuted),
          const SizedBox(width: VeilSpace.md),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
