import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';

// In-process stand-in for the relay's account routes: registration, login
// challenges, device transfer, device revocation and account deletion. It
// checks every signature the way the API does (AuthService.verify,
// AuthService.verifyDeviceStepUp, DeviceTransferService): Ed25519 over the
// UTF-8 bytes of the same domain-separated strings, base64url encoded,
// against the auth key the relay stored for the device. Step-up proofs are
// required in every case the API requires them, and a challenge is consumed
// on first presentation, whether or not its signature holds.

class FakeAccountDevice {
  FakeAccountDevice({
    required this.id,
    required this.userId,
    required this.authPublicKey,
    required this.publicIdentityKey,
  });

  final String id;
  final String userId;
  final String authPublicKey;
  final String publicIdentityKey;
  bool active = true;
}

class FakeAccountUser {
  FakeAccountUser({required this.id, required this.handle});

  final String id;
  final String handle;
  bool deleted = false;
}

class FakeTransferClaim {
  FakeTransferClaim({
    required this.claimId,
    required this.authPublicKey,
    required this.publicIdentityKey,
    required this.claimantFingerprint,
  });

  final String claimId;
  final String authPublicKey;
  final String publicIdentityKey;
  final String claimantFingerprint;
  bool approved = false;
}

class FakeTransferSession {
  FakeTransferSession({
    required this.id,
    required this.userId,
    required this.oldDeviceId,
    required this.transferToken,
    required this.expiresAt,
  });

  final String id;
  final String userId;
  final String oldDeviceId;
  final String transferToken;
  final DateTime expiresAt;
  FakeTransferClaim? claim;
  bool invalidated = false;
  DateTime? completedAt;
  String? newDeviceId;
}

class FakeAccountRelay extends VeilApiClient {
  FakeAccountRelay() : super(baseUrl: 'http://relay.invalid/v1');

  final Map<String, FakeAccountUser> usersByHandle = {};
  final Map<String, FakeAccountDevice> devices = {};
  final Map<String, FakeTransferSession> transfers = {};
  final Map<String, ({String challenge, String deviceId})> _challenges = {};
  final Map<String, String> _deviceByAccessToken = {};
  int _ids = 0;

  /// Every route called, in order (`POST /device-transfer/complete`, ...).
  final List<String> calls = [];

  /// Completions to commit and then answer with a network failure, as a
  /// connection that drops after the relay committed does.
  int dropCompletionResponses = 0;

  /// Completions to answer with a 503 before anything is committed.
  int failCompletions = 0;

  /// Login challenges to answer with a 503.
  int failChallenges = 0;

  /// Runs before each completion is handled (to approve mid-poll, say).
  void Function()? onComplete;

  /// Runs after each login challenge was issued.
  void Function()? onChallenge;

  String _id(String prefix) => '$prefix-${++_ids}';

  int callsTo(String route) => calls.where((call) => call == route).length;

  FakeAccountUser userOf(FakeAccountDevice device) =>
      usersByHandle.values.firstWhere((user) => user.id == device.userId);

