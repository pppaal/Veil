import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/crypto/message_padding.dart';
import 'package:veil_mobile/src/core/crypto/payload/inner_payload.dart';
import 'package:veil_mobile/src/core/crypto/random_source.dart';
import 'package:veil_mobile/src/core/crypto/ratchet/aead.dart';
import 'package:veil_mobile/src/core/crypto/ratchet/double_ratchet.dart';
import 'package:veil_mobile/src/core/crypto/ratchet/frame_codec.dart';
import 'package:veil_mobile/src/core/crypto/ratchet/kdf.dart';
import 'package:veil_mobile/src/core/crypto/x3dh/curve25519.dart';
import 'package:veil_mobile/src/core/crypto/x3dh/identity_keys.dart';
import 'package:veil_mobile/src/core/crypto/x3dh/x3dh_handshake.dart';

import 'support/crypto_harness.dart';

const _conversationId = 'conv-x3dh';

Map<String, dynamic> _decodeBundle(String bundle) =>
    json.decode(utf8.decode(b64uDecode(bundle))) as Map<String, dynamic>;

String _encodeBundle(Map<String, dynamic> map) => b64uEncode(utf8.encode(json.encode(map)));

/// The identity fields a PreKey header carries.
typedef _IdentityClaim = ({Uint8List ed25519, Uint8List x25519, Uint8List ikxSignature});

/// What anyone can copy from [party]'s published identity and bundle.
_IdentityClaim _publishedClaim(Party party) {
  final bundle = _decodeBundle(party.identity.signedPrekeyBundle);
  return (
    ed25519: b64uDecode(party.identity.identityPublicKey),
    x25519: b64uDecode(bundle['ikx'] as String),
    ikxSignature: b64uDecode(bundle['ikxSig'] as String),
  );
}

Uint8List _ikxPrivate(Party party) => LocalIdentity.tryParse(party.identity.identityPrivateKeyRef)!.x25519Private;

/// A first PreKey frame built by hand: the header carries [claim], and DH1
/// uses [dh1Private], the X25519 private key the sender really holds. Every
/// other byte (DH2..DH4, ratchet init, header, AAD with the X3DH AD, seal)
/// is computed exactly as an honest initiator would, so the frame is
/// internally consistent and authenticates only if DH1 matches the claim.
Future<CryptoEnvelope> _handcraftedPreKeyFrame({
  required Party to,
  required String senderDeviceId,
  required _IdentityClaim claim,
  required List<int> dh1Private,
  required OneTimePrekey oneTimePrekey,
  required String body,
}) async {
  final random = SecureRandomSource();
  final bundle =
      await verifyRemoteBundle(to.identity.signedPrekeyBundle, to.identity.identityPublicKey) as PrekeyBundleV2;
  final ephemeral = await generateX25519KeyPair(random);
  final keys = await deriveInitiatorKeys(
    identityEd25519: claim.ed25519,
    identityX25519Private: dh1Private,
    identityX25519: claim.x25519,
    ephemeralPrivate: ephemeral.privateKey,
    remoteIdentityEd25519: b64uDecode(to.identity.identityPublicKey),
    remoteIdentityX25519: bundle.ikx,
    remoteSignedPrekey: bundle.spk,
    remoteOneTimePrekey: b64uDecode(oneTimePrekey.publicKey),
  );
  final chain = await deriveInitialSendingChain(keys.sharedKey, bundle.spk, random);
  final preKey = PreKeyHeader(
    identityEd25519: claim.ed25519,
    identityX25519: claim.x25519,
    identityX25519Signature: claim.ikxSignature,
    baseKey: ephemeral.publicKey,
    signedPrekeyId: bundle.spkId,
    oneTimePrekeyId: oneTimePrekey.keyId,
  );
  final header = FrameV2.encodeHeader(
    preKeyHeader: preKey.encode(),
    ratchetPublic: chain.ratchetKeyPair.publicKey,
    previousCounter: 0,
    counter: 0,
  );
  final nonce = random.nextBytes(gcmNonceLength);
  final sealed = await aesGcmSeal(
    key: await deriveMessageKey(chain.chainKey, 0),
    nonce: nonce,
    plaintext: MessagePadding.pad(InnerPayload(body: body, kind: MessageKind.text).encode()),
    aad: buildFrameAadV4(
      version: envelopeVersionV2,
      conversationId: _conversationId,
      senderDeviceId: senderDeviceId,
      messageKind: MessageKind.text.name,
      header: header,
      associatedData: keys.associatedData,
    ),
  );
  return CryptoEnvelope(
    version: envelopeVersionV2,
    conversationId: _conversationId,
    senderDeviceId: senderDeviceId,
    recipientUserId: to.userId,
    ciphertext: b64uEncode(concatBytes([header, sealed])),
    nonce: b64uEncode(nonce),
    messageKind: MessageKind.text,
  );
}

