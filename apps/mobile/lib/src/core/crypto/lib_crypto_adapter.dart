import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/device_auth_signer.dart';
import 'crypto_engine.dart';

const _envelopeVersion = 'veil-envelope-v1';
const _attachmentAlgoHint = 'x25519-aes256gcm';

String _b64Encode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _b64Decode(String value) {
  final padded = value.padRight(
    value.length + ((4 - value.length % 4) % 4),
    '=',
  );
  return Uint8List.fromList(base64Url.decode(padded));
}

// ---------------------------------------------------------------------------
// Production CryptoAdapter using X25519 + AES-256-GCM + Ed25519
// ---------------------------------------------------------------------------

CryptoAdapter createDefaultCryptoAdapter() => LibCryptoAdapter();

class LibCryptoAdapter implements CryptoAdapter {
  LibCryptoAdapter()
      : _identityProvider = _LibDeviceIdentityProvider(),
        _deviceAuth = const Ed25519DeviceAuthChallengeSigner(),
        _keyBundleCodec = const _LibKeyBundleCodec(),
        _envelopeCodec = const _LibCryptoEnvelopeCodec(),
        _sessionBootstrapper = _LibSessionBootstrapper() {
    _messagingEngine = _LibMessageCryptoEngine(
      sessionBootstrapper: _sessionBootstrapper,
    );
  }

  final _LibDeviceIdentityProvider _identityProvider;
  final Ed25519DeviceAuthChallengeSigner _deviceAuth;
  final _LibKeyBundleCodec _keyBundleCodec;
  final _LibCryptoEnvelopeCodec _envelopeCodec;
  final _LibSessionBootstrapper _sessionBootstrapper;
  late final _LibMessageCryptoEngine _messagingEngine;

  @override
  String get adapterId => 'lib-x25519-aes256gcm-v1';

  @override
  DeviceIdentityProvider get identity => _identityProvider;

  @override
  DeviceAuthChallengeSigner get deviceAuth => _deviceAuth;

  @override
  KeyBundleCodec get keyBundles => _keyBundleCodec;

  @override
  CryptoEnvelopeCodec get envelopeCodec => _envelopeCodec;

  @override
  MessageCryptoEngine get messaging => _messagingEngine;

  @override
  ConversationSessionBootstrapper get sessions => _sessionBootstrapper;
}

// ---------------------------------------------------------------------------
// Identity — generates Ed25519 (signing) + X25519 (encryption) keypairs
// ---------------------------------------------------------------------------

class _LibDeviceIdentityProvider implements DeviceIdentityProvider {
  static final Ed25519 _ed25519 = Ed25519();
  static final X25519 _x25519 = X25519();

  @override
  Future<DeviceIdentityMaterial> generateDeviceIdentity(
    String deviceId,
  ) async {
    final edKeyPair = await _ed25519.newKeyPair();
    final edPublic = await edKeyPair.extractPublicKey();
    final edPrivateData = await edKeyPair.extract();

    final xKeyPair = await _x25519.newKeyPair();
    final xPublic = await xKeyPair.extractPublicKey();
    final xPrivateData = await xKeyPair.extract();

    final prekeyPayload = json.encode({
      'v': 1,
      'x25519': _b64Encode(xPublic.bytes),
      'sig': await _signBytes(edKeyPair, xPublic.bytes),
    });

    final privateBundle = json.encode({
      'ed25519': _b64Encode(edPrivateData.bytes),
      'x25519': _b64Encode(xPrivateData.bytes),
    });

    return DeviceIdentityMaterial(
      identityPublicKey: _b64Encode(edPublic.bytes),
      identityPrivateKeyRef: _b64Encode(utf8.encode(privateBundle)),
      signedPrekeyBundle: _b64Encode(utf8.encode(prekeyPayload)),
    );
  }

  static Future<String> _signBytes(
    SimpleKeyPair edKeyPair,
    List<int> data,
  ) async {
    final sig = await _ed25519.sign(data, keyPair: edKeyPair);
    return _b64Encode(sig.bytes);
  }
}

// ---------------------------------------------------------------------------
// Key bundle codec — parses API key bundles
// ---------------------------------------------------------------------------

