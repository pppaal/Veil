import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/veil_config.dart';
import '../../core/crypto/crypto_engine.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/network/veil_api_client.dart';
import '../../core/storage/conversation_cache_service.dart';
import '../../core/storage/secure_storage_service.dart';
import '../../features/attachments/data/attachment_temp_file_store.dart';
import '../app_session_state.dart';

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
        errorMessage: handled ? null : formatUserFacingError(error),
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
        errorMessage: formatUserFacingError(error),
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
          errorMessage: handled ? null : formatUserFacingError(error));
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
          errorMessage: handled ? null : formatUserFacingError(error));
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
