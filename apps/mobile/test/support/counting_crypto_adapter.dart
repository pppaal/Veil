import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';

/// Number of calls that reached the wrapped adapter's crypto primitives.
class CryptoCallCounts {
  int encrypt = 0;
  int decrypt = 0;
  int bootstrap = 0;
  int inboundBootstrap = 0;
  int encryptAttachment = 0;

  void reset() {
    encrypt = 0;
    decrypt = 0;
    bootstrap = 0;
    inboundBootstrap = 0;
    encryptAttachment = 0;
  }
}

/// Delegates every call to [inner] and counts the ones that consume or
/// create key material, so tests can assert "decrypted exactly once" or
/// "never re-bootstrapped". The envelope codec is passed through untouched
/// so capability checks such as `is InboundEnvelopeInspector` still see the
/// real codec.
class CountingCryptoAdapter implements CryptoAdapter {
  CountingCryptoAdapter(this.inner) {
    messaging = _CountingMessaging(inner.messaging, counts);
    sessions = _CountingSessions(inner.sessions, counts);
  }

  final CryptoAdapter inner;
  final CryptoCallCounts counts = CryptoCallCounts();

  @override
  late final MessageCryptoEngine messaging;

  @override
  late final ConversationSessionBootstrapper sessions;

  @override
  String get adapterId => inner.adapterId;

  @override
  DeviceIdentityProvider get identity => inner.identity;

  @override
  DeviceAuthChallengeSigner get deviceAuth => inner.deviceAuth;

  @override
  KeyBundleCodec get keyBundles => inner.keyBundles;

  @override
  CryptoEnvelopeCodec get envelopeCodec => inner.envelopeCodec;
}

class _CountingMessaging implements MessageCryptoEngine {
  _CountingMessaging(this._inner, this._counts);

  final MessageCryptoEngine _inner;
  final CryptoCallCounts _counts;

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
  }) {
    _counts.encrypt += 1;
    return _inner.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientUserId: recipientUserId,
      body: body,
      messageKind: messageKind,
      recipientBundle: recipientBundle,
      expiresAt: expiresAt,
      attachment: attachment,
    );
  }

  @override
  Future<DecryptedMessage> decryptMessage(CryptoEnvelope envelope) {
    _counts.decrypt += 1;
    return _inner.decryptMessage(envelope);
  }

  @override
  Future<AttachmentCipher> encryptAttachment({
    required String attachmentId,
    required String storageKey,
    required String contentType,
    required List<int> plaintext,
    required KeyBundle recipientBundle,
  }) {
    _counts.encryptAttachment += 1;
    return _inner.encryptAttachment(
      attachmentId: attachmentId,
      storageKey: storageKey,
      contentType: contentType,
      plaintext: plaintext,
      recipientBundle: recipientBundle,
    );
  }

  @override
  Future<List<int>> decryptAttachment({
    required AttachmentReference reference,
    required List<int> ciphertext,
    required String localIdentityPrivateRef,
  }) {
    return _inner.decryptAttachment(
      reference: reference,
      ciphertext: ciphertext,
      localIdentityPrivateRef: localIdentityPrivateRef,
    );
  }
}

class _CountingSessions implements ConversationSessionBootstrapper {
  _CountingSessions(this._inner, this._counts);

  final ConversationSessionBootstrapper _inner;
  final CryptoCallCounts _counts;

  @override
  Future<SessionBootstrapMaterial> bootstrapSession(SessionBootstrapRequest request) {
    _counts.bootstrap += 1;
    return _inner.bootstrapSession(request);
  }

  @override
  Future<SessionBootstrapMaterial> bootstrapSessionFromInbound(
    InboundSessionBootstrapRequest request,
  ) {
    _counts.inboundBootstrap += 1;
    return _inner.bootstrapSessionFromInbound(request);
  }

  @override
  bool hasSessionFor(String conversationId) => _inner.hasSessionFor(conversationId);

  @override
  Future<bool> forceRekeyNextSend(String conversationId) =>
      _inner.forceRekeyNextSend(conversationId);
}
