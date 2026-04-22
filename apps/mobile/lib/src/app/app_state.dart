import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../core/config/veil_config.dart';
import '../core/crypto/crypto_adapter_registry.dart';
import '../core/crypto/crypto_engine.dart';
import '../core/crypto/lib_crypto_adapter.dart';
import '../core/network/veil_api_client.dart';
import '../core/notifications/local_notification_service.dart';
import '../core/notifications/push_token_coordinator.dart';
import '../core/notifications/remote_push_service.dart';
import '../core/realtime/realtime_service.dart';
import '../core/security/app_lock_service.dart';
import '../core/security/local_data_cipher.dart';
import '../core/security/platform_security_service.dart';
import '../core/security/sensitive_text_redactor.dart';
import '../core/storage/app_database.dart';
import '../core/storage/conversation_cache_service.dart';
import '../core/storage/database_provider.dart';
import '../core/storage/secure_storage_service.dart';
import '../features/attachments/data/attachment_temp_file_store.dart';
import '../features/conversations/data/veil_messenger_controller.dart';

final secureStorageProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final platformSecurityServiceProvider =
    Provider<PlatformSecurityService>((ref) {
  return MethodChannelPlatformSecurityService();
});

final platformSecurityStatusProvider =
    FutureProvider<PlatformSecurityStatus>((ref) async {
  final service = ref.read(platformSecurityServiceProvider);
  await service.applyPrivacyProtections();
  return service.getStatus();
});

final appDatabaseFutureProvider = FutureProvider<AppDatabase>((ref) async {
  final database = await createAppDatabase(
    secureStorage: ref.read(secureStorageProvider),
    platformSecurityService: ref.read(platformSecurityServiceProvider),
  );
  ref.onDispose(database.close);
  return database;
});

final cacheEpochProvider = StateProvider<int>((ref) => 0);

final conversationCacheProvider =
    FutureProvider<ConversationCacheService?>((ref) async {
  ref.watch(cacheEpochProvider);
  if (!VeilConfig.enableLocalCache) {
    return null;
  }

  final database = await ref.watch(appDatabaseFutureProvider.future);
  final secureStorage = ref.read(secureStorageProvider);
  final cacheKey = await secureStorage.readOrCreateCacheKey();
  final cipher = await LocalDataCipher.fromBase64Key(cacheKey);
  return DriftConversationCacheService(
    database,
    envelopeCodec: ref.read(cryptoAdapterProvider).envelopeCodec,
    cipher: cipher,
  );
});

final apiClientProvider = Provider<VeilApiClient>((ref) {
  return VeilApiClient(baseUrl: VeilConfig.apiBaseUrl);
});

final attachmentTempFileStoreProvider =
    Provider<AttachmentTempFileStore>((ref) {
  return DefaultAttachmentTempFileStore(
    onDirectoryPrepared: (path) =>
        ref.read(platformSecurityServiceProvider).excludePathFromBackup(path),
  );
});

final cryptoAdapterProvider = Provider<CryptoAdapter>((ref) {
  return createConfiguredCryptoAdapter();
});

final messagingCryptoProvider = Provider<MessageCryptoEngine>((ref) {
  return ref.read(cryptoAdapterProvider).messaging;
});

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  return RealtimeService();
});

final localNotificationServiceProvider =
    Provider<LocalNotificationService>((ref) {
  final service = LocalNotificationService();
  unawaited(service.initialize());
  return service;
});

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService(
    DeviceLocalUnlockAuthenticator(LocalAuthentication()),
    ref.read(secureStorageProvider),
  );
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
    required this.integrityCompromised,
    required this.integrityReasons,
    required this.screenCaptureProtectionSupported,
    required this.screenCaptureProtectionEnabled,
    required this.appPreviewProtectionEnabled,
  });

  final bool hasDeviceSecretRefs;
  final bool hasPin;
  final bool biometricsAvailable;
  final bool integrityCompromised;
  final List<String> integrityReasons;
  final bool screenCaptureProtectionSupported;
  final bool screenCaptureProtectionEnabled;
  final bool appPreviewProtectionEnabled;
}

