import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/router/app_router.dart';
import '../core/theme/veil_theme.dart';
import '../shared/presentation/veil_ui.dart';
import 'app_state.dart';

class VeilApp extends ConsumerWidget {
  const VeilApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return _PrivacyLifecycleBoundary(
      child: MaterialApp.router(
        title: 'VEIL',
        theme: VeilTheme.dark(),
        debugShowCheckedModeBanner: false,
        routerConfig: router,
      ),
    );
  }
}

class _PrivacyLifecycleBoundary extends ConsumerStatefulWidget {
  const _PrivacyLifecycleBoundary({required this.child});

  final Widget child;

  @override
  ConsumerState<_PrivacyLifecycleBoundary> createState() =>
      _PrivacyLifecycleBoundaryState();
}

class _PrivacyLifecycleBoundaryState
    extends ConsumerState<_PrivacyLifecycleBoundary>
    with WidgetsBindingObserver {
  bool _obscured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPlatformSecurity();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _engagePrivacyShield();
        break;
      case AppLifecycleState.resumed:
        _refreshPlatformSecurity();
        unawaited(ref.read(messengerControllerProvider).handleAppResumed());
        Future<void>.delayed(const Duration(milliseconds: 180), () {
          if (!mounted) {
            return;
          }
          setState(() {
            _obscured = false;
          });
        });
        break;
      case AppLifecycleState.detached:
        _engagePrivacyShield();
        break;
    }
  }

  void _engagePrivacyShield() {
    final session = ref.read(appSessionProvider);
    if (session.isAuthenticated) {
      ref.read(appSessionProvider.notifier).lock();
    }
    if (mounted && !_obscured) {
      setState(() {
        _obscured = true;
      });
    }
  }

  Future<void> _refreshPlatformSecurity() async {
    final service = ref.read(platformSecurityServiceProvider);
    await service.applyPrivacyProtections();
    final status = await service.getStatus();
    if (!mounted) {
      return;
    }

    if (!status.integrityCompromised) {
      return;
    }

    final session = ref.read(appSessionProvider);
    if (session.isAuthenticated && !session.locked) {
      ref.read(appSessionProvider.notifier).lock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_obscured)
          IgnorePointer(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: const Padding(
                    padding: EdgeInsets.all(24),
                    child: VeilHeroPanel(
                      eyebrow: 'PRIVACY SHIELD',
                      title: 'VEIL is hidden while inactive.',
                      body:
                          'Recent-app previews are obscured and the local barrier is re-armed when the app leaves the foreground.',
                      bottom: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          VeilStatusPill(label: 'Session locked'),
                          VeilStatusPill(label: 'Preview obscured'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