/// Storage whose one-time prekey deletes always fail.
class _UndeletableOneTimePrekeys extends InMemoryLocalPrekeyStore {
  @override
  Future<void> deleteOneTimePrekey(int keyId) => Future.error(StateError('storage unavailable'));
}

/// Storage whose first one-time prekey read fails, as a locked keystore might.
class _FlakyOneTimePrekeyReads extends InMemoryLocalPrekeyStore {
  var _failNextRead = true;

  @override
  Future<List<int>?> loadOneTimePrekey(int keyId) {
    if (!_failNextRead) return super.loadOneTimePrekey(keyId);
    _failNextRead = false;
    return Future.error(StateError('storage unavailable'));
  }
}

void main() {
  test('forged initiator holding only the public bundle cannot open a session (scenarioUnauthInbound)', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final mallory = await createParty('mallory');
    final recorder = SnapshotRecorder();
    bob.adapter.setSessionPersistence(persister: recorder.call);
    final prekey = (await bob.adapter.generateOneTimePrekeys(count: 1)).single;
    final aliceClaim = _publishedClaim(alice);

    // Mallory copies everything Alice publishes, her genuine ikxSig
    // included, and builds an otherwise perfect frame. Without IKx_A's
    // private key she can only compute DH1 with a key of her own.
    final forged = await _handcraftedPreKeyFrame(
      to: bob,
      senderDeviceId: alice.deviceId,
      claim: aliceClaim,
      dh1Private: _ikxPrivate(mallory),
      oneTimePrekey: prekey,
      body: 'hi bob, it is alice (forged)',
    );
    final result = await receive(bob, forged);
    expect(result.status, DecryptStatus.failed);
    expect(result.failureReason, 'aead_failed');
    expect(result.body, isNot(contains('forged')));
    expect(bob.adapter.sessions.hasSessionFor(_conversationId), isFalse);
    expect(recorder.writes, isEmpty);

    // Pairing Alice's identity key with Mallory's own certified X25519 key
    // instead fails the IKx certification outright.
    final malloryClaim = _publishedClaim(mallory);
    final mixed = await _handcraftedPreKeyFrame(
      to: bob,
      senderDeviceId: alice.deviceId,
      claim: (ed25519: aliceClaim.ed25519, x25519: malloryClaim.x25519, ikxSignature: malloryClaim.ikxSignature),
      dh1Private: _ikxPrivate(mallory),
      oneTimePrekey: prekey,
      body: 'mixed',
    );
    final mixedResult = await receive(bob, mixed);
    expect(mixedResult.status, DecryptStatus.failed);
    expect(mixedResult.failureReason, 'bad_ikx_signature');
    expect(bob.adapter.sessions.hasSessionFor(_conversationId), isFalse);
    expect(recorder.writes, isEmpty);

    // Positive control: the same construction with Alice's real IKx private
    // key opens the session, on the one-time prekey the forgeries left
    // untouched.
    final genuine = await _handcraftedPreKeyFrame(
      to: bob,
      senderDeviceId: alice.deviceId,
      claim: aliceClaim,
      dh1Private: _ikxPrivate(alice),
      oneTimePrekey: prekey,
      body: 'really alice',
    );
    final accepted = await receive(bob, genuine);
    expect(accepted.status, DecryptStatus.ok, reason: accepted.failureReason);
    expect(accepted.body, 'really alice');
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

  test('a message is sealed only to the identity the caller chose', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final mallory = await createParty('mallory');
    await bootstrap(alice, bob, conversationId: _conversationId);
    await receive(bob, await send(alice, bob, 'hello', conversationId: _conversationId));
    expect((await receive(alice, await send(bob, alice, 'hi', conversationId: _conversationId))).body, 'hi');
    // A handshake the pins admit replaces the sending state with one bound
    // to mallory.
    alice.adapter.setRemoteIdentityVerifier((_) async => true);
    await bootstrap(mallory, alice, conversationId: _conversationId);
    expect((await receive(alice, await send(mallory, alice, 'me too', conversationId: _conversationId))).isOk, isTrue);

    await expectLater(
        send(alice, bob, 'for bob', conversationId: _conversationId), throwsA(isA<SessionRecipientChanged>()));
    // The same key in another base64url spelling is the same recipient.
    final padded = base64Url.encode(b64uDecode(mallory.identity.identityPublicKey));
    expect(padded, endsWith('='));
    final sealed = await alice.adapter.messaging.encryptMessage(
      conversationId: _conversationId,
      senderDeviceId: alice.deviceId,
      recipientUserId: mallory.userId,
      body: 'for mallory',
      messageKind: MessageKind.text,
      recipientBundle: KeyBundle(
        userId: mallory.userId,
        deviceId: mallory.deviceId,
        handle: mallory.name,
        identityPublicKey: padded,
        signedPrekeyBundle: mallory.identity.signedPrekeyBundle,
      ),
    );
    expect((await receive(mallory, sealed)).body, 'for mallory');
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

  test('a failed OPK delete still returns the plaintext and keeps the OPK spent', () async {
    final alice = await createParty('alice');
    final carol = await createParty('carol');
    final bob = await createParty('bob');
    bob.adapter.setLocalPrekeyStore(_UndeletableOneTimePrekeys());
    final prekey = (await bob.adapter.generateOneTimePrekeys(count: 1)).single;

    await bootstrap(alice, bob, conversationId: 'conv-alice', oneTimePrekey: prekey);
    final first = await receive(bob, await send(alice, bob, 'first', conversationId: 'conv-alice'));
    expect(first.status, DecryptStatus.ok);
    expect(first.body, 'first');

    await bootstrap(carol, bob, conversationId: 'conv-carol', oneTimePrekey: prekey);
    final reused = await receive(bob, await send(carol, bob, 'reuse', conversationId: 'conv-carol'));
    expect(reused.status, DecryptStatus.failed);
    expect(reused.failureReason, 'opk_unavailable');
  });

  test('a failed OPK read releases its claim so a retry succeeds', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    bob.adapter.setLocalPrekeyStore(_FlakyOneTimePrekeyReads());
    final prekey = (await bob.adapter.generateOneTimePrekeys(count: 1)).single;
    await bootstrap(alice, bob, conversationId: 'conv-alice', oneTimePrekey: prekey);
    final first = await send(alice, bob, 'first', conversationId: 'conv-alice');

    await expectLater(receive(bob, first), throwsA(isA<StateError>()));
    expect(bob.adapter.sessions.hasSessionFor('conv-alice'), isFalse);
    final retried = await receive(bob, first);
    expect(retried.status, DecryptStatus.ok, reason: retried.failureReason);
    expect(retried.body, 'first');
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
    expect((await bob.adapter.currentSignedPrekey())!.createdAt, bobNow);
    // The directory accepted it, so from now on spkId 1 is superseded.
    await bob.adapter.markSignedPrekeyPublished(rotation.spkId);

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

  test('a signed prekey whose successor never reached the directory keeps answering', () async {
    var bobNow = DateTime.utc(2026, 11, 1);
    final bob = await createParty('bob', clock: () => bobNow);
    final alice = await createParty('alice', clock: () => bobNow);
    await bootstrap(alice, bob, conversationId: 'conv-alice');
    // Rotated, but the directory never accepted it: it still serves spkId 1.
    await bob.adapter.rotateSignedPrekey();

    bobNow = bobNow.add(const Duration(days: 30));
    expect(await bob.adapter.pruneSignedPrekeys(), 0);
    final late = await receive(bob, await send(alice, bob, 'still on spk 1', conversationId: 'conv-alice'));
    expect(late.status, DecryptStatus.ok);
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