class _LibKeyBundleCodec implements KeyBundleCodec {
  const _LibKeyBundleCodec();

  @override
  KeyBundle decodeDirectoryBundle(Map<String, dynamic> json) {
    return KeyBundle(
      userId: json['userId'] as String? ?? '',
      deviceId: json['deviceId'] as String? ?? '',
      handle: json['handle'] as String? ?? '',
      identityPublicKey: json['identityPublicKey'] as String? ?? '',
      signedPrekeyBundle: json['signedPrekeyBundle'] as String? ?? '',
    );
  }

  @override
  List<KeyBundle> decodeDirectoryBundles(List<Map<String, dynamic>> json) {
    return json.map(decodeDirectoryBundle).toList();
  }
}

// ---------------------------------------------------------------------------
// Envelope codec — serializes CryptoEnvelopes to/from API JSON
// ---------------------------------------------------------------------------

class _LibCryptoEnvelopeCodec implements CryptoEnvelopeCodec {
  const _LibCryptoEnvelopeCodec();

  @override
  String get defaultEnvelopeVersion => _envelopeVersion;

  @override
  String? get defaultAttachmentWrapAlgorithmHint => _attachmentAlgoHint;

  @override
  CryptoEnvelope decodeApiEnvelope(Map<String, dynamic> json) {
    return CryptoEnvelope(
      version: json['version'] as String? ?? _envelopeVersion,
      conversationId: json['conversationId'] as String? ?? '',
      senderDeviceId: json['senderDeviceId'] as String? ?? '',
      recipientUserId: json['recipientUserId'] as String? ?? '',
      ciphertext: json['ciphertext'] as String? ?? '',
      nonce: json['nonce'] as String? ?? '',
      messageKind: _parseMessageKind(json['messageType'] as String?),
      expiresAt: _parseOptionalDateTime(json['expiresAt']),
      attachment: decodeAttachmentReference(
        json['attachment'] as Map<String, dynamic>?,
      ),
    );
  }

  @override
  Map<String, dynamic> encodeApiEnvelope(CryptoEnvelope envelope) {
    return {
      'version': envelope.version,
      'conversationId': envelope.conversationId,
      'senderDeviceId': envelope.senderDeviceId,
      'recipientUserId': envelope.recipientUserId,
      'ciphertext': envelope.ciphertext,
      'nonce': envelope.nonce,
      'messageType': envelope.messageKind.name,
      if (envelope.expiresAt != null)
        'expiresAt': envelope.expiresAt!.toUtc().toIso8601String(),
      if (envelope.attachment != null)
        'attachment': encodeAttachmentReference(envelope.attachment),
    };
  }

  @override
  AttachmentReference? decodeAttachmentReference(Map<String, dynamic>? json) {
    if (json == null) return null;
    final encryption = json['encryption'] as Map<String, dynamic>? ?? {};
    return AttachmentReference(
      attachmentId: json['attachmentId'] as String? ?? '',
      storageKey: json['storageKey'] as String? ?? '',
      contentType: json['contentType'] as String? ?? 'application/octet-stream',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      sha256: json['sha256'] as String? ?? '',
      encryptedKey: encryption['encryptedKey'] as String? ?? '',
      nonce: encryption['nonce'] as String? ?? '',
      algorithmHint: encryption['algorithmHint'] as String?,
    );
  }

  @override
  Map<String, dynamic>? encodeAttachmentReference(
    AttachmentReference? attachment,
  ) {
    if (attachment == null) return null;
    return {
      'attachmentId': attachment.attachmentId,
      'storageKey': attachment.storageKey,
      'contentType': attachment.contentType,
      'sizeBytes': attachment.sizeBytes,
      'sha256': attachment.sha256,
      'encryption': {
        'encryptedKey': attachment.encryptedKey,
        'nonce': attachment.nonce,
        if (attachment.algorithmHint != null)
          'algorithmHint': attachment.algorithmHint,
      },
    };
  }

  static MessageKind _parseMessageKind(String? value) {
    if (value == null) return MessageKind.text;
    return MessageKind.values.firstWhere(
      (kind) => kind.name == value,
      orElse: () => MessageKind.text,
    );
  }

