import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_state.dart';
import '../../../shared/presentation/veil_shell.dart';

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

    return const VeilShell(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('VEIL', style: TextStyle(fontSize: 42, fontWeight: FontWeight.w700)),
            SizedBox(height: 12),
            Text('No backup. No recovery. No leaks.'),
          ],
        ),
      ),
    );
  }
}
