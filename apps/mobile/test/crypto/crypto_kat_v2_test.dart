import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/crypto/message_padding.dart';
import 'package:veil_mobile/src/core/crypto/payload/inner_payload.dart';
import 'package:veil_mobile/src/core/crypto/ratchet/frame_codec.dart';
import 'package:veil_mobile/src/core/crypto/x3dh/x3dh_handshake.dart';

import 'support/crypto_harness.dart';

// Replays packages/shared/test-vectors/crypto-kat.json `protocolV2` (made by
// the independent node:crypto reference in scripts/crypto-test-vectors.mjs)
// through the real adapter with a scripted random source. Every byte the
// adapter emits must match; this is what pins the wire format for the web
// port.
void main() {
  final vectors = (json.decode(File('../../packages/shared/test-vectors/crypto-kat.json').readAsStringSync())
      as Map<String, dynamic>)['vectors']['protocolV2'] as Map<String, dynamic>;
  final bundle = vectors['bundle'] as Map<String, dynamic>;
  final alice = vectors['alice'] as Map<String, dynamic>;
  final x3dh = vectors['x3dh'] as Map<String, dynamic>;
  final oneTime = vectors['oneTimePrekey'] as Map<String, dynamic>;
  final sendSteps = vectors['sendSteps'] as Map<String, dynamic>;
  final frames = vectors['frames'] as Map<String, dynamic>;
  final attachment = vectors['attachment'] as Map<String, dynamic>;
  final messages = {
    for (final m in (frames['messages'] as List<dynamic>).cast<Map<String, dynamic>>()) m['label'] as String: m,
  };
  final conversationId = frames['conversationId'] as String;
  List<int> hex(Object? value) => [
        for (var i = 0; i < (value as String).length; i += 2) int.parse(value.substring(i, i + 2), radix: 16),
      ];
  DateTime at(Object? ms) => DateTime.fromMillisecondsSinceEpoch(ms as int, isUtc: true);

  test('padme table', () {
    for (final row in (vectors['padme'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      expect(MessagePadding.padmeLength(row['n'] as int), row['padme'], reason: 'n=${row['n']}');
    }
  });

  test('bundle v2, identity key and one-time prekey', () async {
    final bob = LibCryptoAdapter(
      random: ScriptedRandomSource(
          [hex(bundle['identitySeed']), hex(bundle['ikxPrivate']), hex(bundle['spkPrivate']), hex(oneTime['private'])]),
      clock: () => at(bundle['spkTs']),
    );
    final identity = await bob.identity.generateDeviceIdentity('device-b-0002');
    expect(identity.identityPublicKey, bundle['identityPublicKey']);
    expect(identity.signedPrekeyBundle, bundle['signedPrekeyBundle']);
    final prekeys = await bob.generateOneTimePrekeys(count: 1);
    expect(prekeys.single.keyId, oneTime['keyId']);
    expect(prekeys.single.publicKey, oneTime['publicKey']);
  });

  test('X3DH shared key, associated data and PreKey header', () async {
    final keys = await deriveInitiatorKeys(
      identityEd25519: hex(alice['identityPublic']),
      identityX25519Private: hex(alice['ikxPrivate']),
      identityX25519: hex(alice['ikxPublic']),
      ephemeralPrivate: hex(x3dh['ephemeralPrivate']),
      remoteIdentityEd25519: hex(bundle['identityPublic']),
      remoteIdentityX25519: hex(bundle['ikxPublic']),
      remoteSignedPrekey: hex(bundle['spkPublic']),
      remoteOneTimePrekey: hex(oneTime['public']),
    );
    expect(hexEncode(keys.sharedKey), x3dh['sharedKey']);
    expect(hexEncode(keys.associatedData), x3dh['associatedData']);
    final header = PreKeyHeader.decode(hex(x3dh['preKeyHeader']));
    expect(hexEncode(header.encode()), x3dh['preKeyHeader']);
    expect(hexEncode(header.baseKey), x3dh['ephemeralPublic']);
  });

  test('attachment pointer cipher', () async {
    final adapter = LibCryptoAdapter(random: ScriptedRandomSource([hex(attachment['key']), hex(attachment['nonce'])]));
    final pointer = attachment['pointer'] as Map<String, dynamic>;
    final cipher = await adapter.messaging.encryptAttachment(
      attachmentId: attachment['attachmentId'] as String,
      storageKey: 'blob://kat',
      contentType: pointer['ct'] as String,
      plaintext: hex(attachment['plaintextHex']),
      recipientBundle:
          const KeyBundle(userId: '', deviceId: '', handle: '', identityPublicKey: '', signedPrekeyBundle: ''),
    );
    expect(hexEncode(cipher.ciphertext), attachment['blob']);
    expect(cipher.reference.encryptedKey, pointer['ck']);
    expect(cipher.reference.nonce, pointer['n']);
    expect(cipher.reference.sha256, pointer['d']);
    expect(cipher.reference.sizeBytes, pointer['sz']);
    expect(cipher.reference.algorithmHint, pointer['alg']);
  });

  test('full transcript: PreKey frames, a turn, and a PN straggler', () async {
    final a0 = messages['A0']!;
    final a1 = messages['A1']!;
    final b0 = messages['B0']!;
    final a2 = messages['A2']!;
    Map<String, dynamic> payloadOf(Map<String, dynamic> vector) =>
        json.decode(vector['innerPayloadJson'] as String) as Map<String, dynamic>;

    final bobAdapter = LibCryptoAdapter(
      random: ScriptedRandomSource([
        hex(bundle['identitySeed']),
        hex(bundle['ikxPrivate']),
        hex(bundle['spkPrivate']),
        hex(oneTime['private']),
        hex(sendSteps['bob']['ratchetPrivate']),
        hex(b0['nonce']),
      ]),
      clock: () => at(bundle['spkTs']),
    );
    final aliceAdapter = LibCryptoAdapter(
      random: ScriptedRandomSource([
        hex(alice['identitySeed']),
        hex(alice['ikxPrivate']),
        hex(alice['spkPrivate']),
        hex(x3dh['ephemeralPrivate']),
        hex(vectors['ratchetInit']['aliceRatchetPrivate']),
        hex(a0['nonce']),
        hex(a1['nonce']),
        hex(sendSteps['alice']['ratchetPrivate']),
        hex(a2['nonce']),
      ]),
      clock: () => at(alice['clockMs']),
    );
    final bob = Party('b-0002', bobAdapter, await bobAdapter.identity.generateDeviceIdentity('device-b-0002'));
    final prekey = (await bobAdapter.generateOneTimePrekeys(count: 1)).single;
    final aliceParty =
        Party('a-0001', aliceAdapter, await aliceAdapter.identity.generateDeviceIdentity('device-a-0001'));
    expect(aliceParty.deviceId, frames['aliceDeviceId']);
    expect(bob.deviceId, frames['bobDeviceId']);

    await bootstrap(aliceParty, bob, conversationId: conversationId, oneTimePrekey: prekey);

    void expectFrame(CryptoEnvelope envelope, Map<String, dynamic> vector) {
      expect(envelope.version, envelopeVersionV2);
      expect(envelope.ciphertext, vector['envelopeCiphertext'], reason: '${vector['label']} frame');
      expect(envelope.nonce, vector['envelopeNonce'], reason: '${vector['label']} nonce');
      expect(hexEncode(frameOf(envelope).header), vector['header']);
    }

    final a0Expiry = at(payloadOf(a0)['x']);
    final envA0 =
        await send(aliceParty, bob, payloadOf(a0)['b'] as String, conversationId: conversationId, expiresAt: a0Expiry);
    expectFrame(envA0, a0);
    final envA1 = await send(aliceParty, bob, payloadOf(a1)['b'] as String, conversationId: conversationId);
    expectFrame(envA1, a1);

    final gotA0 = await receive(bob, envA0);
    expect(gotA0.status, DecryptStatus.ok);
    expect(gotA0.body, payloadOf(a0)['b']);
    expect(gotA0.expiresAt!.isAtSameMomentAs(a0Expiry), isTrue);

    final envB0 = await send(bob, aliceParty, payloadOf(b0)['b'] as String, conversationId: conversationId);
    expectFrame(envB0, b0);
    expect((await receive(aliceParty, envB0)).body, payloadOf(b0)['b']);

    final pointer =
        InnerPayload.decode(utf8.encode(a2['innerPayloadJson'] as String), fallbackKind: MessageKind.text).attachment!;
    expect(
      utf8.decode(
          InnerPayload(body: payloadOf(a2)['b'] as String, kind: MessageKind.file, attachment: pointer).encode()),
      a2['innerPayloadJson'],
    );
    final envA2 = await send(aliceParty, bob, payloadOf(a2)['b'] as String,
        conversationId: conversationId, kind: MessageKind.file, attachment: pointer);
    expectFrame(envA2, a2);

    expect(frames['deliveryOrderToBob'], ['A0', 'A2', 'A1']);
    final gotA2 = await receive(bob, envA2);
    expect(gotA2.status, DecryptStatus.ok);
    expect(gotA2.attachment!.encryptedKey, attachment['pointer']['ck']);
    final gotA1 = await receive(bob, envA1);
    expect(gotA1.status, DecryptStatus.ok);
    expect(gotA1.body, payloadOf(a1)['b']);
  });

  test('AAD v4 layout', () {
    final a0 = messages['A0']!;
    final aad = buildFrameAadV4(
      version: envelopeVersionV2,
      conversationId: conversationId,
      senderDeviceId: a0['senderDeviceId'] as String,
      messageKind: a0['messageKind'] as String,
      header: hex(a0['header']),
      associatedData: hex(x3dh['associatedData']),
    );
    expect(hexEncode(aad), a0['aad']);
    expect(hexEncode(MessagePadding.pad(utf8.encode(a0['innerPayloadJson'] as String))), a0['paddedPlaintext']);
  });
}
