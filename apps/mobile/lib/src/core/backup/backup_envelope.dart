import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

// User-visible backup blob: a passphrase-sealed AES-256-GCM envelope.
// Format (ASCII, single line):
//   veilbak:v1:<salt>:<nonce>:<ciphertext>:<mac>
// where each field is base64url (padding-stripped). The passphrase never
// touches disk; we re-derive the key on restore. PBKDF2-SHA256 with 600k
// iterations meets OWASP 2023 guidance, portable across pure-dart targets
// without pulling a native Argon2 dependency. When cryptography_flutter is
// available a future revision can switch to Argon2id under the same prefix
// by bumping the version marker.
class BackupEnvelope {
  BackupEnvelope._();

  static const _magic = 'veilbak';
  static const _version = 'v1';
  static const _prefix = '$_magic:$_version';
  static const int _saltBytes = 16;
  static const int _nonceBytes = 12;
  static const int _iterations = 600000;
  static const int _keyBytes = 32;

  static final _rng = Random.secure();
  static final AesGcm _cipher = AesGcm.with256bits();

  static Future<String> seal(String passphrase, List<int> plaintext) async {
    if (passphrase.isEmpty) {
      throw ArgumentError.value(passphrase, 'passphrase', 'must not be empty');
    }

    final salt = _randomBytes(_saltBytes);
    final nonce = _randomBytes(_nonceBytes);
    final key = await _deriveKey(passphrase, salt);

    final secretBox = await _cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );

    return [
      _prefix,
      _b64(salt),
      _b64(secretBox.nonce),
      _b64(secretBox.cipherText),
      _b64(secretBox.mac.bytes),
    ].join(':');
  }

  static Future<Uint8List> open(String passphrase, String envelope) async {
    if (passphrase.isEmpty) {
      throw ArgumentError.value(passphrase, 'passphrase', 'must not be empty');
    }
    if (!envelope.startsWith('$_prefix:')) {
      throw const FormatException('Not a Veil backup envelope');
    }

    final parts = envelope.split(':');
    if (parts.length != 6) {
      throw const FormatException('Malformed Veil backup envelope');
    }

    final salt = _fromB64(parts[2]);
    final nonce = _fromB64(parts[3]);
    final cipherText = _fromB64(parts[4]);
    final mac = _fromB64(parts[5]);
    final key = await _deriveKey(passphrase, salt);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(mac));
    final plaintext = await _cipher.decrypt(secretBox, secretKey: key);
    return Uint8List.fromList(plaintext);
  }

  static Future<SecretKey> _deriveKey(String passphrase, List<int> salt) async {
    final kdf = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _iterations,
      bits: _keyBytes * 8,
    );
    return kdf.deriveKeyFromPassword(password: passphrase, nonce: salt);
  }

  static Uint8List _randomBytes(int count) {
    final bytes = Uint8List(count);
    for (var i = 0; i < count; i++) {
      bytes[i] = _rng.nextInt(256);
    }
    return bytes;
  }

  static String _b64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  static Uint8List _fromB64(String value) {
    final padLen = (4 - value.length % 4) % 4;
    return base64Url.decode(value.padRight(value.length + padLen, '='));
  }
}