final localSecuritySnapshotProvider =
    FutureProvider<LocalSecuritySnapshot>((ref) async {
  final storage = ref.read(secureStorageProvider);
  final appLock = ref.read(appLockServiceProvider);
  final platformSecurityService = ref.read(platformSecurityServiceProvider);
  await platformSecurityService.applyPrivacyProtections();
  final platformSecurity = await platformSecurityService.getStatus();
  final values = await Future.wait<bool>([
    storage.hasDeviceSecretRefs(),
    appLock.hasPin(),
    appLock.canUseBiometrics(),
  ]);

  return LocalSecuritySnapshot(
    hasDeviceSecretRefs: values[0],
    hasPin: values[1],
    biometricsAvailable: values[2],
    integrityCompromised: platformSecurity.integrityCompromised,
    integrityReasons: platformSecurity.integrityReasons,
    screenCaptureProtectionSupported:
        platformSecurity.screenCaptureProtectionSupported,
    screenCaptureProtectionEnabled:
        platformSecurity.screenCaptureProtectionEnabled,
    appPreviewProtectionEnabled: platformSecurity.appPreviewProtectionEnabled,
  );
});

class AppSessionState {
  static const Object _unset = Object();

  const AppSessionState({
    this.accessToken,
    this.refreshToken,
    this.userId,
    this.deviceId,
    this.handle,
    this.displayName,
    this.onboardingAccepted = false,
    this.privacyConsentAccepted = false,
    this.locked = true,
    this.initializing = true,
    this.authFlowStage = AuthFlowStage.idle,
    this.errorMessage,
  });

  final String? accessToken;
  final String? refreshToken;
  final String? userId;
  final String? deviceId;
  final String? handle;
  final String? displayName;
  final bool onboardingAccepted;
  final bool privacyConsentAccepted;
  final bool locked;
  final bool initializing;
  final AuthFlowStage authFlowStage;
  final String? errorMessage;

  bool get isAuthenticated =>
      accessToken != null &&
      userId != null &&
      deviceId != null &&
      handle != null;

  bool get isAuthenticating =>
      authFlowStage != AuthFlowStage.idle &&
      authFlowStage != AuthFlowStage.complete;

