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
    this.remoteOneTimePrekey,
  });

  final String conversationId;
  final String localDeviceId;
  final String localUserId;
  final String remoteUserId;
  final String remoteDeviceId;
  final String remoteIdentityPublicKey;
  final String remoteSignedPrekeyBundle;
  // One-time prekey claimed from the directory for this handshake. Optional:
  // without it the handshake still authenticates both identities, it only
  // loses the extra forward secrecy a single-use key provides.
  final OneTimePrekey? remoteOneTimePrekey;
}

/// Public half of a one-time prekey, as published to (or claimed from) the
/// key directory. `publicKey` is base64url X25519.
class OneTimePrekey {
  const OneTimePrekey({required this.keyId, required this.publicKey});

  final int keyId;
  final String publicKey;
}

/// A signed prekey ready to publish: its signed bundle and what it names.
class SignedPrekeyRotation {
  const SignedPrekeyRotation({
    required this.signedPrekeyBundle,
    required this.spkId,
    required this.createdAt,
    this.upgradedIdentityPrivateRef,
  });

  final String signedPrekeyBundle;
  final int spkId;
  final DateTime createdAt;
  // Set when the local identity ref had to change shape (v1 -> v2); the
  // caller must persist it in place of the old ref.
  final String? upgradedIdentityPrivateRef;
}

/// Optional capability: adapters that publish signed and one-time prekeys.
/// Callers check `adapter is PrekeyManager` instead of widening
/// [CryptoAdapter].
abstract class PrekeyManager {
  Future<List<OneTimePrekey>> generateOneTimePrekeys({int count = 100});

  Future<SignedPrekeyRotation> rotateSignedPrekey();

  /// The newest signed prekey as a bundle to publish, or null when the
  /// identity has none of its own (a v1 identity). Signing is
  /// deterministic, so this is byte for byte the bundle that was, or would
  /// have been, published with it. Carries the upgraded identity ref while
  /// the stored one is still v1.
  Future<SignedPrekeyRotation?> currentSignedPrekey();

  /// The signed prekey the directory last accepted from this device; null
  /// when that is not known.
  Future<int?> publishedSignedPrekeyId();

  /// Records that the directory accepted signed prekey [spkId].
  Future<void> markSignedPrekeyPublished(int spkId);

  /// Deletes the signed prekeys older than the published one once it has
  /// been published for longer than [grace]; returns how many were removed.
  /// While the published one is not known, every signed prekey is kept.
  Future<int> pruneSignedPrekeys({Duration grace = const Duration(days: 14)});
}

/// When the directory accepted a signed prekey: from then on it serves that
/// one, and older signed prekeys only have to answer handshakes still in
/// flight.
class SignedPrekeyPublication {
  const SignedPrekeyPublication({required this.spkId, required this.publishedAt});

  final int spkId;
  final DateTime publishedAt;
}

/// The identity a session initiator proved in its handshake. Keys are
/// base64url.
class RemoteIdentityClaim {
  const RemoteIdentityClaim({
    required this.conversationId,
    required this.senderDeviceId,
    required this.identityKeyEd25519,
    required this.identityKeyX25519,
  });

  final String conversationId;
  final String senderDeviceId;
  final String identityKeyEd25519;
  final String identityKeyX25519;
}

/// Decides whether an authenticated initiator identity may open a session
/// (identity pinning). Returning false stores nothing.
typedef RemoteIdentityVerifier = Future<bool> Function(RemoteIdentityClaim claim);

/// Private half of a published signed prekey, kept so PreKey frames that
/// name it can still be answered during the rotation grace period.
class StoredSignedPrekey {
  const StoredSignedPrekey({
    required this.keyId,
    required this.privateKey,
    required this.createdAt,
  });

  final int keyId;
  final List<int> privateKey;
  final DateTime createdAt;
}

/// Device-local storage for prekey private halves.
abstract class LocalPrekeyStore {
  /// Reserves [count] consecutive one-time prekey ids and returns the first.
  /// Ids are never handed out twice, so a stale directory entry can never
  /// alias a fresh key.
  Future<int> reserveOneTimePrekeyIds(int count);

  Future<void> saveOneTimePrekey(int keyId, List<int> privateKey);

  Future<List<int>?> loadOneTimePrekey(int keyId);

  Future<void> deleteOneTimePrekey(int keyId);

  Future<void> saveSignedPrekey(StoredSignedPrekey prekey);

  Future<List<StoredSignedPrekey>> loadSignedPrekeys();

  Future<SignedPrekeyPublication?> loadSignedPrekeyPublication();

