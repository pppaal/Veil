import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';

/// MockCryptoAdapter with production ratchet semantics where tests care
/// about them: every ciphertext opens at most once, a device can never open
/// what it sealed itself, and sessions exist only after a bootstrap. The
/// plain mock is idempotent and decrypts anything, which hides exactly the
/// bugs a single-use ratchet exposes.
///
/// A device's own envelopes are recognised by their sender device: any
/// device this adapter has sealed as, plus [localDeviceId] when given, so
/// an adapter standing in for a relaunched app refuses its own history
/// before it has sealed anything.
///
/// With [opensSessionOnDecrypt] the first peer frame a device opens also
/// establishes its session, the way protocol v2 and libsignal run the
/// responder half of the handshake inside decrypt.
class StrictMockCryptoAdapter implements CryptoAdapter {
  StrictMockCryptoAdapter({String? localDeviceId, bool opensSessionOnDecrypt = false})
      : _inner = MockCryptoAdapter() {
    final strictSessions = _StrictSessions(_inner.sessions);
    sessions = strictSessions;
    messaging = _StrictMessaging(
      _inner.messaging,
      ownDeviceIds: {if (localDeviceId != null) localDeviceId},
      onOpened: opensSessionOnDecrypt ? strictSessions._established.add : null,
    );
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
  _StrictMessaging(this._inner, {required Set<String> ownDeviceIds, this.onOpened})
      : _ownDeviceIds = ownDeviceIds;

  final MessageCryptoEngine _inner;
  final void Function(String conversationId)? onOpened;
  final Set<String> _ownDeviceIds;
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
    _ownDeviceIds.add(senderDeviceId);
    return envelope;
  }

  @override
  Future<DecryptedMessage> decryptMessage(CryptoEnvelope envelope, {BeforeCommit? beforeCommit}) async {
    // What the production ratchet reports for a sender's own frame, which it
    // cannot open, and for a message key that was already used.
    if (_ownDeviceIds.contains(envelope.senderDeviceId)) {
      return DecryptedMessage(body: '', messageKind: envelope.messageKind, status: DecryptStatus.failed);
    }
    if (!_opened.add(envelope.ciphertext)) {
      return DecryptedMessage(body: '', messageKind: envelope.messageKind, status: DecryptStatus.replayed);
    }
    onOpened?.call(envelope.conversationId);
    return _inner.decryptMessage(envelope, beforeCommit: beforeCommit);
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
}
