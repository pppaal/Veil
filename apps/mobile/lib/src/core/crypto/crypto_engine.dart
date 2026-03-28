enum MessageKind { text, image, file, system }

class DeviceIdentityMaterial {
  const DeviceIdentityMaterial({
    required this.identityPublicKey,
    required this.identityPrivateKeyRef,
    required this.authPublicKey,
    required this.authPrivateKeyRef,
    required this.signedPrekeyBundle,
  });

  final String identityPublicKey;
  final String identityPrivateKeyRef;
  final String authPublicKey;
  final String authPrivateKeyRef;
  final String signedPrekeyBundle;
}

class KeyBundle {
  const KeyBundle({
    required this.userId,
    required this.deviceId,
    required this.handle,
    required this.identityPublicKey,
    required this.signedPrekeyBundle,
  });

  final String userId;
  final String deviceId;
  final String handle;
  final String identityPublicKey;
  final String signedPrekeyBundle;
}

class AttachmentReference {
  const AttachmentReference({
    required this.attachmentId,
    required this.storageKey,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
    required this.encryptedKey,
    required this.nonce,
  });

  final String attachmentId;
  final String storageKey;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final String encryptedKey;
  final String nonce;
}

class CryptoEnvelope {
  const CryptoEnvelope({
    required this.version,
    required this.conversationId,
    required this.senderDeviceId,
    required this.recipientUserId,
    required this.ciphertext,
    required this.nonce,
    required this.messageKind,
    this.expiresAt,
    this.attachment,
  });

  final String version;
  final String conversationId;
  final String senderDeviceId;
  final String recipientUserId;
  final String ciphertext;
  final String nonce;
  final MessageKind messageKind;
  final DateTime? expiresAt;
  final AttachmentReference? attachment;
}

class DecryptedMessage {
  const DecryptedMessage({
    required this.body,
    required this.messageKind,
    this.expiresAt,
    this.attachment,
  });

  final String body;
  final MessageKind messageKind;
  final DateTime? expiresAt;
  final AttachmentReference? attachment;
}

abstract class CryptoEngine {
  String get adapterId;

  Future<DeviceIdentityMaterial> generateDeviceIdentity(String deviceId);

  Future<CryptoEnvelope> encryptMessage({
    required String conversationId,
    required String senderDeviceId,
    required String recipientUserId,
    required String body,
    required MessageKind messageKind,
    required KeyBundle recipientBundle,
    DateTime? expiresAt,
    AttachmentReference? attachment,
  });

  Future<DecryptedMessage> decryptMessage(CryptoEnvelope envelope);

  Future<AttachmentReference> encryptAttachment({
    required String attachmentId,
    required String storageKey,
    required String contentType,
    required int sizeBytes,
    required String sha256,
    required KeyBundle recipientBundle,
  });
}
