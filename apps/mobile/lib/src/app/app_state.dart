import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../core/config/veil_config.dart';
import '../core/crypto/crypto_engine.dart';
import '../core/crypto/mock_crypto_engine.dart';
import '../core/network/veil_api_client.dart';
import '../core/realtime/realtime_service.dart';
import '../core/security/app_lock_service.dart';
import '../core/security/device_auth_signer.dart';
import '../core/security/local_data_cipher.dart';
import '../core/storage/app_database.dart';
import '../core/storage/conversation_cache_service.dart';
import '../core/storage/database_provider.dart';
import '../core/storage/secure_storage_service.dart';
import '../features/conversations/data/veil_messenger_controller.dart';

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final appDatabaseFutureProvider = FutureProvider<AppDatabase>((ref) async {
  final database = await createAppDatabase();
  ref.onDispose(database.close);
  return database;
});

final conversationCacheProvider = FutureProvider<ConversationCacheService?>((ref) async {
  if (!VeilConfig.enableLocalCache) {
    return null;
  }

  final database = await ref.watch(appDatabaseFutureProvider.future);
  final secureStorage = ref.read(secureStorageProvider);
  final cacheKey = await secureStorage.readOrCreateCacheKey();
  final cipher = await LocalDataCipher.fromBase64Key(cacheKey);
  return DriftConversationCacheService(database, cipher: cipher);
});

final apiClientProvider = Provider<VeilApiClient>((ref) {
  return VeilApiClient(baseUrl: VeilConfig.apiBaseUrl);
});

final cryptoEngineProvider = Provider<CryptoEngine>((ref) {
  return MockCryptoEngine();
});

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  return RealtimeService();
});

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService(LocalAuthentication(), ref.read(secureStorageProvider));
});

enum AuthFlowStage {
  idle('Idle'),
  generatingKeys('Generating local identity'),
  registering('Registering handle'),
  requestingChallenge('Requesting challenge'),
  verifying('Verifying device'),
  complete('Bound');

  const AuthFlowStage(this.label);

  final String label;
}

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
    this.authFlowStage = AuthFlowStage.idle,
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
  final AuthFlowStage authFlowStage;
  final String? errorMessage;

  bool get isAuthenticated =>
      accessToken != null && userId != null && deviceId != null && handle != null;

  bool get isAuthenticating => authFlowStage != AuthFlowStage.idle && authFlowStage != AuthFlowStage.complete;

  AppSessionState copyWith({
    Object? accessToken = _unset,
    Object? userId = _unset,
    Object? deviceId = _unset,
    Object? handle = _unset,
    Object? displayName = _unset,
    bool? onboardingAccepted,
    bool? locked,
    bool? initializing,
    AuthFlowStage? authFlowStage,
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
      authFlowStage: authFlowStage ?? this.authFlowStage,
      errorMessage: identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
    );
  }
}

class AppSessionController extends StateNotifier<AppSessionState> {
  AppSessionController(this._storage, this._apiClient, this._cryptoEngine)
      : super(const AppSessionState());

  final SecureStorageService _storage;
  final VeilApiClient _apiClient;
  final CryptoEngine _cryptoEngine;
  DeviceIdentityMaterial? _pendingTransferIdentity;
  DeviceAuthKeyMaterial? _pendingTransferAuthKey;
  String? _pendingTransferSessionId;
  String? _pendingTransferToken;
  String? _pendingTransferClaimId;

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
    state = state.copyWith(errorMessage: null, authFlowStage: AuthFlowStage.generatingKeys);

