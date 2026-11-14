import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const int gcmNonceLength = 12;
const int gcmTagLength = 16;

final AesGcm _aesGcm = AesGcm.with256bits();

/// AES-256-GCM returning `ciphertext || tag`, the layout every VEIL frame
/// and attachment blob uses.
Future<Uint8List> aesGcmSeal({
  required List<int> key,
  required List<int> nonce,
  required List<int> plaintext,
  List<int> aad = const [],
}) async {
  final box = await _aesGcm.encrypt(
    plaintext,
    secretKey: SecretKey(Uint8List.fromList(key)),
    nonce: nonce,
    aad: aad,
  );
  final out = Uint8List(box.cipherText.length + gcmTagLength)
    ..setRange(0, box.cipherText.length, box.cipherText)
    ..setRange(box.cipherText.length, box.cipherText.length + gcmTagLength, box.mac.bytes);
  return out;
}

/// Inverse of [aesGcmSeal]. Throws [SecretBoxAuthenticationError] when the
/// tag does not verify.
Future<Uint8List> aesGcmOpen({
  required List<int> key,
  required List<int> nonce,
  required List<int> sealed,
  List<int> aad = const [],
}) async {
  if (sealed.length < gcmTagLength) {
    throw const FormatException('AES-GCM input shorter than its tag');
  }
  final split = sealed.length - gcmTagLength;
  final plaintext = await _aesGcm.decrypt(
    SecretBox(sealed.sublist(0, split), nonce: nonce, mac: Mac(sealed.sublist(split))),
    secretKey: SecretKey(Uint8List.fromList(key)),
    aad: aad,
  );
  return Uint8List.fromList(plaintext);
}
