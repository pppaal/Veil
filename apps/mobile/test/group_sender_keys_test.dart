import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/group_sender_keys.dart';

// Exercises the design test matrix in docs/group-sender-keys-design.md.

const groupId = 'group-1';

class _Member {
  _Member(this.deviceId) : engine = GroupSenderKeyEngine();
  final String deviceId;
  final GroupSenderKeyEngine engine;
}

Future<void> _distribute(List<_Member> members, int epoch) async {
  for (final m in members) {
    final key = await m.engine.ensureOwnSenderKey(
      groupId: groupId,
      epoch: epoch,
      localDeviceId: m.deviceId,
    );
    for (final other in members) {
      if (identical(other, m)) continue;
      await other.engine.ingestSenderKey(key);
    }
  }
}

Future<GroupCiphertext> _send(_Member m, String text) => m.engine.encrypt(
      groupId: groupId,
      localDeviceId: m.deviceId,
      plaintext: utf8.encode(text),
    );

Future<String> _recv(_Member m, GroupCiphertext ct) async {
  final out = await m.engine.decrypt(groupId: groupId, payload: ct.payload, nonce: ct.nonce);
  return utf8.decode(out.plaintext);
}

Future<String> _code(Future<void> Function() fn) async {
  try {
    await fn();
    return 'ok';
  } on GroupCryptoException catch (e) {
    return e.code;
  }
}

