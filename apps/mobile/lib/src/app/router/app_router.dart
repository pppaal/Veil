import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/veil_theme.dart';
import '../../features/app_lock/presentation/app_lock_screen.dart';
import '../../features/auth/presentation/choose_handle_screen.dart';
import '../../features/auth/presentation/create_account_screen.dart';
import '../../features/chat/presentation/chat_room_screen.dart';
import '../../features/secret_link/presentation/one_time_link_screen.dart';
import '../../features/contacts/presentation/contacts_screen.dart';
import '../../features/conversations/data/conversation_models.dart';
import '../../features/conversations/presentation/conversation_list_screen.dart';
import '../../features/conversations/presentation/start_direct_chat_screen.dart';
import '../../features/conversations/presentation/start_group_screen.dart';
import '../../features/device_transfer/presentation/device_transfer_screen.dart';
import '../../features/onboarding/presentation/onboarding_warning_screen.dart';
import '../../features/onboarding/presentation/privacy_consent_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/security/presentation/safety_numbers_screen.dart';
import '../../features/security_status/presentation/security_status_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/trusted_devices_screen.dart';
import '../app_state.dart';
import 'main_tab_shell.dart';
import 'route_guard.dart';

/// The app's route table. Separate from [appRouterProvider] so tests can
/// exercise the real guard and refresh wiring against lightweight screens.
final appRoutesProvider = Provider<List<RouteBase>>((ref) => _buildRoutes());

/// The single router for the app's lifetime.
///
/// It reads the session instead of watching it: rebuilding the router on
/// every session change (token refresh, lock) restarted navigation at
/// /splash and threw the user out of the screen they were on. Session
/// changes now only re-run the redirect, and only when the routing-relevant
/// [RouteGuardState] actually changed.
final appRouterProvider = Provider<GoRouter>((ref) {
  final guard = ValueNotifier<RouteGuardState>(
    RouteGuardState.fromSession(ref.read(appSessionProvider)),
  );
  final router = GoRouter(
    initialLocation: '/splash',
    refreshListenable: guard,
    redirect: (context, state) => redirectFor(guard.value, state.uri),
    routes: ref.read(appRoutesProvider),
    // A location no route has (an old link, a mistyped one) has nothing to
    // show. It opens the app where it normally opens instead of a dead end,
    // and the guard above still has the last word on where that is.
    onException: (context, state, router) => router.go('/conversations'),
  );

  // Locking replaces the navigation stack, and `?from=` can only name its
  // base location: GoRouter keeps pushed pages (a chat opened from the list)
  // out of it. Keeping the stack lets unlock put those pages back as well.
  RouteMatchList? stackBeforeLock;
  ref.listen<AppSessionState>(appSessionProvider, (_, next) {
    final previous = guard.value;
    final updated = RouteGuardState.fromSession(next);
    final current = router.routerDelegate.currentConfiguration;
    if (!previous.lockedOut && updated.lockedOut && current.isNotEmpty) {
      stackBeforeLock = current;
    }
    final interruptedStack = stackBeforeLock;
    final unlocked =
        previous.lockedOut && updated.authenticated && !updated.locked;
    final resume = unlocked &&
        interruptedStack != null &&
        resumesInterruptedLocation(current.uri, interruptedStack.uri);
    if (!updated.lockedOut) {
      stackBeforeLock = null;
    }
    // ValueNotifier only notifies when the new value differs (==), so a
    // token-only change never refreshes the router.
    guard.value = updated;
    if (resume) {
      // Restoring re-runs the redirect, so the guard still has the last word.
      router.restore(interruptedStack);
    }
  });
  ref.onDispose(() {
    router.dispose();
    guard.dispose();
  });
  return router;
});

