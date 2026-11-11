import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../security/device_auth_signer.dart';
import 'attachment/attachment_cipher_v2.dart';
import 'attachment/legacy_attachment.dart';
import 'bytes.dart';
import 'crypto_engine.dart';
import 'payload/inner_payload.dart';
import 'random_source.dart';
import 'ratchet/legacy_session.dart';
import 'ratchet/session_cipher.dart';
import 'ratchet/session_store.dart';
import 'x3dh/curve25519.dart';
import 'x3dh/identity_keys.dart';
import 'x3dh/local_keyring.dart';

export 'ratchet/session_store.dart' show SessionPersister;

// ---------------------------------------------------------------------------
// Production CryptoAdapter (protocol v2, docs/crypto-envelope-spec.md):
// X3DH with signed and one-time prekeys authenticates BOTH parties, then a
// Double Ratchet over AES-256-GCM gives forward secrecy and post-compromise
// security. Peers that still publish v1 bundles get the legacy protocol,
// whose results are typed legacyUnauthenticated.
//
// The pieces live under x3dh/ (identities, bundles, handshake, prekeys),
// ratchet/ (state, steps, frames, records, persistence), payload/ and
// attachment/; this file only adapts them to the CryptoAdapter boundary.
// ---------------------------------------------------------------------------

CryptoAdapter createDefaultCryptoAdapter() => LibCryptoAdapter();

/// Public facade over this adapter's identity-key helpers so sibling crypto
/// components (group Sender Keys distribution) reuse the exact same bundle
/// verification and private-ref parsing instead of re-implementing them.
/// Exposes no new capability: everything here is already reachable through
/// `bootstrapSession` / `decryptAttachment`.
class LibIdentityKeys {
  const LibIdentityKeys._();

  /// Verifies `signedPrekeyBundle` against `identityPublicKey` (Ed25519) and
  /// returns the authenticated X25519 identity key (IKx for v2 bundles).
  /// Throws on any mismatch.
  static Future<SimplePublicKey> resolveRemoteX25519(
    String signedPrekeyBundle,
    String identityPublicKey,
  ) async {
    final bundle = await verifyRemoteBundle(signedPrekeyBundle, identityPublicKey);
    final x25519 = switch (bundle) {
      PrekeyBundleV2(:final ikx) => ikx,
      LegacyPrekeyBundle(:final x25519) => x25519,
    };
    return SimplePublicKey(x25519, type: KeyPairType.x25519);
  }

  /// 32-byte X25519 identity private key from a v1 or v2 identity ref, or
  /// null if the ref is not a lib-adapter ref.
  static List<int>? localX25519Private(String identityPrivateRef) =>
      LocalIdentity.tryParse(identityPrivateRef)?.x25519Private;

  /// 32-byte Ed25519 seed from a v1 or v2 identity ref, or null.
  static List<int>? localEd25519Seed(String identityPrivateRef) =>
      LocalIdentity.tryParse(identityPrivateRef)?.ed25519Seed;
}

class LibCryptoAdapter implements CryptoAdapter, PrekeyManager {
  /// [random] and [clock] exist for known-answer tests; production uses the
  /// secure RNG and the wall clock.
  LibCryptoAdapter({RandomSource? random, DateTime Function()? clock}) {
    final source = random ?? SecureRandomSource();
    final now = clock ?? () => DateTime.now().toUtc();
    _keyring = LocalKeyring(random: source, clock: now);
    _store = SessionRecordStore(clock: now);
    _cipher = SessionCipher(store: _store, keyring: _keyring, random: source, clock: now);
    _identityProvider = _LibDeviceIdentityProvider(_keyring);
    _sessionBootstrapper = _LibSessionBootstrapper(_cipher, _store);
    _messagingEngine = _LibMessageCryptoEngine(_cipher, source);
  }

  late final LocalKeyring _keyring;
  late final SessionRecordStore _store;
  late final SessionCipher _cipher;
  late final _LibDeviceIdentityProvider _identityProvider;
  late final _LibSessionBootstrapper _sessionBootstrapper;
  late final _LibMessageCryptoEngine _messagingEngine;

  @override
  String get adapterId => 'lib-x3dh-x25519-aes256gcm-v4';

  @override
  DeviceIdentityProvider get identity => _identityProvider;

  @override
  DeviceAuthChallengeSigner get deviceAuth => const Ed25519DeviceAuthChallengeSigner();

  @override
  KeyBundleCodec get keyBundles => const _LibKeyBundleCodec();

  @override
  CryptoEnvelopeCodec get envelopeCodec => const _LibCryptoEnvelopeCodec();

  @override
  MessageCryptoEngine get messaging => _messagingEngine;

  @override
  ConversationSessionBootstrapper get sessions => _sessionBootstrapper;