void main() {
  late _Member alice;
  late _Member bob;
  late _Member carol;

  setUp(() async {
    alice = _Member('dev-alice');
    bob = _Member('dev-bob');
    carol = _Member('dev-carol');
    await _distribute([alice, bob, carol], 0);
  });

  test('#1 three-member group: alice sends, bob and carol decrypt', () async {
    final ct = await _send(alice, 'hello group');
    expect(await _recv(bob, ct), 'hello group');
    expect(await _recv(carol, ct), 'hello group');
    // The sender can read its own frame back from server history.
    expect(await _recv(alice, ct), 'hello group');
  });

  test('frame header is parseable without any key material', () async {
    final ct = await _send(alice, 'x');
    final header = GroupSenderKeyEngine.parseHeader(ct.payload)!;
    expect(header.senderDeviceId, 'dev-alice');
    expect(header.epoch, 0);
    expect(header.counter, 0);
    expect(GroupSenderKeyEngine.parseHeader('!!not-b64!!'), isNull);
  });

  test('#2/#3 join: dave decrypts post-join frames but nothing pre-join', () async {
    final preJoin = await _send(bob, 'before dave');
    final dave = _Member('dev-dave');

    // Server bumps the epoch; every existing member resets + redistributes.
    for (final m in [alice, bob, carol]) {
      await m.engine.resetForEpoch(groupId: groupId, epoch: 1);
    }
    await _distribute([alice, bob, carol, dave], 1);

    final postJoin = await _send(alice, 'after dave');
    expect(await _recv(dave, postJoin), 'after dave');
    expect(await _recv(bob, postJoin), 'after dave');

    // Pre-join ciphertext: dave holds epoch-1 state only.
    expect(await _code(() => _recv(dave, preJoin)), 'epochMismatch');
  });

  test('#4/#6 leave: departed member cannot read or forge on the new epoch', () async {
    final dave = _Member('dev-dave');
    for (final m in [alice, bob, carol]) {
      await m.engine.resetForEpoch(groupId: groupId, epoch: 1);
    }
    await _distribute([alice, bob, carol, dave], 1);

    // dave is removed → epoch 2; remaining members reset and redistribute
    // among themselves only, and drop dave's chain.
    for (final m in [alice, bob, carol]) {
      await m.engine.resetForEpoch(groupId: groupId, epoch: 2);
    }
    await _distribute([alice, bob, carol], 2);

    final ct = await _send(alice, 'dave is gone');
    expect(await _recv(bob, ct), 'dave is gone');
    expect(await _code(() => _recv(dave, ct)), 'epochMismatch');

    // dave forges under his stale (epoch 1) chain.
    final forged = await _send(dave, 'still here?');
    expect(await _code(() => _recv(bob, forged)), 'epochMismatch');

    // Even if dave learned the new epoch number, nobody holds his key.
    await dave.engine.ensureOwnSenderKey(groupId: groupId, epoch: 2, localDeviceId: dave.deviceId);
    final forged2 = await _send(dave, 'epoch guessed');
    expect(await _code(() => _recv(bob, forged2)), 'senderKeyMissing');
  });

  test('#5 replaying an already-consumed frame is rejected', () async {
    final ct = await _send(alice, 'once');
    expect(await _recv(bob, ct), 'once');
    expect(await _code(() => _recv(bob, ct)), 'replayed');
  });

  test('#9 bob cannot speak as alice', () async {
    // bob produces a frame under his own chain, then rewrites the header's
    // senderDeviceId to alice's. Both the AD and the signature must fail.
    final ct = await _send(bob, 'impersonation');
    final bytes = base64Url.decode(_pad(ct.payload));
    // layout: [0x01][len][sender][...] — swap bob's id for alice's.
    final oldLen = bytes[1];
    final sender = utf8.encode('dev-alice');
    final patched = <int>[0x01, sender.length, ...sender, ...bytes.sublist(2 + oldLen)];
    final forged = GroupCiphertext(
      payload: base64Url.encode(patched).replaceAll('=', ''),
      nonce: ct.nonce,
    );
    expect(await _code(() => _recv(carol, forged)), 'signatureInvalid');
    // carol's chain for alice was not advanced by the rejected frame.
    final real = await _send(alice, 'genuine');
    expect(await _recv(carol, real), 'genuine');
  });

  test('#10 out-of-order delivery resolves via skipped keys', () async {
    final c1 = await _send(alice, 'one');
    final c2 = await _send(alice, 'two');
    final c3 = await _send(alice, 'three');
    expect(await _recv(bob, c2), 'two');
    expect(await _recv(bob, c1), 'one');
    expect(await _recv(bob, c3), 'three');
    // The stashed key for #1 was consumed; a second delivery is a replay.
    expect(await _code(() => _recv(bob, c1)), 'replayed');
  });

  test('forward skip is bounded', () async {
    final ct = await _send(alice, 'x');
    final bytes = base64Url.decode(_pad(ct.payload));
    // counter sits after [0x01][len][sender 9][epoch 8]
    final ctrOffset = 2 + 9 + 8;
    final patched = List<int>.from(bytes)
      ..setRange(ctrOffset, ctrOffset + 4, [0x00, 0x01, 0x00, 0x00]); // 65536
    final far = GroupCiphertext(
      payload: base64Url.encode(patched).replaceAll('=', ''),
      nonce: ct.nonce,
    );
    // Signature covers the counter, so this fails as a forgery first — the
    // bound is defence in depth for a compromised signing key.
    expect(await _code(() => _recv(bob, far)), 'signatureInvalid');
  });

  test('tampered ciphertext fails closed and does not advance the chain', () async {
    final ct = await _send(alice, 'payload');
    final bytes = base64Url.decode(_pad(ct.payload));
    final patched = List<int>.from(bytes);
    patched[patched.length - 1] ^= 0x01; // flip a tag bit
    final tampered = GroupCiphertext(
      payload: base64Url.encode(patched).replaceAll('=', ''),
      nonce: ct.nonce,
    );
    expect(await _code(() => _recv(bob, tampered)), 'signatureInvalid');
    expect(await _recv(bob, ct), 'payload');
  });

  test('#8 forward secrecy: a leaked chain key reveals nothing already sent', () async {
    final c1 = await _send(alice, 'past');
    // Attacker learns alice's chain *now* (after c1) via a fresh distribution.
    final leaked = alice.engine.exportOwnSenderKey(groupId)!;
    expect(leaked.counter, 1);
    final eve = _Member('dev-eve');
    await eve.engine.resetForEpoch(groupId: groupId, epoch: 0);
    await eve.engine.ingestSenderKey(leaked);
    expect(await _code(() => _recv(eve, c1)), 'replayed');
    final c2 = await _send(alice, 'future');
    expect(await _recv(eve, c2), 'future');
  });

  test('snapshot/restore round-trips chain state and skipped keys', () async {
    final persisted = <String, Map<String, dynamic>?>{};
    final engine = GroupSenderKeyEngine(
      persister: (id, snap) async => persisted[id] = snap,
    );
    final key = await engine.ensureOwnSenderKey(groupId: groupId, epoch: 0, localDeviceId: 'dev-p');
    await bob.engine.ingestSenderKey(key);
    await engine.ingestSenderKey(bob.engine.exportOwnSenderKey(groupId)!);

    final b1 = await _send(bob, 'b1');
    final b2 = await _send(bob, 'b2');
    // Receive #2 first so a skipped key for #1 is stashed in the snapshot.
    await engine.decrypt(groupId: groupId, payload: b2.payload, nonce: b2.nonce);

    final restored = GroupSenderKeyEngine();
    await restored.restoreFromSnapshots({groupId: persisted[groupId]!});
    final out = await restored.decrypt(groupId: groupId, payload: b1.payload, nonce: b1.nonce);
    expect(utf8.decode(out.plaintext), 'b1');
    // Our own chain survived too: we can still send and bob decrypts.
    final mine = await restored.encrypt(groupId: groupId, localDeviceId: 'dev-p', plaintext: utf8.encode('hi'));
    expect(await _recv(bob, mine), 'hi');

    await restored.forget(groupId);
    expect(restored.currentEpoch(groupId), isNull);
  });

  test('ingest refuses stale epochs and own-chain overwrite', () async {
    final stale = GroupSenderKey(
      groupId: groupId,
      epoch: 0,
      senderDeviceId: 'dev-zed',
      chainKey: List<int>.filled(32, 7),
      counter: 0,
      signingPublicKey: List<int>.filled(32, 9),
    );
    await alice.engine.resetForEpoch(groupId: groupId, epoch: 5);
    expect(await _code(() => alice.engine.ingestSenderKey(stale)), 'epochMismatch');
    await alice.engine.ensureOwnSenderKey(groupId: groupId, epoch: 5, localDeviceId: alice.deviceId);
    final selfSpoof = GroupSenderKey(
      groupId: groupId,
      epoch: 5,
      senderDeviceId: alice.deviceId,
      chainKey: List<int>.filled(32, 1),
      counter: 0,
      signingPublicKey: List<int>.filled(32, 2),
    );
    expect(await _code(() => alice.engine.ingestSenderKey(selfSpoof)), 'distributionInvalid');
  });

  group('GroupSenderKeySealer', () {
    final x25519 = X25519();
    final ed25519 = Ed25519();

    test('seal/unseal round-trips and binds the sender identity', () async {
      final recipientX = await x25519.newKeyPair();
      final recipientXPub = await recipientX.extractPublicKey();
      final recipientXPriv = (await recipientX.extract()).bytes;
      final senderId = await ed25519.newKeyPair();
      final senderIdSeed = (await senderId.extract()).bytes;
      final senderIdPub = base64Url.encode((await senderId.extractPublicKey()).bytes).replaceAll('=', '');

      final sealer = GroupSenderKeySealer(
        resolveRecipientPrekey: (bundle, identity) async {
          expect(bundle, 'bundle-of-recipient');
          return recipientXPub;
        },
      );
      final key = await alice.engine.ensureOwnSenderKey(
        groupId: groupId,
        epoch: 0,
        localDeviceId: alice.deviceId,
      );

      final sealed = await sealer.seal(
        key: key,
        recipientUserId: 'user-bob',
        recipientIdentityPublicKey: 'id-of-recipient',
        recipientSignedPrekeyBundle: 'bundle-of-recipient',
        senderIdentityEd25519Seed: senderIdSeed,
      );
      expect(sealed.version, kGroupKeyDistributionVersion);

      final opened = await sealer.unseal(
        groupId: groupId,
        epoch: 0,
        senderDeviceId: alice.deviceId,
        localUserId: 'user-bob',
        encryptedChainKey: sealed.encryptedChainKey,
        nonce: sealed.nonce,
        version: sealed.version,
        localIdentityX25519Private: recipientXPriv,
        senderIdentityPublicKey: senderIdPub,
      );
      expect(groupKeyBytesEqual(opened.chainKey, key.chainKey), isTrue);
      expect(groupKeyBytesEqual(opened.signingPublicKey, key.signingPublicKey), isTrue);
      expect(opened.counter, key.counter);

      // Wrong claimed sender identity → signature fails.
      final otherId = await ed25519.newKeyPair();
      final otherPub = base64Url.encode((await otherId.extractPublicKey()).bytes).replaceAll('=', '');
      expect(
        await _code(() => sealer.unseal(
              groupId: groupId,
              epoch: 0,
              senderDeviceId: alice.deviceId,
              localUserId: 'user-bob',
              encryptedChainKey: sealed.encryptedChainKey,
              nonce: sealed.nonce,
              version: sealed.version,
              localIdentityX25519Private: recipientXPriv,
              senderIdentityPublicKey: otherPub,
            )),
        'signatureInvalid',
      );

      // Re-addressed to another recipient / epoch → AD mismatch.
      expect(
        await _code(() => sealer.unseal(
              groupId: groupId,
              epoch: 1,
              senderDeviceId: alice.deviceId,
              localUserId: 'user-bob',
              encryptedChainKey: sealed.encryptedChainKey,
              nonce: sealed.nonce,
              version: sealed.version,
              localIdentityX25519Private: recipientXPriv,
              senderIdentityPublicKey: senderIdPub,
            )),
        'signatureInvalid',
      );

      // Wrong recipient private key → AEAD fails.
      final otherX = (await (await x25519.newKeyPair()).extract()).bytes;
      expect(
        await _code(() => sealer.unseal(
              groupId: groupId,
              epoch: 0,
              senderDeviceId: alice.deviceId,
              localUserId: 'user-bob',
              encryptedChainKey: sealed.encryptedChainKey,
              nonce: sealed.nonce,
              version: sealed.version,
              localIdentityX25519Private: otherX,
              senderIdentityPublicKey: senderIdPub,
            )),
        'decryptFailed',
      );
    });
  });
}

String _pad(String b64u) => b64u.padRight(b64u.length + ((4 - b64u.length % 4) % 4), '=');
