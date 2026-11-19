import 'dart:convert';
import 'dart:typed_data';

/// Unpadded base64url, the encoding VEIL uses for every key and blob on the
/// wire and in storage.
String base64UrlNoPadEncode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Decodes base64url with or without `=` padding. Throws [FormatException] on
/// malformed input.
Uint8List base64UrlNoPadDecode(String value) {
  final padded = value.padRight(value.length + ((4 - value.length % 4) % 4), '=');
  return base64Url.decode(padded);
}
