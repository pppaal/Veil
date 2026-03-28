import 'dart:convert';
import 'dart:math';

import 'crypto_engine.dart';

const devEnvelopeVersion = 'veil-envelope-v1-dev';

class MockCryptoEngine implements CryptoEngine {
  MockCryptoEngine({Random? random}) : _random = random ?? Random.secure();

  final Random _random;

  @override
  String get adapterId => 'mock-dev-adapter';

  @override
  Future<DeviceIdentityMaterial> generateDeviceIdentity(String deviceId) async {
    // TODO(security): Replace this dev-only adapter with audited production crypto.
    return DeviceIdentityMaterial(
      identityPublicKey: 'mock-id-pub-$deviceId',
      identityPrivateKeyRef: 'secure-store://identity/$deviceId',
      authPublicKey: 'mock-auth-pub-$deviceId',
      authPrivateKeyRef: 'secure-store://auth/$deviceId',
      signedPrekeyBundle: base64Url.encode(utf8.encode('prekey:$deviceId')),
    );
  }

  @override
  Future<CryptoEnvelope> encryptMessage({
    required String conversationId,
    required String senderDeviceId,
    required String recipientUserId,
    required String body,
    required MessageKind messageKind,
    required KeyBundle recipientBundle,
    DateTime? expiresAt,
    AttachmentReference? attachment,
  }) async {
    final payload = jsonEncode({
      'body': body,
      'messageKind': messageKind.name,
      'expiresAt': expiresAt?.toIso8601String(),
    });

    return CryptoEnvelope(
      version: devEnvelopeVersion,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientUserId: recipientBundle.userId,
      ciphertext: base64Url.encode(utf8.encode(payload)),
      nonce: 'mock-nonce-${_random.nextInt(1 << 32)}',
      messageKind: messageKind,
      expiresAt: expiresAt,
      attachment: attachment,
    );
  }

  @override
  Future<DecryptedMessage> decryptMessage(CryptoEnvelope envelope) async {
    final decoded =
        jsonDecode(utf8.decode(base64Url.decode(envelope.ciphertext))) as Map<String, dynamic>;

    return DecryptedMessage(
      body: decoded['body'] as String? ?? '',
      messageKind: MessageKind.values.byName(decoded['messageKind'] as String? ?? 'text'),
      expiresAt:
          decoded['expiresAt'] == null ? null : DateTime.parse(decoded['expiresAt'] as String),
      attachment: envelope.attachment,
    );
  }

  @override
  Future<AttachmentReference> encryptAttachment({
    required String attachmentId,
    required String storageKey,
    required String contentType,
    required int sizeBytes,
    required String sha256,
    required KeyBundle recipientBundle,
  }) async {
    return AttachmentReference(
      attachmentId: attachmentId,
      storageKey: storageKey,
      contentType: contentType,
      sizeBytes: sizeBytes,
      sha256: sha256,
      encryptedKey: base64Url.encode(utf8.encode('${recipientBundle.deviceId}:content-key')),
      nonce: 'mock-attachment-${_random.nextInt(1 << 32)}',
    );
  }
}
