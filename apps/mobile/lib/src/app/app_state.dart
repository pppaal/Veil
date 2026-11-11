import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../core/config/veil_config.dart';
import '../core/crypto/crypto_adapter_registry.dart';
import '../core/crypto/crypto_engine.dart';
import '../core/crypto/group_sender_keys.dart';
import '../core/crypto/lib_crypto_adapter.dart';
import '../core/identity/trusted_identity_resolver.dart';
import '../core/identity/trusted_identity_store.dart';
import '../core/network/keys_api.dart';
import '../core/network/pinned_http_client.dart';
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
import '../core/storage/cache_handle.dart';
import '../core/storage/conversation_cache_service.dart';
import '../core/storage/database_provider.dart';
import '../core/storage/secure_storage_service.dart';
import '../features/attachments/data/attachment_temp_file_store.dart';
import '../features/conversations/data/group_sender_key_coordinator.dart';
import '../features/conversations/data/messenger/envelope_version_policy.dart';
import '../features/conversations/data/messenger/identity_trust.dart';
import '../features/conversations/data/messenger/legacy_trust_migration.dart';
import '../features/conversations/data/messenger/prekey_maintenance.dart';
import '../features/conversations/data/veil_messenger_controller.dart';
import '../features/settings/data/privacy_preferences.dart';
import 'app_session_state.dart';

