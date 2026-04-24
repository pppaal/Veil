import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

// Regression tests for Ed25519 signature verification on signed prekey
// bundles. Before the fix, `_resolveRemoteX25519Key` accepted any x25519
// public key embedded in the bundle without checking the `sig` field,
// allowing a hostile server to swap in an attacker-controlled pub and MITM
// every new session. These tests pin the behavior that:
//   - a tampered x25519 pub fails bootstrap,
//   - a bundle missing its `sig` field fails bootstrap,
//   - a bundle signed by a different identity key fails bootstrap.
//
// Each test asserts bootstrap throws; no session must exist afterwards.

const _conversationId = 'conv-sigcheck';

String _b64Encode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _b64Decode(String value) {
  final padded = value.padRight(
    value.length + ((4 - value.length % 4) % 4),
    '=',
  );
  return Uint8List.fromList(base64Url.decode(padded));
}

String _reencodeBundle(Map<String, dynamic> bundle) =>
    _b64Encode(utf8.encode(json.encode(bundle)));

Map<String, dynamic> _decodeBundle(String b64) =>
    json.decode(utf8.decode(_b64Decode(b64))) as Map<String, dynamic>;

void main() {
  test('bootstrap rejects a bundle whose x25519 field was swapped',
      () async {
    final alice = LibCryptoAdapter();
    final bob = LibCryptoAdapter();
    final bobId = await bob.identity.generateDeviceIdentity('device-bob');

    // Attacker swaps the x25519 pub but cannot re-sign it without the
    // identity private key.
    final decoded = _decodeBundle(bobId.signedPrekeyBundle);
    final attackerPub = List<int>.generate(32, (i) => i); // any 32 bytes
    decoded['x25519'] = _b64Encode(attackerPub);
    final tamperedBundle = _reencodeBundle(decoded);

    await expectLater(
      alice.sessions.bootstrapSession(
        SessionBootstrapRequest(
          conversationId: _conversationId,
          localDeviceId: 'device-alice',
          localUserId: 'device-alice',
          remoteUserId: 'device-bob',
          remoteDeviceId: 'device-bob',
          remoteIdentityPublicKey: bobId.identityPublicKey,
          remoteSignedPrekeyBundle: tamperedBundle,
        ),
      ),
      throwsA(isA<StateError>()),
    );

    expect(alice.sessions.hasSessionFor(_conversationId), isFalse);
  });

  test('bootstrap rejects a bundle missing the sig field', () async {
    final alice = LibCryptoAdapter();
    final bob = LibCryptoAdapter();
    final bobId = await bob.identity.generateDeviceIdentity('device-bob');

    final decoded = _decodeBundle(bobId.signedPrekeyBundle);
    decoded.remove('sig');
    final unsignedBundle = _reencodeBundle(decoded);

    await expectLater(
      alice.sessions.bootstrapSession(
        SessionBootstrapRequest(
          conversationId: _conversationId,
          localDeviceId: 'device-alice',
          localUserId: 'device-alice',
          remoteUserId: 'device-bob',
          remoteDeviceId: 'device-bob',
          remoteIdentityPublicKey: bobId.identityPublicKey,
          remoteSignedPrekeyBundle: unsignedBundle,
        ),
      ),
      throwsA(isA<StateError>()),
    );

    expect(alice.sessions.hasSessionFor(_conversationId), isFalse);
  });

  test('bootstrap rejects when identity key belongs to a different peer',
      () async {
    final alice = LibCryptoAdapter();
    final bob = LibCryptoAdapter();
    final mallory = LibCryptoAdapter();
    final bobId = await bob.identity.generateDeviceIdentity('device-bob');
    final malloryId =
        await mallory.identity.generateDeviceIdentity('device-mallory');

    // Bob's bundle was signed by Bob's identity key, not Mallory's.
    // If Alice is told "this is Mallory's bundle" but the bundle's sig was
    // produced by Bob, verification against Mallory's identity key must fail.
    await expectLater(
      alice.sessions.bootstrapSession(
        SessionBootstrapRequest(
          conversationId: _conversationId,
          localDeviceId: 'device-alice',
          localUserId: 'device-alice',
          remoteUserId: 'device-mallory',
          remoteDeviceId: 'device-mallory',
          remoteIdentityPublicKey: malloryId.identityPublicKey,
          remoteSignedPrekeyBundle: bobId.signedPrekeyBundle,
        ),
      ),
      throwsA(isA<StateError>()),
    );

    expect(alice.sessions.hasSessionFor(_conversationId), isFalse);
  });

  test('bootstrap accepts a well-formed signed bundle', () async {
    final alice = LibCryptoAdapter();
    final bob = LibCryptoAdapter();
    final bobId = await bob.identity.generateDeviceIdentity('device-bob');

    await alice.sessions.bootstrapSession(
      SessionBootstrapRequest(
        conversationId: _conversationId,
        localDeviceId: 'device-alice',
        localUserId: 'device-alice',
        remoteUserId: 'device-bob',
        remoteDeviceId: 'device-bob',
        remoteIdentityPublicKey: bobId.identityPublicKey,
        remoteSignedPrekeyBundle: bobId.signedPrekeyBundle,
      ),
    );

    expect(alice.sessions.hasSessionFor(_conversationId), isTrue);
  });
}
