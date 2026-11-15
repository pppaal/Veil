import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/lib_crypto_adapter.dart';
import '../features/onboarding/presentation/brand_mark.dart';
import 'router/app_router.dart';
import '../core/theme/veil_theme.dart';
import '../l10n/generated/app_localizations.dart';
import 'app_state.dart';
import 'theme_mode_provider.dart';

class VeilApp extends ConsumerWidget {
  const VeilApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same instance for the app's lifetime: session changes re-run its
    // redirects instead of replacing it, so MaterialApp.router keeps the
    // current location across token refreshes and lock/unlock.
    final router = ref.watch(appRouterProvider);
    final notificationService = ref.read(localNotificationServiceProvider);

    notificationService.onNotificationTapped = (conversationId) {
      if (conversationId != null && conversationId.isNotEmpty) {
        router.go('/chat/$conversationId');
      }
    };

    return _PrivacyLifecycleBoundary(
      child: MaterialApp.router(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: VeilTheme.light(),
        darkTheme: VeilTheme.dark(),
        // Honor the user's persisted choice. Defaults to ThemeMode.system,
        // which follows the OS appearance until the user picks light/dark.
        themeMode: ref.watch(themeModeProvider),
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
      unawaited(ref.read(localNotificationServiceProvider).requestPermission());
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
        _flushPendingWrites();
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
        _flushPendingWrites();
        break;
    }
  }

  // Drain debounced writes (ratchet snapshots, messenger state) before the
  // OS freezes or kills the process — otherwise the latest state could be
  // lost within the debounce window.
  void _flushPendingWrites() {
    final adapter = ref.read(cryptoAdapterProvider);
    if (adapter is LibCryptoAdapter) {
      unawaited(adapter.flushPendingSnapshotWrites());
    }
    // A messenger not created yet has nothing to write.
    if (ref.exists(messengerControllerProvider)) {
      unawaited(ref.read(messengerControllerProvider).flushPendingWrites());
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
        // What the app switcher shows while the app is away: the page and
        // the mark, nothing of what was on screen and nothing to read.
        if (_obscured)
          IgnorePointer(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: const Center(child: BrandMark()),
            ),
          ),
      ],
    );
  }
}