export 'app_session_state.dart' show AppSessionState, AuthFlowStage;

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
    FutureProvider<DriftConversationCacheService?>((ref) async {
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

// Explicit variable type: apiClientProvider and appSessionProvider refer
// to each other, so the analyzer cannot infer their top-level types
// without this annotation (top_level_cycle).
final Provider<VeilApiClient> apiClientProvider = Provider<VeilApiClient>((ref) {
  final pins = parsePinList(VeilConfig.tlsPins);
  final httpClient = buildPinnedHttpClient(allowedFingerprints: pins);
  return VeilApiClient(
    baseUrl: VeilConfig.apiBaseUrl,
    client: httpClient,
    // Resolved lazily so the api client and session controller can refer to
    // each other without a Riverpod cycle. Returns null when there is no
    // refresh token, which keeps the original 401 surface to the caller.
    tokenRefresher: () => ref.read(appSessionProvider.notifier).refreshSession(),
  );
});

/// The conversation cache as long-lived consumers hold it: one object for
/// the app's life that always reaches the current database. Null when the
/// local cache is turned off.
final cacheHandleProvider = Provider<CacheHandle?>((ref) {
  if (!VeilConfig.enableLocalCache) return null;
  return CacheHandle(() async {
    final cache = await ref.read(conversationCacheProvider.future);
    return cache!;
  });
});

final keysApiProvider = Provider<KeysApi>((ref) {
  return KeysApi(ref.read(apiClientProvider), ref.read(cryptoAdapterProvider).keyBundles);
});

/// Contact identity pins, kept in the keystore and wiped with the device.
/// What earlier builds knew is migrated in before any decision is made,
/// reading the cache directly: the messenger decrypts and looks keys up as
/// soon as it applies a session. A cache that cannot be read fails the
/// migration (to be tried again) rather than reading as empty, which would
/// finish it with nothing carried over.
final identityTrustProvider = Provider<IdentityTrust>((ref) {
  final storage = ref.read(secureStorageProvider);
  final resolver = TrustedIdentityResolver(store: TrustedIdentityStore(storage.scoped(SecureScope.identity)));
  final trust = IdentityTrust(
    resolver,
    prepare: () => migrateLegacyTrust(
      storage: storage,
      resolver: resolver,
      readConversations: () async {
        final cache = await ref.read(conversationCacheProvider.future);
        return cache == null ? const [] : cache.readConversations();
      },
    ),
  );
  ref.onDispose(trust.dispose);
  return trust;
});

final privacyPreferencesProvider = ChangeNotifierProvider<PrivacyPreferences>((ref) {
  final preferences = PrivacyPreferences(ref.read(secureStorageProvider).scoped(SecureScope.privacy));
  unawaited(preferences.load());
  return preferences;
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
      // The display name stays on this device as the user's nickname; the
      // relay learns the handle and keys only.
      final registered = await _apiClient.register({
        'handle': handle,
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

  /// The user's own nickname, which only this device knows.
  Future<void> updateLocalNickname(String nickname) async {
    final value = nickname.isEmpty ? null : nickname;
    await _storage.persistLocalNickname(value);
    state = state.copyWith(displayName: value);
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
      );

      state = state.copyWith(
        accessToken: verified['accessToken'] as String,
        refreshToken: verified['refreshToken'] as String?,
        userId: verified['userId'] as String,
        deviceId: verified['deviceId'] as String,
        handle: handle,
        displayName: null,
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

final StateNotifierProvider<AppSessionController, AppSessionState>
    appSessionProvider =
    StateNotifierProvider<AppSessionController, AppSessionState>((ref) {
  return AppSessionController(
    ref.read(secureStorageProvider),
    ref.read(apiClientProvider),
    ref.read(cryptoAdapterProvider),
    // Read, not watched: the session controller outlives every database.
    cacheService: ref.read(cacheHandleProvider),
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
  final keys = ref.read(keysApiProvider);
  final trust = ref.read(identityTrustProvider);
  final privacy = ref.read(privacyPreferencesProvider);
  // Bound below; the group coordinator reaches the controller only after
  // both exist.
  late final VeilMessengerController controller;

  // Double Ratchet session persistence: wire the adapter's after-mutate
  // callback to secure storage, and build a restorer that rehydrates
  // snapshots into memory on first authenticated applySession.
  Future<void> Function()? sessionRestorer;
  GroupSenderKeyCoordinator? groupCrypto;
  // Adapters that publish their own prekeys keep the directory stocked.
  final prekeyMaintenance = cryptoAdapter is PrekeyManager
      ? PrekeyMaintenance(
          prekeys: cryptoAdapter as PrekeyManager,
          keys: keys,
          persistIdentityRef: secureStorage.replaceIdentityPrivateRef,
        )
      : null;
  if (cryptoAdapter is LibCryptoAdapter) {
    cryptoAdapter
      ..setSessionPersistence(
        persister: (conversationId, snapshot) =>
            secureStorage.writeSessionSnapshot(conversationId, snapshot),
      )
      // The responder side of the v2 handshake needs the persisted identity
      // and the prekey private halves it published.
      ..setLocalIdentityLoader(() => secureStorage.readIdentityPrivateRef())
      ..setLocalPrekeyStore(SecureStorageLocalPrekeyStore(secureStorage))
      // Inbound handshakes face the same identity pins as outbound ones.
      ..setRemoteIdentityVerifier((claim) => controller.verifyRemoteIdentity(claim));

    // Group Sender Keys ride on the same identity material as the 1:1
    // ratchet (X25519 prekey for sealing, Ed25519 identity for authorship),
    // so they are only wired when the lib adapter is active.
    final groupEngine = GroupSenderKeyEngine(
      persister: (groupId, snapshot) =>
          secureStorage.writeGroupSenderKeySnapshot(groupId, snapshot),
    );
    groupCrypto = GroupSenderKeyCoordinator(
      engine: groupEngine,
      sealer: GroupSenderKeySealer(
        resolveRecipientPrekey: LibIdentityKeys.resolveRemoteX25519,
      ),
      apiClient: ref.read(apiClientProvider),
      keys: keys,
      identityPrivateRefLoader: () => secureStorage.readIdentityPrivateRef(),
      localX25519PrivateParser: LibIdentityKeys.localX25519Private,
      localEd25519SeedParser: LibIdentityKeys.localEd25519Seed,
      conversationLookup: (conversationId) => controller.conversationById(conversationId),
      onKeysChanged: (conversationId) => controller.onGroupKeysChanged(conversationId),
      trustCheck: trust.admit,
    );

    sessionRestorer = () async {
      final snapshots = await secureStorage.readAllSessionSnapshots();
      if (snapshots.isNotEmpty) {
        await cryptoAdapter.restoreSessionsFromSnapshots(snapshots);
      }
      final groupSnapshots = await secureStorage.readAllGroupSenderKeySnapshots();
      if (groupSnapshots.isNotEmpty) {
        await groupEngine.restoreFromSnapshots(groupSnapshots);
      }
    };
  }

  controller = VeilMessengerController(
    apiClient: ref.read(apiClientProvider),
    cryptoEngine: ref.read(messagingCryptoProvider),
    keyBundleCodec: cryptoAdapter.keyBundles,
    envelopeCodec: cryptoAdapter.envelopeCodec,
    sessionBootstrapper: cryptoAdapter.sessions,
    realtimeService: ref.read(realtimeServiceProvider),
    // A stable handle, read lazily: watching the cache provider rebuilt the
    // controller once the database opened, which dropped in-flight state
    // such as attachment transfers.
    cacheService: ref.read(cacheHandleProvider),
    attachmentTempFileStore: ref.read(attachmentTempFileStoreProvider),
    notificationService: notificationService,
    onSecurityException: (error) async {
      await ref
          .read(appSessionProvider.notifier)
          .handleSecurityException(error);
    },
    sessionSnapshotRestorer: sessionRestorer,
    groupCrypto: groupCrypto,
    readReceiptsEnabled: () => privacy.sendReadReceipts,
    typingIndicatorsEnabled: () => privacy.sendTypingIndicators,
    keysApi: keys,
    identityTrust: trust,
    envelopeVersions: EnvelopeVersionPolicy(store: secureStorage.scoped(SecureScope.conversationPolicy)),
    prekeyMaintenance: prekeyMaintenance,
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
  // ChangeNotifierProvider disposes the controller itself; a second dispose
  // here used to trip ChangeNotifier's disposed assertion.
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
