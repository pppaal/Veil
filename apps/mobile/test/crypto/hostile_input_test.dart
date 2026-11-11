import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/group_sender_keys.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/crypto/payload/inner_payload.dart';
import 'package:veil_mobile/src/core/crypto/random_source.dart';
import 'package:veil_mobile/src/core/crypto/ratchet/session_cipher.dart';
import 'package:veil_mobile/src/core/crypto/ratchet/session_store.dart';
import 'package:veil_mobile/src/core/crypto/x3dh/local_keyring.dart';

import 'support/crypto_harness.dart';

// Fields the server relays and payloads a peer authenticates are both
// attacker-controlled, and must fail as a typed result, never a throw: the
// messenger caches the decrypt future, so a throw leaves the bubble stuck on
// "Decrypting…" and breaks search in that conversation. A rejected frame
// leaves the session exactly as it was, so the next genuine one still opens.
void main() {
  const conversationId = 'conv-hostile';

  List<Uint8List> liveSecrets(Party party) =>
      [for (final buffer in party.adapter.debugLiveSecretBuffers(conversationId)) Uint8List.fromList(buffer)];

  test('a routing field too long for its AAD length prefix is an invalid envelope', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final recorder = SnapshotRecorder();
    bob.adapter.setSessionPersistence(persister: recorder.call);
    await bootstrap(alice, bob, conversationId: conversationId);

    final first = await send(alice, bob, 'first', conversationId: conversationId);
    // On first contact, no session may come of it.
    final firstContact = await receive(bob, copyEnvelope(first, senderDeviceId: 'd' * 70000));
    expect(firstContact.status, DecryptStatus.failed);
    expect(firstContact.failureReason, 'invalid_envelope');
    expect(bob.adapter.sessions.hasSessionFor(conversationId), isFalse);
    expect((await receive(bob, first)).status, DecryptStatus.ok);

    final writes = recorder.writes.length;
    final secrets = liveSecrets(bob);
    final second = await send(alice, bob, 'second', conversationId: conversationId);
    // The limit is on UTF-8 bytes: 40000 two-byte characters exceed it.
    final oversized = <CryptoEnvelope>[
      copyEnvelope(second, senderDeviceId: 'd' * 70000),
      copyEnvelope(second, conversationId: 'é' * 40000),
      copyEnvelope(second, version: 'v' * 70000),
    ];
    for (final envelope in oversized) {
      final result = await receive(bob, envelope);
      expect(result.status, DecryptStatus.failed);
      expect(result.failureReason, 'invalid_envelope');
    }
    expect(bob.adapter.sessions.hasSessionFor('é' * 40000), isFalse);
    expect(recorder.writes, hasLength(writes));
    expect(liveSecrets(bob), secrets);

    final genuine = await receive(bob, second);
    expect(genuine.status, DecryptStatus.ok);
    expect(genuine.body, 'second');
  });

  group('an authenticated payload with out-of-range numbers is malformed', () {
    // Each is sealed by a genuine peer, so it passes AEAD and reaches the
    // payload decoder.
    const hostilePayloads = <String>[
      '{"pv":2,"b":"","k":"text","x":9000000000000000,"att":null}',
      '{"pv":2,"b":"","k":"text","x":-9000000000000000,"att":null}',
      '{"pv":2,"b":"","k":"file","x":null,"att":{"id":"a1","ck":"key","n":"n","d":"d","ct":"t","sz":1e400}}',
      '{"pv":2,"b":"","k":"file","x":null,"att":{"id":"a1","ck":"key","n":"n","d":"d","ct":"t","sz":-1}}',
      '{"body":"","att":{"attachmentId":"a1","encryptedKey":"key","sizeBytes":1e400}}',
    ];

    test('on the PreKey frame that would open the session', () async {
      final bob = await createParty('bob');
      final recorder = SnapshotRecorder();
      bob.adapter.setSessionPersistence(persister: recorder.call);
      final peer = await _ModifiedPeer.bootstrap(to: bob, conversationId: conversationId);

      for (final json in hostilePayloads) {
        final result = await receive(bob, await peer.send(_RawPayload(json)));
        expect(result.status, DecryptStatus.failed, reason: json);
        expect(result.failureReason, 'malformed_payload', reason: json);
      }
      expect(bob.adapter.sessions.hasSessionFor(conversationId), isFalse);
      expect(recorder.writes, isEmpty);

      final genuine = await receive(bob, await peer.send(const InnerPayload(body: 'genuine', kind: MessageKind.text)));
      expect(genuine.status, DecryptStatus.ok);
      expect(genuine.body, 'genuine');
    });

    test('on an established session', () async {
      final bob = await createParty('bob');
      final recorder = SnapshotRecorder();
      bob.adapter.setSessionPersistence(persister: recorder.call);
      final peer = await _ModifiedPeer.bootstrap(to: bob, conversationId: conversationId);
      final first = await receive(bob, await peer.send(const InnerPayload(body: 'first', kind: MessageKind.text)));
      expect(first.status, DecryptStatus.ok);
      // The peer keeps sending PreKey frames until Bob replies; Bob now
      // decrypts them on the session the first one opened.

      final writes = recorder.writes.length;
      final secrets = liveSecrets(bob);
      for (final json in hostilePayloads) {
        final result = await receive(bob, await peer.send(_RawPayload(json)));
        expect(result.status, DecryptStatus.failed, reason: json);
      }
      expect(recorder.writes, hasLength(writes));
      expect(liveSecrets(bob), secrets);

      final genuine = await receive(bob, await peer.send(const InnerPayload(body: 'second', kind: MessageKind.text)));
      expect(genuine.status, DecryptStatus.ok);
      expect(genuine.body, 'second');
    });
  });

  test('a group key distribution with an oversized routing field is a typed refusal', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final sealer = GroupSenderKeySealer(resolveRecipientPrekey: LibIdentityKeys.resolveRemoteX25519);
    final sealed = await sealer.seal(
      key: GroupSenderKey(
        groupId: conversationId,
        epoch: 0,
        senderDeviceId: alice.deviceId,
        chainKey: List<int>.filled(32, 1),
        counter: 0,
        signingPublicKey: List<int>.filled(32, 2),
        generation: 1,
      ),
      recipientUserId: bob.userId,
      recipientIdentityPublicKey: bob.identity.identityPublicKey,
      recipientSignedPrekeyBundle: bob.identity.signedPrekeyBundle,
      senderIdentityEd25519Seed: LibIdentityKeys.localEd25519Seed(alice.identity.identityPrivateKeyRef)!,
    );
    Future<GroupKeyDistribution> unseal({String groupId = conversationId, String? senderDeviceId}) => sealer.unseal(
          groupId: groupId,
          epoch: 0,
          senderDeviceId: senderDeviceId ?? alice.deviceId,
          localUserId: bob.userId,
          encryptedChainKey: sealed.encryptedChainKey,
          nonce: sealed.nonce,
          version: sealed.version,
          localIdentityX25519Private: LibIdentityKeys.localX25519Private(bob.identity.identityPrivateKeyRef)!,
          senderIdentityPublicKey: alice.identity.identityPublicKey,
        );

    final refused = throwsA(isA<GroupCryptoException>().having((e) => e.code, 'code', 'distributionInvalid'));
    await expectLater(unseal(senderDeviceId: 'd' * 70000), refused);
    await expectLater(unseal(groupId: 'é' * 40000), refused);
    expect((await unseal()).key.senderDeviceId, alice.deviceId);
  });
}

