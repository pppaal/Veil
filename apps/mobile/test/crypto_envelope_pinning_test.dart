import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

// Pins the production crypto wire format against silent drift. If these tests
// fail because the envelope version, adapter id, byte layout, or JSON shape
// changed, that change MUST be documented as a spec revision in
// docs/crypto-envelope-spec.md and given a new envelope version string so
// existing peers fail cleanly rather than silently mis-decrypt.
void main() {
  group('LibCryptoAdapter constants', () {
    test('adapter id is frozen', () {
      expect(LibCryptoAdapter().adapterId, 'lib-x25519-aes256gcm-v2');
    });

    test('envelope version is frozen', () {
      expect(
        LibCryptoAdapter().envelopeCodec.defaultEnvelopeVersion,
        'veil-envelope-v1',
      );
    });

    test('attachment algorithm hint is frozen', () {
      expect(
        LibCryptoAdapter().envelopeCodec.defaultAttachmentWrapAlgorithmHint,
        'x25519-aes256gcm',
      );
    });
  });

  group('Envelope binary frame', () {
    Future<CryptoEnvelope> buildEnvelope({
      required LibCryptoAdapter alice,
      required LibCryptoAdapter bob,
      required String conversationId,
      required String body,
    }) async {
      final bobIdentity =
          await bob.identity.generateDeviceIdentity('device-bob');
      await alice.identity.generateDeviceIdentity('device-alice');
      await alice.sessions.bootstrapSession(
        SessionBootstrapRequest(
          conversationId: conversationId,
          localDeviceId: 'device-alice',
          localUserId: 'user-alice',
          remoteUserId: 'user-bob',
          remoteDeviceId: 'device-bob',
          remoteIdentityPublicKey: bobIdentity.identityPublicKey,
          remoteSignedPrekeyBundle: bobIdentity.signedPrekeyBundle,
        ),
      );
      return alice.messaging.encryptMessage(
        conversationId: conversationId,
        senderDeviceId: 'device-alice',
        recipientUserId: 'user-bob',
        body: body,
        messageKind: MessageKind.text,
        recipientBundle: KeyBundle(
          userId: 'user-bob',
          deviceId: 'device-bob',
          handle: 'bob',
          identityPublicKey: bobIdentity.identityPublicKey,
          signedPrekeyBundle: bobIdentity.signedPrekeyBundle,
        ),
      );
    }

    test('nonce is exactly 12 base64url-decoded bytes', () async {
      final envelope = await buildEnvelope(
        alice: LibCryptoAdapter(),
        bob: LibCryptoAdapter(),
        conversationId: 'conv-nonce',
        body: 'hello',
      );
      final nonceBytes = _b64UrlDecode(envelope.nonce);
      expect(nonceBytes.length, 12);
    });

    test('ciphertext frame has minimum 52 bytes (ephPub+counter+mac)',
        () async {
      final envelope = await buildEnvelope(
        alice: LibCryptoAdapter(),
        bob: LibCryptoAdapter(),
        conversationId: 'conv-minframe',
        body: '',
      );
      final frame = _b64UrlDecode(envelope.ciphertext);
      expect(frame.length, greaterThanOrEqualTo(52));
    });

    test('counter at bytes [32..36] increments per message', () async {
      final alice = LibCryptoAdapter();
      final bob = LibCryptoAdapter();
      const conversationId = 'conv-counter';

      final first = await buildEnvelope(
        alice: alice,
        bob: bob,
        conversationId: conversationId,
        body: 'one',
      );

      final bobIdentity2 = KeyBundle(
        userId: 'user-bob',
        deviceId: 'device-bob',
        handle: 'bob',
        identityPublicKey: '',
        signedPrekeyBundle: '',
      );
      final second = await alice.messaging.encryptMessage(
        conversationId: conversationId,
        senderDeviceId: 'device-alice',
        recipientUserId: 'user-bob',
        body: 'two',
        messageKind: MessageKind.text,
        recipientBundle: bobIdentity2,
      );

      expect(_readCounter(first), 0);
      expect(_readCounter(second), 1);
    });

    test('counter is big-endian uint32', () async {
      final envelope = await buildEnvelope(
        alice: LibCryptoAdapter(),
        bob: LibCryptoAdapter(),
        conversationId: 'conv-be',
        body: 'x',
      );
      final frame = _b64UrlDecode(envelope.ciphertext);
      // First message's counter is 0 → all four counter bytes MUST be 0x00.
      // If encoding were little-endian of a larger sentinel we'd see non-zero
      // bytes; if the field moved, this check would drift.
      expect(frame.sublist(32, 36), [0, 0, 0, 0]);
    });

    test('sender ratchet public key occupies the first 32 bytes', () async {
      final alice = LibCryptoAdapter();
      final bob = LibCryptoAdapter();
      final envelope = await buildEnvelope(
        alice: alice,
        bob: bob,
        conversationId: 'conv-ephpub',
        body: 'y',
      );

      final extracted = (alice.envelopeCodec as InboundEnvelopeInspector)
          .extractSenderEphemeralPublicKey(envelope);
      expect(extracted, isNotNull);
      expect(extracted!.length, 32);

      final frame = _b64UrlDecode(envelope.ciphertext);
      expect(frame.sublist(0, 32), extracted);
    });
  });

  group('Envelope JSON shape', () {
    test('omits expiresAt and attachment when absent', () async {
      final alice = LibCryptoAdapter();
      final bob = LibCryptoAdapter();
      final bobIdentity =
          await bob.identity.generateDeviceIdentity('device-bob');
      await alice.sessions.bootstrapSession(
        SessionBootstrapRequest(
          conversationId: 'conv-json-shape',
          localDeviceId: 'device-alice',
          localUserId: 'user-alice',
          remoteUserId: 'user-bob',
          remoteDeviceId: 'device-bob',
          remoteIdentityPublicKey: bobIdentity.identityPublicKey,
          remoteSignedPrekeyBundle: bobIdentity.signedPrekeyBundle,
        ),
      );
      final envelope = await alice.messaging.encryptMessage(
        conversationId: 'conv-json-shape',
        senderDeviceId: 'device-alice',
        recipientUserId: 'user-bob',
        body: 'no-optionals',
        messageKind: MessageKind.text,
        recipientBundle: KeyBundle(
          userId: 'user-bob',
          deviceId: 'device-bob',
          handle: 'bob',
          identityPublicKey: bobIdentity.identityPublicKey,
          signedPrekeyBundle: bobIdentity.signedPrekeyBundle,
        ),
      );

      final json = alice.envelopeCodec.encodeApiEnvelope(envelope);
      expect(json.containsKey('expiresAt'), isFalse);
      expect(json.containsKey('attachment'), isFalse);
      expect(json['version'], 'veil-envelope-v1');
      expect(json['messageType'], 'text');
    });
  });
}

Uint8List _b64UrlDecode(String value) {
  final padded = value.padRight(
    value.length + ((4 - value.length % 4) % 4),
    '=',
  );
  return Uint8List.fromList(base64Url.decode(padded));
}

int _readCounter(CryptoEnvelope envelope) {
  final frame = _b64UrlDecode(envelope.ciphertext);
  final view = ByteData.view(
    Uint8List.fromList(frame.sublist(32, 36)).buffer,
  );
  return view.getUint32(0, Endian.big);
}
