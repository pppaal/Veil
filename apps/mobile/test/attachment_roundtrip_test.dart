import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

// End-to-end regression test for attachment encrypt → decrypt.
//
// Pins that ciphertext produced by `encryptAttachment` is decryptable by the
// recipient holding the matching identity private ref, and that tampering
// with either the ciphertext or the reference is caught before producing
// garbage plaintext.

void main() {
  Future<(KeyBundle bundle, DeviceIdentityMaterial identity, LibCryptoAdapter adapter)>
      makeRecipient(String deviceId) async {
    final adapter = LibCryptoAdapter();
    final id = await adapter.identity.generateDeviceIdentity(deviceId);
    final bundle = KeyBundle(
      userId: 'user-$deviceId',
      deviceId: deviceId,
      handle: deviceId,
      identityPublicKey: id.identityPublicKey,
      signedPrekeyBundle: id.signedPrekeyBundle,
    );
    return (bundle, id, adapter);
  }

  test('roundtrip: recipient recovers exact plaintext bytes', () async {
    final sender = LibCryptoAdapter();
    final (bundle, identity, recipient) = await makeRecipient('device-bob');

    final plaintext = List<int>.generate(1024, (i) => (i * 31 + 7) & 0xff);

    final cipher = await sender.messaging.encryptAttachment(
      attachmentId: 'att-roundtrip',
      storageKey: 'blob://att-roundtrip',
      contentType: 'application/octet-stream',
      plaintext: plaintext,
      recipientBundle: bundle,
    );

    final recovered = await recipient.messaging.decryptAttachment(
      reference: cipher.reference,
      ciphertext: cipher.ciphertext,
      localIdentityPrivateRef: identity.identityPrivateKeyRef,
    );

    expect(recovered, equals(plaintext));
    // Reference's size/sha256 describe the ciphertext — defense-in-depth
    // against a server swapping blobs under a valid reference.
    expect(cipher.reference.sizeBytes, equals(cipher.ciphertext.length));
  });

  test('roundtrip: empty plaintext is a valid round-trip', () async {
    final sender = LibCryptoAdapter();
    final (bundle, identity, recipient) = await makeRecipient('device-carol');

    final cipher = await sender.messaging.encryptAttachment(
      attachmentId: 'att-empty',
      storageKey: 'blob://att-empty',
      contentType: 'application/octet-stream',
      plaintext: const <int>[],
      recipientBundle: bundle,
    );
    final recovered = await recipient.messaging.decryptAttachment(
      reference: cipher.reference,
      ciphertext: cipher.ciphertext,
      localIdentityPrivateRef: identity.identityPrivateKeyRef,
    );
    expect(recovered, equals(<int>[]));
  });

  test('tampering with the ciphertext body fails with a precise error',
      () async {
    final sender = LibCryptoAdapter();
    final (bundle, identity, recipient) = await makeRecipient('device-dave');

    final cipher = await sender.messaging.encryptAttachment(
      attachmentId: 'att-tamper',
      storageKey: 'blob://att-tamper',
      contentType: 'application/octet-stream',
      plaintext: List<int>.generate(128, (i) => i),
      recipientBundle: bundle,
    );

    // Flip a bit deep in the ciphertext body. The sha256 pre-check should
    // catch this before GCM even gets a chance to fail.
    final mutated = List<int>.from(cipher.ciphertext);
    mutated[10] ^= 0x01;

    expect(
      () => recipient.messaging.decryptAttachment(
        reference: cipher.reference,
        ciphertext: mutated,
        localIdentityPrivateRef: identity.identityPrivateKeyRef,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('hash does not match'),
        ),
      ),
    );
  });

  test('wrong recipient identity fails to unwrap the content key', () async {
    final sender = LibCryptoAdapter();
    final (bundle, _, _) = await makeRecipient('device-intended');
    // Second recipient whose identity was NOT used to wrap the key.
    final (_, wrongIdentity, wrongRecipient) =
        await makeRecipient('device-wrong');

    final cipher = await sender.messaging.encryptAttachment(
      attachmentId: 'att-wrong-recipient',
      storageKey: 'blob://att-wrong-recipient',
      contentType: 'application/octet-stream',
      plaintext: List<int>.generate(64, (i) => i * 3),
      recipientBundle: bundle,
    );

    expect(
      () => wrongRecipient.messaging.decryptAttachment(
        reference: cipher.reference,
        ciphertext: cipher.ciphertext,
        localIdentityPrivateRef: wrongIdentity.identityPrivateKeyRef,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Wrapped attachment key failed authentication'),
        ),
      ),
    );
  });

  test('rejects legacy single-nonce reference format', () async {
    final sender = LibCryptoAdapter();
    final (bundle, identity, recipient) = await makeRecipient('device-legacy');

    final cipher = await sender.messaging.encryptAttachment(
      attachmentId: 'att-legacy',
      storageKey: 'blob://att-legacy',
      contentType: 'application/octet-stream',
      plaintext: const <int>[1, 2, 3],
      recipientBundle: bundle,
    );

    // Strip the second nonce chunk so the reference looks like the old format
    // that only stored a single nonce.
    final legacyNonce = cipher.reference.nonce.split('.').first;
    final legacyRef = cipher.reference.copyWith(nonce: legacyNonce);

    expect(
      () => recipient.messaging.decryptAttachment(
        reference: legacyRef,
        ciphertext: cipher.ciphertext,
        localIdentityPrivateRef: identity.identityPrivateKeyRef,
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('legacy nonce format'),
        ),
      ),
    );
  });
}
