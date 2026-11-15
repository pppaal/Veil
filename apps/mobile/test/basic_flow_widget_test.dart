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
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';
import 'package:veil_mobile/src/features/app_lock/presentation/app_lock_screen.dart';
import 'package:veil_mobile/src/features/auth/presentation/create_account_screen.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/onboarding/presentation/onboarding_warning_screen.dart';
import 'package:veil_mobile/src/features/settings/presentation/trusted_devices_screen.dart';

void main() {
  testWidgets('onboarding warning keeps no-recovery copy explicit',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: _TestApp(
          child: OnboardingWarningScreen(),
        ),
      ),
    );

    expect(find.text('Before you start'), findsOneWidget);
    expect(find.text('No backup'), findsOneWidget);
    expect(
      find.textContaining(
          'If you lose this phone, you lose this account and its messages.'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('I understand'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('I understand'), findsOneWidget);
  });

  testWidgets(
      'create account screen keeps transfer and no-restore copy visible',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: _TestApp(
          child: CreateAccountScreen(),
        ),
      ),
    );

    expect(find.text('Already have an account?'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Continue'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Move from another phone'), findsOneWidget);
  });

  testWidgets('app lock screen surfaces local-only barrier status',
      (tester) async {
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

    expect(find.text('Veil is locked'), findsOneWidget);
    // The metric strip that showed "Required" and "Available" draws nothing
    // any more (design system 7.10): PIN and biometrics are Security rows.
    await tester.scrollUntilVisible(
      find.text('Use biometrics'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Use biometrics'), findsOneWidget);
  });

  testWidgets('the devices screen shows the trusted devices of the account', (tester) async {
    // Tall enough for the three devices at once: the list builds what is
    // near the screen.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final storage = SecureStorageService(_MemorySecureKeyValueStore());
    final sessionController = AppSessionController(
      storage,
      VeilApiClient(baseUrl: 'http://localhost:3000/v1'),
      createDefaultCryptoAdapter(),
      cacheService: _MemoryConversationCache(),
    );
    sessionController.state = const AppSessionState(
      accessToken: 'token',
      userId: 'user-1',
      deviceId: 'device-current',
      handle: 'atlas',
      displayName: 'Atlas',
      onboardingAccepted: true,
      locked: false,
      initializing: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSessionProvider.overrideWith((ref) => sessionController),
          apiClientProvider.overrideWithValue(_FakeSettingsApiClient()),
        ],
        child: const _TestApp(
          child: TrustedDevicesScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Pixel Fold'), findsOneWidget);
    expect(find.text('Old iPhone'), findsOneWidget);
    expect(find.text('MacBook Air'), findsOneWidget);
    // Two devices hold the account (this one and the quiet laptop); the
    // third was revoked. The quiet one is counted among the trusted, not
    // beside them: the parts add up to the three devices listed.
    expect(find.text('2 devices (1 stale)  ·  '), findsOneWidget);
    expect(find.text('1 revoked'), findsOneWidget);
    expect(find.text('1 stale  ·  '), findsNothing);
    expect(find.textContaining('stale'), findsWidgets);
    expect(find.text('This device'), findsOneWidget);
    expect(find.text('Revoked'), findsOneWidget);
    expect(find.text('Revoke'), findsOneWidget);
    // The server keeps only the UTC day of device activity: it is shown as
    // that day, with no time of day that never happened.
    expect(find.text('Last seen Apr 2 (UTC)'), findsOneWidget);
    expect(find.text('Last synced Mar 30 (UTC)'), findsOneWidget);
    expect(find.text('Last activity Apr 2 (UTC)'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^Last (seen|synced|active|activity) .*\d\d:\d\d')), findsNothing);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: VeilTheme.dark(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
  Future<void> purgeExpiredMessages({DateTime? now}) async {}

  @override
  Future<List<ConversationPreview>> readConversations() async => const [];

  @override
  Future<List<ChatMessage>> readMessages(String conversationId) async =>
      const [];

  @override
  Future<List<PendingMessageRecord>> readPendingMessages() async => const [];

  @override
  Future<ConversationPagingState> readPagingState(
          String conversationId) async =>
      const ConversationPagingState();

  @override
  Future<void> removePendingMessage(String clientMessageId) async {}

  @override
  Future<void> indexMessageBody({
    required String conversationId,
    required String messageId,
    required String searchableBody,
  }) async {}

  @override
  Future<List<String>> searchCachedMessageIds({
    required String conversationId,
    required String query,
  }) async =>
      const [];

  @override
  Future<MessageSearchPage> searchMessageArchive({
    required MessageSearchQuery query,
    required String currentDeviceId,
  }) async =>
      const MessageSearchPage(items: <MessageSearchResult>[]);

  @override
  Future<void> storeConversations(
      List<ConversationPreview> conversations) async {}

  @override
  Future<void> storeMessages(
      String conversationId, List<ChatMessage> messages) async {}

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

class _FakeSettingsApiClient extends VeilApiClient {
  _FakeSettingsApiClient() : super(baseUrl: 'http://localhost:3000/v1');

  @override
  Future<Map<String, dynamic>> listDevices(String accessToken) async {
    return {
      'activeDeviceId': 'device-current',
      'items': [
        {
          'id': 'device-current',
          'deviceName': 'Pixel Fold',
          'platform': 'android',
          'isActive': true,
          'trustState': 'current',
          'revokedAt': null,
          'trustedAt': DateTime.utc(2026, 4, 1, 8, 0, 0).toIso8601String(),
          'joinedFromDeviceId': null,
          'joinedFromDeviceName': null,
          'joinedFromPlatform': null,
          'createdAt': DateTime.utc(2026, 4, 1, 8, 0, 0).toIso8601String(),
          'lastSeenAt': DateTime.utc(2026, 4, 2).toIso8601String(),
          'lastSyncAt': DateTime.utc(2026, 4, 2).toIso8601String(),
          'lastTrustedActivityAt':
              DateTime.utc(2026, 4, 2).toIso8601String(),
        },
        {
          'id': 'device-old',
          'deviceName': 'Old iPhone',
          'platform': 'ios',
          'isActive': false,
          'trustState': 'revoked',
          'revokedAt': DateTime.utc(2026, 4, 1, 9, 0, 0).toIso8601String(),
          'trustedAt': DateTime.utc(2026, 3, 10, 8, 0, 0).toIso8601String(),
          'joinedFromDeviceId': null,
          'joinedFromDeviceName': null,
          'joinedFromPlatform': null,
          'createdAt': DateTime.utc(2026, 3, 10, 8, 0, 0).toIso8601String(),
          'lastSeenAt': DateTime.utc(2026, 4, 1).toIso8601String(),
          'lastSyncAt': null,
          'lastTrustedActivityAt':
              DateTime.utc(2026, 4, 1).toIso8601String(),
        },
        {
          'id': 'device-laptop',
          'deviceName': 'MacBook Air',
          'platform': 'macos',
          'isActive': true,
          'trustState': 'stale',
          'revokedAt': null,
          'trustedAt': DateTime.utc(2026, 3, 20, 8, 0, 0).toIso8601String(),
          'joinedFromDeviceId': 'device-current',
          'joinedFromDeviceName': 'Pixel Fold',
          'joinedFromPlatform': 'android',
          'createdAt': DateTime.utc(2026, 3, 20, 8, 0, 0).toIso8601String(),
          'lastSeenAt': DateTime.utc(2026, 4, 1).toIso8601String(),
          'lastSyncAt': DateTime.utc(2026, 3, 30).toIso8601String(),
          'lastTrustedActivityAt':
              DateTime.utc(2026, 4, 1).toIso8601String(),
        },
      ],
    };
  }
}
