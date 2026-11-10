import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import '../security/device_auth_signer.dart';
import 'crypto_engine.dart';
import 'message_padding.dart';

// ---------------------------------------------------------------------------
// libsignal bridge adapter.
//
// Implements the `CryptoAdapter` boundary by delegating every key- and
// session-touching operation to a native handler (Kotlin / Swift) that wraps
// Signal's audited `libsignal`. Dart never sees private keys or session
// bytes: identity refs and session locators are opaque handles the native
// side resolves, exactly as docs/crypto-mobile-bridge-design.md requires.
//
// What stays in Dart, deliberately:
//   * JSON (de)serialization of the API envelope / key bundle shapes;
//   * the inner message payload (`body`/`kind`/`expiresAt`/`att`) and its
//     length padding — plaintext never leaves the device, and this keeps the
//     native surface to "bytes in, bytes out";
//   * AES-256-GCM of attachment *blobs* via the `cryptography` package. The
//     blob *key* is wrapped natively; libsignal has no attachment primitive
//     and shipping a 25 MB blob across the platform channel twice is worse
//     than a symmetric AEAD over a key native produced.
//   * Device-auth challenge signing (`Ed25519DeviceAuthChallengeSigner`),
//     which is transport authentication to the relay, not message crypto.
//
// Wire format: `CryptoEnvelope.ciphertext` is the serialized libsignal
// `CiphertextMessage`; `CryptoEnvelope.nonce` carries the message type tag
// (`prekey` = PreKeySignalMessage, `signal` = SignalMessage) because
// libsignal manages its own nonces. Envelope version is `libsignal-v1`,
// which the server allowlists but never interprets.
//
// Selected with `--dart-define=VEIL_CRYPTO_ADAPTER=libsignal`; the default
// build keeps `LibCryptoAdapter` until the native bridge has been verified on
// both platforms (see docs/libsignal-migration-implementation.md §10).
// ---------------------------------------------------------------------------

const String kLibsignalAdapterId = 'libsignal-v1';
const String kLibsignalEnvelopeVersion = 'libsignal-v1';
const String kLibsignalChannelName = 'io.veil.crypto/bridge';

/// Attachment key-wrap scheme. The native side performs the same
/// ephemeral-X25519 → HKDF-SHA256 → AES-256-GCM wrap as the lib adapter but
/// with libsignal's primitives, so the wire format and server allowlist entry
/// are unchanged.
const String kLibsignalAttachmentAlgoHint = 'x25519-aes256gcm';

/// Session schema stamp for bridge-backed sessions. Distinct from the lib
/// adapter's (3) so a migration can tell them apart.
const int kLibsignalSessionSchemaVersion = 100;

const String _kNoncePreKey = 'prekey';
const String _kNonceSignal = 'signal';

/// libsignal `CiphertextMessage` type constants.
const int _kCiphertextTypeWhisper = 2;
const int _kCiphertextTypePreKey = 3;

String _b64Encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List _b64Decode(String value) {
  final padded = value.padRight(value.length + ((4 - value.length % 4) % 4), '=');
  return Uint8List.fromList(base64Url.decode(padded));
}

/// Typed failure from the native bridge. `code` is one of the stable channel
/// error codes (`sessionNotFound`, `identityMismatch`, `decryptFailed`,
/// `keyWipeRequired`, `bridgeUnavailable`, `invalidArgument`,
/// `bundleInvalid`) and is safe to branch on; `message` is for logs only.
class CryptoBridgeException implements Exception {
  const CryptoBridgeException({required this.code, this.message});

  final String code;
  final String? message;

  @override
  String toString() => 'CryptoBridgeException($code${message == null ? '' : ': $message'})';
}

/// Thin invoke wrapper so every method maps platform errors the same way and
/// no raw `PlatformException` leaks into app logic.
class LibsignalBridgeChannel {
  LibsignalBridgeChannel([MethodChannel? channel])
      : _channel = channel ?? const MethodChannel(kLibsignalChannelName);

  final MethodChannel _channel;

