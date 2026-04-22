import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/device_auth_signer.dart';
import 'crypto_engine.dart';

const _envelopeVersion = 'veil-envelope-v1';
const _attachmentAlgoHint = 'x25519-aes256gcm';
const int _currentSessionSchemaVersion = 2;

String _b64Encode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _b64Decode(String value) {
  final padded = value.padRight(
    value.length + ((4 - value.length % 4) % 4),
    '=',
  );
  return Uint8List.fromList(base64Url.decode(padded));
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// Callback that lets the host app wire this engine to a persistent store so
// Double Ratchet state survives app restart. Optional; with no persister
// wired, the adapter works in-memory only (same behavior as v1).
typedef SessionPersister =
    Future<void> Function(String conversationId, Map<String, dynamic> snapshot);

// ---------------------------------------------------------------------------
// Production CryptoAdapter: X25519 identity + AES-256-GCM, now with a
// Double Ratchet (DH ratchet + symmetric hash ratchet) giving both forward
// secrecy and post-compromise security.
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
  String get adapterId => 'lib-x25519-aes256gcm-v2';

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

  // Wires a persistence callback. `persister` is invoked after every
  // mutation (bootstrap, encrypt, decrypt) so a restart can restore the same
  // chain state. Pass null to disable persistence.
  void setSessionPersistence({SessionPersister? persister}) {
    _sessionBootstrapper.setPersistence(persister: persister);
  }

  // Rehydrates in-memory sessions from a previously-saved snapshot map.
  // Snapshots from an incompatible schema version are silently skipped.
  Future<void> restoreSessionsFromSnapshots(
    Map<String, Map<String, dynamic>> snapshots,
  ) async {
    await _sessionBootstrapper.restoreSessions(snapshots);
  }
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

class _LibCryptoEnvelopeCodec
    implements CryptoEnvelopeCodec, InboundEnvelopeInspector {
  const _LibCryptoEnvelopeCodec();

  @override
  List<int>? extractSenderEphemeralPublicKey(CryptoEnvelope envelope) {
    try {
      final bytes = _b64Decode(envelope.ciphertext);
      if (bytes.length < 52) return null;
      return bytes.sublist(0, 32);
    } catch (_) {
      return null;
    }
  }

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
// Session state
//
// Double-Ratchet state:
//   rootKey          — seeds every DH ratchet step, rotates on each step.
//   sendChainKey     — symmetric chain advanced on every message we send.
//   receiveChainKey  — symmetric chain advanced on every message we decrypt.
//   currentSendRatchetPriv/Pub — our current X25519 ratchet keypair. The pub
//       goes on the wire; we rotate it whenever we're about to send after
//       having received at least one message since our last send.
//   lastSeenPeerRatchetPub — the peer's ratchet pub from the last envelope
//       we processed. A mismatch on inbound triggers a receive DH step.
//   hasReceivedSinceLastSend — latched true on every successful receive,
//       cleared when we rotate-and-send; the "did the turn just flip to us"
//       signal that drives send-side DH rotation.
//
// Forward secrecy: chain keys advance one-way via HKDF; compromise of the
// current chain key reveals no previously-derived message keys.
// Post-compromise security: a DH ratchet step mixes a fresh ECDH shared
// secret into the root key, so an adversary who captures the full session
// state loses visibility as soon as either side performs a DH step.
// ---------------------------------------------------------------------------

class _SessionState {
  _SessionState({
    required this.sessionLocator,
    required this.rootKey,
    required this.sendChainKey,
    required this.receiveChainKey,
    required this.currentSendRatchetPriv,
    required this.currentSendRatchetPub,
    required this.lastSeenPeerRatchetPub,
    required this.hasReceivedSinceLastSend,
    required this.remoteIdentityFingerprint,
    required this.localDeviceId,
    required this.remoteDeviceId,
    this.sendCounter = 0,
    this.receiveCounter = 0,
  });

  final String sessionLocator;
  SecretKey rootKey;
  SecretKey sendChainKey;
  SecretKey receiveChainKey;
  int sendCounter;
  int receiveCounter;
  // Stashed out-of-order message keys. Key format: "<peerPubB64>|<counter>".
  // The peerPub prefix means stragglers from a pre-rotation DH epoch don't
  // alias counters on the post-rotation chain.
  final Map<String, SecretKey> skippedMessageKeys = {};
  SimpleKeyPairData currentSendRatchetPriv;
  SimplePublicKey currentSendRatchetPub;
  List<int> lastSeenPeerRatchetPub;
  bool hasReceivedSinceLastSend;
  final String remoteIdentityFingerprint;
  final String localDeviceId;
  final String remoteDeviceId;

  Future<Map<String, dynamic>> snapshot() async {
    final rootBytes = await rootKey.extractBytes();
    final sendBytes = await sendChainKey.extractBytes();
    final recvBytes = await receiveChainKey.extractBytes();
    final skipped = <String, String>{};
    for (final entry in skippedMessageKeys.entries) {
      skipped[entry.key] = _b64Encode(await entry.value.extractBytes());
    }
    return {
      'v': _currentSessionSchemaVersion,
      'sessionLocator': sessionLocator,
      'rootKey': _b64Encode(rootBytes),
      'sendChainKey': _b64Encode(sendBytes),
      'receiveChainKey': _b64Encode(recvBytes),
      'sendCounter': sendCounter,
      'receiveCounter': receiveCounter,
      'sendRatchetPriv': _b64Encode(currentSendRatchetPriv.bytes),
      'sendRatchetPub': _b64Encode(currentSendRatchetPub.bytes),
      'lastSeenPeerPub': _b64Encode(lastSeenPeerRatchetPub),
      'hasReceivedSinceLastSend': hasReceivedSinceLastSend,
      'remoteIdentityFingerprint': remoteIdentityFingerprint,
      'localDeviceId': localDeviceId,
      'remoteDeviceId': remoteDeviceId,
      'skippedKeys': skipped,
    };
  }

  static Future<_SessionState?> tryRestore(Map<String, dynamic> json) async {
    try {
      if (json['v'] != _currentSessionSchemaVersion) return null;
      final privBytes = _b64Decode(json['sendRatchetPriv'] as String);
      final pubBytes = _b64Decode(json['sendRatchetPub'] as String);
      final kp = await X25519().newKeyPairFromSeed(privBytes);
      final kpData = await kp.extract();
      final pub = SimplePublicKey(pubBytes, type: KeyPairType.x25519);
      final state = _SessionState(
        sessionLocator: json['sessionLocator'] as String,
        rootKey: SecretKey(_b64Decode(json['rootKey'] as String)),
        sendChainKey: SecretKey(_b64Decode(json['sendChainKey'] as String)),
        receiveChainKey: SecretKey(_b64Decode(json['receiveChainKey'] as String)),
        currentSendRatchetPriv: kpData,
        currentSendRatchetPub: pub,
        lastSeenPeerRatchetPub: _b64Decode(json['lastSeenPeerPub'] as String),
        hasReceivedSinceLastSend:
            json['hasReceivedSinceLastSend'] as bool? ?? false,
        remoteIdentityFingerprint:
            json['remoteIdentityFingerprint'] as String? ?? '',
        localDeviceId: json['localDeviceId'] as String,
        remoteDeviceId: json['remoteDeviceId'] as String,
        sendCounter: (json['sendCounter'] as num?)?.toInt() ?? 0,
        receiveCounter: (json['receiveCounter'] as num?)?.toInt() ?? 0,
      );
      final skipped = json['skippedKeys'] as Map<String, dynamic>? ?? {};
      for (final entry in skipped.entries) {
        state.skippedMessageKeys[entry.key] =
            SecretKey(_b64Decode(entry.value as String));
      }
      return state;
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Session bootstrapper — handles initial X25519 DH and DH ratchet steps.
// ---------------------------------------------------------------------------

class _LibSessionBootstrapper implements ConversationSessionBootstrapper {
  static final X25519 _x25519 = X25519();
  static final Sha256 _sha256 = Sha256();

  final Map<String, _SessionState> _sessions = {};
  SessionPersister? _persister;

  void setPersistence({SessionPersister? persister}) {
    _persister = persister;
  }

  _SessionState? getSession(String conversationId) => _sessions[conversationId];

  Future<void> notifySessionChanged(String conversationId) async {
    final persister = _persister;
    if (persister == null) return;
    final session = _sessions[conversationId];
    if (session == null) return;
    final snap = await session.snapshot();
    await persister(conversationId, snap);
  }

  Future<void> restoreSessions(
    Map<String, Map<String, dynamic>> snapshots,
  ) async {
    for (final entry in snapshots.entries) {
      final restored = await _SessionState.tryRestore(entry.value);
      if (restored != null) {
        _sessions[entry.key] = restored;
      }
    }
  }

  @override
  bool hasSessionFor(String conversationId) =>
      _sessions.containsKey(conversationId);

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

    final rootKey = await _deriveRootKey(sharedSecret, request.conversationId);
    final (sendChain, recvChain) = await _deriveInitialChainKeys(
      sharedSecret: sharedSecret,
      conversationId: request.conversationId,
      localDeviceId: request.localDeviceId,
      remoteDeviceId: request.remoteDeviceId,
    );

    final session = _SessionState(
      sessionLocator: 'session://${request.conversationId}',
      rootKey: rootKey,
      sendChainKey: sendChain,
      receiveChainKey: recvChain,
      currentSendRatchetPriv: ephemeralPrivate,
      currentSendRatchetPub: ephemeralPublic,
      lastSeenPeerRatchetPub: remoteX25519Public.bytes,
      // Initiator hasn't received yet; first send uses the bootstrap chain.
      hasReceivedSinceLastSend: false,
      remoteIdentityFingerprint: fingerprint,
      localDeviceId: request.localDeviceId,
      remoteDeviceId: request.remoteDeviceId,
    );
    _sessions[request.conversationId] = session;
    await notifySessionChanged(request.conversationId);

    return SessionBootstrapMaterial(
      sessionLocator: session.sessionLocator,
      sessionEnvelopeVersion: _envelopeVersion,
      requiresLocalPersistence: true,
      sessionSchemaVersion: _currentSessionSchemaVersion,
      localDeviceId: request.localDeviceId,
      remoteDeviceId: request.remoteDeviceId,
      remoteIdentityFingerprint: fingerprint,
      auditHint: 'x25519-double-ratchet+hkdf-sha256+aes256gcm',
    );
  }

  @override
  Future<SessionBootstrapMaterial> bootstrapSessionFromInbound(
    InboundSessionBootstrapRequest request,
  ) async {
    final localX25519Priv = _parseLocalX25519Private(
      request.localIdentityPrivateRef,
    );
    if (localX25519Priv == null) {
      throw StateError(
        'Local identity bundle missing an x25519 private key; cannot bootstrap '
        'inbound session for ${request.conversationId}.',
      );
    }
    if (request.remoteEphemeralPublicKey.length != 32) {
      throw StateError(
        'Inbound ephemeral key must be exactly 32 bytes '
        '(got ${request.remoteEphemeralPublicKey.length}).',
      );
    }

    final localKeyPair = await _x25519.newKeyPairFromSeed(localX25519Priv);
    final localPrivateData = await localKeyPair.extract();
    final localPublicKey = await localKeyPair.extractPublicKey();
    final remoteEphemeralPub = SimplePublicKey(
      request.remoteEphemeralPublicKey,
      type: KeyPairType.x25519,
    );
    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remoteEphemeralPub,
    );

    final rootKey = await _deriveRootKey(sharedSecret, request.conversationId);
    final (sendChain, recvChain) = await _deriveInitialChainKeys(
      sharedSecret: sharedSecret,
      conversationId: request.conversationId,
      localDeviceId: request.localDeviceId,
      remoteDeviceId: request.remoteDeviceId,
    );

    final session = _SessionState(
      sessionLocator: 'session://${request.conversationId}',
      rootKey: rootKey,
      sendChainKey: sendChain,
      receiveChainKey: recvChain,
      // Responder's placeholder keypair is its own static X25519 identity.
      // It will never be used for a DH step because the first outbound send
      // will rotate before deriving dh (hasReceivedSinceLastSend=true below).
      currentSendRatchetPriv: localPrivateData,
      currentSendRatchetPub: localPublicKey,
      lastSeenPeerRatchetPub: request.remoteEphemeralPublicKey,
      hasReceivedSinceLastSend: true,
      remoteIdentityFingerprint: '',
      localDeviceId: request.localDeviceId,
      remoteDeviceId: request.remoteDeviceId,
    );
    _sessions[request.conversationId] = session;
    await notifySessionChanged(request.conversationId);

    return SessionBootstrapMaterial(
      sessionLocator: session.sessionLocator,
      sessionEnvelopeVersion: _envelopeVersion,
      requiresLocalPersistence: true,
      sessionSchemaVersion: _currentSessionSchemaVersion,
      localDeviceId: request.localDeviceId,
      remoteDeviceId: request.remoteDeviceId,
      remoteIdentityFingerprint: '',
      auditHint: 'x25519-double-ratchet-inbound+hkdf-sha256+aes256gcm',
    );
  }

  static List<int>? _parseLocalX25519Private(String identityPrivateRef) {
    try {
      final decoded = utf8.decode(_b64Decode(identityPrivateRef));
      final map = json.decode(decoded) as Map<String, dynamic>;
      final xB64 = map['x25519'] as String?;
      if (xB64 == null) return null;
      final bytes = _b64Decode(xB64);
      return bytes.length == 32 ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  // Extracts a 32-byte root-key from the initial X25519 shared secret.
  // Bound to the conversation id so distinct conversations on the same peer
  // don't share roots.
  static Future<SecretKey> _deriveRootKey(
    SecretKey sharedSecret,
    String conversationId,
  ) async {
    return Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(conversationId),
      info: utf8.encode('veil-root-v2'),
    );
  }

  // Derives initiator/responder chain keys deterministically from the shared
  // secret. The device with the lexicographically smaller id is "A"; both
  // peers agree by comparing ids so sendChain(A)==recvChain(B) and vice versa.
  static Future<(SecretKey, SecretKey)> _deriveInitialChainKeys({
    required SecretKey sharedSecret,
    required String conversationId,
    required String localDeviceId,
    required String remoteDeviceId,
  }) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final chainA = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(conversationId),
      info: utf8.encode('veil-chain-A-v2'),
    );
    final chainB = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: utf8.encode(conversationId),
      info: utf8.encode('veil-chain-B-v2'),
    );
    final localIsA = localDeviceId.compareTo(remoteDeviceId) < 0;
    return localIsA ? (chainA, chainB) : (chainB, chainA);
  }

  // DH ratchet step: combines a new ECDH output with the current root key
  // into a new root key + a new chain key. Both peers compute the same 64
  // bytes from symmetric inputs, so whichever side they assign to send vs.
  // recv still agrees after the step.
  static Future<(SecretKey, SecretKey)> _kdfRootKey(
    SecretKey rootKey,
    SecretKey dhOutput,
  ) async {
    final rootBytes = await rootKey.extractBytes();
    final derived = await Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 64,
    ).deriveKey(
      secretKey: dhOutput,
      nonce: rootBytes,
      info: utf8.encode('veil-dh-rk-v2'),
    );
    final bytes = await derived.extractBytes();
    return (
      SecretKey(bytes.sublist(0, 32)),
      SecretKey(bytes.sublist(32, 64)),
    );
  }

  // Send-side DH step: generate a fresh ratchet keypair, DH with the last
  // seen peer pub, mix into root, reset send chain + counter. Called right
  // before we're about to encrypt a message whose turn-flag was set by a
  // receive.
  static Future<void> performSendDhStep(_SessionState session) async {
    final newKp = await _x25519.newKeyPair();
    final newPriv = await newKp.extract();
    final newPub = await newKp.extractPublicKey();
    final dh = await _x25519.sharedSecretKey(
      keyPair: newKp,
      remotePublicKey: SimplePublicKey(
        session.lastSeenPeerRatchetPub,
        type: KeyPairType.x25519,
      ),
    );
    final (newRoot, newSendChain) = await _kdfRootKey(session.rootKey, dh);
    session.rootKey = newRoot;
    session.sendChainKey = newSendChain;
    session.sendCounter = 0;
    session.currentSendRatchetPriv = newPriv;
    session.currentSendRatchetPub = newPub;
    session.hasReceivedSinceLastSend = false;
  }

  // Receive-side DH step: the inbound envelope carries a new peer ratchet
  // pub; combine it with our current ratchet priv, mix into root, reset
  // recv chain + counter, and remember the new peer pub.
  static Future<void> performReceiveDhStep(
    _SessionState session,
    List<int> incomingPeerPub,
  ) async {
    final dh = await _x25519.sharedSecretKey(
      keyPair: session.currentSendRatchetPriv,
      remotePublicKey: SimplePublicKey(
        incomingPeerPub,
        type: KeyPairType.x25519,
      ),
    );
    final (newRoot, newRecvChain) = await _kdfRootKey(session.rootKey, dh);
    session.rootKey = newRoot;
    session.receiveChainKey = newRecvChain;
    session.receiveCounter = 0;
    session.lastSeenPeerRatchetPub = incomingPeerPub;
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
// Message crypto engine — AES-256-GCM with HKDF-derived per-message keys
// driven by the session's Double Ratchet chains.
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

    // DH send-ratchet step: rotate our ratchet keypair if we've received at
    // least one message since our last send. Produces a new root + send
    // chain + zeroes send counter. This is the step that gives post-
    // compromise security.
    if (session.hasReceivedSinceLastSend) {
      await _LibSessionBootstrapper.performSendDhStep(session);
    }

    // Forward-secret symmetric step: derive a one-shot message key from the
    // current chain at the current counter, then advance the chain.
    final counter = session.sendCounter;
    final messageKey = await _deriveMessageKeyFromChain(
      session.sendChainKey,
      counter,
    );
    session.sendChainKey = await _advanceChainKey(session.sendChainKey);
    session.sendCounter = counter + 1;

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

    // Wire layout: [ratchetPub(32)] [counter(4 BE)] [ciphertext] [mac(16)].
    // ratchetPub is the pub we just rotated to (if we rotated) or the pub
    // carried forward from the previous send.
    final ratchetPub = session.currentSendRatchetPub.bytes;
    final counterBytes = _encodeCounter(counter);
    final ciphertextWithKey =
        Uint8List(32 + 4 + secretBox.cipherText.length + 16);
    ciphertextWithKey.setRange(0, 32, ratchetPub);
    ciphertextWithKey.setRange(32, 36, counterBytes);
    ciphertextWithKey.setRange(
        36, 36 + secretBox.cipherText.length, secretBox.cipherText);
    ciphertextWithKey.setRange(
        36 + secretBox.cipherText.length,
        ciphertextWithKey.length,
        secretBox.mac.bytes);

    await sessionBootstrapper.notifySessionChanged(conversationId);

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

    // Minimum frame: 32 (ratchet pub) + 4 (counter) + 16 (mac) = 52 bytes.
    if (ciphertextBytes.length < 52) {
      return DecryptedMessage(
        body: '[Unable to decrypt: invalid envelope]',
        messageKind: envelope.messageKind,
      );
    }

    final incomingPeerPub = ciphertextBytes.sublist(0, 32);
    final counter = _decodeCounter(ciphertextBytes.sublist(32, 36));

    final macStart = ciphertextBytes.length - 16;
    final encryptedData = ciphertextBytes.sublist(36, macStart);
    final macBytes = ciphertextBytes.sublist(macStart);

    final session = sessionBootstrapper.getSession(envelope.conversationId);
    if (session == null) {
      return DecryptedMessage(
        body: '[Session not established — sync required]',
        messageKind: envelope.messageKind,
      );
    }

    // DH receive-ratchet step: if the sender rotated, advance our receive
    // chain via ECDH with their new pub. Skipped-keys from the pre-rotation
    // chain remain indexed by the old pub, so old stragglers still resolve.
    if (!_bytesEqual(incomingPeerPub, session.lastSeenPeerRatchetPub)) {
      try {
        await _LibSessionBootstrapper.performReceiveDhStep(
          session,
          incomingPeerPub,
        );
      } catch (_) {
        return DecryptedMessage(
          body: '[Decryption failed]',
          messageKind: envelope.messageKind,
        );
      }
    }

    final messageKey = await _resolveReceiveMessageKey(
      session,
      incomingPeerPub,
      counter,
    );
    if (messageKey == null) {
      return DecryptedMessage(
        body: '[Replayed or out-of-window message]',
        messageKind: envelope.messageKind,
      );
    }

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

      // A successful receive latches the turn-flag so the next send
      // performs a DH rotate.
      session.hasReceivedSinceLastSend = true;
      await sessionBootstrapper.notifySessionChanged(envelope.conversationId);

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

  // Derives a one-shot AES-GCM key from the chain key at a specific counter.
  // Using distinct `info` per counter means the same chain key can't be used
  // to decrypt a different message, even if we haven't advanced yet.
  static Future<SecretKey> _deriveMessageKeyFromChain(
    SecretKey chainKey,
    int counter,
  ) async {
    return _hkdf.deriveKey(
      secretKey: chainKey,
      nonce: utf8.encode('veil-msg-n$counter'),
      info: utf8.encode('veil-msg-v1'),
    );
  }

  // Advances the chain by hashing forward. The old chain key is replaced,
  // providing forward secrecy: compromise of the advanced chain does not
  // reveal keys derived from earlier chain states.
  static Future<SecretKey> _advanceChainKey(SecretKey chainKey) async {
    return _hkdf.deriveKey(
      secretKey: chainKey,
      nonce: const [0],
      info: utf8.encode('veil-chain-next-v1'),
    );
  }

  // Caps the number of skipped keys we will derive while chasing a counter,
  // to prevent a hostile peer from forcing unbounded HKDF work / memory by
  // sending a message with a huge counter.
  static const int _maxSkippedKeys = 1000;

  // Resolves the message key for a given (peerPub, counter) tuple. If the
  // counter is ahead of our state, we advance the chain and stash
  // intermediate keys so out-of-order messages can still decrypt. If already
  // consumed, reject as replay.
  static Future<SecretKey?> _resolveReceiveMessageKey(
    _SessionState session,
    List<int> peerPub,
    int counter,
  ) async {
    final skippedKey = _skippedKey(peerPub, counter);
    // Out-of-order: already stashed.
    final cached = session.skippedMessageKeys.remove(skippedKey);
    if (cached != null) return cached;

    // Replay or below-window.
    if (counter < session.receiveCounter) return null;

    // Gap too big → refuse (could be attacker-induced DoS).
    if (counter - session.receiveCounter > _maxSkippedKeys) return null;

    // Cap total stashed keys across all epochs.
    if (session.skippedMessageKeys.length +
            (counter - session.receiveCounter) >
        _maxSkippedKeys) {
      return null;
    }

    // Advance: derive keys for all counters in [receiveCounter, counter).
    // Stash intermediate ones under (current peer pub, counter).
    while (session.receiveCounter < counter) {
      final k = await _deriveMessageKeyFromChain(
        session.receiveChainKey,
        session.receiveCounter,
      );
      session.skippedMessageKeys[_skippedKey(peerPub, session.receiveCounter)] =
          k;
      session.receiveChainKey =
          await _advanceChainKey(session.receiveChainKey);
      session.receiveCounter += 1;
    }

    final targetKey =
        await _deriveMessageKeyFromChain(session.receiveChainKey, counter);
    session.receiveChainKey =
        await _advanceChainKey(session.receiveChainKey);
    session.receiveCounter = counter + 1;
    return targetKey;
  }

  static String _skippedKey(List<int> peerPub, int counter) =>
      '${_b64Encode(peerPub)}|$counter';

  static Uint8List _encodeCounter(int counter) {
    final buf = Uint8List(4);
    final view = ByteData.view(buf.buffer);
    view.setUint32(0, counter, Endian.big);
    return buf;
  }

  static int _decodeCounter(List<int> bytes) {
    final view = ByteData.view(Uint8List.fromList(bytes).buffer);
    return view.getUint32(0, Endian.big);
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
