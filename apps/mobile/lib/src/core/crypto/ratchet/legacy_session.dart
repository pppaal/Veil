/// Protocol v1 ('veil-envelope-v1'), kept byte-compatible for peers that
/// still publish v1 bundles. Its one-DH bootstrap authenticates only the
/// responder, so everything decrypted here is reported as
/// legacyUnauthenticated.
///
///   frame = ratchetPub(32) || u32 N || ciphertext || tag(16)
///   AAD   = "veil-frame-aad-v3" || ratchetPub || u32 N || utf8(senderDeviceId)
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;

import '../bytes.dart';
import '../crypto_engine.dart';
import '../random_source.dart';
import '../x3dh/curve25519.dart';
import '../x3dh/identity_keys.dart';
import 'aead.dart';
import 'kdf.dart';
import 'ratchet_state.dart';

const String envelopeVersionLegacy = 'veil-envelope-v1';
const String frameAadLabelV3 = 'veil-frame-aad-v3';
const int legacyFrameMinLength = 32 + 4 + gcmTagLength;

class LegacyFrame {
  LegacyFrame._(this.ratchetPublic, this.counter, this.sealed);

  final Uint8List ratchetPublic;
  final int counter;
  final Uint8List sealed;

  static LegacyFrame decode(List<int> bytes) {
    if (bytes.length < legacyFrameMinLength) {
      throw const FormatException('v1 frame truncated');
    }
    return LegacyFrame._(
      Uint8List.fromList(bytes.sublist(0, 32)),
      readU32be(bytes, 32),
      Uint8List.fromList(bytes.sublist(36)),
    );
  }

  static Uint8List encode(List<int> ratchetPublic, int counter, List<int> sealed) =>
      concatBytes([ratchetPublic, u32be(counter), sealed]);
}

Uint8List buildFrameAadV3({
  required List<int> ratchetPublic,
  required int counter,
  required String senderDeviceId,
}) =>
    concatBytes([utf8.encode(frameAadLabelV3), ratchetPublic, u32be(counter), utf8.encode(senderDeviceId)]);

/// Initiator side: sharedSecret = X25519(ephemeral, responder IKx).
Future<RatchetState> initiateLegacySession(
  SessionBootstrapRequest request,
  LegacyPrekeyBundle bundle,
  RandomSource random,
  DateTime now,
) async {
  final ephemeral = await generateX25519KeyPair(random);
  final shared = await x25519SharedSecret(ephemeral.privateKey, bundle.x25519);
  final (rootKey, sendChain, receiveChain) = await _deriveInitialKeys(
    shared,
    conversationId: request.conversationId,
    localDeviceId: request.localDeviceId,
    remoteDeviceId: request.remoteDeviceId,
  );
  final identityHash = hash.sha256.convert(b64uDecode(request.remoteIdentityPublicKey)).bytes;
  return RatchetState(
    protocol: protocolLegacy,
    sessionLocator: 'session://${request.conversationId}',
    localDeviceId: request.localDeviceId,
    remoteDeviceId: request.remoteDeviceId,
    remoteIdentityFingerprint: b64uEncode(identityHash.sublist(0, 16)),
    initiatedLocally: true,
    createdAt: now,
    rootKey: rootKey,
    sendChainKey: sendChain,
    receiveChainKey: receiveChain,
    sendRatchetPrivate: ephemeral.privateKey,
    sendRatchetPublic: ephemeral.publicKey,
    remoteRatchetPublic: bundle.x25519,
    associatedData: Uint8List(0),
  );
}

/// Responder side, from the sender ephemeral lifted off the first frame.
Future<RatchetState> acceptLegacySession(InboundSessionBootstrapRequest request, DateTime now) async {
  final identity = LocalIdentity.tryParse(request.localIdentityPrivateRef);
  if (identity == null) {
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
  final local = await x25519KeyPairFromPrivate(identity.x25519Private);
  identity.destroy();
  final shared = await x25519SharedSecret(local.privateKey, request.remoteEphemeralPublicKey);
  final (rootKey, sendChain, receiveChain) = await _deriveInitialKeys(
    shared,
    conversationId: request.conversationId,
    localDeviceId: request.localDeviceId,
    remoteDeviceId: request.remoteDeviceId,
  );
  return RatchetState(
    protocol: protocolLegacy,
    sessionLocator: 'session://${request.conversationId}',
    localDeviceId: request.localDeviceId,
    remoteDeviceId: request.remoteDeviceId,
    remoteIdentityFingerprint: '',
    initiatedLocally: false,
    createdAt: now,
    rootKey: rootKey,
    sendChainKey: sendChain,
    receiveChainKey: receiveChain,
    // The static identity key is only a placeholder: the first send rotates
    // before deriving anything from it.
    sendRatchetPrivate: local.privateKey,
    sendRatchetPublic: local.publicKey,
    remoteRatchetPublic: Uint8List.fromList(request.remoteEphemeralPublicKey),
    needsSendStep: true,
    associatedData: Uint8List(0),
  );
}

// rootKey / chain A / chain B = HKDF(shared, salt utf8(conversationId),
// "veil-root-v2" / "veil-chain-A-v2" / "veil-chain-B-v2"); the device with
// the lexicographically smaller id sends on chain A.
Future<(Uint8List, Uint8List, Uint8List)> _deriveInitialKeys(
  Uint8List shared, {
  required String conversationId,
  required String localDeviceId,
  required String remoteDeviceId,
}) async {
  final salt = utf8.encode(conversationId);
  Future<Uint8List> derive(String label) => hkdfSha256(ikm: shared, salt: salt, info: utf8.encode(label), length: 32);
  final rootKey = await derive('veil-root-v2');
  final chainA = await derive('veil-chain-A-v2');
  final chainB = await derive('veil-chain-B-v2');
  zeroize(shared);
  final localIsA = localDeviceId.compareTo(remoteDeviceId) < 0;
  return localIsA ? (rootKey, chainA, chainB) : (rootKey, chainB, chainA);
}
