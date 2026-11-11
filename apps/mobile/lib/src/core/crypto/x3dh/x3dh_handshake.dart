import 'dart:convert';
import 'dart:typed_data';

import '../bytes.dart';
import '../ratchet/kdf.dart';
import 'curve25519.dart';

/// X3DH key agreement for protocol v2 (docs/crypto-envelope-spec.md §v2).
///
/// DH1 = DH(IKx_A, SPK_B) is what authenticates the initiator: only the
/// holder of IKx_A's private key can compute it, so a party holding nothing
/// but public bundles (including the server) cannot open a session as A.

const String x3dhInfoLabel = 'veil-x3dh-v2';
const int noOneTimePrekeyId = 0xFFFFFFFF;

/// The initiator's identity proof and handshake keys, carried in every frame
/// until the responder replies.
class PreKeyHeader {
  PreKeyHeader({
    required this.identityEd25519,
    required this.identityX25519,
    required this.identityX25519Signature,
    required this.baseKey,
    required this.signedPrekeyId,
    required this.oneTimePrekeyId,
  });

  static const int encodedLength = 32 + 32 + 64 + 32 + 4 + 4;

  final Uint8List identityEd25519;
  final Uint8List identityX25519;
  final Uint8List identityX25519Signature;
  // EK_A: the initiator's ephemeral key; also identifies the session a
  // PreKey frame belongs to.
  final Uint8List baseKey;
  final int signedPrekeyId;
  final int oneTimePrekeyId;

  bool get usesOneTimePrekey => oneTimePrekeyId != noOneTimePrekeyId;

  Uint8List encode() => concatBytes([
        identityEd25519,
        identityX25519,
        identityX25519Signature,
        baseKey,
        u32be(signedPrekeyId),
        u32be(oneTimePrekeyId),
      ]);

  static PreKeyHeader decode(List<int> bytes, [int offset = 0]) {
    if (bytes.length - offset < encodedLength) {
      throw const FormatException('PreKey header truncated');
    }
    Uint8List take(int start, int length) => Uint8List.fromList(bytes.sublist(offset + start, offset + start + length));
    return PreKeyHeader(
      identityEd25519: take(0, 32),
      identityX25519: take(32, 32),
      identityX25519Signature: take(64, 64),
      baseKey: take(128, 32),
      signedPrekeyId: readU32be(bytes, offset + 160),
      oneTimePrekeyId: readU32be(bytes, offset + 164),
    );
  }
}

class HandshakeKeys {
  HandshakeKeys(this.sharedKey, this.associatedData);

  final Uint8List sharedKey;
  // AD = IKed_A || IKx_A || IKed_B || IKx_B, bound into every frame's AAD.
  final Uint8List associatedData;
}

Future<HandshakeKeys> deriveInitiatorKeys({
  required List<int> identityEd25519,
  required List<int> identityX25519Private,
  required List<int> identityX25519,
  required List<int> ephemeralPrivate,
  required List<int> remoteIdentityEd25519,
  required List<int> remoteIdentityX25519,
  required List<int> remoteSignedPrekey,
  List<int>? remoteOneTimePrekey,
}) async {
  final dhs = [
    await x25519SharedSecret(identityX25519Private, remoteSignedPrekey),
    await x25519SharedSecret(ephemeralPrivate, remoteIdentityX25519),
    await x25519SharedSecret(ephemeralPrivate, remoteSignedPrekey),
    if (remoteOneTimePrekey != null) await x25519SharedSecret(ephemeralPrivate, remoteOneTimePrekey),
  ];
  return _finish(
    dhs,
    initiatorEd25519: identityEd25519,
    initiatorX25519: identityX25519,
    responderEd25519: remoteIdentityEd25519,
    responderX25519: remoteIdentityX25519,
  );
}

Future<HandshakeKeys> deriveResponderKeys({
  required PreKeyHeader header,
  required List<int> identityEd25519,
  required List<int> identityX25519Private,
  required List<int> identityX25519,
  required List<int> signedPrekeyPrivate,
  List<int>? oneTimePrekeyPrivate,
}) async {
  final dhs = [
    await x25519SharedSecret(signedPrekeyPrivate, header.identityX25519),
    await x25519SharedSecret(identityX25519Private, header.baseKey),
    await x25519SharedSecret(signedPrekeyPrivate, header.baseKey),
    if (oneTimePrekeyPrivate != null) await x25519SharedSecret(oneTimePrekeyPrivate, header.baseKey),
  ];
  return _finish(
    dhs,
    initiatorEd25519: header.identityEd25519,
    initiatorX25519: header.identityX25519,
    responderEd25519: identityEd25519,
    responderX25519: identityX25519,
  );
}

// SK = HKDF-SHA256(0xFF*32 || DH1 || DH2 || DH3 [|| DH4], salt 0x00*32,
// info "veil-x3dh-v2" || IKed_A || IKed_B). The 0xFF prefix is X3DH's
// domain separator against other uses of the same X25519 keys.
Future<HandshakeKeys> _finish(
  List<Uint8List> dhs, {
  required List<int> initiatorEd25519,
  required List<int> initiatorX25519,
  required List<int> responderEd25519,
  required List<int> responderX25519,
}) async {
  final ikm = concatBytes([Uint8List(32)..fillRange(0, 32, 0xFF), ...dhs]);
  final sharedKey = await hkdfSha256(
    ikm: ikm,
    salt: Uint8List(32),
    info: concatBytes([utf8.encode(x3dhInfoLabel), initiatorEd25519, responderEd25519]),
    length: 32,
  );
  zeroize(ikm);
  dhs.forEach(zeroize);
  return HandshakeKeys(
    sharedKey,
    concatBytes([initiatorEd25519, initiatorX25519, responderEd25519, responderX25519]),
  );
}