  /// Wires durable session storage. Every committed ratchet mutation awaits
  /// [persister] before the operation returns. Pass null to stay in memory.
  void setSessionPersistence({SessionPersister? persister}) {
    _store.persister = persister;
  }

  /// Rehydrates session records (snapshot v4, or legacy v2/v3) after a
  /// restart. Unreadable snapshots are skipped so the peer re-bootstraps.
  Future<void> restoreSessionsFromSnapshots(Map<String, Map<String, dynamic>> snapshots) async {
    for (final entry in snapshots.entries) {
      await _store.restore(entry.key, entry.value);
    }
  }

  /// Waits for snapshot writes still in flight. Call before the OS may
  /// suspend the process and before logout/wipe.
  Future<void> flushPendingSnapshotWrites() => _store.flush();

  /// Forces the next outbound message on this conversation to perform a DH
  /// ratchet step (the "rotate keys" UX) and drops the current state's
  /// skipped keys so pre-rotation stragglers no longer decrypt. Returns false
  /// when no session exists or the peer has not yet replied to our handshake.
  /// Known limitation (docs/crypto-envelope-spec.md): if the peer has a reply
  /// in flight, the forced step desynchronises the session.
  Future<bool> forceRekeyNextSend(String conversationId) => _cipher.forceRekey(conversationId);

  void setLocalPrekeyStore(LocalPrekeyStore store) {
    _keyring.store = store;
  }

  /// Supplies the persisted identity private ref; consulted before the
  /// identity this instance generated or was handed by a legacy bootstrap.
  void setLocalIdentityLoader(Future<String?> Function() loader) {
    _keyring.identityLoader = loader;
  }

  void setRemoteIdentityVerifier(RemoteIdentityVerifier? verifier) {
    _cipher.identityVerifier = verifier;
  }

  @override
  Future<List<OneTimePrekey>> generateOneTimePrekeys({int count = 100}) => _keyring.generateOneTimePrekeys(count);

  @override
  Future<SignedPrekeyRotation> rotateSignedPrekey() => _keyring.rotateSignedPrekey();

  @override
  Future<SignedPrekeyRotation?> currentSignedPrekey() => _keyring.currentSignedPrekey();

  @override
  Future<int?> publishedSignedPrekeyId() => _keyring.publishedSignedPrekeyId();

  @override
  Future<void> markSignedPrekeyPublished(int spkId) => _keyring.markSignedPrekeyPublished(spkId);

  @override
  Future<int> pruneSignedPrekeys({Duration grace = signedPrekeyGrace}) => _keyring.pruneSignedPrekeys(grace);

  /// The live current state's secret buffers, so tests can prove superseded
  /// buffers are zeroed after a commit.
  @visibleForTesting
  List<Uint8List> debugLiveSecretBuffers(String conversationId) {
    final state = _store[conversationId]?.current;
    if (state == null) return const [];
    return [
      state.rootKey,
      state.sendRatchetPrivate,
      if (state.sendChainKey != null) state.sendChainKey!,
      if (state.receiveChainKey != null) state.receiveChainKey!,
    ];
  }
}

class _LibDeviceIdentityProvider implements DeviceIdentityProvider {
  _LibDeviceIdentityProvider(this._keyring);

  final LocalKeyring _keyring;

  @override
  Future<DeviceIdentityMaterial> generateDeviceIdentity(String deviceId) => _keyring.generateIdentity();

  @override
  Future<String> extractIdentityPublicKeyFromPrivateRef(String identityPrivateRef) async {
    final identity = LocalIdentity.tryParse(identityPrivateRef);
    if (identity == null) {
      throw ArgumentError('identity bundle missing ed25519 private key');
    }
    final publicKey = await ed25519PublicKeyFromSeed(identity.ed25519Seed);
    identity.destroy();
    return b64uEncode(publicKey);
  }
}

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

class _LibCryptoEnvelopeCodec implements CryptoEnvelopeCodec, InboundEnvelopeInspector {
  const _LibCryptoEnvelopeCodec();

  /// Only legacy frames need the controller's explicit inbound bootstrap;
  /// v2 PreKey frames establish the session inside decryptMessage, so this
  /// returns null for them and the controller hook stays inert.
  @override
  List<int>? extractSenderEphemeralPublicKey(CryptoEnvelope envelope) {
    if (envelope.version != envelopeVersionLegacy) return null;
    try {
      final bytes = b64uDecode(envelope.ciphertext);
      if (bytes.length < legacyFrameMinLength) return null;
      return bytes.sublist(0, 32);
    } catch (_) {
      return null;
    }
  }

  /// The version assumed for envelopes stored without one; those predate
  /// v2. Outgoing envelopes take their version from the session instead.
  @override
  String get defaultEnvelopeVersion => envelopeVersionLegacy;

