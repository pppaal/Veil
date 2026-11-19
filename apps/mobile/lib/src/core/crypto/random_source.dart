import 'dart:math';
import 'dart:typed_data';

/// Single entry point for every random byte the crypto layer consumes (key
/// pairs, nonces, attachment keys). Injectable so known-answer tests can
/// replay a scripted sequence and reproduce wire bytes exactly.
abstract class RandomSource {
  Uint8List nextBytes(int length);
}

class SecureRandomSource implements RandomSource {
  SecureRandomSource() : _random = Random.secure();

  final Random _random;

  @override
  Uint8List nextBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }
}
