import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';

/// Body the production ratchet returns when a message key was already used.
const strictReplayPlaceholder = '[Replayed or out-of-window message]';

/// Body the production ratchet returns for a frame it cannot open, which is
/// what a sender gets for its own envelopes.
const strictOwnEnvelopePlaceholder = '[Decryption failed]';

/// MockCryptoAdapter with production ratchet semantics where tests care
/// about them: every ciphertext opens at most once, a device can never open
/// what it sealed itself, and sessions exist only after a bootstrap. The
/// plain mock is idempotent and decrypts anything, which hides exactly the
/// bugs a single-use ratchet exposes.
class StrictMockCryptoAdapter implements CryptoAdapter {
  StrictMockCryptoAdapter() : _inner = MockCryptoAdapter() {
    messaging = _StrictMessaging(_inner.messaging);
    sessions = _StrictSessions(_inner.sessions);
  }

  final MockCryptoAdapter _inner;

  @override
  late final MessageCryptoEngine messaging;

  @override
  late final ConversationSessionBootstrapper sessions;

  @override
  String get adapterId => 'strict-${_inner.adapterId}';

  @override
  DeviceIdentityProvider get identity => _inner.identity;

  @override
  DeviceAuthChallengeSigner get deviceAuth => _inner.deviceAuth;

  @override
  KeyBundleCodec get keyBundles => _inner.keyBundles;

  @override
  CryptoEnvelopeCodec get envelopeCodec => _inner.envelopeCodec;
}

class _StrictMessaging implements MessageCryptoEngine {
  _StrictMessaging(this._inner);

  final MessageCryptoEngine _inner;
  final Set<String> _sealedHere = {};
  final Set<String> _opened = {};

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
    final envelope = await _inner.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientUserId: recipientUserId,
      body: body,
      messageKind: messageKind,
      recipientBundle: recipientBundle,
      expiresAt: expiresAt,
      attachment: attachment,
    );
    _sealedHere.add(envelope.ciphertext);
    return envelope;
  }

  @override
  Future<DecryptedMessage> decryptMessage(CryptoEnvelope envelope) async {
    if (_sealedHere.contains(envelope.ciphertext)) {
      return DecryptedMessage(
        body: strictOwnEnvelopePlaceholder,
        messageKind: envelope.messageKind,
      );
    }
    if (!_opened.add(envelope.ciphertext)) {
      return DecryptedMessage(
        body: strictReplayPlaceholder,
        messageKind: envelope.messageKind,
      );
    }
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

class _StrictSessions implements ConversationSessionBootstrapper {
  _StrictSessions(this._inner);

  final ConversationSessionBootstrapper _inner;
  final Set<String> _established = {};

  @override
  Future<SessionBootstrapMaterial> bootstrapSession(SessionBootstrapRequest request) async {
    final material = await _inner.bootstrapSession(request);
    _established.add(request.conversationId);
    return material;
  }

  @override
  Future<SessionBootstrapMaterial> bootstrapSessionFromInbound(
    InboundSessionBootstrapRequest request,
  ) async {
    final material = await _inner.bootstrapSessionFromInbound(request);
    _established.add(request.conversationId);
    return material;
  }

  @override
  bool hasSessionFor(String conversationId) => _established.contains(conversationId);

  @override
  Future<bool> forceRekeyNextSend(String conversationId) async =>
      _established.contains(conversationId);
}
