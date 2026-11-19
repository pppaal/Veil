import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/crypto/random_source.dart';
import 'package:veil_mobile/src/core/crypto/ratchet/frame_codec.dart';

/// Shared two-party fixtures for the protocol v2 tests.

class Party {
  Party(this.name, this.adapter, this.identity);

  final String name;
  final LibCryptoAdapter adapter;
  final DeviceIdentityMaterial identity;

  String get deviceId => 'device-$name';
  String get userId => 'user-$name';

  KeyBundle get bundle => KeyBundle(
        userId: userId,
        deviceId: deviceId,
        handle: name,
        identityPublicKey: identity.identityPublicKey,
        signedPrekeyBundle: identity.signedPrekeyBundle,
      );
}

Future<Party> createParty(String name, {RandomSource? random, DateTime Function()? clock}) async {
  final adapter = LibCryptoAdapter(random: random, clock: clock);
  final identity = await adapter.identity.generateDeviceIdentity('device-$name');
  return Party(name, adapter, identity);
}

Future<SessionBootstrapMaterial> bootstrap(
  Party from,
  Party to, {
  required String conversationId,
  OneTimePrekey? oneTimePrekey,
  String? signedPrekeyBundle,
}) =>
    from.adapter.sessions.bootstrapSession(SessionBootstrapRequest(
      conversationId: conversationId,
      localDeviceId: from.deviceId,
      localUserId: from.userId,
      remoteUserId: to.userId,
      remoteDeviceId: to.deviceId,
      remoteIdentityPublicKey: to.identity.identityPublicKey,
      remoteSignedPrekeyBundle: signedPrekeyBundle ?? to.identity.signedPrekeyBundle,
      remoteOneTimePrekey: oneTimePrekey,
    ));

Future<CryptoEnvelope> send(
  Party from,
  Party to,
  String body, {
  required String conversationId,
  MessageKind kind = MessageKind.text,
  DateTime? expiresAt,
  AttachmentReference? attachment,
}) =>
    from.adapter.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: from.deviceId,
      recipientUserId: to.userId,
      body: body,
      messageKind: kind,
      recipientBundle: to.bundle,
      expiresAt: expiresAt,
      attachment: attachment,
    );

Future<DecryptedMessage> receive(Party to, CryptoEnvelope envelope) => to.adapter.messaging.decryptMessage(envelope);

FrameV2 frameOf(CryptoEnvelope envelope) => FrameV2.decode(b64uDecode(envelope.ciphertext));

CryptoEnvelope copyEnvelope(
  CryptoEnvelope e, {
  String? version,
  String? conversationId,
  String? senderDeviceId,
  String? ciphertext,
  MessageKind? messageKind,
  DateTime? expiresAt,
  AttachmentReference? attachment,
}) =>
    CryptoEnvelope(
      version: version ?? e.version,
      conversationId: conversationId ?? e.conversationId,
      senderDeviceId: senderDeviceId ?? e.senderDeviceId,
      recipientUserId: e.recipientUserId,
      ciphertext: ciphertext ?? e.ciphertext,
      nonce: e.nonce,
      messageKind: messageKind ?? e.messageKind,
      expiresAt: expiresAt ?? e.expiresAt,
      attachment: attachment ?? e.attachment,
    );

/// Replays an explicit sequence of draws, so a test controls every key and
/// nonce the adapter generates. Each draw must have the requested length.
class ScriptedRandomSource implements RandomSource {
  ScriptedRandomSource(Iterable<List<int>> draws) : _draws = draws.map(Uint8List.fromList).toList();

  final List<Uint8List> _draws;
  var _next = 0;

  @override
  Uint8List nextBytes(int length) {
    if (_next >= _draws.length) {
      throw StateError('scripted random source exhausted after $_next draws');
    }
    final draw = _draws[_next++];
    if (draw.length != length) {
      throw StateError('draw $_next has ${draw.length} bytes, adapter asked for $length');
    }
    return Uint8List.fromList(draw);
  }
}

/// Deterministic (insecure) randomness for reproducible fuzzing.
class SeededRandomSource implements RandomSource {
  SeededRandomSource(int seed) : _random = Random(seed);

  final Random _random;

  @override
  Uint8List nextBytes(int length) => Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));
}

/// A legacy (v1) identity as pre-v2 installs generated it: ref
/// {ed25519, x25519} and bundle {v: 1, x25519, sig}.
class LegacyIdentity {
  LegacyIdentity(this.identityPrivateKeyRef, this.identityPublicKey, this.signedPrekeyBundle, this.x25519Private);

  final String identityPrivateKeyRef;
  final String identityPublicKey;
  final String signedPrekeyBundle;
  final List<int> x25519Private;
}