  @override
  String? get defaultAttachmentWrapAlgorithmHint => attachmentAlgorithmV2;

  @override
  CryptoEnvelope decodeApiEnvelope(Map<String, dynamic> json) {
    return CryptoEnvelope(
      // Rows written before the server persisted the version are v1 frames.
      version: json['version'] as String? ?? envelopeVersionLegacy,
      conversationId: json['conversationId'] as String? ?? '',
      senderDeviceId: json['senderDeviceId'] as String? ?? '',
      recipientUserId: json['recipientUserId'] as String? ?? '',
      ciphertext: json['ciphertext'] as String? ?? '',
      nonce: json['nonce'] as String? ?? '',
      messageKind: _parseMessageKind(json['messageType'] as String?),
      expiresAt: _parseOptionalDateTime(json['expiresAt']),
      attachment: decodeAttachmentReference(json['attachment'] as Map<String, dynamic>?),
    );
  }

  @override
  Map<String, dynamic> encodeApiEnvelope(CryptoEnvelope envelope) {
    // Group sends use an empty recipientUserId because there is no single
    // recipient. The server validates the field as UUID-or-absent, so an
    // empty string would 400 — strip it before serializing.
    final recipientUserId = envelope.recipientUserId;
    final attachment = envelope.attachment;
    return {
      'version': envelope.version,
      'conversationId': envelope.conversationId,
      'senderDeviceId': envelope.senderDeviceId,
      if (recipientUserId.isNotEmpty) 'recipientUserId': recipientUserId,
      'ciphertext': envelope.ciphertext,
      'nonce': envelope.nonce,
      'messageType': envelope.messageKind.name,
      if (envelope.expiresAt != null) 'expiresAt': envelope.expiresAt!.toUtc().toIso8601String(),
      // The server only needs the id for blob lifecycle; key, digest, size
      // and type travel inside the authenticated payload (contract C3).
      if (attachment != null) 'attachment': {'attachmentId': attachment.attachmentId},
    };
  }

  /// Tolerates partial input: the outer envelope now carries only an
  /// attachmentId, and the local cache stores full references.
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

  /// Full local serialization (encrypted message cache). Never used for the
  /// outer envelope.
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
    return MessageKind.values.firstWhere((kind) => kind.name == value, orElse: () => MessageKind.text);
  }

  static DateTime? _parseOptionalDateTime(Object? value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value)?.toLocal();
    }
    return null;
  }
}

class _LibSessionBootstrapper implements ConversationSessionBootstrapper {
  _LibSessionBootstrapper(this._cipher, this._store);

  final SessionCipher _cipher;
  final SessionRecordStore _store;

  @override
  Future<SessionBootstrapMaterial> bootstrapSession(SessionBootstrapRequest request) => _cipher.bootstrap(request);

  @override
  Future<SessionBootstrapMaterial> bootstrapSessionFromInbound(InboundSessionBootstrapRequest request) =>
      _cipher.acceptLegacyInbound(request);

  @override
  bool hasSessionFor(String conversationId) => _store.contains(conversationId);

  @override
  Future<bool> forceRekeyNextSend(String conversationId) => _cipher.forceRekey(conversationId);
}

class _LibMessageCryptoEngine implements MessageCryptoEngine {
  _LibMessageCryptoEngine(this._cipher, this._random);

  final SessionCipher _cipher;
  final RandomSource _random;

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
  }) =>
      _cipher.encrypt(
        conversationId: conversationId,
        senderDeviceId: senderDeviceId,
        recipientUserId: recipientUserId,
        payload: InnerPayload(body: body, kind: messageKind, expiresAt: expiresAt, attachment: attachment),
        recipientIdentityKey: recipientBundle.identityPublicKey,
      );

  @override
  Future<DecryptedMessage> decryptMessage(CryptoEnvelope envelope) => _cipher.decrypt(envelope);

  @override
  Future<AttachmentCipher> encryptAttachment({
    required String attachmentId,
    required String storageKey,
    required String contentType,
    required List<int> plaintext,
    required KeyBundle recipientBundle,
  }) =>
      encryptAttachmentV2(
        attachmentId: attachmentId,
        storageKey: storageKey,
        contentType: contentType,
        plaintext: plaintext,
        random: _random,
      );

  @override
  Future<List<int>> decryptAttachment({
    required AttachmentReference reference,
    required List<int> ciphertext,
    required String localIdentityPrivateRef,
  }) =>
      reference.algorithmHint == attachmentAlgorithmV2
          ? decryptAttachmentV2(reference: reference, ciphertext: ciphertext)
          : decryptLegacyWrappedAttachment(
              reference: reference,
              ciphertext: ciphertext,
              localIdentityPrivateRef: localIdentityPrivateRef,
            );
}
