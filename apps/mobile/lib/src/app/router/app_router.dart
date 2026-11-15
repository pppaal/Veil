import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/veil_theme.dart';
import '../../features/ai/ai_feature.dart';
import '../../features/app_lock/presentation/app_lock_screen.dart';
import '../../features/attachments/attachments_feature.dart';
import '../../features/attachments/presentation/attachment_preview_screen.dart';
import '../../features/auth/presentation/choose_handle_screen.dart';
import '../../features/auth/presentation/create_account_screen.dart';
import '../../features/ai/presentation/ai_chat_screen.dart';
import '../../features/calls/calls_feature.dart';
import '../../features/calls/presentation/call_history_screen.dart';
import '../../features/calls/presentation/call_screen.dart';
import '../../features/chat/presentation/chat_room_screen.dart';
import '../../features/secret_link/presentation/one_time_link_screen.dart';
import '../../features/contacts/presentation/contacts_screen.dart';
import '../../features/conversations/data/conversation_models.dart';
import '../../features/conversations/presentation/conversation_list_screen.dart';
import '../../features/conversations/presentation/start_direct_chat_screen.dart';
import '../../features/conversations/presentation/start_group_screen.dart';
import '../../features/device_transfer/presentation/device_transfer_screen.dart';
import '../../features/media/media_feature.dart';
import '../../features/media/presentation/media_picker_screen.dart';
import '../../features/onboarding/presentation/onboarding_warning_screen.dart';
import '../../features/onboarding/presentation/privacy_consent_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/security/presentation/safety_numbers_screen.dart';
import '../../features/security_status/presentation/security_status_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/trusted_devices_screen.dart';
import '../../features/stickers/presentation/sticker_picker_screen.dart';
import '../../features/stickers/stickers_feature.dart';
import '../../features/stories/presentation/stories_screen.dart';
import '../../features/stories/presentation/story_viewer_screen.dart';
import '../../features/stories/stories_feature.dart';
import '../../features/voice/presentation/voice_recorder_screen.dart';
import '../../features/voice/voice_feature.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/presentation/veil_ui.dart';
import '../app_state.dart';
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
    // A location no route has (a link into a feature this build has
    // switched off, a mistyped one) has nothing to show. It opens the app
    // where it normally opens instead of a dead end, and the guard above
    // still has the last word on where that is.
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
      builder: (context, state, child) => _VeilMainShell(child: child),
      routes: [
        GoRoute(path: '/conversations', builder: (context, state) => const ConversationListScreen()),
        GoRoute(path: '/contacts', builder: (context, state) => const ContactsScreen()),
        if (kStoriesEnabled) GoRoute(path: '/stories', builder: (context, state) => const StoriesScreen()),
        if (kCallsEnabled) GoRoute(path: '/calls', builder: (context, state) => const CallHistoryScreen()),
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
    // The routes of a feature this build has switched off are left out, so
    // no location reaches its screen (see each *_feature.dart).
    if (kAttachmentsEnabled)
      GoRoute(
        path: '/attachment/:conversationId',
        builder: (context, state) => AttachmentPreviewScreen(
          conversationId: state.pathParameters['conversationId']!,
        ),
      ),
    if (kMediaPickerEnabled)
      GoRoute(
        path: '/media/:conversationId',
        builder: (context, state) => const MediaPickerScreen(),
      ),
    if (kVoiceMessagesEnabled)
      GoRoute(
        path: '/voice/:conversationId',
        builder: (context, state) => const VoiceRecorderScreen(),
      ),
    if (kStickerPickerEnabled)
      GoRoute(
        path: '/stickers/:conversationId',
        builder: (context, state) => const StickerPickerScreen(),
      ),
    if (kCallsEnabled)
      GoRoute(
        path: '/call/:conversationId',
        builder: (context, state) => CallScreen(
          contactName: switch (state.extra) { {'name': final String name} => name, _ => '' },
        ),
      ),
    if (kStoriesEnabled)
      GoRoute(
        path: '/story-viewer/:userId',
        builder: (context, state) => StoryViewerScreen(
          authorUserId: state.pathParameters['userId']!,
        ),
      ),
    if (kAssistantEnabled)
      GoRoute(
        path: '/ai-chat',
        pageBuilder: (context, state) => _veilPushPage(state, const AiChatScreen()),
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

class _VeilMainShell extends StatelessWidget {
  const _VeilMainShell({required this.child});

  final Widget child;

  // Chats, Contacts and Settings, with the tab of each switched-on feature
  // between them.
  static const _tabs = <_VeilNavTab>[
    _VeilNavTab(path: '/conversations', icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: _chatsLabel),
    _VeilNavTab(path: '/contacts', icon: Icons.people_outline_rounded, activeIcon: Icons.people_rounded, label: _contactsLabel),
    if (kStoriesEnabled)
      _VeilNavTab(path: '/stories', icon: Icons.amp_stories_outlined, activeIcon: Icons.amp_stories_rounded, label: _storiesLabel),
    if (kCallsEnabled)
      _VeilNavTab(path: '/calls', icon: Icons.call_outlined, activeIcon: Icons.call_rounded, label: _callsLabel),
    _VeilNavTab(path: '/settings', icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: _settingsLabel),
  ];

  static String _chatsLabel(AppLocalizations l10n) => l10n.navChats;
  static String _contactsLabel(AppLocalizations l10n) => l10n.navContacts;
  static String _storiesLabel(AppLocalizations l10n) => l10n.navStories;
  static String _callsLabel(AppLocalizations l10n) => l10n.navCalls;
  static String _settingsLabel(AppLocalizations l10n) => l10n.navSettings;

  @override
  Widget build(BuildContext context) {
    final palette = context.veilPalette;
    final l10n = AppLocalizations.of(context);
    final currentPath = GoRouterState.of(context).fullPath ?? '/conversations';
    var currentIndex = _tabs.indexWhere((tab) => currentPath.startsWith(tab.path));
    if (currentIndex < 0) {
      currentIndex = 0;
    }

    return Scaffold(
      extendBody: true,
      body: child,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: palette.stroke.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: VeilBlur(
          intensity: 28,
          tintAlpha: 0.72,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VeilSpace.md,
                vertical: VeilSpace.xs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(_tabs.length, (index) {
                  final tab = _tabs[index];
                  final selected = index == currentIndex;
                  return Expanded(
                    child: VeilPressable(
                      haptic: false,
                      onTap: () {
                        if (!selected) {
                          VeilHaptics.selection();
                        }
                        context.go(tab.path);
                      },
                      scale: 0.92,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: VeilSpace.sm),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedContainer(
                              duration: VeilMotion.fast,
                              curve: VeilMotion.springGentle,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(VeilRadius.pill),
                                color: selected ? palette.primarySoft : Colors.transparent,
                              ),
                              child: Icon(
                                selected ? tab.activeIcon : tab.icon,
                                size: 22,
                                color: selected ? palette.primary : palette.textSubtle,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tab.label(l10n),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                                color: selected ? palette.primary : palette.textSubtle,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VeilNavTab {
  const _VeilNavTab({
    required this.path,
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final String path;
  final IconData icon;
  final IconData activeIcon;

  /// The tab's name in the user's language.
  final String Function(AppLocalizations l10n) label;
}