  Future<Map<String, dynamic>> invoke(String method, Map<String, dynamic> args) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(method, args);
      return result ?? const <String, dynamic>{};
    } on MissingPluginException {
      throw const CryptoBridgeException(
        code: 'bridgeUnavailable',
        message: 'native libsignal bridge is not registered on this platform',
      );
    } on PlatformException catch (e) {
      throw CryptoBridgeException(code: e.code, message: e.message);
    }
  }
}

CryptoAdapter createLibsignalBridgeAdapter() => LibsignalBridgeAdapter();

class LibsignalBridgeAdapter implements CryptoAdapter {
  LibsignalBridgeAdapter({LibsignalBridgeChannel? channel})
      : _channel = channel ?? LibsignalBridgeChannel() {
    _identity = _BridgeIdentityProvider(_channel);
    _sessions = _BridgeSessionBootstrapper(_channel);
    _messaging = _BridgeMessageCryptoEngine(_channel, _sessions);
  }

  final LibsignalBridgeChannel _channel;
  late final _BridgeIdentityProvider _identity;
  late final _BridgeSessionBootstrapper _sessions;
  late final _BridgeMessageCryptoEngine _messaging;

  @override
  String get adapterId => kLibsignalAdapterId;

  @override
  DeviceIdentityProvider get identity => _identity;

  @override
  DeviceAuthChallengeSigner get deviceAuth => const Ed25519DeviceAuthChallengeSigner();

  @override
  KeyBundleCodec get keyBundles => const _BridgeKeyBundleCodec();

  @override
  CryptoEnvelopeCodec get envelopeCodec => const _BridgeEnvelopeCodec();

  @override
  MessageCryptoEngine get messaging => _messaging;

  @override
  ConversationSessionBootstrapper get sessions => _sessions;

  /// Clears every native session, prekey and identity (revoke / logout /
  /// device wipe). `scope` is `all` or a conversation id.
  Future<bool> wipeCryptoState({String scope = 'all'}) async {
    final remoteDeviceId = scope == 'all' ? null : _sessions.remoteDeviceFor(scope);
    final result = await _channel.invoke('wipeCryptoState', {
      'scope': scope,
      if (remoteDeviceId != null) 'remoteDeviceId': remoteDeviceId,
    });
    _sessions.forget(scope);
    return result['wiped'] == true;
  }
}

// ---- identity ---------------------------------------------------------------

class _BridgeIdentityProvider implements DeviceIdentityProvider {
  _BridgeIdentityProvider(this._channel);
  final LibsignalBridgeChannel _channel;

  @override
  Future<DeviceIdentityMaterial> generateDeviceIdentity(String deviceId) async {
    final r = await _channel.invoke('generateDeviceIdentity', {'deviceId': deviceId});
    return DeviceIdentityMaterial(
      identityPublicKey: _requireString(r, 'identityPublicKey'),
      identityPrivateKeyRef: _requireString(r, 'identityPrivateKeyRef'),
      signedPrekeyBundle: _requireString(r, 'signedPrekeyBundle'),
    );
  }

  @override
  Future<String> extractIdentityPublicKeyFromPrivateRef(String identityPrivateRef) async {
    final r = await _channel.invoke('extractIdentityPublicKey', {
      'identityPrivateKeyRef': identityPrivateRef,
    });
    return _requireString(r, 'identityPublicKey');
  }
}

// ---- codecs -----------------------------------------------------------------

class _BridgeKeyBundleCodec implements KeyBundleCodec {
  const _BridgeKeyBundleCodec();

  @override
  KeyBundle decodeDirectoryBundle(Map<String, dynamic> json) => KeyBundle(
        userId: json['userId'] as String? ?? '',
        deviceId: json['deviceId'] as String? ?? '',
        handle: json['handle'] as String? ?? '',
        identityPublicKey: json['identityPublicKey'] as String? ?? '',
        signedPrekeyBundle: json['signedPrekeyBundle'] as String? ?? '',
      );

