import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../core/config/veil_config.dart';
import '../core/crypto/mock_crypto_engine.dart';
import '../core/network/veil_api_client.dart';
import '../core/realtime/realtime_service.dart';
import '../core/security/app_lock_service.dart';
import '../core/security/mock_device_auth_proof.dart';
import '../core/storage/app_database.dart';
import '../core/storage/conversation_cache_service.dart';
import '../core/storage/database_provider.dart';
import '../core/storage/secure_storage_service.dart';
import '../features/conversations/data/mock_messenger_repository.dart';
import '../features/conversations/data/veil_messenger_controller.dart';

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final appDatabaseFutureProvider = FutureProvider<AppDatabase>((ref) async {
  final database = await createAppDatabase();
  ref.onDispose(database.close);
  return database;
});

final conversationCacheProvider = FutureProvider<ConversationCacheService>((ref) async {
  final database = await ref.watch(appDatabaseFutureProvider.future);
  return DriftConversationCacheService(database);
});

final apiClientProvider = Provider<VeilApiClient>((ref) {
  return VeilApiClient(baseUrl: VeilConfig.apiBaseUrl);
});

final cryptoEngineProvider = Provider<MockCryptoEngine>((ref) {
  return MockCryptoEngine();
});

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  return RealtimeService();
});

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService(LocalAuthentication(), ref.read(secureStorageProvider));
});

class LocalSecuritySnapshot {
  const LocalSecuritySnapshot({
    required this.hasDeviceSecretRefs,
    required this.hasPin,
    required this.biometricsAvailable,
  });

  final bool hasDeviceSecretRefs;
  final bool hasPin;
  final bool biometricsAvailable;
}

final localSecuritySnapshotProvider = FutureProvider<LocalSecuritySnapshot>((ref) async {
  final storage = ref.read(secureStorageProvider);
  final appLock = ref.read(appLockServiceProvider);
  final values = await Future.wait<bool>([
    storage.hasDeviceSecretRefs(),
    appLock.hasPin(),
    appLock.canUseBiometrics(),
  ]);

  return LocalSecuritySnapshot(
    hasDeviceSecretRefs: values[0],
    hasPin: values[1],
    biometricsAvailable: values[2],
  );
});

class AppSessionState {
  static const Object _unset = Object();

  const AppSessionState({
    this.accessToken,
    this.userId,
    this.deviceId,
    this.handle,
    this.displayName,
    this.onboardingAccepted = false,
    this.locked = true,
    this.initializing = true,
    this.errorMessage,
  });

  final String? accessToken;
  final String? userId;
  final String? deviceId;
  final String? handle;
  final String? displayName;
  final bool onboardingAccepted;
  final bool locked;
  final bool initializing;
  final String? errorMessage;

  bool get isAuthenticated =>
      accessToken != null && userId != null && deviceId != null && handle != null;

  AppSessionState copyWith({
    Object? accessToken = _unset,
    Object? userId = _unset,
    Object? deviceId = _unset,
    Object? handle = _unset,
    Object? displayName = _unset,
    bool? onboardingAccepted,
    bool? locked,
    bool? initializing,
    Object? errorMessage = _unset,
  }) {
    return AppSessionState(
      accessToken: identical(accessToken, _unset) ? this.accessToken : accessToken as String?,
      userId: identical(userId, _unset) ? this.userId : userId as String?,
      deviceId: identical(deviceId, _unset) ? this.deviceId : deviceId as String?,
      handle: identical(handle, _unset) ? this.handle : handle as String?,
      displayName: identical(displayName, _unset) ? this.displayName : displayName as String?,
      onboardingAccepted: onboardingAccepted ?? this.onboardingAccepted,
      locked: locked ?? this.locked,
      initializing: initializing ?? this.initializing,
      errorMessage: identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
    );
  }
}

class AppSessionController extends StateNotifier<AppSessionState> {
  AppSessionController(this._storage, this._apiClient, this._cryptoEngine)
      : super(const AppSessionState());

  final SecureStorageService _storage;
  final VeilApiClient _apiClient;
  final MockCryptoEngine _cryptoEngine;

