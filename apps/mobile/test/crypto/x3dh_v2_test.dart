import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/crypto/ratchet/frame_codec.dart';
import 'package:veil_mobile/src/core/crypto/x3dh/identity_keys.dart';
import 'package:veil_mobile/src/core/crypto/x3dh/x3dh_handshake.dart';

import 'support/crypto_harness.dart';

const _conversationId = 'conv-x3dh';

Map<String, dynamic> _decodeBundle(String bundle) =>
    json.decode(utf8.decode(b64uDecode(bundle))) as Map<String, dynamic>;

String _encodeBundle(Map<String, dynamic> map) => b64uEncode(utf8.encode(json.encode(map)));

/// Rewrites the PreKey header of [envelope]'s frame, keeping everything else.
CryptoEnvelope _withPreKeyHeader(CryptoEnvelope envelope, PreKeyHeader header) {
  final frame = b64uDecode(envelope.ciphertext);
  final forged = concatBytes([frame.sublist(0, 2), header.encode(), frame.sublist(2 + PreKeyHeader.encodedLength)]);
  return copyEnvelope(envelope, ciphertext: b64uEncode(forged));
}

void main() {
  test('forged initiator holding only the public bundle cannot open a session (scenarioUnauthInbound)', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final mallory = await createParty('mallory');
    final recorder = SnapshotRecorder();
    bob.adapter.setSessionPersistence(persister: recorder.call);

    // Mallory holds every public key of Alice and Bob, including Alice's
    // genuine ikxSig, but none of Alice's private keys.
    await bootstrap(mallory, bob, conversationId: _conversationId);
    final forged = await send(mallory, bob, 'hi bob, it is alice (forged)', conversationId: _conversationId);
    final malloryHeader = frameOf(forged).preKey!;
    final aliceBundle = _decodeBundle(alice.identity.signedPrekeyBundle);
    final claimingAlice = PreKeyHeader(
      identityEd25519: b64uDecode(alice.identity.identityPublicKey),
      identityX25519: b64uDecode(aliceBundle['ikx'] as String),
      identityX25519Signature: b64uDecode(aliceBundle['ikxSig'] as String),
      baseKey: malloryHeader.baseKey,
      signedPrekeyId: malloryHeader.signedPrekeyId,
      oneTimePrekeyId: malloryHeader.oneTimePrekeyId,
    );

    final result =
        await receive(bob, copyEnvelope(_withPreKeyHeader(forged, claimingAlice), senderDeviceId: alice.deviceId));
    expect(result.status, DecryptStatus.failed);
    expect(result.body, isNot(contains('forged')));
    expect(bob.adapter.sessions.hasSessionFor(_conversationId), isFalse);
    expect(recorder.writes, isEmpty);

    // Pairing Alice's identity key with Mallory's own X25519 key instead
    // fails the IKx certification outright.
    final mixed = PreKeyHeader(
      identityEd25519: claimingAlice.identityEd25519,
      identityX25519: malloryHeader.identityX25519,
      identityX25519Signature: malloryHeader.identityX25519Signature,
      baseKey: malloryHeader.baseKey,
      signedPrekeyId: malloryHeader.signedPrekeyId,
      oneTimePrekeyId: malloryHeader.oneTimePrekeyId,
    );
    final mixedResult = await receive(bob, _withPreKeyHeader(forged, mixed));
    expect(mixedResult.status, DecryptStatus.failed);
    expect(mixedResult.failureReason, 'bad_ikx_signature');
    expect(bob.adapter.sessions.hasSessionFor(_conversationId), isFalse);
  });

  test('session binds initiator fingerprint (non-empty)', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final recorder = SnapshotRecorder();
    bob.adapter.setSessionPersistence(persister: recorder.call);

    final material = await bootstrap(alice, bob, conversationId: _conversationId);
    expect(
        material.remoteIdentityFingerprint, hash.sha256.convert(b64uDecode(bob.identity.identityPublicKey)).toString());

    final result = await receive(bob, await send(alice, bob, 'hello', conversationId: _conversationId));
    expect(result.status, DecryptStatus.ok);
    final bobState = recorder.latest[_conversationId]!['current'] as Map<String, dynamic>;
    final fingerprint = bobState['remoteIdentityFingerprint'] as String;
    expect(fingerprint, isNotEmpty);
    expect(fingerprint, hash.sha256.convert(b64uDecode(alice.identity.identityPublicKey)).toString());
  });

  test('verifier rejection yields identityRejected and stores nothing', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final recorder = SnapshotRecorder();
    bob.adapter.setSessionPersistence(persister: recorder.call);
    final prekey = (await bob.adapter.generateOneTimePrekeys(count: 1)).single;
    final claims = <RemoteIdentityClaim>[];
    bob.adapter.setRemoteIdentityVerifier((claim) async {
      claims.add(claim);
      return false;
    });

    await bootstrap(alice, bob, conversationId: _conversationId, oneTimePrekey: prekey);
    final envelope = await send(alice, bob, 'pin me', conversationId: _conversationId);
    final rejected = await receive(bob, envelope);

    expect(rejected.status, DecryptStatus.identityRejected);
    expect(rejected.body, isNot('pin me'));
    expect(claims.single.identityKeyEd25519, alice.identity.identityPublicKey);
    expect(claims.single.identityKeyX25519, _decodeBundle(alice.identity.signedPrekeyBundle)['ikx']);
    expect(claims.single.senderDeviceId, alice.deviceId);
    expect(claims.single.conversationId, _conversationId);
    expect(bob.adapter.sessions.hasSessionFor(_conversationId), isFalse);
    expect(recorder.writes, isEmpty);

    // Nothing was consumed: once the identity is approved the same frame
    // (and its one-time prekey) still opens the session.
    bob.adapter.setRemoteIdentityVerifier((_) async => true);
    expect((await receive(bob, envelope)).body, 'pin me');
  });

  test('OPK consumed once; reuse fails closed', () async {
    final alice = await createParty('alice');
    final carol = await createParty('carol');
    final bob = await createParty('bob');
    final prekey = (await bob.adapter.generateOneTimePrekeys(count: 1)).single;

    await bootstrap(alice, bob, conversationId: 'conv-alice', oneTimePrekey: prekey);
    expect(
        (await receive(bob, await send(alice, bob, 'first', conversationId: 'conv-alice'))).status, DecryptStatus.ok);
    // Alice keeps sending PreKey frames until Bob replies; they belong to
    // the session already opened and need no one-time prekey.
    expect((await receive(bob, await send(alice, bob, 'second', conversationId: 'conv-alice'))).body, 'second');

    // A stale directory hands Carol the same one-time prekey.
    await bootstrap(carol, bob, conversationId: 'conv-carol', oneTimePrekey: prekey);
    final reused = await receive(bob, await send(carol, bob, 'reuse', conversationId: 'conv-carol'));
    expect(reused.status, DecryptStatus.failed);
    expect(reused.failureReason, 'opk_unavailable');
    expect(bob.adapter.sessions.hasSessionFor('conv-carol'), isFalse);
  });

  test('two initiators get distinct OPKs and both decrypt', () async {
    final alice = await createParty('alice');
    final carol = await createParty('carol');
    final bob = await createParty('bob');
    final prekeys = await bob.adapter.generateOneTimePrekeys(count: 2);
    expect(prekeys.map((p) => p.keyId).toSet(), hasLength(2));
    expect(prekeys.map((p) => p.publicKey).toSet(), hasLength(2));

    await bootstrap(alice, bob, conversationId: 'conv-alice', oneTimePrekey: prekeys[0]);
    await bootstrap(carol, bob, conversationId: 'conv-carol', oneTimePrekey: prekeys[1]);
    final fromAlice = await send(alice, bob, 'from alice', conversationId: 'conv-alice');
    final fromCarol = await send(carol, bob, 'from carol', conversationId: 'conv-carol');
    expect(frameOf(fromAlice).preKey!.oneTimePrekeyId, prekeys[0].keyId);
    expect(frameOf(fromCarol).preKey!.oneTimePrekeyId, prekeys[1].keyId);

    expect((await receive(bob, fromAlice)).body, 'from alice');
    expect((await receive(bob, fromCarol)).body, 'from carol');
  });

  test('previous SPK decrypts within grace, fails after prune', () async {
    var bobNow = DateTime.utc(2026, 11, 1);
    final initiatorsNow = DateTime.utc(2026, 11, 1);
    final bob = await createParty('bob', clock: () => bobNow);
    final alice = await createParty('alice', clock: () => initiatorsNow);
    final carol = await createParty('carol', clock: () => initiatorsNow);

    // Both initiators fetched Bob's bundle (spkId 1) before he rotated.
    await bootstrap(alice, bob, conversationId: 'conv-alice');
    await bootstrap(carol, bob, conversationId: 'conv-carol');
    final rotation = await bob.adapter.rotateSignedPrekey();
    expect(rotation.spkId, 2);
    expect(rotation.upgradedIdentityPrivateRef, isNull);
    expect(await bob.adapter.currentSignedPrekeyCreatedAt(), bobNow);

    bobNow = bobNow.add(const Duration(days: 1));
    expect(await bob.adapter.pruneSignedPrekeys(), 0);
    final withinGrace = await receive(bob, await send(alice, bob, 'old spk, in grace', conversationId: 'conv-alice'));
    expect(withinGrace.status, DecryptStatus.ok);

    bobNow = bobNow.add(const Duration(days: 14));
    expect(await bob.adapter.pruneSignedPrekeys(), 1);
    final afterPrune = await receive(bob, await send(carol, bob, 'old spk, too late', conversationId: 'conv-carol'));
    expect(afterPrune.status, DecryptStatus.failed);
    expect(afterPrune.failureReason, 'spk_unavailable');

    // The rotated bundle keeps working.
    final dave = await createParty('dave', clock: () => bobNow);
    await bootstrap(dave, bob, conversationId: 'conv-dave', signedPrekeyBundle: rotation.signedPrekeyBundle);
    expect(
        (await receive(bob, await send(dave, bob, 'new spk', conversationId: 'conv-dave'))).status, DecryptStatus.ok);
  });

  test('bad ikxSig/spkSig rejected', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final original = _decodeBundle(bob.identity.signedPrekeyBundle);

    Future<void> expectRejected(Map<String, dynamic> tampered) => expectLater(
          bootstrap(alice, bob, conversationId: _conversationId, signedPrekeyBundle: _encodeBundle(tampered)),
          throwsA(isA<StateError>()),
        );

    final flipped = b64uDecode(original['ikxSig'] as String)..[0] ^= 1;
    await expectRejected({...original, 'ikxSig': b64uEncode(flipped)});
    final flippedSpk = b64uDecode(original['spkSig'] as String)..[5] ^= 1;
    await expectRejected({...original, 'spkSig': b64uEncode(flippedSpk)});
    await expectRejected({...original, 'spk': b64uEncode(List<int>.generate(32, (i) => i + 1))});
    await expectRejected({...original, 'ikx': b64uEncode(List<int>.generate(32, (i) => i + 1))});
    await expectRejected({...original, 'spkId': (original['spkId'] as int) + 1});
    expect(alice.adapter.sessions.hasSessionFor(_conversationId), isFalse);

    await bootstrap(alice, bob, conversationId: _conversationId);
    expect(alice.adapter.sessions.hasSessionFor(_conversationId), isTrue);
  });

  test('stale spkTs rejected', () async {
    final bobCreated = DateTime.utc(2026, 1, 1);
    final bob = await createParty('bob', clock: () => bobCreated);
    Future<SessionBootstrapMaterial> bootstrapAt(DateTime now) async =>
        bootstrap(await createParty('alice', clock: () => now), bob, conversationId: _conversationId);

    await expectLater(bootstrapAt(bobCreated.add(const Duration(days: 61))), throwsA(isA<StateError>()));
    await expectLater(bootstrapAt(bobCreated.subtract(const Duration(days: 2))), throwsA(isA<StateError>()));
    expect((await bootstrapAt(bobCreated.add(const Duration(days: 59)))).sessionEnvelopeVersion, envelopeVersionV2);
    expect(
        (await bootstrapAt(bobCreated.subtract(const Duration(hours: 12)))).sessionEnvelopeVersion, envelopeVersionV2);
  });

  test('v1 ref upgraded by rotateSignedPrekey', () async {
    final legacy = await createLegacyIdentity();
    final bobAdapter = LibCryptoAdapter()..setLocalIdentityLoader(() async => legacy.identityPrivateKeyRef);

    final rotation = await bobAdapter.rotateSignedPrekey();
    expect(rotation.spkId, 1);
    final upgraded = LocalIdentity.tryParse(rotation.upgradedIdentityPrivateRef!)!;
    expect(upgraded.version, 2);
    expect(upgraded.x25519Private, legacy.x25519Private);
    expect(upgraded.signedPrekey!.id, 1);
    // The v1 X25519 identity key is now the certified IKx.
    final legacyIkx = await LibIdentityKeys.resolveRemoteX25519(legacy.signedPrekeyBundle, legacy.identityPublicKey);
    final upgradedIkx =
        await LibIdentityKeys.resolveRemoteX25519(rotation.signedPrekeyBundle, legacy.identityPublicKey);
    expect(upgradedIkx.bytes, legacyIkx.bytes);

    final bob = Party(
      'bob',
      bobAdapter,
      DeviceIdentityMaterial(
        identityPublicKey: legacy.identityPublicKey,
        identityPrivateKeyRef: legacy.identityPrivateKeyRef,
        signedPrekeyBundle: rotation.signedPrekeyBundle,
      ),
    );
    final alice = await createParty('alice');
    expect((await bootstrap(alice, bob, conversationId: _conversationId)).sessionEnvelopeVersion, envelopeVersionV2);
    final result = await receive(bob, await send(alice, bob, 'to an upgraded device', conversationId: _conversationId));
    expect(result.status, DecryptStatus.ok);
    expect(result.body, 'to an upgraded device');
  });

  test('bundle v2 vector reproduced', () async {
    final adapter = LibCryptoAdapter(
      random: ScriptedRandomSource([List.filled(32, 0x11), List.filled(32, 0x55), List.filled(32, 0x66)]),
      clock: () => DateTime.fromMillisecondsSinceEpoch(1767225600000, isUtc: true),
    );
    final identity = await adapter.identity.generateDeviceIdentity('device-vector');
    expect(identity.identityPublicKey, '0EqyMnQrtKs6E2i9RhXk5tAiSrcaAWuvhSCjMsl3hzc');
    expect(
      identity.signedPrekeyBundle,
      'eyJ2IjoyLCJpa3giOiJPS3RtUzlodmQ5Zm1hOTJhNEhrcEU2bFAyTE02RW1BQ2ZrdEd3ZlNJVEdjIiwiaWt4U2lnIjoiUlJEdzVl'
      'c05wdXZySjVYQnNlVXRFdVM2SFNjVG1TVjQwdHRsdkc4N0gzWkRQLTZpX2F5bVpvX29TWlVTNWtBRHF2WGZLU1hnX3E3NHZ3R09tNlhu'
      'RFEiLCJzcGtJZCI6MSwic3BrIjoiSVo1TmdBMnBhTktsX0xBSng0VDBkR3h4T08yNTdraEV0em5vTUxCYzlDUSIsInNwa1RzIjoxNzY3'
      'MjI1NjAwMDAwLCJzcGtTaWciOiJXNTJGa1ZtTTU3YjNaaFBNZkd3NjVNMnB1NHpMUmR3dmpGcWgzc0QzclI0MTRZaU9vWWVicFFBV216'
      'U05wX3FEX1JsN2s3a29zdFJVbnNiTzNxQ3NBZyJ9',
    );
    // The private ref is v2 and carries the published SPK.
    final ref = LocalIdentity.tryParse(identity.identityPrivateKeyRef)!;
    expect(ref.version, 2);
    expect(ref.signedPrekey!.id, 1);
    expect(ref.signedPrekey!.createdAt.millisecondsSinceEpoch, 1767225600000);
  });
}