    try {
      final materialSeed = 'device-material-${DateTime.now().microsecondsSinceEpoch}';
      final identity = await _cryptoEngine.generateDeviceIdentity(materialSeed);
      final authKeyMaterial = await DeviceAuthSigner.generate();

      await _storage.persistDeviceSecretRefs(
        identityPrivateRef: identity.identityPrivateKeyRef,
        authPrivateKey: authKeyMaterial.privateKey,
        authPublicKey: authKeyMaterial.publicKey,
      );

      state = state.copyWith(authFlowStage: AuthFlowStage.registering);
      final registered = await _apiClient.register({
        'handle': handle,
        'displayName': displayName,
        'deviceName': 'VEIL Mobile',
        'platform': _platformName(),
        'publicIdentityKey': identity.identityPublicKey,
        'signedPrekeyBundle': identity.signedPrekeyBundle,
        'authPublicKey': authKeyMaterial.publicKey,
      });
      final registeredDeviceId = registered['deviceId'] as String;

      state = state.copyWith(authFlowStage: AuthFlowStage.requestingChallenge);
      final challenge = await _apiClient.challenge({
        'handle': handle,
        'deviceId': registeredDeviceId,
      });
      state = state.copyWith(authFlowStage: AuthFlowStage.verifying);
      final proof = await DeviceAuthSigner.signChallenge(
        challenge: challenge['challenge'] as String,
        keyMaterial: authKeyMaterial,
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
        authFlowStage: AuthFlowStage.complete,
        errorMessage: null,
      );
    } catch (error) {
      state = state.copyWith(
        errorMessage: _formatUserFacingError(error),
        initializing: false,
        authFlowStage: AuthFlowStage.idle,
      );
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
    _clearPendingTransferClaim();
    state = state.copyWith(
      accessToken: null,
      userId: null,
      deviceId: null,
      handle: null,
      displayName: null,
      errorMessage: null,
      locked: true,
      authFlowStage: AuthFlowStage.idle,
    );
  }

  Future<TransferClaimResult> claimTransfer({
    required String sessionId,
    required String transferToken,
    String? deviceName,
  }) async {
    state = state.copyWith(errorMessage: null);

    try {
      if (!VeilConfig.hasApi) {
        throw StateError('API mode is required for device transfer.');
      }

      final materialSeed = 'device-transfer-${DateTime.now().microsecondsSinceEpoch}';
      final identity = await _cryptoEngine.generateDeviceIdentity(materialSeed);
      final authKeyMaterial = await DeviceAuthSigner.generate();
      final authProof = await DeviceAuthSigner.signChallenge(
        challenge: 'transfer-claim:$sessionId:$transferToken',
        keyMaterial: authKeyMaterial,
      );

      final claimed = await _apiClient.claimTransfer({
        'sessionId': sessionId,
        'transferToken': transferToken,
        'newDeviceName': deviceName?.trim().isNotEmpty == true
            ? deviceName!.trim()
            : 'VEIL ${Platform.isIOS ? 'iPhone' : 'Mobile'}',
        'platform': _platformName(),
        'publicIdentityKey': identity.identityPublicKey,
        'signedPrekeyBundle': identity.signedPrekeyBundle,
        'authPublicKey': authKeyMaterial.publicKey,
        'authProof': authProof,
      });

      _pendingTransferIdentity = identity;
      _pendingTransferAuthKey = authKeyMaterial;
      _pendingTransferSessionId = sessionId;
      _pendingTransferToken = transferToken;
      _pendingTransferClaimId = claimed['claimId'] as String;

      return TransferClaimResult(
        claimId: claimed['claimId'] as String,
        claimantFingerprint: claimed['claimantFingerprint'] as String,
        expiresAt: DateTime.parse(claimed['expiresAt'] as String),
      );
    } catch (error) {
      state = state.copyWith(errorMessage: _formatUserFacingError(error));
      rethrow;
    }
  }

