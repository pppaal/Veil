enum MessageKind { text, image, file, system }

class DeviceIdentityMaterial {
  const DeviceIdentityMaterial({
    required this.identityPublicKey,
    required this.identityPrivateKeyRef,
    required this.signedPrekeyBundle,
  });

  final String identityPublicKey;
  final String identityPrivateKeyRef;
  final String signedPrekeyBundle;
}

class DeviceAuthKeyMaterial {
  const DeviceAuthKeyMaterial({
    required this.publicKey,
    required this.privateKey,
  });

  final String publicKey;
  final String privateKey;
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
    this.algorithmHint,
  });

  final String attachmentId;
  final String storageKey;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final String encryptedKey;
  final String nonce;
  final String? algorithmHint;

  AttachmentReference copyWith({
    String? attachmentId,
    String? storageKey,
    String? contentType,
    int? sizeBytes,
    String? sha256,
    String? encryptedKey,
    String? nonce,
    Object? algorithmHint = _unset,
  }) {
    return AttachmentReference(
      attachmentId: attachmentId ?? this.attachmentId,
      storageKey: storageKey ?? this.storageKey,
      contentType: contentType ?? this.contentType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      encryptedKey: encryptedKey ?? this.encryptedKey,
      nonce: nonce ?? this.nonce,
      algorithmHint:
          identical(algorithmHint, _unset) ? this.algorithmHint : algorithmHint as String?,
    );
  }

  static const _unset = Object();
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

abstract class DeviceIdentityProvider {
  Future<DeviceIdentityMaterial> generateDeviceIdentity(String deviceId);
}

abstract class DeviceAuthChallengeSigner {
  Future<DeviceAuthKeyMaterial> generateAuthKeyMaterial();

  Future<String> signChallenge({
    required String challenge,
    required DeviceAuthKeyMaterial keyMaterial,
  });
}

abstract class KeyBundleCodec {
  KeyBundle decodeDirectoryBundle(Map<String, dynamic> json);
}

abstract class CryptoEnvelopeCodec {
  String get defaultEnvelopeVersion;

  String? get defaultAttachmentWrapAlgorithmHint;

  CryptoEnvelope decodeApiEnvelope(Map<String, dynamic> json);

  Map<String, dynamic> encodeApiEnvelope(CryptoEnvelope envelope);

  AttachmentReference? decodeAttachmentReference(Map<String, dynamic>? json);

  Map<String, dynamic>? encodeAttachmentReference(AttachmentReference? attachment);
}

abstract class MessageCryptoEngine {
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

abstract class CryptoAdapter {
  String get adapterId;

  DeviceIdentityProvider get identity;

  DeviceAuthChallengeSigner get deviceAuth;

  KeyBundleCodec get keyBundles;

  CryptoEnvelopeCodec get envelopeCodec;

  MessageCryptoEngine get messaging;
}
