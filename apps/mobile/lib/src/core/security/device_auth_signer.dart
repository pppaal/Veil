import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../crypto/crypto_engine.dart';

class Ed25519DeviceAuthChallengeSigner implements DeviceAuthChallengeSigner {
  const Ed25519DeviceAuthChallengeSigner();

  static final Ed25519 _algorithm = Ed25519();

  @override
  Future<DeviceAuthKeyMaterial> generateAuthKeyMaterial() async {
    final keyPair = await _algorithm.newKeyPair();
    final keyPairData = await keyPair.extract();
    final publicKey = await keyPair.extractPublicKey();

    return DeviceAuthKeyMaterial(
      publicKey: _encode(publicKey.bytes),
      privateKey: _encode(keyPairData.bytes),
    );
  }

  @override
  Future<String> signChallenge({
    required String challenge,
    required DeviceAuthKeyMaterial keyMaterial,
  }) async {
    final publicKey = SimplePublicKey(
      _decode(keyMaterial.publicKey),
      type: KeyPairType.ed25519,
    );
    final keyPair = SimpleKeyPairData(
      _decode(keyMaterial.privateKey),
      publicKey: publicKey,
      type: KeyPairType.ed25519,
    );

    final signature = await _algorithm.sign(
      utf8.encode(challenge),
      keyPair: keyPair,
    );
    return _encode(signature.bytes);
  }

  static String _encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static List<int> _decode(String value) {
    final normalized = value.padRight(
      value.length + ((4 - value.length % 4) % 4),
      '=',
    );
    return base64Url.decode(normalized);
  }
}
