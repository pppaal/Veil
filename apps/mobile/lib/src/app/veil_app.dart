import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/crypto/lib_crypto_adapter.dart';
import '../core/security/platform_security_service.dart';
import '../features/onboarding/presentation/brand_mark.dart';
import 'router/app_router.dart';
import '../core/theme/veil_theme.dart';
import '../l10n/generated/app_localizations.dart';
import 'app_state.dart';
import 'system_sheet_grace.dart';
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

/// The lock and the privacy cover, as the app's lifecycle and the session
/// move. Leaving the foreground covers the app and locks it, unless a
/// system sheet the user opened is up (SystemSheetGrace); on iOS the scene
/// entering the background always locks. Every lock, whatever caused it,
/// ends the running sheets, tells the platform (which on iOS closes what is
/// presented and keeps its cover until the lock screen is drawn) and drops
/// decrypted media from memory.
class _PrivacyLifecycleBoundaryState
    extends ConsumerState<_PrivacyLifecycleBoundary>
    with WidgetsBindingObserver {
  bool _obscured = false;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;
  StreamSubscription<PlatformSecurityEvent>? _securityEvents;
  ProviderSubscription<AppSessionState>? _sessionChanges;

  @override
  void initState() {
    super.initState();
    _lifecycle = WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _securityEvents = ref.read(platformSecurityServiceProvider).events.listen(_onPlatformSecurityEvent);
    _sessionChanges = ref.listenManual<AppSessionState>(appSessionProvider, _onSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPlatformSecurity();
      unawaited(ref.read(localNotificationServiceProvider).requestPermission());
      _syncMediaInUse();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_securityEvents?.cancel());
    _sessionChanges?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _engagePrivacyShield(state);
        _flushPendingWrites();
        break;
      case AppLifecycleState.resumed:
        // Back from a sheet that was up too long: locked before anything
        // else happens.
        if (ref.read(systemSheetGraceProvider).noteResumedShouldLock()) _lock();
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
        _engagePrivacyShield(state);
        _flushPendingWrites();
        break;
    }
    _syncMediaInUse();
  }

  void _onPlatformSecurityEvent(PlatformSecurityEvent event) {
    if (event != PlatformSecurityEvent.sceneEnteredBackground) return;
    ref.read(systemSheetGraceProvider).sceneEnteredBackground();
    _lock();
  }

  // Locked: an account whose lock screen is up.
  static bool _isLocked(AppSessionState session) => session.isAuthenticated && session.locked;

  void _onSessionChanged(AppSessionState? previous, AppSessionState next) {
    final wasLocked = previous != null && _isLocked(previous);
    final locked = _isLocked(next);
    final platformSecurity = ref.read(platformSecurityServiceProvider);
    if (locked && !wasLocked) {
      ref.read(systemSheetGraceProvider).closeAllForLock();
      unawaited(platformSecurity.lockEngaged());
      if (ref.exists(messengerControllerProvider)) ref.read(messengerControllerProvider).media.evictDecrypted();
      // The frame after the lock draws the lock screen; only then may the
      // native cover go.
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(platformSecurity.lockScreenShown()));
      WidgetsBinding.instance.ensureVisualUpdate();
    } else if (wasLocked && !locked) {
      unawaited(platformSecurity.sessionUnlocked());
    }
    _syncMediaInUse();
  }

  // Media work (prefetching photos) runs only while the app is in front
  // and unlocked.
  void _syncMediaInUse() {
    final session = ref.read(appSessionProvider);
    final inUse = _lifecycle == AppLifecycleState.resumed && session.isAuthenticated && !session.locked;
    if (inUse) {
      ref.read(messengerControllerProvider).media.setInUse(true);
    } else if (ref.exists(messengerControllerProvider)) {
      ref.read(messengerControllerProvider).media.setInUse(false);
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

  // Always covers; locks unless a system sheet the user opened is up.
  void _engagePrivacyShield(AppLifecycleState state) {
    if (ref.read(systemSheetGraceProvider).shouldLockOn(state)) _lock();
    if (mounted && !_obscured) {
      setState(() {
        _obscured = true;
      });
    }
  }

  void _lock() {
    final session = ref.read(appSessionProvider);
    if (session.isAuthenticated) {
      ref.read(appSessionProvider.notifier).lock();
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
      // Above MaterialApp there is no Directionality to resolve the default
      // start alignment against; both children fill the stack anyway.
      alignment: Alignment.center,
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
