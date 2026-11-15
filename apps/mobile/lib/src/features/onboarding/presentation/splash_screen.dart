import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../../shared/presentation/veil_error_text.dart';
import '../../../shared/presentation/veil_shell.dart';
import '../../../shared/presentation/veil_ui.dart';
import 'brand_mark.dart';

const double _markWidth = 96;
const double _indicatorSize = 24;
const double _indicatorGap = 24;

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
    final error = session.errorMessage;

    // The mark where the native splash had it, and under it that the app
    // is starting; no words. Only a start that failed says something.
    return VeilShell(
      maxWidth: null,
      child: error != null
          ? VeilEmptyState.error(title: l10n.splashErrorTitle, body: veilErrorText(l10n, error))
          : SizedBox.expand(
              child: Stack(
                children: [
                  const Center(child: BrandMark(width: _markWidth)),
                  // 24 under the mark, which stays at the centre.
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: _markWidth + 2 * _indicatorGap + _indicatorSize),
                      child: Semantics(
                        label: l10n.splashPreparingTitle,
                        child: const SizedBox.square(
                          dimension: _indicatorSize,
                          child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