  @override
  List<KeyBundle> decodeDirectoryBundles(List<Map<String, dynamic>> json) =>
      json.map(decodeDirectoryBundle).toList();
}

/// Deliberately NOT an `InboundEnvelopeInspector`: libsignal establishes the
/// responder side of a session while decrypting the first
/// PreKeySignalMessage, so the controller's explicit inbound-bootstrap hook
/// is a no-op for this adapter.
class _BridgeEnvelopeCodec implements CryptoEnvelopeCodec {
  const _BridgeEnvelopeCodec();

  @override
  String get defaultEnvelopeVersion => kLibsignalEnvelopeVersion;

  @override
  String? get defaultAttachmentWrapAlgorithmHint => kLibsignalAttachmentAlgoHint;

  @override
  CryptoEnvelope decodeApiEnvelope(Map<String, dynamic> json) => CryptoEnvelope(
        version: json['version'] as String? ?? kLibsignalEnvelopeVersion,
        conversationId: json['conversationId'] as String? ?? '',
        senderDeviceId: json['senderDeviceId'] as String? ?? '',
        recipientUserId: json['recipientUserId'] as String? ?? '',
        ciphertext: json['ciphertext'] as String? ?? '',
        nonce: json['nonce'] as String? ?? '',
        messageKind: _parseMessageKind(json['messageType'] as String?),
        expiresAt: _parseOptionalDateTime(json['expiresAt']),
        attachment: decodeAttachmentReference(json['attachment'] as Map<String, dynamic>?),
      );

  @override
  Map<String, dynamic> encodeApiEnvelope(CryptoEnvelope envelope) {
    final recipientUserId = envelope.recipientUserId;
    return {
      'version': envelope.version,
      'conversationId': envelope.conversationId,
      'senderDeviceId': envelope.senderDeviceId,
      if (recipientUserId.isNotEmpty) 'recipientUserId': recipientUserId,
      'ciphertext': envelope.ciphertext,
      'nonce': envelope.nonce,
      'messageType': envelope.messageKind.name,
      if (envelope.expiresAt != null) 'expiresAt': envelope.expiresAt!.toUtc().toIso8601String(),
      if (envelope.attachment != null) 'attachment': encodeAttachmentReference(envelope.attachment),
    };
  }

  @override
  AttachmentReference? decodeAttachmentReference(Map<String, dynamic>? json) {
    if (json == null) return null;
    final encryption = json['encryption'] as Map<String, dynamic>? ?? const {};
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
  Map<String, dynamic>? encodeAttachmentReference(AttachmentReference? attachment) {
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
        if (attachment.algorithmHint != null) 'algorithmHint': attachment.algorithmHint,
      },
    };
  }

  static MessageKind _parseMessageKind(String? value) {
    if (value == null) return MessageKind.text;
    return MessageKind.values.firstWhere((k) => k.name == value, orElse: () => MessageKind.text);
  }

  static DateTime? _parseOptionalDateTime(Object? value) {
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}

// ---- sessions -----------------------------------------------------------------

class _BridgeSessionBootstrapper implements ConversationSessionBootstrapper {
  _BridgeSessionBootstrapper(this._channel);
  final LibsignalBridgeChannel _channel;

  // Conversations the native side has confirmed a session for. Native owns
  // the truth; this is only the synchronous hint `hasSessionFor` needs.
  final Set<String> _known = <String>{};
  // conversationId → remote device address, so encrypt/decrypt can name the
  // libsignal `ProtocolAddress` without the caller re-supplying it.
  final Map<String, String> _remoteDeviceByConversation = <String, String>{};

  String? remoteDeviceFor(String conversationId) => _remoteDeviceByConversation[conversationId];

  void noteSession(String conversationId, {String? remoteDeviceId}) {
    _known.add(conversationId);
    if (remoteDeviceId != null && remoteDeviceId.isNotEmpty) {
      _remoteDeviceByConversation[conversationId] = remoteDeviceId;
    }
  }

  void forget(String scope) {
    if (scope == 'all') {
      _known.clear();
      _remoteDeviceByConversation.clear();
    } else {
      _known.remove(scope);
      _remoteDeviceByConversation.remove(scope);
    }
  }

