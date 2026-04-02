import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/security/app_lock_service.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/auth/presentation/create_account_screen.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/onboarding_warning_screen.dart';

void main() {
  testWidgets('onboarding warning keeps no-recovery copy explicit', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: _TestApp(
          child: OnboardingWarningScreen(),
        ),
      ),
    );

    expect(find.text('No backup.\nNo recovery.\nNo leaks.'), findsOneWidget);
    expect(find.text('Unrecoverable by design'), findsOneWidget);
    expect(
      find.textContaining('If you lose your device, your account and messages are gone.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('I understand'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('I understand'), findsOneWidget);
  });

  testWidgets('create account screen keeps transfer and no-restore copy visible', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: _TestApp(
          child: CreateAccountScreen(),
        ),
      ),
    );

    expect(find.text('This device becomes your identity.'), findsOneWidget);
    expect(find.text('No restore path'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Continue'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Transfer from old device'), findsOneWidget);
  });

  testWidgets('app lock screen surfaces local-only barrier status', (tester) async {
    final storage = SecureStorageService(_MemorySecureKeyValueStore());
    final sessionController = AppSessionController(
      storage,
      VeilApiClient(baseUrl: 'http://localhost:3000/v1'),
      createDefaultCryptoAdapter(),
      cacheService: _MemoryConversationCache(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appLockServiceProvider.overrideWithValue(
            AppLockService(
              _FakeAuthenticator(biometricsAvailable: true),
              storage,
            ),
          ),
          appSessionProvider.overrideWith((ref) => sessionController),
        ],
        child: const _TestApp(
          child: AppLockScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('VEIL never unlocks itself remotely.'), findsOneWidget);
    expect(find.text('PIN required'), findsOneWidget);
    expect(find.text('Biometrics available'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Use biometrics'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Use biometrics'), findsOneWidget);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: VeilTheme.dark(),
      home: child,
    );
  }
}

class _FakeAuthenticator implements LocalUnlockAuthenticator {
  _FakeAuthenticator({required this.biometricsAvailable});

  final bool biometricsAvailable;

  @override
  Future<bool> authenticateBiometric() async => false;

  @override
  Future<bool> canUseBiometrics() async => biometricsAvailable;
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String?> values = <String, String?>{};

  @override
  Future<void> delete({required String key}) async {
    values.remove(key);
  }

  @override
  Future<String?> read({required String key}) async => values[key];

  @override
  Future<void> write({required String key, required String? value}) async {
    if (value == null) {
      values.remove(key);
      return;
    }
    values[key] = value;
  }
}

class _MemoryConversationCache implements ConversationCacheService {
  @override
  Future<void> clearAll() async {}

  @override
  Future<void> purgeExpiredMessages() async {}

  @override
  Future<List<ConversationPreview>> readConversations() async => const [];

  @override
  Future<List<ChatMessage>> readMessages(String conversationId) async => const [];

  @override
  Future<List<PendingMessageRecord>> readPendingMessages() async => const [];

  @override
  Future<ConversationPagingState> readPagingState(String conversationId) async =>
      const ConversationPagingState();

  @override
  Future<void> removePendingMessage(String clientMessageId) async {}

  @override
  Future<void> storeConversations(List<ConversationPreview> conversations) async {}

  @override
  Future<void> storeMessages(String conversationId, List<ChatMessage> messages) async {}

  @override
  Future<void> storePagingState(
    String conversationId, {
    String? nextCursor,
    required bool hasMoreHistory,
    DateTime? lastSyncedAt,
  }) async {}

  @override
  Future<void> upsertPendingMessage(PendingMessageRecord pending) async {}
}