List<RouteBase> _buildRoutes() {
  return [
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(
      path: '/privacy-consent',
      pageBuilder: (context, state) =>
          _veilFadePage(state, const PrivacyConsentScreen()),
    ),
    GoRoute(
      path: '/onboarding',
      pageBuilder: (context, state) =>
          _veilFadePage(state, const OnboardingWarningScreen()),
    ),
    GoRoute(
      path: '/create-account',
      pageBuilder: (context, state) =>
          _veilFadePage(state, const CreateAccountScreen()),
    ),
    GoRoute(
      path: '/choose-handle',
      pageBuilder: (context, state) =>
          _veilFadePage(state, const ChooseHandleScreen()),
    ),
    ShellRoute(
      // Per route table, so two routers (e.g. consecutive tests) never share
      // one GlobalKey.
      navigatorKey: GlobalKey<NavigatorState>(),
      builder: (context, state, child) => MainTabShell(child: child),
      routes: [
        GoRoute(path: '/conversations', builder: (context, state) => const ConversationListScreen()),
        GoRoute(path: '/contacts', builder: (context, state) => const ContactsScreen()),
        GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      ],
    ),
    GoRoute(
      path: '/start-chat',
      pageBuilder: (context, state) =>
          _veilModalPage(state, const StartDirectChatScreen()),
    ),
    GoRoute(
      path: '/secret-link',
      pageBuilder: (context, state) =>
          _veilModalPage(state, const OneTimeLinkScreen()),
    ),
    GoRoute(
      path: '/start-group',
      pageBuilder: (context, state) =>
          _veilModalPage(state, const StartGroupScreen()),
    ),
    GoRoute(
      path: '/chat/:conversationId',
      pageBuilder: (context, state) => _veilPushPage(
        state,
        ChatRoomScreen(
          conversationId: state.pathParameters['conversationId']!,
          navigationTarget: state.extra is MessageNavigationTarget
              ? state.extra as MessageNavigationTarget
              : null,
        ),
      ),
    ),
    GoRoute(
      path: '/profile',
      pageBuilder: (context, state) => _veilPushPage(state, const ProfileScreen()),
    ),
    GoRoute(
      path: '/trusted-devices',
      pageBuilder: (context, state) => _veilPushPage(state, const TrustedDevicesScreen()),
    ),
    GoRoute(
      path: '/lock',
      pageBuilder: (context, state) =>
          _veilFadePage(state, const AppLockScreen()),
    ),
    GoRoute(
      path: '/device-transfer',
      pageBuilder: (context, state) =>
          _veilPushPage(state, const DeviceTransferScreen()),
    ),
    GoRoute(
      path: '/security-status',
      pageBuilder: (context, state) =>
          _veilPushPage(state, const SecurityStatusScreen()),
    ),
    GoRoute(
      path: '/safety-numbers/:conversationId',
      pageBuilder: (context, state) => _veilPushPage(
        state,
        SafetyNumbersScreen(
          conversationId: state.pathParameters['conversationId']!,
          memberUserId: state.uri.queryParameters['member'],
        ),
      ),
    ),
  ];
}

CustomTransitionPage<void> _veilFadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: VeilMotion.normal,
    reverseTransitionDuration: VeilMotion.fast,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) {
        return child;
      }
      final slide = Tween<Offset>(
        begin: const Offset(0, 0.04),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(parent: animation, curve: VeilMotion.emphasize),
      );
      return FadeTransition(
        opacity: animation,
        child: SlideTransition(position: slide, child: child),
      );
    },
  );
}

/// iOS-style horizontal push. The incoming screen slides in from the trailing
/// edge while the previous screen parallax-translates and dims — this is the
/// Cupertino page transition, just surfaced through go_router.
CupertinoPage<void> _veilPushPage(GoRouterState state, Widget child) {
  return CupertinoPage<void>(
    key: state.pageKey,
    child: child,
  );
}

/// iOS-style modal sheet. The new screen slides up from the bottom with the
/// canonical 0.36 emphasize curve, and dismissing reverses at snappier speed.
CustomTransitionPage<void> _veilModalPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: VeilMotion.normal,
    reverseTransitionDuration: VeilMotion.fast,
    opaque: false,
    barrierColor: const Color(0x66000000),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) {
        return child;
      }
      final slide = Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: animation,
          curve: VeilMotion.springGentle,
          reverseCurve: VeilMotion.emphasize,
        ),
      );
      return SlideTransition(position: slide, child: child);
    },
  );
}
