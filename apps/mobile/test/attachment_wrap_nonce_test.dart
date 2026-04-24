import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

// Regression test for attachment-wrap hygiene.
//
// The previous encrypt path reused a single random 12-byte value as BOTH
// the HKDF salt AND the AES-GCM nonce. While not catastrophic in the
// original shape (a fresh ephemeral X25519 keypair per attachment keeps
// the derived wrap key unique per message), mixing those two roles invites
// a future refactor — e.g., caching the ephemeral keypair when fanning out
// to many recipients — to silently produce (key, nonce) collisions, which
// in AES-GCM leaks plaintext and breaks integrity.
//
// The fix: HKDF now takes the ephemeral public key bytes as its salt; two
// independent random 12-byte nonces are used for (a) wrapping the content
// key and (b) encrypting the blob itself. These tests pin the invariants
// that (a) HKDF salt and neither GCM nonce share bytes on the wire, and
// (b) two sequential attachment wraps produce fully independent wrap
// material (different ephemeral pubs, different nonces, different ciphertexts).

Uint8List _b64Decode(String value) {
  final padded = value.padRight(
    value.length + ((4 - value.length % 4) % 4),
    '=',
  );
  return Uint8List.fromList(base64Url.decode(padded));
}

({Uint8List contentNonce, Uint8List wrapNonce}) _parseNonces(String joined) {
  final parts = joined.split('.');
  expect(parts.length, 2,
      reason: 'nonce field must be "contentNonceB64.wrapNonceB64"');
  return (
    contentNonce: _b64Decode(parts[0]),
    wrapNonce: _b64Decode(parts[1]),
  );
}

void main() {
  test('attachment wrap stores GCM nonces distinct from the ephemeral pub',
      () async {
    final sender = LibCryptoAdapter();
    final recipient = LibCryptoAdapter();
    final recipientId =
        await recipient.identity.generateDeviceIdentity('device-bob');

    final bundle = KeyBundle(
      userId: 'bob',
      deviceId: 'device-bob',
      handle: 'bob',
      identityPublicKey: recipientId.identityPublicKey,
      signedPrekeyBundle: recipientId.signedPrekeyBundle,
    );

    final cipher = await sender.messaging.encryptAttachment(
      attachmentId: 'att-1',
      storageKey: 'blob://att-1',
      contentType: 'application/octet-stream',
      plaintext: List<int>.generate(64, (i) => i),
      recipientBundle: bundle,
    );
    final ref = cipher.reference;

    // First 32 bytes of the wrapped key are the ephemeral X25519 pub that
    // the decrypt side needs to re-derive wrapSecret. The reference stores
    // two distinct AES-GCM nonces. None of these three values should share
    // bytes with each other — that would mean an HKDF salt or GCM nonce is
    // being double-purposed.
    final wrapped = _b64Decode(ref.encryptedKey);
    final ephPub = wrapped.sublist(0, 32);
    final nonces = _parseNonces(ref.nonce);

    expect(nonces.contentNonce.length, 12);
    expect(nonces.wrapNonce.length, 12);
    expect(
      nonces.contentNonce,
      isNot(equals(nonces.wrapNonce)),
      reason: 'content-nonce and wrap-nonce must be independent random values',
    );
    expect(
      nonces.contentNonce,
      isNot(equals(ephPub.sublist(0, 12))),
      reason: 'content-nonce must not equal the first 12 bytes of the '
          'ephemeral pub — that would double-purpose the HKDF salt.',
    );
    expect(
      nonces.wrapNonce,
      isNot(equals(ephPub.sublist(0, 12))),
      reason: 'wrap-nonce must not equal the first 12 bytes of the '
          'ephemeral pub — that would double-purpose the HKDF salt.',
    );
  });

  test('two attachment wraps produce independent ephemeral pub and nonces',
      () async {
    final sender = LibCryptoAdapter();
    final recipient = LibCryptoAdapter();
    final recipientId =
        await recipient.identity.generateDeviceIdentity('device-bob');

    final bundle = KeyBundle(
      userId: 'bob',
      deviceId: 'device-bob',
      handle: 'bob',
      identityPublicKey: recipientId.identityPublicKey,
      signedPrekeyBundle: recipientId.signedPrekeyBundle,
    );

    final a = await sender.messaging.encryptAttachment(
      attachmentId: 'att-a',
      storageKey: 'blob://att-a',
      contentType: 'application/octet-stream',
      plaintext: List<int>.generate(32, (i) => i),
      recipientBundle: bundle,
    );
    final b = await sender.messaging.encryptAttachment(
      attachmentId: 'att-b',
      storageKey: 'blob://att-b',
      contentType: 'application/octet-stream',
      plaintext: List<int>.generate(32, (i) => i),
      recipientBundle: bundle,
    );

    final aEph = _b64Decode(a.reference.encryptedKey).sublist(0, 32);
    final bEph = _b64Decode(b.reference.encryptedKey).sublist(0, 32);
    expect(aEph, isNot(equals(bEph)));
    expect(a.reference.nonce, isNot(equals(b.reference.nonce)));
    expect(a.reference.encryptedKey, isNot(equals(b.reference.encryptedKey)));
    // Even with identical plaintext, the ciphertexts must differ because the
    // content key and nonce are fresh per attachment.
    expect(a.ciphertext, isNot(equals(b.ciphertext)));
  });
}