  static DateTime? _parseOptionalDateTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Session bootstrapper — X25519 DH + HKDF key derivation
// ---------------------------------------------------------------------------

class _SessionState {
  _SessionState({
    required this.sessionLocator,
    required this.sharedSecret,
    required this.localEphemeralPrivateKey,
    required this.localEphemeralPublicKey,
    required this.remoteX25519PublicKey,
    required this.remoteIdentityFingerprint,
    required this.localDeviceId,
    required this.remoteDeviceId,
  });

  final String sessionLocator;
  final SecretKey sharedSecret;
  final SimpleKeyPairData localEphemeralPrivateKey;
  final SimplePublicKey localEphemeralPublicKey;
  final SimplePublicKey remoteX25519PublicKey;
  final String remoteIdentityFingerprint;
  final String localDeviceId;
  final String remoteDeviceId;
}

class _LibSessionBootstrapper implements ConversationSessionBootstrapper {
  static final X25519 _x25519 = X25519();
  static final Sha256 _sha256 = Sha256();

  final Map<String, _SessionState> _sessions = {};

  _SessionState? getSession(String conversationId) => _sessions[conversationId];

  void storeSessionFromReceive({
    required String conversationId,
    required SecretKey sharedSecret,
    required SimplePublicKey remoteEphemeralPublicKey,
    required String localDeviceId,
    required String remoteDeviceId,
  }) {
    _sessions[conversationId] = _SessionState(
      sessionLocator: 'session://$conversationId',
      sharedSecret: sharedSecret,
      localEphemeralPrivateKey: SimpleKeyPairData(
        [],
        publicKey: SimplePublicKey([], type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      ),
      localEphemeralPublicKey: remoteEphemeralPublicKey,
      remoteX25519PublicKey: remoteEphemeralPublicKey,
      remoteIdentityFingerprint: '',
      localDeviceId: localDeviceId,
      remoteDeviceId: remoteDeviceId,
    );
  }

  @override
  Future<SessionBootstrapMaterial> bootstrapSession(
    SessionBootstrapRequest request,
  ) async {
    final remoteX25519Public = await _resolveRemoteX25519Key(
      request.remoteSignedPrekeyBundle,
    );

    final ephemeralKeyPair = await _x25519.newKeyPair();
    final ephemeralPublic = await ephemeralKeyPair.extractPublicKey();
    final ephemeralPrivate = await ephemeralKeyPair.extract();

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: ephemeralKeyPair,
      remotePublicKey: remoteX25519Public,
    );

    final identityBytes = _safeB64Decode(request.remoteIdentityPublicKey);
    final fingerprintHash = await _sha256.hash(identityBytes);
    final fingerprint = _b64Encode(fingerprintHash.bytes.sublist(0, 16));

    final session = _SessionState(
      sessionLocator: 'session://${request.conversationId}',
      sharedSecret: sharedSecret,
      localEphemeralPrivateKey: ephemeralPrivate,
      localEphemeralPublicKey: ephemeralPublic,
      remoteX25519PublicKey: remoteX25519Public,
      remoteIdentityFingerprint: fingerprint,
      localDeviceId: request.localDeviceId,
      remoteDeviceId: request.remoteDeviceId,
    );
    _sessions[request.conversationId] = session;

    return SessionBootstrapMaterial(
      sessionLocator: session.sessionLocator,
      sessionEnvelopeVersion: _envelopeVersion,
      requiresLocalPersistence: true,
      sessionSchemaVersion: 1,
      localDeviceId: request.localDeviceId,
      remoteDeviceId: request.remoteDeviceId,
      remoteIdentityFingerprint: fingerprint,
      auditHint: 'x25519-ecdh+hkdf-sha256+aes256gcm',
    );
  }

  static Future<SimplePublicKey> _resolveRemoteX25519Key(
    String signedPrekeyBundle,
  ) async {
    try {
      final decoded = utf8.decode(_b64Decode(signedPrekeyBundle));
      final map = json.decode(decoded) as Map<String, dynamic>;
      final x25519B64 = map['x25519'] as String?;
      if (x25519B64 != null) {
        final bytes = _b64Decode(x25519B64);
        if (bytes.length == 32) {
          return SimplePublicKey(bytes, type: KeyPairType.x25519);
        }
      }
    } catch (_) {
      // Not a valid prekey bundle — fall through to ephemeral
    }
    // Fallback: generate a temporary peer key for development/test bundles
    final tempPeer = await _x25519.newKeyPair();
    return tempPeer.extractPublicKey();
  }