/// Seals exactly the bytes it is given, as modified peer code could.
class _RawPayload extends InnerPayload {
  const _RawPayload(this.json) : super(body: '', kind: MessageKind.text);

  final String json;

  @override
  Uint8List encode() => utf8.encode(json);
}

/// A genuine peer (its handshake authenticates) driving [SessionCipher]
/// directly, so it can seal payloads the adapter would never produce.
class _ModifiedPeer {
  _ModifiedPeer._(this._cipher, this._to, this._conversationId);

  static const _deviceId = 'device-modified';

  static Future<_ModifiedPeer> bootstrap({required Party to, required String conversationId}) async {
    DateTime clock() => DateTime.now().toUtc();
    final random = SecureRandomSource();
    final keyring = LocalKeyring(random: random, clock: clock);
    await keyring.generateIdentity();
    final cipher =
        SessionCipher(store: SessionRecordStore(clock: clock), keyring: keyring, random: random, clock: clock);
    await cipher.bootstrap(SessionBootstrapRequest(
      conversationId: conversationId,
      localDeviceId: _deviceId,
      localUserId: 'user-modified',
      remoteUserId: to.userId,
      remoteDeviceId: to.deviceId,
      remoteIdentityPublicKey: to.identity.identityPublicKey,
      remoteSignedPrekeyBundle: to.identity.signedPrekeyBundle,
    ));
    return _ModifiedPeer._(cipher, to, conversationId);
  }

  final SessionCipher _cipher;
  final Party _to;
  final String _conversationId;

  Future<CryptoEnvelope> send(InnerPayload payload) => _cipher.encrypt(
        conversationId: _conversationId,
        senderDeviceId: _deviceId,
        recipientUserId: _to.userId,
        payload: payload,
      );
}