  @override
  bool hasSessionFor(String conversationId) => _known.contains(conversationId);

  @override
  Future<SessionBootstrapMaterial> bootstrapSession(SessionBootstrapRequest request) async {
    final r = await _channel.invoke('bootstrapSession', {
      'conversationId': request.conversationId,
      'localDeviceId': request.localDeviceId,
      'localUserId': request.localUserId,
      'remoteUserId': request.remoteUserId,
      'remoteDeviceId': request.remoteDeviceId,
      'remoteIdentityPublicKey': request.remoteIdentityPublicKey,
      'remoteSignedPrekeyBundle': request.remoteSignedPrekeyBundle,
    });
    noteSession(request.conversationId, remoteDeviceId: request.remoteDeviceId);
    return SessionBootstrapMaterial(
      sessionLocator: 'libsignal://${request.conversationId}',
      sessionEnvelopeVersion: kLibsignalEnvelopeVersion,
      // Native persists the session record; Dart keeps only metadata.
      requiresLocalPersistence: false,
      sessionSchemaVersion: kLibsignalSessionSchemaVersion,
      localDeviceId: request.localDeviceId,
      remoteDeviceId: request.remoteDeviceId,
      remoteIdentityFingerprint: _requireString(r, 'remoteIdentityFingerprint'),
      auditHint: 'libsignal:x3dh+pqxdh+double-ratchet',
    );
  }

  /// libsignal builds the responder session implicitly when the first
  /// PreKeySignalMessage is decrypted, so there is nothing to do here except
  /// record the peer address. Kept for interface completeness.
  @override
  Future<SessionBootstrapMaterial> bootstrapSessionFromInbound(
    InboundSessionBootstrapRequest request,
  ) async {
    noteSession(request.conversationId, remoteDeviceId: request.remoteDeviceId);
    return SessionBootstrapMaterial(
      sessionLocator: 'libsignal://${request.conversationId}',
      sessionEnvelopeVersion: kLibsignalEnvelopeVersion,
      requiresLocalPersistence: false,
      sessionSchemaVersion: kLibsignalSessionSchemaVersion,
      localDeviceId: request.localDeviceId,
      remoteDeviceId: request.remoteDeviceId,
      remoteIdentityFingerprint: '',
      auditHint: 'libsignal:inbound-implicit',
    );
  }

  /// libsignal performs a DH ratchet step on every send/receive turn, and a
  /// full re-key means fetching a fresh prekey bundle — the app layer's
  /// `_ensureConversationSession` already does that after `wipeCryptoState`
  /// for a single conversation. No manual arming needed here.
  @override
  Future<bool> forceRekeyNextSend(String conversationId) async => false;
}

// ---- messaging ----------------------------------------------------------------

class _BridgeMessageCryptoEngine implements MessageCryptoEngine {
  _BridgeMessageCryptoEngine(this._channel, this._sessions);

  final LibsignalBridgeChannel _channel;
  final _BridgeSessionBootstrapper _sessions;

