import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
import '../../../l10n/generated/app_localizations.dart';
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

    return VeilShell(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VeilHeroPanel(
              eyebrow: l10n.splashEyebrow,
              title: l10n.appTitle,
              body: l10n.splashBody,
              bottom: Column(
                children: [
                  Wrap(
                    spacing: VeilSpace.xs,
                    runSpacing: VeilSpace.xs,
                    alignment: WrapAlignment.center,
                    children: [
                      VeilStatusPill(label: l10n.pillDeviceBoundMessenger),
                      VeilStatusPill(label: l10n.pillPrivateBeta),
                    ],
                  ),
                  const SizedBox(height: VeilSpace.lg),
                  if (session.errorMessage != null)
                    VeilInlineBanner(
                      title: l10n.splashErrorTitle,
                        message: session.errorMessage!,
                        tone: VeilBannerTone.danger,
                      )
                  else
                    VeilSurfaceCard(
                      toned: true,
                      child: Column(
                        children: [
                          VeilLoadingBlock(
                            title: l10n.splashPreparingTitle,
                            body: l10n.splashPreparingBody,
                          ),
                          const SizedBox(height: VeilSpace.md),
                          const Row(
                            children: [
                              Expanded(child: VeilSkeletonLine()),
                              SizedBox(width: VeilSpace.sm),
                              VeilSkeletonLine(width: 72),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
