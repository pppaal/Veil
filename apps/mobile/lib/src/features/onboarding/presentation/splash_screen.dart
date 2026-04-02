import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../core/theme/veil_theme.dart';
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

    return VeilShell(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VeilHeroPanel(
              eyebrow: 'PRIVATE BETA',
              title: 'VEIL',
              body: 'No backup. No recovery. No leaks.',
              bottom: Column(
                children: [
                  const Wrap(
                    spacing: VeilSpace.xs,
                    runSpacing: VeilSpace.xs,
                    alignment: WrapAlignment.center,
                    children: [
                      VeilStatusPill(label: 'Device-bound messenger'),
                      VeilStatusPill(label: 'Private beta'),
                    ],
                  ),
                  const SizedBox(height: VeilSpace.lg),
                  if (session.errorMessage != null)
                    VeilInlineBanner(
                      title: 'Runtime configuration blocked',
                      message: session.errorMessage!,
                      tone: VeilBannerTone.danger,
                    )
                  else
                    const VeilLoadingBlock(
                      title: 'Preparing local state',
                      body: 'Checking onboarding, session binding, and local security state.',
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