  static final AesGcm _aesGcm = AesGcm.with256bits();
  static final Sha256 _sha256 = Sha256();
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
    if (!_sessions.hasSessionFor(conversationId)) {
      throw StateError(
        'No session for conversation $conversationId. Bootstrap a session before sending.',
      );
    }
    final payload = json.encode({
      'body': body,
      'kind': messageKind.name,
      if (expiresAt != null) 'expiresAt': expiresAt.toUtc().toIso8601String(),
      if (attachment != null) 'att': _serializeAttachmentRef(attachment),
    });
    final r = await _channel.invoke('encryptMessage', {
      'conversationId': conversationId,
      'remoteDeviceId': _sessions.remoteDeviceFor(conversationId) ?? recipientBundle.deviceId,
      'plaintext': _b64Encode(MessagePadding.pad(utf8.encode(payload))),
    });
    final type = (r['messageType'] as num?)?.toInt();
    final nonceTag = switch (type) {
      _kCiphertextTypePreKey => _kNoncePreKey,
      _kCiphertextTypeWhisper => _kNonceSignal,
      _ => throw CryptoBridgeException(
          code: 'invalidArgument',
          message: 'native returned unknown messageType $type',
        ),
    };
    return CryptoEnvelope(
      version: kLibsignalEnvelopeVersion,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientUserId: recipientUserId,
      ciphertext: _requireString(r, 'ciphertext'),
      nonce: nonceTag,
      messageKind: messageKind,
      expiresAt: expiresAt,
      attachment: attachment,
    );
  }

  @override
  Future<DecryptedMessage> decryptMessage(CryptoEnvelope envelope) async {
    final int messageType;
    switch (envelope.nonce) {
      case _kNoncePreKey:
        messageType = _kCiphertextTypePreKey;
        break;
      case _kNonceSignal:
        messageType = _kCiphertextTypeWhisper;
        break;
      default:
        return DecryptedMessage(
          body: '[Unable to decrypt: invalid envelope]',
          messageKind: envelope.messageKind,
        );
    }
    try {
      final r = await _channel.invoke('decryptMessage', {
        'conversationId': envelope.conversationId,
        'senderDeviceId': envelope.senderDeviceId,
        'ciphertext': envelope.ciphertext,
        'messageType': messageType,
      });
      final padded = _b64Decode(_requireString(r, 'plaintext'));
      final map = json.decode(utf8.decode(MessagePadding.unpad(padded))) as Map<String, dynamic>;
      _sessions.noteSession(envelope.conversationId, remoteDeviceId: envelope.senderDeviceId);
      final kind = MessageKind.values.firstWhere(
        (k) => k.name == map['kind'],
        orElse: () => envelope.messageKind,
      );
      final expiresAtStr = map['expiresAt'] as String?;
      final att = map['att'];
      return DecryptedMessage(
        body: map['body'] as String? ?? '',
        messageKind: kind,
        expiresAt: expiresAtStr == null ? null : DateTime.tryParse(expiresAtStr)?.toLocal(),
        attachment: att is Map<String, dynamic> ? _deserializeAttachmentRef(att) : envelope.attachment,
      );
    } on CryptoBridgeException catch (e) {
      // Same user-facing placeholders as the lib adapter so the UI needs no
      // adapter-specific branching. Never a plaintext fallback.
      switch (e.code) {
        case 'sessionNotFound':
          return DecryptedMessage(
            body: '[Session not established — sync required]',
            messageKind: envelope.messageKind,
          );
        case 'identityMismatch':
          return DecryptedMessage(
            body: '[Identity changed — verify safety number]',
            messageKind: envelope.messageKind,
          );
        case 'bridgeUnavailable':
          return DecryptedMessage(
            body: '[Crypto bridge unavailable]',
            messageKind: envelope.messageKind,
          );
        default:
          return DecryptedMessage(body: '[Decryption failed]', messageKind: envelope.messageKind);
      }
    } catch (_) {
      return DecryptedMessage(body: '[Decryption failed]', messageKind: envelope.messageKind);
    }
  }

  @override
  Future<AttachmentCipher> encryptAttachment({
    required String attachmentId,
    required String storageKey,
    required String contentType,
    required List<int> plaintext,
    required KeyBundle recipientBundle,
  }) async {
    final contentKey = List<int>.generate(32, (_) => _random.nextInt(256));
    final contentNonce = List<int>.generate(12, (_) => _random.nextInt(256));

    // Native verifies the bundle signature against the recipient identity
    // and wraps the content key (ephemeral X25519 → HKDF → AES-256-GCM).
    final wrapped = await _channel.invoke('encryptAttachmentKey', {
      'recipientIdentityPublicKey': recipientBundle.identityPublicKey,
      'recipientSignedPrekeyBundle': recipientBundle.signedPrekeyBundle,
      'attachmentKey': _b64Encode(contentKey),
    });
    final wrappedKey = _requireString(wrapped, 'wrappedKey');
    final wrapNonce = _requireString(wrapped, 'wrapNonce');

    final box = await _aesGcm.encrypt(
      plaintext,
      secretKey: SecretKey(contentKey),
      nonce: contentNonce,
    );
    contentKey.fillRange(0, contentKey.length, 0);
    final blob = Uint8List(box.cipherText.length + box.mac.bytes.length)
      ..setRange(0, box.cipherText.length, box.cipherText)
      ..setRange(box.cipherText.length, box.cipherText.length + box.mac.bytes.length, box.mac.bytes);
    final hash = await _sha256.hash(blob);

    return AttachmentCipher(
      reference: AttachmentReference(
        attachmentId: attachmentId,
        storageKey: storageKey,
        contentType: contentType,
        sizeBytes: blob.length,
        sha256: _b64Encode(hash.bytes),
        encryptedKey: wrappedKey,
        nonce: '${_b64Encode(contentNonce)}.$wrapNonce',
        algorithmHint: kLibsignalAttachmentAlgoHint,
      ),
      ciphertext: blob,
    );
  }

  @override
  Future<List<int>> decryptAttachment({
    required AttachmentReference reference,
    required List<int> ciphertext,
    required String localIdentityPrivateRef,
  }) async {
    final computed = await _sha256.hash(ciphertext);
    if (_b64Encode(computed.bytes) != reference.sha256) {
      throw StateError(
        'Attachment ciphertext hash does not match reference.sha256 — '
        'blob has been modified in transit or storage.',
      );
    }
    final parts = reference.nonce.split('.');
    if (parts.length != 2) {
      throw StateError('Attachment reference nonce must be <contentNonce>.<wrapNonce>.');
    }
    final contentNonce = _b64Decode(parts[0]);
    if (contentNonce.length != 12) {
      throw StateError('Attachment content nonce must be exactly 12 bytes.');
    }
    final unwrapped = await _channel.invoke('decryptAttachmentKey', {
      'identityPrivateKeyRef': localIdentityPrivateRef,
      'wrappedKey': reference.encryptedKey,
      'wrapNonce': parts[1],
    });
    final contentKey = _b64Decode(_requireString(unwrapped, 'attachmentKey'));
    if (contentKey.length != 32) {
      throw const CryptoBridgeException(code: 'decryptFailed', message: 'bad attachment key length');
    }
    if (ciphertext.length < 16) {
      throw StateError('Attachment ciphertext too short.');
    }
    final plain = await _aesGcm.decrypt(
      SecretBox(
        ciphertext.sublist(0, ciphertext.length - 16),
        nonce: contentNonce,
        mac: Mac(ciphertext.sublist(ciphertext.length - 16)),
      ),
      secretKey: SecretKey(contentKey),
    );
    contentKey.fillRange(0, contentKey.length, 0);
    return plain;
  }

  static Map<String, dynamic> _serializeAttachmentRef(AttachmentReference a) => {
        'attachmentId': a.attachmentId,
        'storageKey': a.storageKey,
        'contentType': a.contentType,
        'sizeBytes': a.sizeBytes,
        'sha256': a.sha256,
        'encryptedKey': a.encryptedKey,
        'nonce': a.nonce,
        if (a.algorithmHint != null) 'algorithmHint': a.algorithmHint,
      };

  static AttachmentReference _deserializeAttachmentRef(Map<String, dynamic> m) =>
      AttachmentReference(
        attachmentId: m['attachmentId'] as String? ?? '',
        storageKey: m['storageKey'] as String? ?? '',
        contentType: m['contentType'] as String? ?? 'application/octet-stream',
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        sha256: m['sha256'] as String? ?? '',
        encryptedKey: m['encryptedKey'] as String? ?? '',
        nonce: m['nonce'] as String? ?? '',
        algorithmHint: m['algorithmHint'] as String?,
      );
}

String _requireString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is String && value.isNotEmpty) return value;
  throw CryptoBridgeException(
    code: 'invalidArgument',
    message: 'native response missing "$key"',
  );
}
