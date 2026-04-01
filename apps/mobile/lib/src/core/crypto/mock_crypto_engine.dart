import 'dart:convert';
import 'dart:math';

import 'crypto_engine.dart';

class MockCryptoEngine implements CryptoEngine {
  MockCryptoEngine({Random? random}) : _random = random ?? Random.secure();

  final Random _random;
  static final Map<String, DecryptedMessage> _plaintextRegistry = {};

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
    final ciphertext = _opaqueToken(48);
    _plaintextRegistry[ciphertext] = DecryptedMessage(
      body: body,
      messageKind: messageKind,
      expiresAt: expiresAt,
      attachment: attachment,
    );

    return CryptoEnvelope(
      version: devEnvelopeVersion,
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
      encryptedKey: _opaqueToken(32),
      nonce: 'mock-attachment-${_random.nextInt(1 << 32)}',
    );
  }

  String _opaqueToken(int byteLength) {
    final bytes = List<int>.generate(byteLength, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