Future<LegacyIdentity> createLegacyIdentity() async {
  final ed = await Ed25519().newKeyPair();
  final edPublic = await ed.extractPublicKey();
  final edSeed = await ed.extractPrivateKeyBytes();
  final x = await X25519().newKeyPair();
  final xPublic = await x.extractPublicKey();
  final xPrivate = await x.extractPrivateKeyBytes();
  final signature = await Ed25519().sign(xPublic.bytes, keyPair: ed);
  final bundle = json.encode({'v': 1, 'x25519': b64uEncode(xPublic.bytes), 'sig': b64uEncode(signature.bytes)});
  final ref = json.encode({'ed25519': b64uEncode(edSeed), 'x25519': b64uEncode(xPrivate)});
  return LegacyIdentity(
    b64uEncode(utf8.encode(ref)),
    b64uEncode(edPublic.bytes),
    b64uEncode(utf8.encode(bundle)),
    xPrivate,
  );
}

/// A device still on a v1 identity: peers bootstrapping to it get the
/// legacy protocol.
Future<Party> createLegacyParty(String name) async {
  final legacy = await createLegacyIdentity();
  final adapter = LibCryptoAdapter()..setLocalIdentityLoader(() async => legacy.identityPrivateKeyRef);
  return Party(
    name,
    adapter,
    DeviceIdentityMaterial(
      identityPublicKey: legacy.identityPublicKey,
      identityPrivateKeyRef: legacy.identityPrivateKeyRef,
      signedPrekeyBundle: legacy.signedPrekeyBundle,
    ),
  );
}

/// The controller's legacy inbound path: lift the sender ephemeral off the
/// first v1 frame and bootstrap the responder from it.
Future<void> acceptLegacy(Party receiver, Party sender, CryptoEnvelope first, {required String conversationId}) async {
  final inspector = receiver.adapter.envelopeCodec as InboundEnvelopeInspector;
  await receiver.adapter.sessions.bootstrapSessionFromInbound(InboundSessionBootstrapRequest(
    conversationId: conversationId,
    localDeviceId: receiver.deviceId,
    localUserId: receiver.userId,
    localIdentityPrivateRef: receiver.identity.identityPrivateKeyRef,
    remoteUserId: sender.userId,
    remoteDeviceId: sender.deviceId,
    remoteEphemeralPublicKey: inspector.extractSenderEphemeralPublicKey(first)!,
  ));
}

/// Produces a reference in the retired wrap-to-identity format, exactly as
/// pre-v2 senders did, so tests can prove such attachments still open.
Future<AttachmentCipher> createLegacyWrappedAttachment({
  required String attachmentId,
  required List<int> plaintext,
  required KeyBundle recipient,
}) async {
  final random = SecureRandomSource();
  final contentKey = random.nextBytes(32);
  final contentNonce = random.nextBytes(12);
  final wrapNonce = random.nextBytes(12);
  final recipientX25519 =
      await LibIdentityKeys.resolveRemoteX25519(recipient.signedPrekeyBundle, recipient.identityPublicKey);
  final ephemeral = await X25519().newKeyPair();
  final ephemeralPublic = await ephemeral.extractPublicKey();
  final wrapSecret = await X25519().sharedSecretKey(keyPair: ephemeral, remotePublicKey: recipientX25519);
  final wrapKey = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: wrapSecret,
    nonce: ephemeralPublic.bytes,
    info: utf8.encode('veil-attachment-wrap-v1'),
  );
  final aes = AesGcm.with256bits();
  final wrapped = await aes.encrypt(contentKey, secretKey: wrapKey, nonce: wrapNonce);
  final blob = await aes.encrypt(plaintext, secretKey: SecretKey(contentKey), nonce: contentNonce);
  final blobBytes = concatBytes([blob.cipherText, blob.mac.bytes]);
  return AttachmentCipher(
    reference: AttachmentReference(
      attachmentId: attachmentId,
      storageKey: 'blob://$attachmentId',
      contentType: 'application/octet-stream',
      sizeBytes: blobBytes.length,
      sha256: b64uEncode((await Sha256().hash(blobBytes)).bytes),
      encryptedKey: b64uEncode(concatBytes([ephemeralPublic.bytes, wrapped.cipherText, wrapped.mac.bytes])),
      nonce: '${b64uEncode(contentNonce)}.${b64uEncode(wrapNonce)}',
      algorithmHint: 'x25519-aes256gcm',
    ),
    ciphertext: blobBytes,
  );
}

/// Captures every snapshot the adapter persists, keyed by conversation.
class SnapshotRecorder {
  final Map<String, Map<String, dynamic>> latest = {};
  final List<String> writes = [];

  Future<void> call(String conversationId, Map<String, dynamic> snapshot) async {
    writes.add(conversationId);
    latest[conversationId] = json.decode(json.encode(snapshot)) as Map<String, dynamic>;
  }
}
