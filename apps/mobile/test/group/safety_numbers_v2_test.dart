import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/features/security/domain/safety_numbers.dart';

// Cross-language vectors written by scripts/safety-number-vectors.mjs
// (node:crypto). Tests run from apps/mobile, so the repo root is two up.
const _vectorsPath = '../../packages/shared/test-vectors/safety-number-v2.json';

List<int> _hex(String hex) =>
    [for (var i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];

void main() {
  late Map<String, dynamic> vectors;
  late Map<String, dynamic> alice;
  late Map<String, dynamic> bob;
  late List<int> aliceKey;
  late List<int> bobKey;

  setUpAll(() {
    final file = json.decode(File(_vectorsPath).readAsStringSync()) as Map<String, dynamic>;
    vectors = file['vectors'] as Map<String, dynamic>;
    alice = vectors['alice'] as Map<String, dynamic>;
    bob = vectors['bob'] as Map<String, dynamic>;
    aliceKey = _hex(alice['identityPublicKey'] as String);
    bobKey = _hex(bob['identityPublicKey'] as String);
  });

  String number({
    required String localUserId,
    required List<int> localKey,
    required String remoteUserId,
    required List<int> remoteKey,
  }) =>
      computeSafetyNumberV2(
        localUserId: localUserId,
        localIdentityKey: localKey,
        remoteUserId: remoteUserId,
        remoteIdentityKey: remoteKey,
      );

  test('matches shared vectors', () async {
    // The contract (C8) values, so the file itself cannot drift unnoticed.
    expect(vectors['safetyNumber'], '082577859417519724042399200716219577104575101292709615301410');

    for (final party in [alice, bob]) {
      final derived = await (await Ed25519().newKeyPairFromSeed(_hex(party['seed'] as String))).extractPublicKey();
      expect(derived.bytes, _hex(party['identityPublicKey'] as String));
      expect(
        computeSafetyFingerprint(
          version: kSafetyNumberVersion,
          identityKey: derived.bytes,
          userId: party['userId'] as String,
        ),
        party['fingerprint'],
      );
    }

    final fromAlice = number(
      localUserId: alice['userId'] as String,
      localKey: aliceKey,
      remoteUserId: bob['userId'] as String,
      remoteKey: bobKey,
    );
    final fromBob = number(
      localUserId: bob['userId'] as String,
      localKey: bobKey,
      remoteUserId: alice['userId'] as String,
      remoteKey: aliceKey,
    );
    expect(fromAlice, vectors['safetyNumber']);
    expect(fromBob, vectors['safetyNumber']);
    expect(formatSafetyNumber(fromAlice).join(' '), vectors['formatted']);

    final binding = vectors['userIdBinding'] as Map<String, dynamic>;
    expect(
      computeSafetyFingerprint(
        version: kSafetyNumberVersion,
        identityKey: _hex(binding['identityPublicKey'] as String),
        userId: binding['userId'] as String,
      ),
      binding['fingerprint'],
    );

    final qr = vectors['qr'] as Map<String, dynamic>;
    expect(
      encodeSafetyQrPayload(
        localUserId: alice['userId'] as String,
        localIdentityKey: aliceKey,
        remoteUserId: bob['userId'] as String,
        remoteIdentityKey: bobKey,
      ),
      qr['aliceView'],
    );
    expect(
      encodeSafetyQrPayload(
        localUserId: bob['userId'] as String,
        localIdentityKey: bobKey,
        remoteUserId: alice['userId'] as String,
        remoteIdentityKey: aliceKey,
      ),
      qr['bobView'],
    );
  });

  test('different userIds with same keys differ', () {
    final original = number(
      localUserId: alice['userId'] as String,
      localKey: aliceKey,
      remoteUserId: bob['userId'] as String,
      remoteKey: bobKey,
    );
    final relabelled = number(
      localUserId: alice['userId'] as String,
      localKey: aliceKey,
      remoteUserId: 'mallory',
      remoteKey: bobKey,
    );
    expect(relabelled, isNot(original));
  });

  test('version byte change changes number', () {
    final v2 = computeSafetyFingerprint(
      version: kSafetyNumberVersion,
      identityKey: aliceKey,
      userId: alice['userId'] as String,
    );
    final v3 = computeSafetyFingerprint(version: 3, identityKey: aliceKey, userId: alice['userId'] as String);
    expect(v3, isNot(v2));
    expect(v3, (vectors['versionBinding'] as Map<String, dynamic>)['fingerprint']);
  });

  test('QR round trip verifies and swapped key fails', () async {
    final aliceShows = encodeSafetyQrPayload(
      localUserId: alice['userId'] as String,
      localIdentityKey: aliceKey,
      remoteUserId: bob['userId'] as String,
      remoteIdentityKey: bobKey,
    );
    SafetyQrVerification bobScans(String payload, {List<int>? expectedAliceKey}) => verifyScannedSafetyQr(
          scannedPayload: payload,
          localUserId: bob['userId'] as String,
          localIdentityKey: bobKey,
          remoteUserId: alice['userId'] as String,
          remoteIdentityKey: expectedAliceKey ?? aliceKey,
        );

    expect(bobScans(aliceShows), SafetyQrVerification.verified);

    // The server swapped alice's key for its own in bob's view.
    final mallory = (await (await Ed25519().newKeyPair()).extractPublicKey()).bytes;
    expect(bobScans(aliceShows, expectedAliceKey: mallory), SafetyQrVerification.mismatch);

    // bob's own code is not the role-swapped payload.
    final bobShows = encodeSafetyQrPayload(
      localUserId: bob['userId'] as String,
      localIdentityKey: bobKey,
      remoteUserId: alice['userId'] as String,
      remoteIdentityKey: aliceKey,
    );
    expect(bobScans(bobShows), SafetyQrVerification.mismatch);

    final bytes = base64Url.decode(base64Url.normalize(aliceShows));
    final otherVersion = List<int>.from(bytes)..[6] = 3;
    expect(
      bobScans(base64Url.encode(otherVersion).replaceAll('=', '')),
      SafetyQrVerification.unsupportedVersion,
    );
    expect(bobScans('not a qr code!'), SafetyQrVerification.malformed);
    expect(bobScans(base64Url.encode(utf8.encode('OTHER!x'))), SafetyQrVerification.malformed);
  });

  test('formatSafetyNumber rejects anything but 60 digits', () {
    expect(() => formatSafetyNumber('123'), throwsArgumentError);
    expect(() => formatSafetyNumber('x' * 60), throwsArgumentError);
  });
}
