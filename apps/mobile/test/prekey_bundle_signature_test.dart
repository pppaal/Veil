import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/bytes.dart';

import 'crypto/support/crypto_harness.dart';

// Regression tests for Ed25519 verification of published prekey bundles.
// Accepting an unverified key would let a hostile server swap in its own
// and MITM every new session. These pin that, for both the legacy v1 shape
// and bundle v2:
//   - a tampered key fails bootstrap,
//   - a bundle missing its signature fails bootstrap,
//   - a bundle signed by a different identity key fails bootstrap.
// Each rejection asserts no session exists afterwards. (The v2 signature
// fields are exercised field by field in test/crypto/x3dh_v2_test.dart.)

const _conversationId = 'conv-sigcheck';

String _reencodeBundle(Map<String, dynamic> bundle) => b64uEncode(utf8.encode(json.encode(bundle)));

Map<String, dynamic> _decodeBundle(String b64) => json.decode(utf8.decode(b64uDecode(b64))) as Map<String, dynamic>;

void main() {
  test('bootstrap rejects a legacy bundle whose x25519 field was swapped', () async {
    final alice = await createParty('alice');
    final bob = await createLegacyParty('bob');

    // Attacker swaps the x25519 pub but cannot re-sign it without the
    // identity private key.
    final decoded = _decodeBundle(bob.identity.signedPrekeyBundle);
    decoded['x25519'] = b64uEncode(List<int>.generate(32, (i) => i));

    await expectLater(
      bootstrap(alice, bob, conversationId: _conversationId, signedPrekeyBundle: _reencodeBundle(decoded)),
      throwsA(isA<StateError>()),
    );
    expect(alice.adapter.sessions.hasSessionFor(_conversationId), isFalse);
  });

  test('bootstrap rejects a bundle missing its signature', () async {
    final alice = await createParty('alice');
    final legacyBob = await createLegacyParty('bob');
    final bob = await createParty('bob');

    final legacy = _decodeBundle(legacyBob.identity.signedPrekeyBundle)..remove('sig');
    await expectLater(
      bootstrap(alice, legacyBob, conversationId: _conversationId, signedPrekeyBundle: _reencodeBundle(legacy)),
      throwsA(isA<StateError>()),
    );
    final v2 = _decodeBundle(bob.identity.signedPrekeyBundle)..remove('spkSig');
    await expectLater(
      bootstrap(alice, bob, conversationId: _conversationId, signedPrekeyBundle: _reencodeBundle(v2)),
      throwsA(isA<StateError>()),
    );
    expect(alice.adapter.sessions.hasSessionFor(_conversationId), isFalse);
  });

  test('bootstrap rejects when identity key belongs to a different peer', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final mallory = await createParty('mallory');

    // Alice is told "this is Mallory's bundle", but it was signed by Bob.
    await expectLater(
      bootstrap(alice, mallory, conversationId: _conversationId, signedPrekeyBundle: bob.identity.signedPrekeyBundle),
      throwsA(isA<StateError>()),
    );
    expect(alice.adapter.sessions.hasSessionFor(_conversationId), isFalse);
  });

  test('bootstrap accepts a well-formed signed bundle', () async {
    final alice = await createParty('alice');
    final bob = await createParty('bob');
    final legacyBob = await createLegacyParty('carol');

    await bootstrap(alice, bob, conversationId: _conversationId);
    expect(alice.adapter.sessions.hasSessionFor(_conversationId), isTrue);
    await bootstrap(alice, legacyBob, conversationId: 'conv-legacy');
    expect(alice.adapter.sessions.hasSessionFor('conv-legacy'), isTrue);
  });
}
