import 'package:flutter/foundation.dart';

import '../../../app/app_session_state.dart';
import '../../../core/config/veil_config.dart';
import '../../../core/errors/user_facing_error.dart';
import '../../../core/network/veil_api_client.dart';
import '../../../core/security/device_step_up.dart';

/// The old device's half of a device transfer: it opens a transfer session,
/// shows its token, and approves the claim the new device made with it.
/// The new device's half (claim and completion) belongs to the session
/// controller, which owns the identity it creates.
class DeviceTransferController extends ChangeNotifier {
  DeviceTransferController({
    required VeilApiClient apiClient,
    required AppSessionState Function() session,
    Future<void> Function(Object error)? onSecurityException,
    Future<String> Function(String message)? signWithDeviceKey,
  })  : _apiClient = apiClient,
        _session = session,
        _onSecurityException = onSecurityException,
        _signWithDeviceKey = signWithDeviceKey;

  final VeilApiClient _apiClient;
  final AppSessionState Function() _session;
  final Future<void> Function(Object error)? _onSecurityException;
  // Signs with the auth key this device logs in with (DeviceStepUp.sign).
  final Future<String> Function(String message)? _signWithDeviceKey;

  bool _isBusy = false;
  bool _disposed = false;
  String? _errorMessage;
  String? _transferSessionId;
  String? _transferToken;
  String? _transferStatus;
  DateTime? _transferExpiresAt;

  bool get isBusy => _isBusy;
  String? get errorMessage => _errorMessage;
  String? get transferSessionId => _transferSessionId;
  String? get transferToken => _transferToken;
  String? get transferStatus => _transferStatus;
  DateTime? get transferExpiresAt => _transferExpiresAt;
  String? get transferPayload => _transferSessionId == null || _transferToken == null
      ? null
      : 'VEIL_TRANSFER::${_transferSessionId!}::${_transferToken!}';

  Future<void> initTransfer() async {
    await _run(() async {
      final session = _session();
      final deviceId = session.deviceId;
      final accessToken = session.accessToken;
      if (!session.isAuthenticated || !VeilConfig.hasApi || deviceId == null || accessToken == null) {
        _transferStatus = 'Transfer requires API mode.';
        return;
      }

      final response = await _apiClient.initTransfer(accessToken, deviceId);
      _transferSessionId = response['sessionId'] as String;
      _transferToken = response['transferToken'] as String;
      _transferExpiresAt = DateTime.parse(response['expiresAt'] as String);
      _transferStatus = 'Init complete. Token ready.';
    });
  }

  Future<void> approveTransfer(String claimId) async {
    await _run(() async {
      final trimmedClaimId = claimId.trim();
      final session = _session();
      final accessToken = session.accessToken;
      if (_transferSessionId == null || !session.isAuthenticated || !VeilConfig.hasApi || accessToken == null) {
        _transferStatus = 'Start transfer first.';
        return;
      }
      if (trimmedClaimId.isEmpty) {
        _transferStatus = 'Enter the new-device claim code first.';
        return;
      }

      final sign = _signWithDeviceKey;
      if (sign == null) {
        throw StateError('This device cannot sign a transfer approval.');
      }

      // Signed with this device's auth key, so a stolen bearer token cannot
      // hand the account to other keys (C-PROOF). The signature names the
      // fingerprint of the claimant's keys as the relay holds them.
      final sessionId = _transferSessionId!;
      final status = await _apiClient.getTransferStatus(accessToken, sessionId);
      final claim = status['pendingClaim'];
      if (claim is! Map<String, dynamic> || claim['claimId'] != trimmedClaimId) {
        _transferStatus = 'No claim $trimmedClaimId is waiting on this transfer.';
        return;
      }
      final fingerprint = claim['claimantFingerprint'] as String;
      final approvalProof = await sign(DeviceStepUpPurpose.transferApproval(
        sessionId: sessionId,
        claimId: trimmedClaimId,
        claimantFingerprint: fingerprint,
      ));
      await _apiClient.approveTransfer(accessToken, {
        'sessionId': sessionId,
        'claimId': trimmedClaimId,
        'approvalProof': approvalProof,
      });
      _transferStatus = 'Approved claim $trimmedClaimId on old device. Key fingerprint: $fingerprint';
    });
  }

  void clearTransferState() {
    _transferSessionId = null;
    _transferToken = null;
    _transferStatus = null;
    _transferExpiresAt = null;
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() action) async {
    _isBusy = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      await _onSecurityException?.call(error);
      _errorMessage = formatUserFacingError(error);
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // Requests finish asynchronously and may land after the owning provider
  // disposed this controller.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }
}
