import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/util/base64url.dart';

void main() {
  test('identity keys decode from padding-less b64url', () {
    final raw = List<int>.generate(32, (i) => i);
    // VEIL stores keys as base64Url without `=` padding.
    const b64NoPad = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';
    expect(base64UrlNoPadDecode(b64NoPad), raw);
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
