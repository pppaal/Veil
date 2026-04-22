import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/features/security/domain/safety_numbers.dart';

void main() {
  group('computeSafetyNumber', () {
    test('both parties compute the same 60-digit number', () async {
      final alice = List<int>.generate(32, (i) => i);
      final bob = List<int>.generate(32, (i) => 0xff - i);

      final fromAlice = await computeSafetyNumber(
        localIdentityPublicKey: alice,
        peerIdentityPublicKey: bob,
      );
      final fromBob = await computeSafetyNumber(
        localIdentityPublicKey: bob,
        peerIdentityPublicKey: alice,
      );

      expect(fromAlice.digits, fromBob.digits);
      expect(fromAlice.digits.length, 60);
      expect(fromAlice.groups, hasLength(12));
      for (final group in fromAlice.groups) {
        expect(group.length, 5);
        expect(int.tryParse(group), isNotNull);
      }
    });

    test('number changes when either identity key changes', () async {
      final alice = List<int>.generate(32, (i) => i);
      final bob = List<int>.generate(32, (i) => 0xff - i);
      final mallory = List<int>.generate(32, (i) => (i * 7) & 0xff);

      final aliceBob = await computeSafetyNumber(
        localIdentityPublicKey: alice,
        peerIdentityPublicKey: bob,
      );
      final aliceMallory = await computeSafetyNumber(
        localIdentityPublicKey: alice,
        peerIdentityPublicKey: mallory,
      );

      expect(aliceBob.digits, isNot(aliceMallory.digits));
    });

    test('spaced form joins 12 groups with single spaces', () async {
      final alice = List<int>.generate(32, (i) => i);
      final bob = List<int>.generate(32, (i) => 0xff - i);
      final result = await computeSafetyNumber(
        localIdentityPublicKey: alice,
        peerIdentityPublicKey: bob,
      );
      expect(result.spaced.split(' '), hasLength(12));
      expect(result.spaced.replaceAll(' ', ''), result.digits);
    });

    test('rejects empty key bytes', () async {
      expect(
        computeSafetyNumber(
          localIdentityPublicKey: const <int>[],
          peerIdentityPublicKey: const <int>[1, 2, 3],
        ),
        throwsArgumentError,
      );
    });

    test('decodeIdentityPublicKeyB64 round-trips padding-less b64url', () {
      final raw = List<int>.generate(32, (i) => i);
      // VEIL stores keys as base64Url without `=` padding.
      const b64NoPad = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
      final decoded = decodeIdentityPublicKeyB64(b64NoPad);
      expect(decoded, raw);
    });
  });

  group('extractIdentityPublicKeyFromPrivateRef', () {
    test('lib adapter round-trips Ed25519 pub from stored private ref',
        () async {
      final adapter = LibCryptoAdapter();
      final DeviceIdentityMaterial generated =
          await adapter.identity.generateDeviceIdentity('device-a');

      final recovered = await adapter.identity
          .extractIdentityPublicKeyFromPrivateRef(
        generated.identityPrivateKeyRef,
      );

      expect(recovered, generated.identityPublicKey);
    });
  });
}
