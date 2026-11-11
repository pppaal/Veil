/// Decrypts references produced before the attachment-pointer model, whose
/// content key was wrapped to the recipient's static X25519 identity key.
/// Kept read-only so attachments already received stay openable; nothing
/// produces this format any more.
///
///   encryptedKey = ephPub(32) || wrapCiphertext || wrapTag(16)
///   nonce        = b64u(contentNonce) "." b64u(wrapNonce)
///   wrapKey      = HKDF(X25519(identity, ephPub), salt ephPub, "veil-attachment-wrap-v1")
library;

import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../bytes.dart';
import '../crypto_engine.dart';
import '../ratchet/aead.dart';
import '../ratchet/kdf.dart';
import '../x3dh/curve25519.dart';
import '../x3dh/identity_keys.dart';

final Sha256 _sha256 = Sha256();

Future<List<int>> decryptLegacyWrappedAttachment({
  required AttachmentReference reference,
  required List<int> ciphertext,
  required String localIdentityPrivateRef,
}) async {
  final computedHash = await _sha256.hash(ciphertext);
  if (b64uEncode(computedHash.bytes) != reference.sha256) {
    throw StateError(
      'Attachment ciphertext hash does not match reference.sha256 — '
      'blob has been modified in transit or storage.',
    );
  }
  final nonceParts = reference.nonce.split('.');
  if (nonceParts.length != 2) {
    throw StateError(
      'Attachment reference uses a legacy nonce format without a separate '
      'content nonce — cannot decrypt.',
    );
  }
  final contentNonce = b64uDecode(nonceParts[0]);
  final wrapNonce = b64uDecode(nonceParts[1]);
  if (contentNonce.length != gcmNonceLength || wrapNonce.length != gcmNonceLength) {
    throw StateError('Attachment nonces must be exactly 12 bytes each.');
  }
  final wrapped = b64uDecode(reference.encryptedKey);
  if (wrapped.length < 32 + gcmTagLength) {
    throw StateError('Wrapped attachment key is too short (expected ephPub + wrapped + mac).');
  }
  final identity = LocalIdentity.tryParse(localIdentityPrivateRef);
  if (identity == null) {
    throw StateError(
      'Local identity bundle missing x25519 private key — cannot unwrap '
      'attachment content key.',
    );
  }

  final ephPub = wrapped.sublist(0, 32);
  final wrapSecret = await x25519SharedSecret(identity.x25519Private, ephPub);
  identity.destroy();
  final wrapKey = await hkdfSha256(
    ikm: wrapSecret,
    salt: ephPub,
    info: utf8.encode('veil-attachment-wrap-v1'),
    length: 32,
  );
  zeroize(wrapSecret);

  final List<int> contentKey;
  try {
    contentKey = await aesGcmOpen(key: wrapKey, nonce: wrapNonce, sealed: wrapped.sublist(32));
  } on SecretBoxAuthenticationError {
    throw StateError(
      'Wrapped attachment key failed authentication — the reference was '
      'not wrapped for this identity (or has been tampered with).',
    );
  } finally {
    zeroize(wrapKey);
  }

  try {
    return await aesGcmOpen(key: contentKey, nonce: contentNonce, sealed: ciphertext);
  } on SecretBoxAuthenticationError {
    throw StateError(
      'Attachment ciphertext failed AES-GCM authentication — blob was '
      'modified or encrypted with a different content key.',
    );
  } on FormatException {
    throw StateError('Attachment ciphertext shorter than the AES-GCM tag (16 bytes).');
  } finally {
    zeroize(contentKey);
  }
}
