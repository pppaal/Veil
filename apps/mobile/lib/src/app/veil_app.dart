import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/lib_crypto_adapter.dart';
import '../core/router/app_router.dart';
import '../core/theme/veil_theme.dart';
import '../l10n/generated/app_localizations.dart';
import '../shared/presentation/veil_ui.dart';
import 'app_state.dart';

class VeilApp extends ConsumerWidget {
  const VeilApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final notificationService = ref.read(localNotificationServiceProvider);

    notificationService.onNotificationTapped = (conversationId) {
      if (conversationId != null && conversationId.isNotEmpty) {
        router.go('/chat/$conversationId');
      }
    };

    return _PrivacyLifecycleBoundary(
      child: MaterialApp.router(
        title: 'VEIL',
        theme: VeilTheme.light(),
        darkTheme: VeilTheme.dark(),
        themeMode: ThemeMode.system,
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
        _flushPendingRatchetSnapshots();
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
        _flushPendingRatchetSnapshots();
        break;
    }
  }

  // Drain debounced session-snapshot writes before the OS freezes or kills
  // the process — otherwise the latest ratchet state could be lost within
  // the debounce window. Safe to call unconditionally: no-op if the active
  // adapter doesn't use the debounced persister.
  void _flushPendingRatchetSnapshots() {
    final adapter = ref.read(cryptoAdapterProvider);
    if (adapter is LibCryptoAdapter) {
      unawaited(adapter.flushPendingSnapshotWrites());
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
    final l10n = AppLocalizations.of(context);
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
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: VeilHeroPanel(
                      eyebrow: l10n.privacyShieldEyebrow,
                      title: l10n.privacyShieldTitle,
                      body: l10n.privacyShieldBody,
                      bottom: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          VeilStatusPill(label: l10n.pillSessionLocked),
                          VeilStatusPill(label: l10n.pillPreviewObscured),
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
