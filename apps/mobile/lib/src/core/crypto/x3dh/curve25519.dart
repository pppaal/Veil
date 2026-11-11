import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../bytes.dart';
import '../random_source.dart';

/// Thin byte-oriented wrappers over package:cryptography's X25519/Ed25519 so
/// the protocol code handles plain buffers it owns (and can zeroize) instead
/// of key objects whose internal copies it cannot reach.

final X25519 _x25519 = X25519();
final Ed25519 _ed25519 = Ed25519();

class X25519KeyPair {
  X25519KeyPair(this.privateKey, this.publicKey);

  final Uint8List privateKey;
  final Uint8List publicKey;
}

Future<X25519KeyPair> x25519KeyPairFromPrivate(List<int> privateKey) async {
  final pair = await _x25519.newKeyPairFromSeed(Uint8List.fromList(privateKey));
  final publicKey = await pair.extractPublicKey();
  return X25519KeyPair(Uint8List.fromList(privateKey), Uint8List.fromList(publicKey.bytes));
}

Future<X25519KeyPair> generateX25519KeyPair(RandomSource random) async {
  final seed = random.nextBytes(32);
  final pair = await x25519KeyPairFromPrivate(seed);
  zeroize(seed);
  return pair;
}

/// X25519 Diffie-Hellman. Throws [FormatException] on an all-zero output, the
/// signature of a low-order peer key.
Future<Uint8List> x25519SharedSecret(List<int> privateKey, List<int> publicKey) async {
  if (publicKey.length != 32) {
    throw const FormatException('X25519 public key must be 32 bytes');
  }
  final pair = await _x25519.newKeyPairFromSeed(Uint8List.fromList(privateKey));
  final secret = await _x25519.sharedSecretKey(
    keyPair: pair,
    remotePublicKey: SimplePublicKey(Uint8List.fromList(publicKey), type: KeyPairType.x25519),
  );
  final out = Uint8List.fromList(await secret.extractBytes());
  secret.destroy();
  if (isAllZero(out)) {
    throw const FormatException('rejected low-order X25519 public key');
  }
  return out;
}

Future<Uint8List> ed25519PublicKeyFromSeed(List<int> seed) async {
  final pair = await _ed25519.newKeyPairFromSeed(Uint8List.fromList(seed));
  return Uint8List.fromList((await pair.extractPublicKey()).bytes);
}

Future<Uint8List> ed25519Sign(List<int> seed, List<int> message) async {
  final pair = await _ed25519.newKeyPairFromSeed(Uint8List.fromList(seed));
  final signature = await _ed25519.sign(message, keyPair: pair);
  return Uint8List.fromList(signature.bytes);
}

Future<bool> ed25519Verify(List<int> publicKey, List<int> message, List<int> signature) {
  if (publicKey.length != 32 || signature.length != 64) return Future.value(false);
  return _ed25519.verify(
    message,
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
    ),
  );
}
