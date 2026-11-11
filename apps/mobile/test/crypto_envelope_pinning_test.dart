import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

import 'crypto/support/crypto_harness.dart';

// Pins the production crypto wire format against silent drift. If these tests
// fail because the envelope version, adapter id, byte layout, or JSON shape
// changed, that change MUST be documented as a spec revision in
// docs/crypto-envelope-spec.md and given a new envelope version string so
// existing peers fail cleanly rather than silently mis-decrypt.
void main() {
  group('LibCryptoAdapter constants', () {
    test('adapter id is frozen', () {
      expect(LibCryptoAdapter().adapterId, 'lib-x3dh-x25519-aes256gcm-v4');
    });

    test('envelope version is frozen', () {
      expect(LibCryptoAdapter().envelopeCodec.defaultEnvelopeVersion, 'veil-envelope-v2');
    });

    test('attachment algorithm hint is frozen', () {
      expect(LibCryptoAdapter().envelopeCodec.defaultAttachmentWrapAlgorithmHint, 'aes256gcm-v2');
    });
  });

  group('Envelope binary frame (v2)', () {
    const conversationId = 'conv-frame';

    Future<(Party, Party)> establish() async {
      final alice = await createParty('alice');
      final bob = await createParty('bob');
      await bootstrap(alice, bob, conversationId: conversationId);
      return (alice, bob);
    }

    test('nonce is exactly 12 base64url-decoded bytes', () async {
      final (alice, bob) = await establish();
      final envelope = await send(alice, bob, 'hello', conversationId: conversationId);
      expect(b64uDecode(envelope.nonce), hasLength(12));
    });

    test('PreKey frame layout until the first reply, Normal frame after', () async {
      final (alice, bob) = await establish();
      final first = await send(alice, bob, '', conversationId: conversationId);
      final bytes = b64uDecode(first.ciphertext);
      expect(bytes.sublist(0, 2), [0x02, 0x01]);
      // version + type + PreKey header + ratchetPub + PN + N + tag.
      expect(bytes.length, greaterThanOrEqualTo(2 + 168 + 32 + 4 + 4 + 16));
      expect(frameOf(first).header.length, 2 + 168 + 40);

      expect((await receive(bob, first)).isOk, isTrue);
      final reply = await send(bob, alice, '', conversationId: conversationId);
      final replyBytes = b64uDecode(reply.ciphertext);
      expect(replyBytes.sublist(0, 2), [0x02, 0x02]);
      expect(frameOf(reply).header.length, 2 + 40);
      expect(replyBytes.length, greaterThanOrEqualTo(2 + 32 + 4 + 4 + 16));
    });

    test('counter is the big-endian u32 closing the header and increments per message', () async {
      final (alice, bob) = await establish();
      final first = await send(alice, bob, 'one', conversationId: conversationId);
      final second = await send(alice, bob, 'two', conversationId: conversationId);
      final header = frameOf(first).header;
      expect(header.sublist(header.length - 8), [0, 0, 0, 0, 0, 0, 0, 0], reason: 'PN 0, N 0');
      expect(frameOf(first).counter, 0);
      expect(frameOf(second).counter, 1);
      final secondHeader = frameOf(second).header;
      expect(secondHeader.sublist(secondHeader.length - 4), [0, 0, 0, 1]);
    });
  });

  group('Envelope JSON shape', () {
    test('omits expiresAt and attachment when absent', () async {
      final alice = await createParty('alice');
      final bob = await createParty('bob');
      await bootstrap(alice, bob, conversationId: 'conv-json-shape');
      final envelope = await send(alice, bob, 'no-optionals', conversationId: 'conv-json-shape');

      final json = alice.adapter.envelopeCodec.encodeApiEnvelope(envelope);
      expect(json.containsKey('expiresAt'), isFalse);
      expect(json.containsKey('attachment'), isFalse);
      expect(json['version'], 'veil-envelope-v2');
      expect(json['messageType'], 'text');
    });

    test('decoding an envelope without a version reads it as a legacy v1 frame', () {
      final decoded = LibCryptoAdapter().envelopeCodec.decodeApiEnvelope({
        'conversationId': 'c',
        'senderDeviceId': 'd',
        'ciphertext': 'AA',
        'nonce': 'AA',
        'messageType': 'text',
      });
      expect(decoded.version, 'veil-envelope-v1');
    });
  });

  group('Legacy v1 frame', () {
    test('ratchet public key occupies the first 32 bytes, counter the next 4', () async {
      final alice = await createParty('alice');
      final bob = await createLegacyParty('bob');
      await bootstrap(alice, bob, conversationId: 'conv-v1');
      final first = await send(alice, bob, 'y', conversationId: 'conv-v1');
      final second = await send(alice, bob, 'z', conversationId: 'conv-v1');
      expect(first.version, 'veil-envelope-v1');

      final extracted = (bob.adapter.envelopeCodec as InboundEnvelopeInspector).extractSenderEphemeralPublicKey(first);
      final frame = b64uDecode(first.ciphertext);
      expect(extracted, frame.sublist(0, 32));
      expect(frame.sublist(32, 36), [0, 0, 0, 0]);
      expect(b64uDecode(second.ciphertext).sublist(32, 36), [0, 0, 0, 1]);
      expect(frame.length, greaterThanOrEqualTo(52));
    });
  });
}