  List<FakeAccountDevice> activeDevicesOf(String userId) =>
      [for (final device in devices.values) if (device.userId == userId && device.active) device];

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> body) async {
    calls.add('POST /auth/register');
    final handle = (body['handle'] as String).toLowerCase();
    if (usersByHandle[handle] case final existing? when !existing.deleted) {
      throw VeilApiException('Handle taken', statusCode: 409, code: 'handle_taken');
    }
    final user = usersByHandle[handle] = FakeAccountUser(id: _id('user'), handle: handle);
    final device = _addDevice(user.id, body['authPublicKey'] as String, body['publicIdentityKey'] as String);
    return {'userId': user.id, 'deviceId': device.id};
  }

  @override
  Future<Map<String, dynamic>> challenge(Map<String, dynamic> body) async {
    calls.add('POST /auth/challenge');
    if (failChallenges > 0) {
      failChallenges -= 1;
      throw VeilApiException('relay unavailable', statusCode: 503);
    }
    final user = usersByHandle[(body['handle'] as String).toLowerCase()];
    final device = devices[body['deviceId']];
    if (user == null || user.deleted || device == null || device.userId != user.id || !device.active) {
      throw VeilApiException('Active device not found for handle', statusCode: 404, code: 'active_device_not_found');
    }
    final challengeId = _id('challenge');
    final challenge = _id('nonce');
    _challenges[challengeId] = (challenge: challenge, deviceId: device.id);
    onChallenge?.call();
    return {
      'challengeId': challengeId,
      'challenge': challenge,
      'expiresAt': DateTime.now().add(const Duration(minutes: 5)).toUtc().toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>> verify(Map<String, dynamic> body) async {
    calls.add('POST /auth/verify');
    final stored = _challenges.remove(body['challengeId']);
    if (stored == null || stored.deviceId != body['deviceId']) {
      throw VeilApiException('Challenge expired or invalid', statusCode: 401, code: 'challenge_invalid');
    }
    final device = devices[stored.deviceId];
    if (device == null || !device.active) {
      throw VeilApiException('Device is not active', statusCode: 401, code: 'device_not_active');
    }
    if (!await _signedBy(device.authPublicKey, stored.challenge, body['signature'])) {
      throw VeilApiException('Invalid device signature', statusCode: 401, code: 'invalid_device_signature');
    }
    final accessToken = _id('access');
    _deviceByAccessToken[accessToken] = device.id;
    return {
      'accessToken': accessToken,
      'refreshToken': _id('refresh'),
      'userId': device.userId,
      'deviceId': device.id,
    };
  }

  @override
  Future<Map<String, dynamic>> initTransfer(String accessToken, String oldDeviceId) async {
    calls.add('POST /device-transfer/init');
    final caller = _authenticate(accessToken);
    if (caller.id != oldDeviceId) {
      throw VeilApiException('Transfer must be initiated from the trusted old device',
          statusCode: 403, code: 'device_forbidden');
    }
    final session = FakeTransferSession(
      id: _id('transfer'),
      userId: caller.userId,
      oldDeviceId: caller.id,
      transferToken: _id('token'),
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
    );
    transfers[session.id] = session;
    return {
      'sessionId': session.id,
      'transferToken': session.transferToken,
      'expiresAt': session.expiresAt.toUtc().toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>> claimTransfer(Map<String, dynamic> body) async {
    calls.add('POST /device-transfer/claim');
    final session = _transfer(body['sessionId']);
    if (_inactive(session)) {
      throw VeilApiException('Transfer session is no longer active', statusCode: 403, code: 'transfer_session_inactive');
    }
    if (body['transferToken'] != session.transferToken) {
      throw VeilApiException('Transfer token invalid', statusCode: 401, code: 'transfer_token_invalid');
    }
    final authPublicKey = body['authPublicKey'] as String;
    if (!await _signedBy(authPublicKey, 'transfer-claim:${session.id}:${session.transferToken}', body['authProof'])) {
      throw VeilApiException('New device claim proof is invalid', statusCode: 401, code: 'transfer_claim_invalid');
    }
    if (session.claim != null) {
      session
        ..invalidated = true
        ..claim = null;
      throw VeilApiException('Transfer session was claimed twice', statusCode: 409, code: 'transfer_claim_invalid');
    }
    final publicIdentityKey = body['publicIdentityKey'] as String;
    final claim = session.claim = FakeTransferClaim(
      claimId: _id('claim'),
      authPublicKey: authPublicKey,
      publicIdentityKey: publicIdentityKey,
      claimantFingerprint: _fingerprint(authPublicKey, publicIdentityKey),
    );
    return {
      'sessionId': session.id,
      'claimId': claim.claimId,
      'claimantFingerprint': claim.claimantFingerprint,
      'expiresAt': session.expiresAt.toUtc().toIso8601String(),
    };
  }

  @override
  Future<Map<String, dynamic>> getTransferStatus(String accessToken, String sessionId) async {
    calls.add('GET /device-transfer/sessions/:id');
    final caller = _authenticate(accessToken);
    final session = transfers[sessionId];
    if (session == null || session.userId != caller.userId || session.oldDeviceId != caller.id) {
      throw VeilApiException('Transfer session not found', statusCode: 404, code: 'transfer_session_not_found');
    }
    final claim = session.invalidated ? null : session.claim;
    return {
      'sessionId': session.id,
      'status': session.invalidated
          ? 'invalidated'
          : session.completedAt != null
              ? 'completed'
              : claim == null
                  ? 'pending'
                  : claim.approved
                      ? 'approved'
                      : 'claimed',
      'expiresAt': session.expiresAt.toUtc().toIso8601String(),
      'pendingClaim': claim == null
          ? null
          : {
              'claimId': claim.claimId,
              'claimantFingerprint': claim.claimantFingerprint,
              'newDeviceName': 'VEIL Mobile',
              'platform': 'android',
              'approvedAt': null,
            },
    };
  }

  // DeviceTransferService.approve: the old device signs
  // 'transfer-approve:<sessionId>:<claimId>:<claimantFingerprint>' with the
  // auth key it logs in with. Required in every environment.
  @override
  Future<Map<String, dynamic>> approveTransfer(String accessToken, Map<String, dynamic> body) async {
    calls.add('POST /device-transfer/approve');
    final caller = _authenticate(accessToken);
    final session = transfers[body['sessionId']];
    if (session == null || session.userId != caller.userId || session.oldDeviceId != caller.id) {
      throw VeilApiException('Transfer session not found', statusCode: 404, code: 'transfer_session_not_found');
    }
    if (_inactive(session)) {
      throw VeilApiException('Transfer session is no longer active', statusCode: 403, code: 'transfer_session_inactive');
    }
    final claim = session.claim;
    if (claim == null || claim.claimId != body['claimId']) {
      throw VeilApiException('A matching new-device claim is required before approval',
          statusCode: 403, code: 'transfer_claim_required');
    }
    final message = 'transfer-approve:${session.id}:${claim.claimId}:${claim.claimantFingerprint}';
    if (!await _signedBy(caller.authPublicKey, message, body['approvalProof'])) {
      throw VeilApiException('The old device must sign the approval', statusCode: 401, code: 'invalid_device_signature');
    }
    claim.approved = true;
    return {'sessionId': session.id, 'claimId': claim.claimId, 'approved': true};
  }

  // DeviceTransferService.complete, including the replay of a completion
  // whose response was lost.
  @override
  Future<Map<String, dynamic>> completeTransfer(Map<String, dynamic> body) async {
    calls.add('POST /device-transfer/complete');
    onComplete?.call();
    if (failCompletions > 0) {
      failCompletions -= 1;
      throw VeilApiException('relay unavailable', statusCode: 503);
    }
    final session = _transfer(body['sessionId']);
    final completionMessage = 'transfer-complete:${body['sessionId']}:${body['claimId']}:${body['transferToken']}';
    final newDeviceId = session.newDeviceId;
    if (session.completedAt != null && newDeviceId != null && body['transferToken'] == session.transferToken) {
      final device = devices[newDeviceId]!;
      if (!device.active) {
        throw VeilApiException('Transfer session already completed', statusCode: 403, code: 'transfer_session_inactive');
      }
      if (!await _signedBy(device.authPublicKey, completionMessage, body['authProof'])) {
        throw VeilApiException('New device completion proof is invalid',
            statusCode: 401, code: 'transfer_completion_invalid');
      }
      return _completion(session, body['claimId'] as String);
    }
    if (_inactive(session)) {
      throw VeilApiException('Transfer session already completed', statusCode: 403, code: 'transfer_session_inactive');
    }
    if (body['transferToken'] != session.transferToken) {
      throw VeilApiException('Transfer token invalid', statusCode: 401, code: 'transfer_token_invalid');
    }
    final claim = session.claim;
    if (claim == null || claim.claimId != body['claimId']) {
      throw VeilApiException('A matching approved claim is required before completion',
          statusCode: 403, code: 'transfer_claim_required');
    }
    if (!claim.approved) {
      throw VeilApiException('Old device approval is required before completion',
          statusCode: 403, code: 'transfer_approval_required');
    }
    if (!await _signedBy(claim.authPublicKey, completionMessage, body['authProof'])) {
      throw VeilApiException('New device completion proof is invalid',
          statusCode: 401, code: 'transfer_completion_invalid');
    }
    final device = _addDevice(session.userId, claim.authPublicKey, claim.publicIdentityKey);
    devices[session.oldDeviceId]!.active = false;
    session
      ..completedAt = DateTime.now()
      ..newDeviceId = device.id
      ..claim = null;
    if (dropCompletionResponses > 0) {
      dropCompletionResponses -= 1;
      throw VeilApiException('The VEIL relay is unreachable.', code: 'network_unavailable');
    }
    return _completion(session, claim.claimId);
  }

  // DevicesService.revoke: revoking the calling device, or the last active
  // one, needs a step-up proof with purpose 'device-revoke:<deviceId>'.
  @override
  Future<Map<String, dynamic>> revokeDevice(
    String accessToken,
    String deviceId, {
    Map<String, String>? proof,
  }) async {
    calls.add('POST /devices/revoke');
    final caller = _authenticate(accessToken);
    final target = devices[deviceId];
    if (target == null) {
      throw VeilApiException('Device not found', statusCode: 404, code: 'device_not_found');
    }
    if (target.userId != caller.userId) {
      throw VeilApiException('Device does not belong to actor', statusCode: 403, code: 'device_forbidden');
    }
    final othersActive = activeDevicesOf(caller.userId).where((device) => device.id != deviceId);
    if (deviceId == caller.id || othersActive.isEmpty) {
      await _verifyStepUp(caller, 'device-revoke:$deviceId', proof);
    }
    target.active = false;
    return {'deviceId': deviceId, 'revokedAt': DateTime.now().toUtc().toIso8601String()};
  }

  // DELETE /account: a step-up proof with purpose 'account-delete'.
  @override
  Future<Map<String, dynamic>> deleteAccount(
    String accessToken, {
    required Map<String, String> proof,
  }) async {
    calls.add('DELETE /account');
    final caller = _authenticate(accessToken);
    await _verifyStepUp(caller, 'account-delete', proof);
    userOf(caller).deleted = true;
    for (final device in activeDevicesOf(caller.userId)) {
      device.active = false;
    }
    return {'deleted': true};
  }

  FakeAccountDevice _addDevice(String userId, String authPublicKey, String publicIdentityKey) {
    final device = FakeAccountDevice(
      id: _id('device'),
      userId: userId,
      authPublicKey: authPublicKey,
      publicIdentityKey: publicIdentityKey,
    );
    return devices[device.id] = device;
  }

  // The JWT guard: a token of a device that is no longer active is refused.
  FakeAccountDevice _authenticate(String accessToken) {
    final device = devices[_deviceByAccessToken[accessToken]];
    if (device == null) {
      throw VeilApiException('Unauthorized', statusCode: 401, code: 'unauthorized');
    }
    if (!device.active) {
      throw VeilApiException('Device is not active', statusCode: 401, code: 'device_not_active');
    }
    return device;
  }

  // AuthService.verifyDeviceStepUp, without the development fallback.
  Future<void> _verifyStepUp(FakeAccountDevice caller, String purpose, Map<String, String>? proof) async {
    final challengeId = proof?['challengeId'];
    final signature = proof?['signature'];
    if (challengeId == null || signature == null) {
      throw VeilApiException('A challenge signed by this device is required',
          statusCode: 401, code: 'challenge_invalid');
    }
    final stored = _challenges.remove(challengeId);
    if (stored == null || stored.deviceId != caller.id) {
      throw VeilApiException('Challenge expired or invalid', statusCode: 401, code: 'challenge_invalid');
    }
    if (!await _signedBy(caller.authPublicKey, '$purpose:$challengeId:${stored.challenge}', signature)) {
      throw VeilApiException('Invalid device signature', statusCode: 401, code: 'invalid_device_signature');
    }
  }

  FakeTransferSession _transfer(Object? sessionId) {
    final session = transfers[sessionId];
    if (session == null) {
      throw VeilApiException('Transfer session not found', statusCode: 404, code: 'transfer_session_not_found');
    }
    return session;
  }

  bool _inactive(FakeTransferSession session) =>
      session.invalidated || session.completedAt != null || !session.expiresAt.isAfter(DateTime.now());

  Map<String, dynamic> _completion(FakeTransferSession session, String claimId) => {
        'sessionId': session.id,
        'claimId': claimId,
        'newDeviceId': session.newDeviceId,
        'revokedDeviceId': session.oldDeviceId,
        'preferredDeviceId': session.newDeviceId,
        'handle': usersByHandle.values.firstWhere((user) => user.id == session.userId).handle,
        'completedAt': session.completedAt!.toUtc().toIso8601String(),
      };

  // Full SHA-256 over both keys, in 16 space-separated groups of 4 hex
  // digits, as the API shows it on both screens.
  static String _fingerprint(String authPublicKey, String publicIdentityKey) {
    final digest = hash.sha256.convert([..._decode(authPublicKey), ...utf8.encode(publicIdentityKey)]).toString();
    return [for (var i = 0; i < digest.length; i += 4) digest.substring(i, i + 4)].join(' ');
  }

  static Future<bool> _signedBy(String publicKey, String message, Object? signature) async {
    if (signature is! String || signature.isEmpty) return false;
    try {
      return await Ed25519().verify(
        utf8.encode(message),
        signature: Signature(
          _decode(signature),
          publicKey: SimplePublicKey(_decode(publicKey), type: KeyPairType.ed25519),
        ),
      );
    } catch (_) {
      return false;
    }
  }

  static List<int> _decode(String value) =>
      base64Url.decode(value.padRight(value.length + (4 - value.length % 4) % 4, '='));
}