  AppSessionState copyWith({
    Object? accessToken = _unset,
    Object? refreshToken = _unset,
    Object? userId = _unset,
    Object? deviceId = _unset,
    Object? handle = _unset,
    Object? displayName = _unset,
    bool? onboardingAccepted,
    bool? privacyConsentAccepted,
    bool? locked,
    bool? initializing,
    AuthFlowStage? authFlowStage,
    Object? errorMessage = _unset,
  }) {
    return AppSessionState(
      accessToken: identical(accessToken, _unset)
          ? this.accessToken
          : accessToken as String?,
      refreshToken: identical(refreshToken, _unset)
          ? this.refreshToken
          : refreshToken as String?,
      userId: identical(userId, _unset) ? this.userId : userId as String?,
      deviceId:
          identical(deviceId, _unset) ? this.deviceId : deviceId as String?,
      handle: identical(handle, _unset) ? this.handle : handle as String?,
      displayName: identical(displayName, _unset)
          ? this.displayName
          : displayName as String?,
      onboardingAccepted: onboardingAccepted ?? this.onboardingAccepted,
      privacyConsentAccepted: privacyConsentAccepted ?? this.privacyConsentAccepted,
      locked: locked ?? this.locked,
      initializing: initializing ?? this.initializing,
      authFlowStage: authFlowStage ?? this.authFlowStage,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class AppSessionController extends StateNotifier<AppSessionState> {
  AppSessionController(
    this._storage,
    this._apiClient,
    this._cryptoAdapter, {
    ConversationCacheService? cacheService,
    AttachmentTempFileStore? attachmentTempFileStore,
    VoidCallback? onLocalCacheMaterialChanged,
  })  : _cacheService = cacheService,
        _attachmentTempFileStore = attachmentTempFileStore,
        _onLocalCacheMaterialChanged = onLocalCacheMaterialChanged,
        super(const AppSessionState());

  final SecureStorageService _storage;
  final VeilApiClient _apiClient;
  final CryptoAdapter _cryptoAdapter;
  final ConversationCacheService? _cacheService;
  final AttachmentTempFileStore? _attachmentTempFileStore;
  final VoidCallback? _onLocalCacheMaterialChanged;
  DeviceIdentityMaterial? _pendingTransferIdentity;
  DeviceAuthKeyMaterial? _pendingTransferAuthKey;
  String? _pendingTransferSessionId;
  String? _pendingTransferToken;
  String? _pendingTransferClaimId;

  Future<void> bootstrap() async {
    final runtimeConfigurationError = VeilConfig.runtimeConfigurationError;
    if (runtimeConfigurationError != null) {
      state = AppSessionState(
        onboardingAccepted: await _storage.readOnboardingAccepted(),
        locked: true,
        initializing: false,
        errorMessage: runtimeConfigurationError,
      );
      return;
    }

    final session = await _storage.readSession();
    final onboardingAccepted = await _storage.readOnboardingAccepted();
    final privacyConsentAccepted = await _storage.readPrivacyConsent();
    state = AppSessionState(
      accessToken: session?.accessToken,
      refreshToken: session?.refreshToken,
      userId: session?.userId,
      deviceId: session?.deviceId,
      handle: session?.handle,
      displayName: session?.displayName,
      onboardingAccepted: onboardingAccepted,
      privacyConsentAccepted: privacyConsentAccepted,
      locked: session != null,
      initializing: false,
    );
  }

  Future<void> acceptOnboarding() async {
    await _storage.persistOnboardingAccepted(true);
    state = state.copyWith(onboardingAccepted: true);
  }

  Future<void> acceptPrivacyConsent() async {
    await _storage.persistPrivacyConsent(true);
    state = state.copyWith(privacyConsentAccepted: true);
  }

  Future<void> registerAndAuthenticate({
    required String handle,
    String? displayName,
  }) async {
    state = state.copyWith(
        errorMessage: null, authFlowStage: AuthFlowStage.generatingKeys);

    try {
      final materialSeed =
          'device-material-${DateTime.now().microsecondsSinceEpoch}';
      final identity =
          await _cryptoAdapter.identity.generateDeviceIdentity(materialSeed);
      final authKeyMaterial =
          await _cryptoAdapter.deviceAuth.generateAuthKeyMaterial();

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
      final proof = await _cryptoAdapter.deviceAuth.signChallenge(
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
        refreshToken: verified['refreshToken'] as String?,
        userId: verified['userId'] as String,
        deviceId: verified['deviceId'] as String,
        handle: handle,
        displayName: displayName,
      );

      state = state.copyWith(
        accessToken: verified['accessToken'] as String,
        refreshToken: verified['refreshToken'] as String?,
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
      final handled = await handleSecurityException(error);
      state = state.copyWith(
        errorMessage: handled ? null : _formatUserFacingError(error),
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
      await _clearLocalState(
        preserveOnboardingAccepted: true,
        preservePin: false,
      );
    }
  }

  Future<void> revokeListedDevice(String deviceId) async {
    final accessToken = state.accessToken;
    final currentDeviceId = state.deviceId;
    if (accessToken == null || deviceId.isEmpty) {
      return;
    }

    if (currentDeviceId == deviceId) {
      await revokeCurrentDevice();
      return;
    }

    await _apiClient.revokeDevice(accessToken, deviceId);
  }

  Future<void> deleteAccount() async {
    final accessToken = state.accessToken;
    if (accessToken == null) {
      return;
    }

    try {
      await _apiClient.deleteAccount(accessToken);
    } finally {
      await _clearLocalState(
        preserveOnboardingAccepted: false,
        preservePin: false,
      );
    }
  }

  Future<void> logout() async {
    final accessToken = state.accessToken;
    final refreshToken = state.refreshToken;
    if (accessToken != null) {
      try {
        await _apiClient.logoutAuth(accessToken, refreshToken: refreshToken);
      } catch (_) {
        // Server-side revoke is best-effort; local wipe must still proceed.
      }
    }
    await _clearLocalState(
      preserveOnboardingAccepted: true,
      preservePin: true,
    );
  }

  /// Attempts to exchange the stored refresh token for a new access token.
  /// Returns the fresh access token on success, or `null` if the session
  /// is no longer usable (caller should fall back to re-authentication).
  Future<String?> refreshSession() async {
    final refreshToken = state.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      return null;
    }

    try {
      final refreshed = await _apiClient.refreshAuth(refreshToken);
      final newAccess = refreshed['accessToken'] as String?;
      final newRefresh = refreshed['refreshToken'] as String?;
      if (newAccess == null || newAccess.isEmpty) {
        return null;
      }
      await _storage.updateAccessTokens(
        accessToken: newAccess,
        refreshToken: newRefresh,
      );
      state = state.copyWith(
        accessToken: newAccess,
        refreshToken: newRefresh ?? state.refreshToken,
      );
      return newAccess;
    } catch (_) {
      return null;
    }
  }

  Future<void> wipeLocalDeviceState() async {
    await _clearLocalState(
      preserveOnboardingAccepted: false,
      preservePin: false,
    );
  }

  Future<bool> handleSecurityException(Object error) async {
    final code = extractVeilApiErrorCode(error);
    if (code == 'device_not_active') {
      await _clearLocalState(
        preserveOnboardingAccepted: true,
        preservePin: false,
      );
      return true;
    }

    if (code == 'transfer_session_inactive' ||
        code == 'transfer_token_invalid' ||
        code == 'transfer_claim_required' ||
        code == 'transfer_approval_required' ||
        code == 'transfer_completion_invalid') {
      _clearPendingTransferClaim();
      state = state.copyWith(
        errorMessage: _formatUserFacingError(error),
      );
      return false;
    }

    return false;
  }

  Future<void> _clearLocalState({
    required bool preserveOnboardingAccepted,
    required bool preservePin,
  }) async {
    await _storage.wipeLocalDeviceState(
      preserveOnboardingAccepted: preserveOnboardingAccepted,
      preservePin: preservePin,
    );
    await _cacheService?.clearAll();
    await _attachmentTempFileStore?.purgeAll();
    _onLocalCacheMaterialChanged?.call();
    _clearPendingTransferClaim();
    state = state.copyWith(
      accessToken: null,
      refreshToken: null,
      userId: null,
      deviceId: null,
      handle: null,
      displayName: null,
      errorMessage: null,
      locked: true,
      onboardingAccepted:
          preserveOnboardingAccepted ? state.onboardingAccepted : false,
      privacyConsentAccepted:
          preserveOnboardingAccepted ? state.privacyConsentAccepted : false,
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

      final materialSeed =
          'device-transfer-${DateTime.now().microsecondsSinceEpoch}';
      final identity =
          await _cryptoAdapter.identity.generateDeviceIdentity(materialSeed);
      final authKeyMaterial =
          await _cryptoAdapter.deviceAuth.generateAuthKeyMaterial();
      final authProof = await _cryptoAdapter.deviceAuth.signChallenge(
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
      final handled = await handleSecurityException(error);
      state = state.copyWith(
          errorMessage: handled ? null : _formatUserFacingError(error));
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
      final completionProof = await _cryptoAdapter.deviceAuth.signChallenge(
        challenge: 'transfer-complete:$sessionId:$claimId:$transferToken',
        keyMaterial: authKeyMaterial,
      );

      final completed = await _apiClient.completeTransfer({
        'sessionId': sessionId,
        'transferToken': transferToken,
        'claimId': claimId,
        'authProof': completionProof,
      });

      final newDeviceId = completed['newDeviceId'] as String;
      final handle = completed['handle'] as String;
      final challenge = await _apiClient.challenge({
        'handle': handle,
        'deviceId': newDeviceId,
      });
      final proof = await _cryptoAdapter.deviceAuth.signChallenge(
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
        refreshToken: verified['refreshToken'] as String?,
        userId: verified['userId'] as String,
        deviceId: verified['deviceId'] as String,
        handle: handle,
        displayName: displayName,
      );

      state = state.copyWith(
        accessToken: verified['accessToken'] as String,
        refreshToken: verified['refreshToken'] as String?,
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
      final handled = await handleSecurityException(error);
      state = state.copyWith(
          errorMessage: handled ? null : _formatUserFacingError(error));
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
    ref.read(cryptoAdapterProvider),
    cacheService: ref.watch(conversationCacheProvider).maybeWhen(
          data: (cache) => cache,
          orElse: () => null,
        ),
    attachmentTempFileStore: ref.read(attachmentTempFileStoreProvider),
    onLocalCacheMaterialChanged: () {
      ref.read(cacheEpochProvider.notifier).state++;
      ref.invalidate(conversationCacheProvider);
    },
  );
});

final pushTokenCoordinatorProvider = Provider<PushTokenCoordinator>((ref) {
  final coordinator = PushTokenCoordinator(
    apiClient: ref.read(apiClientProvider),
    pushService: ref.read(remotePushServiceProvider),
  );
  ref.onDispose(() {
    unawaited(coordinator.dispose());
  });
  return coordinator;
});

final messengerControllerProvider =
    ChangeNotifierProvider<VeilMessengerController>((ref) {
  final notificationService = ref.read(localNotificationServiceProvider);
  final secureStorage = ref.read(secureStorageProvider);
  final cryptoAdapter = ref.read(cryptoAdapterProvider);

  // Double Ratchet session persistence: wire the adapter's after-mutate
  // callback to secure storage, and build a restorer that rehydrates
  // snapshots into memory on first authenticated applySession.
  Future<void> Function()? sessionRestorer;
  if (cryptoAdapter is LibCryptoAdapter) {
    cryptoAdapter.setSessionPersistence(
      persister: (conversationId, snapshot) =>
          secureStorage.writeSessionSnapshot(conversationId, snapshot),
    );
    sessionRestorer = () async {
      final snapshots = await secureStorage.readAllSessionSnapshots();
      if (snapshots.isEmpty) return;
      await cryptoAdapter.restoreSessionsFromSnapshots(snapshots);
    };
  }

  final controller = VeilMessengerController(
    apiClient: ref.read(apiClientProvider),
    cryptoEngine: ref.read(messagingCryptoProvider),
    keyBundleCodec: cryptoAdapter.keyBundles,
    envelopeCodec: cryptoAdapter.envelopeCodec,
    sessionBootstrapper: cryptoAdapter.sessions,
    realtimeService: ref.read(realtimeServiceProvider),
    cacheService: ref.watch(conversationCacheProvider).maybeWhen(
          data: (cache) => cache,
          orElse: () => null,
        ),
    attachmentTempFileStore: ref.read(attachmentTempFileStoreProvider),
    notificationService: notificationService,
    onSecurityException: (error) async {
      await ref
          .read(appSessionProvider.notifier)
          .handleSecurityException(error);
    },
    identityPrivateRefLoader: () => secureStorage.readIdentityPrivateRef(),
    sessionSnapshotRestorer: sessionRestorer,
  );

  final pushCoordinator = ref.read(pushTokenCoordinatorProvider);

  ref.listen<AppSessionState>(appSessionProvider, (previous, next) {
    unawaited(controller.applySession(next));
    final wasAuthed = previous?.isAuthenticated ?? false;
    if (next.isAuthenticated && next.accessToken != null) {
      unawaited(pushCoordinator.bind(next.accessToken!));
    } else if (wasAuthed && !next.isAuthenticated) {
      unawaited(pushCoordinator.unbind());
    }
  });

  final initial = ref.read(appSessionProvider);
  unawaited(controller.applySession(initial));
  if (initial.isAuthenticated && initial.accessToken != null) {
    unawaited(pushCoordinator.bind(initial.accessToken!));
  }
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
      return 'This device no longer has a trusted VEIL session.';
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
  if (normalized == 'API endpoint must use TLS outside local development.') {
    return 'The VEIL API endpoint must use TLS outside local development.';
  }
  if (normalized ==
      'Realtime endpoint must use TLS outside local development.') {
    return 'The VEIL realtime endpoint must use TLS outside local development.';
  }

  return redactSensitiveText(normalized);
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
