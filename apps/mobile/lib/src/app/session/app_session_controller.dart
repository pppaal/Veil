import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/veil_config.dart';
import '../../core/crypto/crypto_engine.dart';
import '../../core/errors/user_facing_error.dart';
import '../../core/network/http_transport.dart' show TransportErrorCode;
import '../../core/network/veil_api_client.dart';
import '../../core/security/device_step_up.dart';
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
    Duration transferRetryDelay = const Duration(seconds: 2),
    Duration transferApprovalWait = const Duration(minutes: 2),
  })  : _cacheService = cacheService,
        _attachmentTempFileStore = attachmentTempFileStore,
        _onLocalCacheMaterialChanged = onLocalCacheMaterialChanged,
        _transferRetryDelay = transferRetryDelay,
        _transferApprovalWait = transferApprovalWait,
        super(const AppSessionState());

  final SecureStorageService _storage;
  final VeilApiClient _apiClient;
  final CryptoAdapter _cryptoAdapter;
  final ConversationCacheService? _cacheService;
  final AttachmentTempFileStore? _attachmentTempFileStore;
  final VoidCallback? _onLocalCacheMaterialChanged;
  final Duration _transferRetryDelay;
  final Duration _transferApprovalWait;
  late final DeviceStepUp _stepUp = DeviceStepUp(
    storage: _storage,
    signer: _cryptoAdapter.deviceAuth,
    apiClient: _apiClient,
  );

  // The transfer this new device claimed, mirrored in the keystore from the
  // moment the relay accepted the claim until the first login on the new
  // device succeeded (see PendingTransferRecord).
  PendingTransferRecord? _pendingTransfer;

  /// The claim this device made and has not finished, also after the app was
  /// stopped, so the transfer screen can offer to complete it.
  PendingTransferRecord? get pendingTransfer => _pendingTransfer;

  // Attempts of /device-transfer/complete through network failures and 5xx.
  static const _maxTransientTransferAttempts = 3;

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

    if (session == null) {
      _pendingTransfer = await _storage.readPendingTransfer();
      // The relay already moved the account to this device's keys: finish
      // the login it was waiting for when the app stopped.
      if (_pendingTransfer?.isCompleted ?? false) {
        unawaited(resumeCompletedTransfer().catchError((Object _) {}));
      }
    }
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

  /// Revokes this device, signed with its auth key (C-PROOF). Local state
  /// is wiped only once the relay revoked it (or already had): wiping a
  /// device the relay still counts as active would leave the account with
  /// an active device nobody holds, and there is no recovery.
  Future<void> revokeCurrentDevice() async {
    final accessToken = state.accessToken;
    final deviceId = state.deviceId;
    final handle = state.handle;
    if (accessToken == null || deviceId == null || handle == null) {
      return;
    }

    await _keepLocalStateUnlessDone(() async {
      final proof = await _stepUp.proof(
        handle: handle,
        deviceId: deviceId,
        purpose: DeviceStepUpPurpose.deviceRevoke(deviceId),
      );
      await _apiClient.revokeDevice(accessToken, deviceId, proof: proof);
    });
    await _clearLocalState(
      preserveOnboardingAccepted: true,
      preservePin: false,
    );
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

  /// Deletes the account, signed with this device's auth key (C-PROOF).
  /// Local state is wiped only once the relay deleted it: a refused or
  /// unanswered request leaves the account alive, and this device is the
  /// only way back into it.
  Future<void> deleteAccount() async {
    final accessToken = state.accessToken;
    final deviceId = state.deviceId;
    final handle = state.handle;
    if (accessToken == null || deviceId == null || handle == null) {
      return;
    }

    await _keepLocalStateUnlessDone(() async {
      final proof = await _stepUp.proof(
        handle: handle,
        deviceId: deviceId,
        purpose: DeviceStepUpPurpose.accountDelete,
      );
      await _apiClient.deleteAccount(accessToken, proof: proof);
    });
    await _clearLocalState(
      preserveOnboardingAccepted: false,
      preservePin: false,
    );
  }

  // Runs an irreversible request. When it fails the device keeps its state,
  // unless the relay says the device is no longer active (which wipes it, as
  // everywhere), and the error is rethrown for the screen to show.
  Future<void> _keepLocalStateUnlessDone(
    Future<void> Function() request,
  ) async {
    try {
      await request();
    } catch (error) {
      final handled = await handleSecurityException(error);
      if (!handled) {
        state = state.copyWith(errorMessage: formatUserFacingError(error));
      }
      rethrow;
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

    // A transfer refusal never drops the claimed keys: once the relay has
    // committed the transfer they are the only keys the account trusts. The
    // next claim replaces them.
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
    _pendingTransfer = null;
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

      final record = PendingTransferRecord(
        sessionId: sessionId,
        transferToken: transferToken,
        claimId: claimed['claimId'] as String,
        claimantFingerprint: claimed['claimantFingerprint'] as String,
        expiresAt: DateTime.parse(claimed['expiresAt'] as String),
        identity: identity,
        authKey: authKeyMaterial,
      );
      // Kept before anything else can fail: the relay holds this claim now,
      // and a second claim would end the transfer session.
      await _storage.persistPendingTransfer(record);
      _pendingTransfer = record;

      return TransferClaimResult(
        claimId: record.claimId,
        claimantFingerprint: record.claimantFingerprint,
        expiresAt: record.expiresAt,
      );
    } catch (error) {
      final handled = await handleSecurityException(error);
      state = state.copyWith(
          errorMessage: handled ? null : formatUserFacingError(error));
      rethrow;
    }
  }

  /// Completes the transfer this device claimed and logs in as the new
  /// device (C-TRANSFER-RETRY). The relay's answer to /complete is kept
  /// before the login starts, so a failed or interrupted login is redone
  /// without completing again. /complete itself is retried after a network
  /// failure or a 5xx (the relay answers an identical retry with the same
  /// completion), and polled while the old device has not approved yet. Any
  /// other refusal stops; the claimed keys stay until the next claim.
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

      var record = _pendingTransfer ?? await _storage.readPendingTransfer();
      if (record == null ||
          record.sessionId != sessionId ||
          record.transferToken != transferToken ||
          record.claimId != claimId) {
        throw StateError('Claim this new device before completion.');
      }
      _pendingTransfer = record;

      if (!record.isCompleted) {
        final completionProof = await _cryptoAdapter.deviceAuth.signChallenge(
          challenge: 'transfer-complete:$sessionId:$claimId:$transferToken',
          keyMaterial: record.authKey,
        );
        final completed = await _completeTransferRequest({
          'sessionId': sessionId,
          'transferToken': transferToken,
          'claimId': claimId,
          'authProof': completionProof,
        });
        record = record.completedAs(
          newDeviceId: completed['newDeviceId'] as String,
          handle: completed['handle'] as String,
        );
        await _storage.persistPendingTransfer(record);
        _pendingTransfer = record;
      }

      await _loginAsTransferredDevice(record);
    } catch (error) {
      final handled = await handleSecurityException(error);
      state = state.copyWith(
          errorMessage: handled ? null : formatUserFacingError(error));
      rethrow;
    }
  }

  /// Finishes a transfer the relay already committed, when the app stopped
  /// between the completion and the first login. Does nothing without one.
  Future<void> resumeCompletedTransfer() async {
    final record = _pendingTransfer ?? await _storage.readPendingTransfer();
    if (record == null || !record.isCompleted || state.isAuthenticated) {
      return;
    }
    await completeTransferAndAuthenticate(
      sessionId: record.sessionId,
      transferToken: record.transferToken,
      claimId: record.claimId,
    );
  }

  Future<Map<String, dynamic>> _completeTransferRequest(
    Map<String, dynamic> body,
  ) async {
    final waiting = Stopwatch()..start();
    var transientFailures = 0;
    while (true) {
      try {
        return await _apiClient.completeTransfer(body);
      } on VeilApiException catch (error) {
        if (error.code == 'transfer_approval_required') {
          if (waiting.elapsed >= _transferApprovalWait) rethrow;
        } else if (_isTransientTransferFailure(error)) {
          transientFailures += 1;
          if (transientFailures >= _maxTransientTransferAttempts) rethrow;
        } else {
          rethrow;
        }
      }
      await Future<void>.delayed(_transferRetryDelay);
    }
  }

  static bool _isTransientTransferFailure(VeilApiException error) {
    final status = error.statusCode;
    if (status != null) return status >= 500;
    return error.code == TransportErrorCode.unavailable ||
        error.code == TransportErrorCode.timeout;
  }

  Future<void> _loginAsTransferredDevice(PendingTransferRecord record) async {
    final newDeviceId = record.newDeviceId!;
    final handle = record.handle!;
    final challenge = await _apiClient.challenge({
      'handle': handle,
      'deviceId': newDeviceId,
    });
    final proof = await _cryptoAdapter.deviceAuth.signChallenge(
      challenge: challenge['challenge'] as String,
      keyMaterial: record.authKey,
    );
    final verified = await _apiClient.verify({
      'challengeId': challenge['challengeId'],
      'deviceId': newDeviceId,
      'signature': proof,
    });

    await _storage.persistDeviceSecretRefs(
      identityPrivateRef: record.identity.identityPrivateKeyRef,
      authPrivateKey: record.authKey.privateKey,
      authPublicKey: record.authKey.publicKey,
    );
    await _storage.persistSession(
      accessToken: verified['accessToken'] as String,
      refreshToken: verified['refreshToken'] as String?,
      userId: verified['userId'] as String,
      deviceId: verified['deviceId'] as String,
      handle: handle,
    );
    await _storage.clearPendingTransfer();
    _pendingTransfer = null;

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