  Future<void> completeTransferAndAuthenticate({
    required String sessionId,
    required String transferToken,
    required String claimId,
  }) async {
    state = state.copyWith(errorMessage: null);

    try {
      if (!VeilConfig.hasApi) {
        throw StateError('API mode is required for device transfer.');
      }

      if (_pendingTransferIdentity == null ||
          _pendingTransferAuthKey == null ||
          _pendingTransferSessionId != sessionId ||
          _pendingTransferToken != transferToken ||
          _pendingTransferClaimId != claimId) {
        throw StateError('Claim this new device before completion.');
      }

      final identity = _pendingTransferIdentity!;
      final authKeyMaterial = _pendingTransferAuthKey!;

      final completed = await _apiClient.completeTransfer({
        'sessionId': sessionId,
        'transferToken': transferToken,
        'claimId': claimId,
      });

      final newDeviceId = completed['newDeviceId'] as String;
      final handle = completed['handle'] as String;
      final challenge = await _apiClient.challenge({
        'handle': handle,
        'deviceId': newDeviceId,
      });
      final proof = await DeviceAuthSigner.signChallenge(
        challenge: challenge['challenge'] as String,
        keyMaterial: authKeyMaterial,
      );
      final verified = await _apiClient.verify({
        'challengeId': challenge['challengeId'],
        'deviceId': newDeviceId,
        'signature': proof,
      });

      final displayName = completed['displayName'] as String?;
      await _storage.persistDeviceSecretRefs(
        identityPrivateRef: identity.identityPrivateKeyRef,
        authPrivateKey: authKeyMaterial.privateKey,
        authPublicKey: authKeyMaterial.publicKey,
      );
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
      _clearPendingTransferClaim();
    } catch (error) {
      state = state.copyWith(errorMessage: _formatUserFacingError(error));
      rethrow;
    }
  }

  void _clearPendingTransferClaim() {
    _pendingTransferIdentity = null;
    _pendingTransferAuthKey = null;
    _pendingTransferSessionId = null;
    _pendingTransferToken = null;
    _pendingTransferClaimId = null;
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
  );

  ref.listen<AppSessionState>(appSessionProvider, (_, next) {
    unawaited(controller.applySession(next));
  });

  unawaited(controller.applySession(ref.read(appSessionProvider)));
  ref.onDispose(controller.dispose);
  return controller;
});

String formatUserFacingError(Object error) => _formatUserFacingError(error);

String _formatUserFacingError(Object error) {
  final raw = error.toString().trim();
  const prefixes = ['Bad state: ', 'Exception: ', 'StateError: '];
  var normalized = raw;
  for (final prefix in prefixes) {
    if (raw.startsWith(prefix)) {
      normalized = raw.substring(prefix.length).trim();
      break;
    }
  }

  switch (normalized) {
    case 'Authenticated API session required.':
      return 'This device is no longer bound. Sign in again on the active device.';
    case 'API mode is required for device transfer.':
      return 'Device transfer is available only while connected to the VEIL API.';
    case 'Claim this new device before completion.':
      return 'Register this new device first, then wait for approval from the old device.';
    case 'Unexpected response shape':
      return 'The relay returned an unexpected response. Try again.';
  }

  if (normalized.startsWith('Attachment upload failed:')) {
    return 'Opaque blob upload failed. Check the relay and try again.';
  }
  if (normalized.startsWith('Request failed: HTTP 401')) {
    return 'This session is no longer valid on this device.';
  }
  if (normalized.startsWith('Request failed: HTTP 403')) {
    return 'This action is not allowed on the current device.';
  }
  if (normalized.startsWith('Request failed: HTTP 404')) {
    return 'The requested VEIL resource was not found.';
  }
  if (normalized.startsWith('Request failed: HTTP 409')) {
    return 'This request conflicts with the current VEIL state. Refresh and try again.';
  }
  if (normalized.startsWith('Request failed: HTTP 422')) {
    return 'The submitted values were rejected. Review the form and try again.';
  }
  if (normalized.startsWith('Request failed: HTTP 5')) {
    return 'The VEIL relay failed to complete the request. Try again shortly.';
  }

  return normalized;
}

String _platformName() {
  if (Platform.isIOS) {
    return 'ios';
  }
  if (Platform.isAndroid) {
    return 'android';
  }
  if (Platform.isWindows) {
    return 'windows';
  }
  if (Platform.isMacOS) {
    return 'macos';
  }
  if (Platform.isLinux) {
    return 'linux';
  }
  return 'unknown';
}

class TransferClaimResult {
  const TransferClaimResult({
    required this.claimId,
    required this.claimantFingerprint,
    required this.expiresAt,
  });

  final String claimId;
  final String claimantFingerprint;
  final DateTime expiresAt;
}
