import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Client-side crypto for one-time secret links, wire-compatible with the web
/// viewer (`apps/web-demo/s.html`). The server only ever stores the opaque
/// [SealedSecret.blob]; the key rides in the link fragment and never leaves
/// the device.
///
/// Formats (must match s.html exactly):
/// - key mode:  blob = `v1.<iv>.<ct>`            fragment = `k.<rawKey>`
/// - pass mode: blob = `v1.<iv>.<ct>.<salt>`     fragment = `p`
///
/// where `ct = AES-256-GCM ciphertext || 16-byte tag` (WebCrypto appends the
/// tag, so we concatenate `cipherText || mac` to interoperate), all parts are
/// base64url without padding, iv is 12 bytes, salt is 16 bytes, and the
/// passphrase key is PBKDF2-HMAC-SHA256, 210000 iterations, 256-bit.
class SealedSecret {
  const SealedSecret({required this.blob, required this.fragment});

  /// Opaque ciphertext stored server-side (no key material).
  final String blob;

  /// Goes in the link fragment after the id: `#<id>.<fragment>`.
  final String fragment;
}

class OneTimeLink {
  OneTimeLink._();

  static final AesGcm _aesGcm = AesGcm.with256bits();
  static final Random _rng = Random.secure();
  static const int _pbkdf2Iterations = 210000;

  static List<int> _randomBytes(int n) =>
      List<int>.generate(n, (_) => _rng.nextInt(256));

  static String _b64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List _unb64(String value) {
    final padded = value.padRight((value.length + 3) & ~3, '=');
    return Uint8List.fromList(base64Url.decode(padded));
  }

  static Future<SecretKey> _deriveKey(String passphrase, List<int> salt) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pbkdf2Iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  /// Encrypt [plaintext]. With a [passphrase] the key is derived from it
  /// (only the salt travels, in the blob); without one a random key is
  /// generated and travels in the fragment.
  static Future<SealedSecret> seal(
    String plaintext, {
    String? passphrase,
  }) async {
    final iv = _aesGcm.newNonce();
    final SecretKey key;
    final String fragment;
    List<int>? salt;

    if (passphrase != null && passphrase.isNotEmpty) {
      salt = _randomBytes(16); // 16-byte salt to match the web viewer
      key = await _deriveKey(passphrase, salt);
      fragment = 'p';
    } else {
      key = await _aesGcm.newSecretKey();
      final raw = await key.extractBytes();
      fragment = 'k.${_b64(raw)}';
    }

    final box = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: iv,
    );
    // WebCrypto returns ciphertext||tag; concatenate to interoperate.
    final ct = <int>[...box.cipherText, ...box.mac.bytes];

    final blob = salt == null
        ? 'v1.${_b64(iv)}.${_b64(ct)}'
        : 'v1.${_b64(iv)}.${_b64(ct)}.${_b64(salt)}';
    return SealedSecret(blob: blob, fragment: fragment);
  }

  /// Reverse [seal]. Provided mainly for round-trip testing; the production
  /// reader is the web viewer. [fragment] is the part after the id.
  static Future<String> open(String blob, String fragment,
      {String? passphrase}) async {
    final parts = blob.split('.');
    if (parts.first != 'v1' || parts.length < 3) {
      throw const FormatException('bad blob');
    }
    final iv = _unb64(parts[1]);
    final ctTag = _unb64(parts[2]);
    final cipherText = ctTag.sublist(0, ctTag.length - 16);
    final mac = Mac(ctTag.sublist(ctTag.length - 16));

    final SecretKey key;
    if (fragment.startsWith('k.')) {
      key = SecretKey(_unb64(fragment.substring(2)));
    } else {
      if (passphrase == null) throw const FormatException('passphrase required');
      key = await _deriveKey(passphrase, _unb64(parts[3]));
    }

    final clear = await _aesGcm.decrypt(
      SecretBox(cipherText, nonce: iv, mac: mac),
      secretKey: key,
    );
    return utf8.decode(clear);
  }
}
