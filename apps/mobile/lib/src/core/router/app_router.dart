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
import '../../features/device_transfer/presentation/device_transfer_screen.dart';
import '../../features/media/presentation/media_picker_screen.dart';
import '../../features/onboarding/presentation/onboarding_warning_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/security_status/presentation/security_status_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/stickers/presentation/sticker_picker_screen.dart';
import '../../features/stories/presentation/stories_screen.dart';
import '../../features/stories/presentation/story_viewer_screen.dart';
import '../../features/voice/presentation/voice_recorder_screen.dart';
import '../theme/veil_theme.dart';

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
      GoRoute(path: '/onboarding', builder: (context, state) => const OnboardingWarningScreen()),
      GoRoute(path: '/create-account', builder: (context, state) => const CreateAccountScreen()),
      GoRoute(path: '/choose-handle', builder: (context, state) => const ChooseHandleScreen()),
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
      GoRoute(path: '/start-chat', builder: (context, state) => const StartDirectChatScreen()),
      GoRoute(
        path: '/chat/:conversationId',
        builder: (context, state) => ChatRoomScreen(
          conversationId: state.pathParameters['conversationId']!,
          navigationTarget: state.extra is MessageNavigationTarget
              ? state.extra as MessageNavigationTarget
              : null,
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
          authorName: state.extra is Map ? (state.extra as Map)['name'] as String? ?? 'Unknown' : 'Unknown',
          authorHandle: state.pathParameters['userId'],
        ),
      ),
      GoRoute(path: '/ai-chat', builder: (context, state) => const AiChatScreen()),
      GoRoute(path: '/profile', builder: (context, state) => const ProfileScreen()),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/lock', builder: (context, state) => const AppLockScreen()),
      GoRoute(path: '/device-transfer', builder: (context, state) => const DeviceTransferScreen()),
      GoRoute(path: '/security-status', builder: (context, state) => const SecurityStatusScreen()),
    ],
  );
});

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
    final palette = Theme.of(context).extension<VeilPalette>()!;
    final currentPath = GoRouterState.of(context).fullPath ?? '/conversations';
    var currentIndex = _tabs.indexWhere((tab) => currentPath.startsWith(tab.path));
    if (currentIndex < 0) {
      currentIndex = 0;
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: palette.stroke, width: 0.5),
          ),
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: (index) {
            context.go(_tabs[index].path);
          },
          backgroundColor: palette.canvasAlt,
          indicatorColor: palette.primarySoft,
          surfaceTintColor: Colors.transparent,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          height: 64,
          destinations: _tabs.map((tab) {
            return NavigationDestination(
              icon: Icon(tab.icon, color: palette.textSubtle, size: VeilIconSize.md),
              selectedIcon: Icon(tab.activeIcon, color: palette.primary, size: VeilIconSize.md),
              label: tab.label,
            );
          }).toList(),
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
