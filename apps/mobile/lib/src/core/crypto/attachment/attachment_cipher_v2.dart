import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../bytes.dart';
import '../crypto_engine.dart';
import '../message_padding.dart';
import '../random_source.dart';
import '../ratchet/aead.dart';

/// Attachment pointer model (Signal-style): a fresh random key and nonce per
/// blob, carried only inside the ratchet-encrypted payload, so attachments
/// inherit the session's forward secrecy and nothing is wrapped to a static
/// identity key.
///
///   padded = ISO7816(plaintext) to padmeLength(len + 1)
///   blob   = AES-256-GCM(key, nonce, padded, aad = "veil-att-v2" || utf8(id))
///   digest = SHA-256(blob)

const String attachmentAlgorithmV2 = 'aes256gcm-v2';
const String attachmentAadLabel = 'veil-att-v2';

final Sha256 _sha256 = Sha256();

Uint8List attachmentAad(String attachmentId) =>
    concatBytes([utf8.encode(attachmentAadLabel), utf8.encode(attachmentId)]);

Future<AttachmentCipher> encryptAttachmentV2({
  required String attachmentId,
  required String storageKey,
  required String contentType,
  required List<int> plaintext,
  required RandomSource random,
}) async {
  final key = random.nextBytes(32);
  final nonce = random.nextBytes(gcmNonceLength);
  final padded = MessagePadding.padTo(plaintext, MessagePadding.padmeLength(plaintext.length + 1));
  final blob = await aesGcmSeal(key: key, nonce: nonce, plaintext: padded, aad: attachmentAad(attachmentId));
  zeroize(padded);
  final digest = await _sha256.hash(blob);
  final reference = AttachmentReference(
    attachmentId: attachmentId,
    storageKey: storageKey,
    contentType: contentType,
    sizeBytes: plaintext.length,
    sha256: b64uEncode(digest.bytes),
    encryptedKey: b64uEncode(key),
    nonce: b64uEncode(nonce),
    algorithmHint: attachmentAlgorithmV2,
  );
  zeroize(key);
  return AttachmentCipher(reference: reference, ciphertext: blob);
}

Future<List<int>> decryptAttachmentV2({
  required AttachmentReference reference,
  required List<int> ciphertext,
}) async {
  final digest = await _sha256.hash(ciphertext);
  if (!constantTimeEquals(digest.bytes, _decodeOrEmpty(reference.sha256))) {
    throw StateError(
      'Attachment ciphertext hash does not match reference.sha256 — '
      'blob has been modified in transit or storage.',
    );
  }
  final key = _decodeOrEmpty(reference.encryptedKey);
  final nonce = _decodeOrEmpty(reference.nonce);
  if (key.length != 32 || nonce.length != gcmNonceLength) {
    throw StateError('Attachment reference key or nonce has the wrong length.');
  }
  try {
    final padded = await aesGcmOpen(
      key: key,
      nonce: nonce,
      sealed: ciphertext,
      aad: attachmentAad(reference.attachmentId),
    );
    return MessagePadding.unpad(padded);
  } on SecretBoxAuthenticationError {
    throw StateError(
      'Attachment ciphertext failed AES-GCM authentication — blob was '
      'modified or encrypted with a different content key.',
    );
  } finally {
    zeroize(key);
  }
}

Uint8List _decodeOrEmpty(String value) {
  try {
    return b64uDecode(value);
  } on FormatException {
    return Uint8List(0);
  }
}
