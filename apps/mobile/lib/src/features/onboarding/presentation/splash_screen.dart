import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    scheduleMicrotask(() async {
      await ref.read(appSessionProvider.notifier).bootstrap();
      if (!mounted) {
        return;
      }
      _route(ref.read(appSessionProvider));
    });
  }

  void _route(AppSessionState session) {
    if (!mounted) {
      return;
    }

    if (session.errorMessage != null) {
      return;
    }

    if (!session.onboardingAccepted) {
      context.go('/onboarding');
      return;
    }

    if (!session.isAuthenticated) {
      context.go('/create-account');
      return;
    }

    if (session.locked) {
      context.go('/lock');
      return;
    }

    context.go('/conversations');
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppSessionState>(appSessionProvider, (_, next) {
      if (!next.initializing) {
        _route(next);
      }
    });

    final session = ref.watch(appSessionProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final palette = context.veilPalette;

    // The name, the line VEIL stands for, and what the app is doing right
    // now (or why it cannot start). Nothing here is for reading twice.
    return VeilShell(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.splashEyebrow,
                  style: theme.textTheme.labelLarge?.copyWith(color: palette.primaryStrong),
                ),
                const SizedBox(height: VeilSpace.sm),
                Text(l10n.appTitle, style: theme.textTheme.displayLarge),
                const SizedBox(height: VeilSpace.xs),
                VeilCopy(
                  l10n.splashBody,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(color: palette.textMuted),
                ),
                if (session.errorMessage != null) ...[
                  const SizedBox(height: VeilSpace.xxl),
                  VeilInlineBanner(
                    title: l10n.splashErrorTitle,
                    message: veilErrorText(l10n, session.errorMessage!),
                    tone: VeilBannerTone.danger,
                  ),
                ] else
                  VeilLoadingBlock(
                    title: l10n.splashPreparingTitle,
                    body: l10n.splashPreparingBody,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
