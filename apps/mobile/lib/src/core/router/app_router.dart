import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_state.dart';
import '../../features/app_lock/presentation/app_lock_screen.dart';
import '../../features/attachments/presentation/attachment_preview_screen.dart';
import '../../features/auth/presentation/choose_handle_screen.dart';
import '../../features/auth/presentation/create_account_screen.dart';
import '../../features/chat/presentation/chat_room_screen.dart';
import '../../features/conversations/presentation/conversation_list_screen.dart';
import '../../features/conversations/presentation/start_direct_chat_screen.dart';
import '../../features/device_transfer/presentation/device_transfer_screen.dart';
import '../../features/onboarding/presentation/onboarding_warning_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/security_status/presentation/security_status_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';

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
      GoRoute(path: '/conversations', builder: (context, state) => const ConversationListScreen()),
      GoRoute(path: '/start-chat', builder: (context, state) => const StartDirectChatScreen()),
      GoRoute(
        path: '/chat/:conversationId',
        builder: (context, state) =>
            ChatRoomScreen(conversationId: state.pathParameters['conversationId']!),
      ),
      GoRoute(
        path: '/attachment/:conversationId',
        builder: (context, state) => AttachmentPreviewScreen(
          conversationId: state.pathParameters['conversationId']!,
        ),
      ),
      GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
      GoRoute(path: '/lock', builder: (context, state) => const AppLockScreen()),
      GoRoute(path: '/device-transfer', builder: (context, state) => const DeviceTransferScreen()),
      GoRoute(path: '/security-status', builder: (context, state) => const SecurityStatusScreen()),
    ],
  );
});
