import '../crypto/crypto_engine.dart';
import '../network/veil_api_client.dart';
import '../storage/secure_storage_service.dart';

/// What this device signs, with the auth key it logs in with, so the relay
/// takes an irreversible request from the device itself and not only from
/// whoever holds its bearer token (C-PROOF). Each string names its purpose,
/// so no signature can stand in for a login proof (which signs the bare
/// challenge) or for another purpose.
abstract final class DeviceStepUpPurpose {
  static const accountDelete = 'account-delete';

  static String deviceRevoke(String deviceId) => 'device-revoke:$deviceId';

  /// The old device's approval of a transfer claim. It names the fingerprint
  /// of the claimant's keys exactly as the relay's claim and status
  /// responses give it.
  static String transferApproval({
    required String sessionId,
    required String claimId,
    required String claimantFingerprint,
  }) =>
      'transfer-approve:$sessionId:$claimId:$claimantFingerprint';
}

/// Signs step-up proofs with the device auth key in the keystore.
class DeviceStepUp {
  DeviceStepUp({
    required SecureStorageService storage,
    required DeviceAuthChallengeSigner signer,
    required VeilApiClient apiClient,
  })  : _storage = storage,
        _signer = signer,
        _apiClient = apiClient;

  final SecureStorageService _storage;
  final DeviceAuthChallengeSigner _signer;
  final VeilApiClient _apiClient;

  /// Base64url Ed25519 signature over the UTF-8 bytes of [message].
  Future<String> sign(String message) async {
    final stored = await _storage.readAuthKeyMaterial();
    if (stored == null) {
      throw VeilApiException(
        'This device has no auth key to sign with.',
        code: 'device_auth_key_missing',
      );
    }
    return _signer.signChallenge(
      challenge: message,
      keyMaterial: DeviceAuthKeyMaterial(
        publicKey: stored.publicKey,
        privateKey: stored.privateKey,
      ),
    );
  }

  /// A fresh single-use challenge for this device, signed over
  /// `<purpose>:<challengeId>:<challenge>`: the body fields
  /// (`challengeId`, `signature`) of a request that needs a step-up proof.
  Future<Map<String, String>> proof({
    required String handle,
    required String deviceId,
    required String purpose,
  }) async {
    final issued = await _apiClient.challenge({
      'handle': handle,
      'deviceId': deviceId,
    });
    final challengeId = issued['challengeId'] as String;
    final signature = await sign('$purpose:$challengeId:${issued['challenge']}');
    return {'challengeId': challengeId, 'signature': signature};
  }
}