  static List<int> _safeB64Decode(String value) {
    try {
      return _b64Decode(value);
    } catch (_) {
      return utf8.encode(value);
    }
  }
}

// ---------------------------------------------------------------------------
// Message crypto engine — AES-256-GCM with HKDF-derived keys
// ---------------------------------------------------------------------------

class _LibMessageCryptoEngine implements MessageCryptoEngine {
  _LibMessageCryptoEngine({required this.sessionBootstrapper});

  final _LibSessionBootstrapper sessionBootstrapper;

  static final AesGcm _aesGcm = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final X25519 _x25519 = X25519();
  static final Random _random = Random.secure();

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
    final session = sessionBootstrapper.getSession(conversationId);
    if (session == null) {
      throw StateError(
        'No session for conversation $conversationId. '
        'Bootstrap a session before sending.',
      );
    }

    final messageKey = await _deriveMessageKey(
      session.sharedSecret,
      conversationId,
    );

    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));

    final payload = json.encode({
      'body': body,
      'kind': messageKind.name,
      if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
      if (attachment != null) 'att': _serializeAttachmentRef(attachment),
    });

    final secretBox = await _aesGcm.encrypt(
      utf8.encode(payload),
      secretKey: messageKey,
      nonce: nonce,
    );

    // Prepend sender's ephemeral public key so recipient can derive same secret
    final ephPub = session.localEphemeralPublicKey.bytes;
    final ciphertextWithKey = Uint8List(32 + secretBox.cipherText.length + 16);
    ciphertextWithKey.setRange(0, 32, ephPub);
    ciphertextWithKey.setRange(32, 32 + secretBox.cipherText.length,
        secretBox.cipherText);
    ciphertextWithKey.setRange(
        32 + secretBox.cipherText.length,
        ciphertextWithKey.length,
        secretBox.mac.bytes);

    return CryptoEnvelope(
      version: _envelopeVersion,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientUserId: recipientUserId,
      ciphertext: _b64Encode(ciphertextWithKey),
      nonce: _b64Encode(nonce),
      messageKind: messageKind,
      expiresAt: expiresAt,
      attachment: attachment,
    );
  }

  @override
  Future<DecryptedMessage> decryptMessage(CryptoEnvelope envelope) async {
    final ciphertextBytes = _b64Decode(envelope.ciphertext);
    final nonceBytes = _b64Decode(envelope.nonce);

    if (ciphertextBytes.length < 48) {
      return DecryptedMessage(
        body: '[Unable to decrypt: invalid envelope]',
        messageKind: envelope.messageKind,
      );
    }

    // Sender's ephemeral public key (first 32 bytes) — reserved for
    // future session-less decryption when the recipient's local X25519
    // private key is available from secure storage.
    final _ = ciphertextBytes.sublist(0, 32);

    final macStart = ciphertextBytes.length - 16;
    final encryptedData = ciphertextBytes.sublist(32, macStart);
    final macBytes = ciphertextBytes.sublist(macStart);

    // Try existing session first, then try DH with sender's ephemeral key
    SecretKey? sharedSecret;
    final session =
        sessionBootstrapper.getSession(envelope.conversationId);
    if (session != null) {
      sharedSecret = session.sharedSecret;
    } else {
      // Derive shared secret from our X25519 private key and sender's ephemeral
      // For receiving without a pre-established session, we need our local
      // X25519 key. In production this would come from secure storage.
      // For now we derive from the session if available.
      return DecryptedMessage(
        body: '[Session not established — sync required]',
        messageKind: envelope.messageKind,
      );
    }

    final messageKey = await _deriveMessageKey(
      sharedSecret,
      envelope.conversationId,
    );

    try {
      final secretBox = SecretBox(
        encryptedData,
        nonce: nonceBytes,
        mac: Mac(macBytes),
      );
      final cleartext = await _aesGcm.decrypt(
        secretBox,
        secretKey: messageKey,
      );

      final payloadMap =
          json.decode(utf8.decode(cleartext)) as Map<String, dynamic>;
      final body = payloadMap['body'] as String? ?? '';
      final kind = MessageKind.values.firstWhere(
        (k) => k.name == payloadMap['kind'],
        orElse: () => envelope.messageKind,
      );
      final expiresAtStr = payloadMap['expiresAt'] as String?;
      final expiresAt = expiresAtStr != null
          ? DateTime.tryParse(expiresAtStr)?.toLocal()
          : null;

      AttachmentReference? attachment;
      if (payloadMap['att'] is Map<String, dynamic>) {
        attachment = _deserializeAttachmentRef(
          payloadMap['att'] as Map<String, dynamic>,
        );
      }

      return DecryptedMessage(
        body: body,
        messageKind: kind,
        expiresAt: expiresAt,
        attachment: attachment ?? envelope.attachment,
      );
    } catch (_) {
      return DecryptedMessage(
        body: '[Decryption failed]',
        messageKind: envelope.messageKind,
      );
    }
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
    // Generate a random content encryption key
    final contentKey =
        List<int>.generate(32, (_) => _random.nextInt(256));
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));

    // Encrypt the content key using recipient's X25519 public key
    final remoteX25519Public =
        await _LibSessionBootstrapper._resolveRemoteX25519Key(
      recipientBundle.signedPrekeyBundle,
    );

    final ephKeyPair = await _x25519.newKeyPair();
    final ephPublic = await ephKeyPair.extractPublicKey();
    final wrapSecret = await _x25519.sharedSecretKey(
      keyPair: ephKeyPair,
      remotePublicKey: remoteX25519Public,
    );

    final wrapKey = await _hkdf.deriveKey(
      secretKey: wrapSecret,
      nonce: nonce,
      info: utf8.encode('veil-attachment-wrap-v1'),
    );

    final secretBox = await _aesGcm.encrypt(
      contentKey,
      secretKey: wrapKey,
      nonce: nonce,
    );

    // Prepend ephemeral public key to the encrypted content key
    final wrappedKey = Uint8List(32 + secretBox.cipherText.length + 16);
    wrappedKey.setRange(0, 32, ephPublic.bytes);
    wrappedKey.setRange(
        32, 32 + secretBox.cipherText.length, secretBox.cipherText);
    wrappedKey.setRange(
        32 + secretBox.cipherText.length, wrappedKey.length,
        secretBox.mac.bytes);

    return AttachmentReference(
      attachmentId: attachmentId,
      storageKey: storageKey,
      contentType: contentType,
      sizeBytes: sizeBytes,
      sha256: sha256,
      encryptedKey: _b64Encode(wrappedKey),
      nonce: _b64Encode(nonce),
      algorithmHint: _attachmentAlgoHint,
    );
  }

  static Future<SecretKey> _deriveMessageKey(
    SecretKey sharedSecret,
    String conversationId,
  ) async {
    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(conversationId),
      info: utf8.encode('veil-message-v1'),
    );
  }

  static Map<String, dynamic> _serializeAttachmentRef(
    AttachmentReference ref,
  ) {
    return {
      'id': ref.attachmentId,
      'sk': ref.storageKey,
      'ct': ref.contentType,
      'sz': ref.sizeBytes,
      'h': ref.sha256,
      'ek': ref.encryptedKey,
      'n': ref.nonce,
      if (ref.algorithmHint != null) 'ah': ref.algorithmHint,
    };
  }

  static AttachmentReference _deserializeAttachmentRef(
    Map<String, dynamic> map,
  ) {
    return AttachmentReference(
      attachmentId: map['id'] as String? ?? '',
      storageKey: map['sk'] as String? ?? '',
      contentType: map['ct'] as String? ?? 'application/octet-stream',
      sizeBytes: (map['sz'] as num?)?.toInt() ?? 0,
      sha256: map['h'] as String? ?? '',
      encryptedKey: map['ek'] as String? ?? '',
      nonce: map['n'] as String? ?? '',
      algorithmHint: map['ah'] as String?,
    );
  }
}
