import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

// Regression test for attachment key/nonce hygiene.
//
// Attachments are no longer wrapped to the recipient's identity key: each
// blob gets its own random AES-256-GCM key and nonce, carried inside the
// ratchet-encrypted payload. A (key, nonce) pair reused across blobs would
// leak plaintext and break integrity under GCM, so these tests pin that
// every encryption draws fresh, correctly sized, independent values.
void main() {
  const unusedBundle = KeyBundle(userId: '', deviceId: '', handle: '', identityPublicKey: '', signedPrekeyBundle: '');

  Future<AttachmentCipher> encrypt(LibCryptoAdapter sender, String id) => sender.messaging.encryptAttachment(
        attachmentId: id,
        storageKey: 'blob://$id',
        contentType: 'application/octet-stream',
        plaintext: List<int>.generate(64, (i) => i),
        recipientBundle: unusedBundle,
      );

  test('attachment key and nonce are well-formed and distinct', () async {
    final ref = (await encrypt(LibCryptoAdapter(), 'att-1')).reference;
    final key = b64uDecode(ref.encryptedKey);
    final nonce = b64uDecode(ref.nonce);

    expect(key, hasLength(32));
    expect(nonce, hasLength(12));
    expect(ref.nonce.contains('.'), isFalse, reason: 'a single nonce: nothing is wrapped any more');
    expect(nonce, isNot(equals(key.sublist(0, 12))), reason: 'key and nonce must be independent draws');
    expect(ref.algorithmHint, 'aes256gcm-v2');
  });

  test('two attachments get independent keys, nonces and ciphertexts', () async {
    final sender = LibCryptoAdapter();
    final a = await encrypt(sender, 'att-a');
    final b = await encrypt(sender, 'att-b');

    expect(a.reference.encryptedKey, isNot(equals(b.reference.encryptedKey)));
    expect(a.reference.nonce, isNot(equals(b.reference.nonce)));
    expect(a.reference.sha256, isNot(equals(b.reference.sha256)));
    // Identical plaintext, yet the blobs differ: fresh key and nonce each.
    expect(a.ciphertext, isNot(equals(b.ciphertext)));
  });
}
