import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_state.dart';
import '../../features/app_lock/presentation/app_lock_screen.dart';
import '../../features/attachments/presentation/attachment_preview_screen.dart';
import '../../features/auth/presentation/choose_handle_screen.dart';
import '../../features/auth/presentation/create_account_screen.dart';
import '../../features/ai/presentation/ai_chat_screen.dart';
import '../../features/calls/presentation/call_history_screen.dart';
import '../../features/calls/presentation/call_screen.dart';
import '../../features/chat/presentation/chat_room_screen.dart';
import '../../features/contacts/presentation/contacts_screen.dart';
import '../../features/conversations/data/conversation_models.dart';
import '../../features/conversations/presentation/conversation_list_screen.dart';
import '../../features/conversations/presentation/start_direct_chat_screen.dart';
import '../../features/conversations/presentation/start_group_screen.dart';
import '../../features/device_transfer/presentation/device_transfer_screen.dart';
import '../../features/media/presentation/media_picker_screen.dart';
import '../../features/onboarding/presentation/onboarding_warning_screen.dart';
import '../../features/onboarding/presentation/privacy_consent_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/security/presentation/safety_numbers_screen.dart';
import '../../features/security_status/presentation/security_status_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/stickers/presentation/sticker_picker_screen.dart';
import '../../features/stories/presentation/stories_screen.dart';
import '../../features/stories/presentation/story_viewer_screen.dart';
import '../../features/voice/presentation/voice_recorder_screen.dart';
import '../theme/veil_theme.dart';
import '../../shared/presentation/veil_ui.dart';

final _mainShellNavigatorKey = GlobalKey<NavigatorState>();

final appRouterProvider = Provider<GoRouter>((ref) {
  final session = ref.watch(appSessionProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final path = state.fullPath ?? '/splash';

      if (session.initializing) {
        return path == '/splash' ? null : '/splash';
      }

      if (session.errorMessage != null) {
        return path == '/splash' ? null : '/splash';
      }

      if (session.locked && session.isAuthenticated) {
        return path == '/lock' ? null : '/lock';
      }

      if (!session.privacyConsentAccepted) {
        return path == '/privacy-consent' ? null : '/privacy-consent';
      }

      if (!session.onboardingAccepted) {
        return path == '/onboarding' ? null : '/onboarding';
      }

      if (!session.isAuthenticated) {
        if (path == '/create-account' ||
            path == '/choose-handle' ||
            path == '/device-transfer' ||
            path == '/splash') {
          return null;
        }
        return '/create-account';
      }

      if (path == '/splash' ||
          path == '/privacy-consent' ||
          path == '/onboarding' ||
          path == '/create-account' ||
          path == '/choose-handle' ||
          path == '/lock') {
        return '/conversations';
      }
      return null;
    },
    routes: [
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
        navigatorKey: _mainShellNavigatorKey,
        builder: (context, state, child) => _VeilMainShell(child: child),
        routes: [
          GoRoute(path: '/conversations', builder: (context, state) => const ConversationListScreen()),
          GoRoute(path: '/calls', builder: (context, state) => const CallHistoryScreen()),
          GoRoute(path: '/stories', builder: (context, state) => const StoriesScreen()),
          GoRoute(path: '/contacts', builder: (context, state) => const ContactsScreen()),
        ],
      ),
      GoRoute(
        path: '/start-chat',
        pageBuilder: (context, state) =>
            _veilModalPage(state, const StartDirectChatScreen()),
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
        path: '/attachment/:conversationId',
        builder: (context, state) => AttachmentPreviewScreen(
          conversationId: state.pathParameters['conversationId']!,
        ),
      ),
      GoRoute(
        path: '/media/:conversationId',
        builder: (context, state) => const MediaPickerScreen(),
      ),
      GoRoute(
        path: '/voice/:conversationId',
        builder: (context, state) => const VoiceRecorderScreen(),
      ),
      GoRoute(
        path: '/stickers/:conversationId',
        builder: (context, state) => const StickerPickerScreen(),
      ),
      GoRoute(
        path: '/call/:conversationId',
        builder: (context, state) => CallScreen(
          contactName: state.extra is Map ? (state.extra as Map)['name'] as String? ?? 'Unknown' : 'Unknown',
          contactHandle: state.pathParameters['conversationId'],
        ),
      ),
      GoRoute(
        path: '/story-viewer/:userId',
        builder: (context, state) => StoryViewerScreen(
          authorUserId: state.pathParameters['userId']!,
        ),
      ),
      GoRoute(
        path: '/ai-chat',
        pageBuilder: (context, state) => _veilPushPage(state, const AiChatScreen()),
      ),
      GoRoute(
        path: '/profile',
        pageBuilder: (context, state) => _veilPushPage(state, const ProfileScreen()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) => _veilPushPage(state, const SettingsScreen()),
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
          ),
        ),
      ),
    ],
  );
});

CustomTransitionPage<void> _veilFadePage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: VeilMotion.normal,
    reverseTransitionDuration: VeilMotion.fast,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
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

  static const _tabs = <_VeilNavTab>[
    _VeilNavTab(path: '/conversations', icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: 'Chats'),
    _VeilNavTab(path: '/contacts', icon: Icons.people_outline_rounded, activeIcon: Icons.people_rounded, label: 'Contacts'),
    _VeilNavTab(path: '/stories', icon: Icons.amp_stories_outlined, activeIcon: Icons.amp_stories_rounded, label: 'Stories'),
    _VeilNavTab(path: '/calls', icon: Icons.call_outlined, activeIcon: Icons.call_rounded, label: 'Calls'),
  ];

  @override
  Widget build(BuildContext context) {
    const palette = VeilPalette.dark;
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
                              tab.label,
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
  final String label;
}
