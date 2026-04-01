enum MessageKind { text, image, file, system }

const devEnvelopeVersion = 'veil-envelope-v1-dev';
const devAttachmentWrapAlgorithmHint = 'dev-wrap';

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

  factory AttachmentReference.fromApiJson(Map<String, dynamic> json) {
    final encryption = json['encryption'] as Map<String, dynamic>? ?? const {};
    return AttachmentReference(
      attachmentId: json['attachmentId'] as String,
      storageKey: json['storageKey'] as String,
      contentType: json['contentType'] as String,
      sizeBytes: json['sizeBytes'] as int,
      sha256: json['sha256'] as String,
      encryptedKey: encryption['encryptedKey'] as String,
      nonce: encryption['nonce'] as String,
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'attachmentId': attachmentId,
      'storageKey': storageKey,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'sha256': sha256,
      'encryption': {
        'encryptedKey': encryptedKey,
        'nonce': nonce,
        'algorithmHint': devAttachmentWrapAlgorithmHint,
      },
    };
  }
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

  factory CryptoEnvelope.fromApiJson(Map<String, dynamic> json) {
    final attachment = json['attachment'] as Map<String, dynamic>?;
    return CryptoEnvelope(
      version: json['version'] as String? ?? devEnvelopeVersion,
      conversationId: json['conversationId'] as String,
      senderDeviceId: json['senderDeviceId'] as String,
      recipientUserId: json['recipientUserId'] as String? ?? '',
      ciphertext: json['ciphertext'] as String,
      nonce: json['nonce'] as String,
      messageKind: MessageKind.values.byName(json['messageType'] as String),
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt'] as String),
      attachment: attachment == null ? null : AttachmentReference.fromApiJson(attachment),
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'version': version,
      'conversationId': conversationId,
      'senderDeviceId': senderDeviceId,
      'recipientUserId': recipientUserId,
      'ciphertext': ciphertext,
      'nonce': nonce,
      'messageType': messageKind.name,
      'expiresAt': expiresAt?.toIso8601String(),
      'attachment': attachment?.toApiJson(),
    };
  }
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
