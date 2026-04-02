import 'dart:convert';
import 'dart:math';

import '../security/device_auth_signer.dart';
import 'crypto_engine.dart';

class MockCryptoAdapter implements CryptoAdapter {
  MockCryptoAdapter({
    Random? random,
    DeviceAuthChallengeSigner? deviceAuthSigner,
  })  : _random = random ?? Random.secure(),
        _deviceAuthSigner = deviceAuthSigner ?? const Ed25519DeviceAuthChallengeSigner() {
    identity = _MockDeviceIdentityProvider(_random);
    keyBundles = const _MockKeyBundleCodec();
    envelopeCodec = const _MockCryptoEnvelopeCodec();
    messaging = _MockMessageCryptoEngine(_random, envelopeCodec);
  }

  final Random _random;
  final DeviceAuthChallengeSigner _deviceAuthSigner;

  @override
  String get adapterId => 'mock-dev-adapter';

  @override
  late final DeviceIdentityProvider identity;

  @override
  DeviceAuthChallengeSigner get deviceAuth => _deviceAuthSigner;

  @override
  late final KeyBundleCodec keyBundles;

  @override
  late final CryptoEnvelopeCodec envelopeCodec;

  @override
  late final MessageCryptoEngine messaging;
}

CryptoAdapter createDefaultCryptoAdapter() => MockCryptoAdapter();

class _MockDeviceIdentityProvider implements DeviceIdentityProvider {
  const _MockDeviceIdentityProvider(this._random);

  final Random _random;

  @override
  Future<DeviceIdentityMaterial> generateDeviceIdentity(String deviceId) async {
    // TODO(security): Replace this dev-only identity provider with audited production crypto.
    return DeviceIdentityMaterial(
      identityPublicKey: 'mock-id-pub-$deviceId',
      identityPrivateKeyRef: 'secure-store://identity/$deviceId',
      signedPrekeyBundle: _opaqueToken(_random, 32),
    );
  }
}

class _MockKeyBundleCodec implements KeyBundleCodec {
  const _MockKeyBundleCodec();

  @override
  KeyBundle decodeDirectoryBundle(Map<String, dynamic> json) {
    return KeyBundle(
      userId: json['userId'] as String,
      deviceId: json['deviceId'] as String,
      handle: json['handle'] as String,
      identityPublicKey: json['identityPublicKey'] as String,
      signedPrekeyBundle: json['signedPrekeyBundle'] as String,
    );
  }
}

class _MockCryptoEnvelopeCodec implements CryptoEnvelopeCodec {
  const _MockCryptoEnvelopeCodec();

  @override
  String get defaultEnvelopeVersion => 'veil-envelope-v1-dev';

  @override
  String get defaultAttachmentWrapAlgorithmHint => 'dev-wrap';

  @override
  CryptoEnvelope decodeApiEnvelope(Map<String, dynamic> json) {
    return CryptoEnvelope(
      version: json['version'] as String? ?? defaultEnvelopeVersion,
      conversationId: json['conversationId'] as String,
      senderDeviceId: json['senderDeviceId'] as String,
      recipientUserId: json['recipientUserId'] as String? ?? '',
      ciphertext: json['ciphertext'] as String,
      nonce: json['nonce'] as String,
      messageKind: MessageKind.values.byName(json['messageType'] as String),
      expiresAt: json['expiresAt'] == null
          ? null
          : DateTime.parse(json['expiresAt'] as String),
      attachment: decodeAttachmentReference(json['attachment'] as Map<String, dynamic>?),
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
      'expiresAt': envelope.expiresAt?.toIso8601String(),
      'attachment': encodeAttachmentReference(envelope.attachment),
    };
  }

  @override
  AttachmentReference? decodeAttachmentReference(Map<String, dynamic>? json) {
    if (json == null) {
      return null;
    }

    final encryption = json['encryption'] as Map<String, dynamic>? ?? const {};
    return AttachmentReference(
      attachmentId: json['attachmentId'] as String,
      storageKey: json['storageKey'] as String,
      contentType: json['contentType'] as String,
      sizeBytes: json['sizeBytes'] as int,
      sha256: json['sha256'] as String,
      encryptedKey: encryption['encryptedKey'] as String,
      nonce: encryption['nonce'] as String,
      algorithmHint: encryption['algorithmHint'] as String?,
    );
  }

  @override
  Map<String, dynamic>? encodeAttachmentReference(AttachmentReference? attachment) {
    if (attachment == null) {
      return null;
    }

    return {
      'attachmentId': attachment.attachmentId,
      'storageKey': attachment.storageKey,
      'contentType': attachment.contentType,
      'sizeBytes': attachment.sizeBytes,
      'sha256': attachment.sha256,
      'encryption': {
        'encryptedKey': attachment.encryptedKey,
        'nonce': attachment.nonce,
        'algorithmHint':
            attachment.algorithmHint ?? defaultAttachmentWrapAlgorithmHint,
      },
    };
  }
}

class _MockMessageCryptoEngine implements MessageCryptoEngine {
  _MockMessageCryptoEngine(this._random, this._codec);

  final Random _random;
  final CryptoEnvelopeCodec _codec;

  static final Map<String, DecryptedMessage> _plaintextRegistry = {};

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
    final ciphertext = _opaqueToken(_random, 48);
    _plaintextRegistry[ciphertext] = DecryptedMessage(
      body: body,
      messageKind: messageKind,
      expiresAt: expiresAt,
      attachment: attachment,
    );

    return CryptoEnvelope(
      version: _codec.defaultEnvelopeVersion,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientUserId: recipientBundle.userId,
      ciphertext: ciphertext,
      nonce: 'mock-nonce-${_random.nextInt(1 << 32)}',
      messageKind: messageKind,
      expiresAt: expiresAt,
      attachment: attachment,
    );
  }

  @override
  Future<DecryptedMessage> decryptMessage(CryptoEnvelope envelope) async {
    final cached = _plaintextRegistry[envelope.ciphertext];
    if (cached != null) {
      return cached;
    }

    return DecryptedMessage(
      body: switch (envelope.messageKind) {
        MessageKind.file => 'Encrypted attachment',
        MessageKind.image => 'Encrypted image',
        MessageKind.system => 'Encrypted system envelope',
        MessageKind.text => 'Encrypted message',
      },
      messageKind: envelope.messageKind,
      expiresAt: envelope.expiresAt,
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
      encryptedKey: _opaqueToken(_random, 32),
      nonce: 'mock-attachment-${_random.nextInt(1 << 32)}',
      algorithmHint: _codec.defaultAttachmentWrapAlgorithmHint,
    );
  }
}

String _opaqueToken(Random random, int byteLength) {
  final bytes = List<int>.generate(byteLength, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
