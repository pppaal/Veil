import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class LocalDataCipher {
  LocalDataCipher._(this._secretKey);

  static const _encodingPrefix = 'enc:v1:';
  static final AesGcm _algorithm = AesGcm.with256bits();
  static final Random _random = Random.secure();

  final SecretKey _secretKey;

  static Future<LocalDataCipher> fromBase64Key(String base64Key) async {
    return LocalDataCipher._(SecretKey(_decode(base64Key)));
  }

  static LocalDataCipher forTesting(String base64Key) {
    return LocalDataCipher._(SecretKey(_decode(base64Key)));
  }

  Future<String?> encryptNullable(String? value) async {
    if (value == null) {
      return null;
    }
    return encryptString(value);
  }

  Future<String?> decryptNullable(String? value) async {
    if (value == null) {
      return null;
    }
    return decryptString(value);
  }

  Future<String> encryptString(String value) async {
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final secretBox = await _algorithm.encrypt(
      utf8.encode(value),
      secretKey: _secretKey,
      nonce: nonce,
    );
    return [
      _encodingPrefix,
      _encode(secretBox.nonce),
      _encode(secretBox.cipherText),
      _encode(secretBox.mac.bytes),
    ].join(':');
  }

  Future<String> decryptString(String value) async {
    if (!value.startsWith(_encodingPrefix)) {
      throw const FormatException('Unencrypted payload is not accepted');
    }

    // encryptString joins the prefix (which already ends in ':') with ':',
    // so every value ever written reads "enc:v1::nonce:ciphertext:mac".
    final parts = value.substring(_encodingPrefix.length).split(':');
    if (parts.length != 4 || parts.first.isNotEmpty) {
      throw const FormatException('Invalid encrypted payload format');
    }

    final secretBox = SecretBox(
      _decode(parts[2]),
      nonce: _decode(parts[1]),
      mac: Mac(_decode(parts[3])),
    );
    final cleartext = await _algorithm.decrypt(
      secretBox,
      secretKey: _secretKey,
    );
    return utf8.decode(cleartext);
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
