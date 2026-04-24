enum MessageKind { text, image, file, system, voice, sticker, reaction, call }

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

class SessionBootstrapRequest {
  const SessionBootstrapRequest({
    required this.conversationId,
    required this.localDeviceId,
    required this.localUserId,
    required this.remoteUserId,
    required this.remoteDeviceId,
    required this.remoteIdentityPublicKey,
    required this.remoteSignedPrekeyBundle,
  });

  final String conversationId;
  final String localDeviceId;
  final String localUserId;
  final String remoteUserId;
  final String remoteDeviceId;
  final String remoteIdentityPublicKey;
  final String remoteSignedPrekeyBundle;
}

// Receive-side bootstrap: derives the same symmetric session as the sender
// using the recipient's stored X25519 private key and the sender's ephemeral
// public key extracted from the inbound envelope's wire bytes.
class InboundSessionBootstrapRequest {
  const InboundSessionBootstrapRequest({
    required this.conversationId,
    required this.localDeviceId,
    required this.localUserId,
    required this.localIdentityPrivateRef,
    required this.remoteUserId,
    required this.remoteDeviceId,
    required this.remoteEphemeralPublicKey,
  });

  final String conversationId;
  final String localDeviceId;
  final String localUserId;
  // Opaque reference (b64 of a JSON bundle in the lib adapter) — the adapter
  // knows how to parse this back into an X25519 private key.
  final String localIdentityPrivateRef;
  final String remoteUserId;
  final String remoteDeviceId;
  // Raw 32 bytes of the sender's ephemeral X25519 public key, as carried in
  // the first 32 bytes of the encrypted envelope payload.
  final List<int> remoteEphemeralPublicKey;
}

class SessionBootstrapMaterial {
  const SessionBootstrapMaterial({
    required this.sessionLocator,
    required this.sessionEnvelopeVersion,
    required this.requiresLocalPersistence,
    required this.sessionSchemaVersion,
    required this.localDeviceId,
    required this.remoteDeviceId,
    required this.remoteIdentityFingerprint,
    this.auditHint,
  });

  final String sessionLocator;
  final String sessionEnvelopeVersion;
  final bool requiresLocalPersistence;
  final int sessionSchemaVersion;
  final String localDeviceId;
  final String remoteDeviceId;
  final String remoteIdentityFingerprint;
  final String? auditHint;
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

  /// Recovers the local device's Ed25519 identity public key from the
  /// opaque [identityPrivateRef] that [generateDeviceIdentity] returned.
  /// Used by the Safety Numbers screen so we don't need to round-trip to
  /// the directory API for our own key.
  Future<String> extractIdentityPublicKeyFromPrivateRef(
    String identityPrivateRef,
  );
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

  List<KeyBundle> decodeDirectoryBundles(List<Map<String, dynamic>> json);
}

abstract class CryptoEnvelopeCodec {
  String get defaultEnvelopeVersion;

  String? get defaultAttachmentWrapAlgorithmHint;

  CryptoEnvelope decodeApiEnvelope(Map<String, dynamic> json);

  Map<String, dynamic> encodeApiEnvelope(CryptoEnvelope envelope);

  AttachmentReference? decodeAttachmentReference(Map<String, dynamic>? json);

  Map<String, dynamic>? encodeAttachmentReference(AttachmentReference? attachment);
}

// Output of a completed attachment encryption. The `reference` is what goes
// inside the `CryptoEnvelope` and travels to the peer; `ciphertext` is the
// opaque blob the caller uploads to attachment storage. Together they give
// the receiving device everything it needs to decrypt:
// - the reference's wrapped content-key lets the receiver unwrap the
//   symmetric blob key via ECDH to its identity x25519 private,
// - the ciphertext is fed back into `decryptAttachment` with that wrapped
//   key to produce plaintext bytes.
class AttachmentCipher {
  const AttachmentCipher({
    required this.reference,
    required this.ciphertext,
  });

  final AttachmentReference reference;
  final List<int> ciphertext;
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

  // Encrypts an attachment blob end-to-end: generates a one-shot content key,
  // encrypts `plaintext` with AES-256-GCM, wraps the content key for the
  // recipient via ephemeral X25519 ECDH + HKDF, and returns both the wrapped
  // reference (for the message envelope) and the ciphertext blob (for
  // attachment storage). `sizeBytes` and `sha256` on the returned reference
  // describe the ciphertext, not the plaintext — they're what the server sees.
  Future<AttachmentCipher> encryptAttachment({
    required String attachmentId,
    required String storageKey,
    required String contentType,
    required List<int> plaintext,
    required KeyBundle recipientBundle,
  });

  // Reverses `encryptAttachment`: unwraps the content key using the local
  // identity's x25519 private (stored under `localIdentityPrivateRef`),
  // then decrypts `ciphertext` with AES-256-GCM and returns plaintext bytes.
  // Implementations SHOULD verify `reference.sha256` against the ciphertext
  // before attempting decryption so storage-layer tampering aborts early
  // with a precise error rather than a generic MAC failure.
  Future<List<int>> decryptAttachment({
    required AttachmentReference reference,
    required List<int> ciphertext,
    required String localIdentityPrivateRef,
  });
}

abstract class ConversationSessionBootstrapper {
  Future<SessionBootstrapMaterial> bootstrapSession(
    SessionBootstrapRequest request,
  );

  Future<SessionBootstrapMaterial> bootstrapSessionFromInbound(
    InboundSessionBootstrapRequest request,
  );

  // Returns true if a session has already been established for this
  // conversation. Lets the app-layer decide whether to proactively kick off an
  // inbound-bootstrap on an incoming envelope. Mock/stub adapters may always
  // return true to short-circuit the bootstrap path in tests.
  bool hasSessionFor(String conversationId) => true;

  // Arms a manual DH ratchet rotation on the next outbound message for this
  // conversation. Implementations that support forward-secret session state
  // should also drop any pre-rotation skipped keys. Returns true if an
  // existing session was armed, false if there's no session yet. Stub/mock
  // adapters without session state may safely return false.
  Future<bool> forceRekeyNextSend(String conversationId) async => false;
}

abstract class InboundEnvelopeInspector {
  // Returns the 32-byte sender ephemeral public key carried in an inbound
  // envelope's wire bytes, or null if the envelope is malformed.
  List<int>? extractSenderEphemeralPublicKey(CryptoEnvelope envelope);
}

abstract class CryptoAdapter {
  String get adapterId;

  DeviceIdentityProvider get identity;

  DeviceAuthChallengeSigner get deviceAuth;

  KeyBundleCodec get keyBundles;

  CryptoEnvelopeCodec get envelopeCodec;

  MessageCryptoEngine get messaging;

  ConversationSessionBootstrapper get sessions;
}