  Future<void> saveSignedPrekeyPublication(SignedPrekeyPublication publication);

  Future<void> deleteSignedPrekey(int keyId);
}

class InMemoryLocalPrekeyStore implements LocalPrekeyStore {
  int _nextOneTimePrekeyId = 1;
  final Map<int, List<int>> _oneTime = {};
  final Map<int, StoredSignedPrekey> _signed = {};
  SignedPrekeyPublication? _publication;

  @override
  Future<int> reserveOneTimePrekeyIds(int count) async {
    final first = _nextOneTimePrekeyId;
    _nextOneTimePrekeyId += count;
    return first;
  }

  @override
  Future<void> saveOneTimePrekey(int keyId, List<int> privateKey) async {
    _oneTime[keyId] = List<int>.of(privateKey);
  }

  @override
  Future<List<int>?> loadOneTimePrekey(int keyId) async {
    final key = _oneTime[keyId];
    return key == null ? null : List<int>.of(key);
  }

  @override
  Future<void> deleteOneTimePrekey(int keyId) async {
    final key = _oneTime.remove(keyId);
    key?.fillRange(0, key.length, 0);
  }

  // Copies on the way in and out so callers may wipe their buffers.
  @override
  Future<void> saveSignedPrekey(StoredSignedPrekey prekey) async {
    _signed[prekey.keyId] = _copy(prekey);
  }

  @override
  Future<List<StoredSignedPrekey>> loadSignedPrekeys() async => _signed.values.map(_copy).toList();

  static StoredSignedPrekey _copy(StoredSignedPrekey prekey) => StoredSignedPrekey(
        keyId: prekey.keyId,
        privateKey: List<int>.of(prekey.privateKey),
        createdAt: prekey.createdAt,
      );

  @override
  Future<void> deleteSignedPrekey(int keyId) async {
    _signed.remove(keyId);
  }

  @override
  Future<SignedPrekeyPublication?> loadSignedPrekeyPublication() async => _publication;

  @override
  Future<void> saveSignedPrekeyPublication(SignedPrekeyPublication publication) async {
    _publication = publication;
  }
}

// Legacy receive-side bootstrap: derives the same symmetric session as the
// sender using the recipient's stored X25519 private key and the sender's
// ephemeral public key extracted from the inbound envelope's wire bytes.
// It authenticates nobody; frames decrypted on such a session are reported
// as legacyUnauthenticated.
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

enum DecryptStatus {
  ok,
  failed,
  replayed,
  sessionMissing,
  awaitingKey,
  identityRejected,
  // Decrypted from a legacy frame whose handshake never authenticated the
  // sender; the body is genuine ciphertext output but its author is unproven.
  legacyUnauthenticated,
}

class DecryptedMessage {
  const DecryptedMessage({
    required this.body,
    required this.messageKind,
    this.expiresAt,
    this.attachment,
    this.status = DecryptStatus.ok,
    this.failureReason,
  });

  // Empty unless the frame opened (ok or legacyUnauthenticated): a failure
  // carries no text, so callers branch on [status], never on the body.
  final String body;
  final MessageKind messageKind;
  // The sender-authenticated expiry from the inner payload, when present.
  final DateTime? expiresAt;
  final AttachmentReference? attachment;
  final DecryptStatus status;
  final String? failureReason;

  bool get isOk => status == DecryptStatus.ok;
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

// Output of a completed attachment encryption. The `reference` travels to
// the peer only inside the encrypted message payload (the outer envelope
// carries just its attachmentId); `ciphertext` is the opaque blob the caller
// uploads to attachment storage. Together they give the receiving device
// everything `decryptAttachment` needs.
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

  // Encrypts an attachment blob end-to-end under a one-shot content key and
  // returns the reference (to embed in the encrypted message payload) plus
  // the ciphertext blob (for attachment storage). Adapters whose references
  // carry the content key inside the ratchet payload ignore
  // `recipientBundle`; it remains for adapters that still wrap the key.
  Future<AttachmentCipher> encryptAttachment({
    required String attachmentId,
    required String storageKey,
    required String contentType,
    required List<int> plaintext,
    required KeyBundle recipientBundle,
  });

  // Reverses `encryptAttachment`. `localIdentityPrivateRef` is only needed
  // for legacy references whose content key was wrapped to the identity.
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
  // legacy envelope's wire bytes, or null if the envelope is malformed or
  // carries its own authenticated handshake (decrypt establishes the
  // session itself, so no explicit inbound bootstrap is needed).
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
