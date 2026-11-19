import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/crypto/libsignal_bridge_adapter.dart';
import 'package:veil_mobile/src/core/crypto/message_padding.dart';
import 'package:veil_mobile/src/core/crypto/payload/inner_payload.dart';

import 'support/crypto_harness.dart';

// Attachment pointer model (audit PoC S6): the key, digest, size and type
// travel only inside the authenticated payload; the outer envelope carries
// just an id the server needs for blob lifecycle, and is never trusted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const conversationId = 'conv-attachment';
  const unusedBundle = KeyBundle(userId: '', deviceId: '', handle: '', identityPublicKey: '', signedPrekeyBundle: '');
  const graftedReference = AttachmentReference(
    attachmentId: 'server-chosen',
    storageKey: 'server/evil.bin',
    contentType: 'application/pdf',
    sizeBytes: 1,
    sha256: 'x',
    encryptedKey: 'x',
    nonce: 'a.b',
  );

  Future<AttachmentCipher> encrypt(LibCryptoAdapter adapter, List<int> plaintext, {String id = 'att-1'}) =>
      adapter.messaging.encryptAttachment(
        attachmentId: id,
        storageKey: 'blob://$id',
        contentType: 'image/png',
        plaintext: plaintext,
        recipientBundle: unusedBundle,
      );

  test('outer attachment on text message ignored (S6) in lib and libsignal adapters', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    final text = await send(alice, bob, 'just text', conversationId: conversationId);
    final grafted = copyEnvelope(text, attachment: graftedReference);
    final lib = await receive(bob, grafted);
    expect(lib.status, DecryptStatus.ok);
    expect(lib.body, 'just text');
    expect(lib.attachment, isNull);

    const channel = MethodChannel(kLibsignalChannelName);
    final plaintext = MessagePadding.pad(const InnerPayload(body: 'just text', kind: MessageKind.text).encode());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => {'plaintext': b64uEncode(plaintext)},
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );
    final bridged = await LibsignalBridgeAdapter().messaging.decryptMessage(const CryptoEnvelope(
          version: kLibsignalEnvelopeVersion,
          conversationId: conversationId,
          senderDeviceId: 'device-alice',
          recipientUserId: 'user-bob',
          ciphertext: 'opaque',
          nonce: 'signal',
          messageKind: MessageKind.text,
          attachment: graftedReference,
        ));
    expect(bridged.status, DecryptStatus.ok);
    expect(bridged.body, 'just text');
    expect(bridged.attachment, isNull);
  });

  test('blob size is a Padme bucket', () async {
    final adapter = LibCryptoAdapter();
    for (final length in [0, 1, 7, 100, 1000, 4097, 70000]) {
      final plaintext = List<int>.generate(length, (i) => (i * 7 + 3) & 0xff);
      final cipher = await encrypt(adapter, plaintext);
      expect(cipher.ciphertext.length - 16, MessagePadding.padmeLength(length + 1), reason: 'length $length');
      expect(cipher.reference.sizeBytes, length);
      expect(cipher.reference.algorithmHint, 'aes256gcm-v2');
      final roundTrip = await adapter.messaging.decryptAttachment(
        reference: cipher.reference,
        ciphertext: cipher.ciphertext,
        localIdentityPrivateRef: '',
      );
      expect(roundTrip, plaintext);
    }
  });

  test('digest mismatch fails', () async {
    final adapter = LibCryptoAdapter();
    final cipher = await encrypt(adapter, List<int>.generate(256, (i) => i));
    Matcher stateError(String text) => throwsA(isA<StateError>().having((e) => e.message, 'message', contains(text)));

    final flipped = List<int>.of(cipher.ciphertext)..[10] ^= 1;
    await expectLater(
      adapter.messaging
          .decryptAttachment(reference: cipher.reference, ciphertext: flipped, localIdentityPrivateRef: ''),
      stateError('hash does not match'),
    );
    final wrongDigest = cipher.reference.copyWith(sha256: b64uEncode(List<int>.filled(32, 7)));
    await expectLater(
      adapter.messaging
          .decryptAttachment(reference: wrongDigest, ciphertext: cipher.ciphertext, localIdentityPrivateRef: ''),
      stateError('hash does not match'),
    );
    // The blob is bound to its attachment id even when the digest matches.
    final renamed = cipher.reference.copyWith(attachmentId: 'att-other');
    await expectLater(
      adapter.messaging
          .decryptAttachment(reference: renamed, ciphertext: cipher.ciphertext, localIdentityPrivateRef: ''),
      stateError('failed AES-GCM authentication'),
    );
  });

  test('outer pointer is attachmentId only', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    await bootstrap(alice, bob, conversationId: conversationId);
    final cipher = await encrypt(alice.adapter, List<int>.generate(500, (i) => i % 251), id: 'att-pointer');
    final envelope = await send(alice, bob, 'Encrypted attachment',
        conversationId: conversationId, kind: MessageKind.file, attachment: cipher.reference);

    final wire = alice.adapter.envelopeCodec.encodeApiEnvelope(envelope);
    expect(wire['attachment'], {'attachmentId': 'att-pointer'});
    final bridgeWire = LibsignalBridgeAdapter().envelopeCodec.encodeApiEnvelope(envelope);
    expect(bridgeWire['attachment'], {'attachmentId': 'att-pointer'});

    // Legacy servers may still relay extra fields; they are parsed but never
    // reach the decrypted message.
    final relayed = bob.adapter.envelopeCodec.decodeApiEnvelope({
      ...wire,
      'attachment': {'attachmentId': 'att-pointer', 'storageKey': 'server/other', 'sizeBytes': 9},
    });
    expect(relayed.attachment!.attachmentId, 'att-pointer');
    final received = await receive(bob, relayed);
    expect(received.status, DecryptStatus.ok);
    final pointer = received.attachment!;
    expect(pointer.attachmentId, 'att-pointer');
    expect(pointer.encryptedKey, cipher.reference.encryptedKey);
    expect(pointer.nonce, cipher.reference.nonce);
    expect(pointer.sha256, cipher.reference.sha256);
    expect(pointer.sizeBytes, 500);
    expect(pointer.contentType, 'image/png');
    expect(pointer.storageKey, isEmpty);
    final plaintext = await bob.adapter.messaging.decryptAttachment(
      reference: pointer,
      ciphertext: cipher.ciphertext,
      localIdentityPrivateRef: bob.identity.identityPrivateKeyRef,
    );
    expect(plaintext, List<int>.generate(500, (i) => i % 251));
  });
}