  Future<void> bootstrap() async {
    final session = await _storage.readSession();
    final onboardingAccepted = await _storage.readOnboardingAccepted();
    state = AppSessionState(
      accessToken: session?.accessToken,
      userId: session?.userId,
      deviceId: session?.deviceId,
      handle: session?.handle,
      displayName: session?.displayName,
      onboardingAccepted: onboardingAccepted,
      locked: session != null,
      initializing: false,
    );
  }

  Future<void> acceptOnboarding() async {
    await _storage.persistOnboardingAccepted(true);
    state = state.copyWith(onboardingAccepted: true);
  }

  Future<void> registerAndAuthenticate({
    required String handle,
    String? displayName,
  }) async {
    state = state.copyWith(errorMessage: null);

    try {
      final materialSeed = 'device-material-${DateTime.now().microsecondsSinceEpoch}';
      final identity = await _cryptoEngine.generateDeviceIdentity(materialSeed);

      await _storage.persistDeviceSecretRefs(
        identityPrivateRef: identity.identityPrivateKeyRef,
        authPrivateRef: identity.authPrivateKeyRef,
      );

      final registered = await _apiClient.register({
        'handle': handle,
        'displayName': displayName,
        'deviceName': 'VEIL Mobile',
        'platform': Platform.isIOS ? 'ios' : 'android',
        'publicIdentityKey': identity.identityPublicKey,
        'signedPrekeyBundle': identity.signedPrekeyBundle,
        'authPublicKey': identity.authPublicKey,
      });
      final registeredDeviceId = registered['deviceId'] as String;

      final challenge = await _apiClient.challenge({
        'handle': handle,
        'deviceId': registeredDeviceId,
      });
      final proof = MockDeviceAuthProof.build(
        challenge: challenge['challenge'] as String,
        authPublicKey: identity.authPublicKey,
        deviceId: registeredDeviceId,
      );
      final verified = await _apiClient.verify({
        'challengeId': challenge['challengeId'],
        'deviceId': registeredDeviceId,
        'signature': proof,
      });

      await _storage.persistSession(
        accessToken: verified['accessToken'] as String,
        userId: verified['userId'] as String,
        deviceId: verified['deviceId'] as String,
        handle: handle,
        displayName: displayName,
      );

      state = state.copyWith(
        accessToken: verified['accessToken'] as String,
        userId: verified['userId'] as String,
        deviceId: verified['deviceId'] as String,
        handle: handle,
        displayName: displayName,
        locked: false,
        initializing: false,
        errorMessage: null,
      );
    } catch (error) {
      state = state.copyWith(errorMessage: error.toString(), initializing: false);
      rethrow;
    }
  }

  void lock() {
    state = state.copyWith(locked: true);
  }

  void unlock() {
    state = state.copyWith(locked: false);
  }

  Future<void> revokeCurrentDevice() async {
    final accessToken = state.accessToken;
    final deviceId = state.deviceId;
    if (accessToken == null || deviceId == null) {
      return;
    }

    try {
      await _apiClient.revokeDevice(accessToken, deviceId);
    } finally {
      await logout();
    }
  }

  Future<void> logout() async {
    await _storage.clearSession();
    state = state.copyWith(
      accessToken: null,
      userId: null,
      deviceId: null,
      handle: null,
      displayName: null,
      errorMessage: null,
      locked: true,
    );
  }
}

final appSessionProvider =
    StateNotifierProvider<AppSessionController, AppSessionState>((ref) {
  return AppSessionController(
    ref.read(secureStorageProvider),
    ref.read(apiClientProvider),
    ref.read(cryptoEngineProvider),
  );
});

final messengerControllerProvider =
    ChangeNotifierProvider<VeilMessengerController>((ref) {
  final controller = VeilMessengerController(
    apiClient: ref.read(apiClientProvider),
    cryptoEngine: ref.read(cryptoEngineProvider),
    realtimeService: ref.read(realtimeServiceProvider),
    cacheService: ref.watch(conversationCacheProvider).maybeWhen(
          data: (cache) => cache,
          orElse: () => null,
        ),
    mockRepository: MockMessengerRepository(
      cryptoEngine: ref.read(cryptoEngineProvider),
    ),
  );

  ref.listen<AppSessionState>(appSessionProvider, (_, next) {
    unawaited(controller.applySession(next));
  });

  unawaited(controller.applySession(ref.read(appSessionProvider)));
  ref.onDispose(controller.dispose);
  return controller;
});
