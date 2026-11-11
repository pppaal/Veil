import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

import 'crypto/support/crypto_harness.dart';

// End-to-end regression test for attachment encrypt → decrypt.
//
// Pins that the blob produced by `encryptAttachment` opens with the
// reference that travels inside the encrypted message, that tampering with
// the blob is caught before producing garbage plaintext, and that
// references in the retired wrap-to-identity format still open for their
// recipient (and only for them).
void main() {
  const unusedBundle = KeyBundle(userId: '', deviceId: '', handle: '', identityPublicKey: '', signedPrekeyBundle: '');

  Future<AttachmentCipher> encrypt(LibCryptoAdapter sender, String id, List<int> plaintext) =>
      sender.messaging.encryptAttachment(
        attachmentId: id,
        storageKey: 'blob://$id',
        contentType: 'application/octet-stream',
        plaintext: plaintext,
        recipientBundle: unusedBundle,
      );

  test('roundtrip: recipient recovers exact plaintext bytes', () async {
    final sender = LibCryptoAdapter();
    final recipient = LibCryptoAdapter();
    final plaintext = List<int>.generate(1024, (i) => (i * 31 + 7) & 0xff);

    final cipher = await encrypt(sender, 'att-roundtrip', plaintext);
    final recovered = await recipient.messaging.decryptAttachment(
      reference: cipher.reference,
      ciphertext: cipher.ciphertext,
      localIdentityPrivateRef: '',
    );

    expect(recovered, equals(plaintext));
    // The authenticated reference reports the plaintext size; the blob is
    // padded so its length only reveals a Padmé bucket.
    expect(cipher.reference.sizeBytes, plaintext.length);
    expect(cipher.ciphertext.length, greaterThan(plaintext.length));
  });

  test('roundtrip: empty plaintext is a valid round-trip', () async {
    final sender = LibCryptoAdapter();
    final cipher = await encrypt(sender, 'att-empty', const <int>[]);
    final recovered = await LibCryptoAdapter().messaging.decryptAttachment(
          reference: cipher.reference,
          ciphertext: cipher.ciphertext,
          localIdentityPrivateRef: '',
        );
    expect(recovered, equals(<int>[]));
  });

  test('tampering with the ciphertext body fails with a precise error', () async {
    final cipher = await encrypt(LibCryptoAdapter(), 'att-tamper', List<int>.generate(128, (i) => i));
    final mutated = List<int>.from(cipher.ciphertext)..[10] ^= 0x01;

    expect(
      () => LibCryptoAdapter().messaging.decryptAttachment(
            reference: cipher.reference,
            ciphertext: mutated,
            localIdentityPrivateRef: '',
          ),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('hash does not match'))),
    );
  });

  test('legacy wrapped reference still decrypts for its recipient only', () async {
    final intended = await createParty('intended');
    final wrong = await createParty('wrong');
    final plaintext = List<int>.generate(64, (i) => i * 3);
    final legacy = await createLegacyWrappedAttachment(
      attachmentId: 'att-legacy',
      plaintext: plaintext,
      recipient: intended.bundle,
    );

    final recovered = await intended.adapter.messaging.decryptAttachment(
      reference: legacy.reference,
      ciphertext: legacy.ciphertext,
      localIdentityPrivateRef: intended.identity.identityPrivateKeyRef,
    );
    expect(recovered, plaintext);

    expect(
      () => wrong.adapter.messaging.decryptAttachment(
        reference: legacy.reference,
        ciphertext: legacy.ciphertext,
        localIdentityPrivateRef: wrong.identity.identityPrivateKeyRef,
      ),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('Wrapped attachment key failed authentication'),
      )),
    );
  });

  test('rejects legacy single-nonce reference format', () async {
    final recipient = await createParty('legacy');
    final legacy = await createLegacyWrappedAttachment(
      attachmentId: 'att-legacy-nonce',
      plaintext: const <int>[1, 2, 3],
      recipient: recipient.bundle,
    );
    // Strip the second nonce chunk: the pre-fix format stored only one.
    final legacyRef = legacy.reference.copyWith(nonce: legacy.reference.nonce.split('.').first);

    expect(
      () => recipient.adapter.messaging.decryptAttachment(
        reference: legacyRef,
        ciphertext: legacy.ciphertext,
        localIdentityPrivateRef: recipient.identity.identityPrivateKeyRef,
      ),
      throwsA(isA<StateError>().having((e) => e.message, 'message', contains('legacy nonce format'))),
    );
  });
}
