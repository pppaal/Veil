/// Byte-level helpers shared by every crypto component, so wire encodings
/// (base64url without padding, big-endian integers, length prefixes) are
/// defined exactly once.
library;

import 'dart:convert';
import 'dart:typed_data';

String b64uEncode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

Uint8List b64uDecode(String value) {
  final padded = value.padRight(value.length + ((4 - value.length % 4) % 4), '=');
  return Uint8List.fromList(base64Url.decode(padded));
}

String hexEncode(List<int> bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// Length-independent-time comparison for secrets and MACs.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// An all-zero X25519 output (or peer key) signals a low-order point and must
/// be rejected rather than fed into a KDF.
bool isAllZero(List<int> bytes) {
  var acc = 0;
  for (final b in bytes) {
    acc |= b;
  }
  return bytes.isNotEmpty && acc == 0;
}

/// Unsigned lexicographic byte order; used to break glare ties identically
/// on both peers.
int compareBytes(List<int> a, List<int> b) {
  final shared = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < shared; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

Uint8List u16be(int value) => Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.big);

Uint8List u32be(int value) => Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.big);

/// Written as two 32-bit halves so the encoding does not depend on 64-bit
/// ByteData support.
Uint8List u64be(int value) {
  final out = Uint8List(8);
  final view = out.buffer.asByteData();
  view.setUint32(0, (value ~/ 0x100000000) & 0xFFFFFFFF, Endian.big);
  view.setUint32(4, value & 0xFFFFFFFF, Endian.big);
  return out;
}

// The top byte is multiplied rather than shifted so the result stays
// unsigned where ints are 32-bit signed (dart2js).
int readU32be(List<int> bytes, int offset) =>
    bytes[offset] * 0x1000000 + ((bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3]);

Uint8List concatBytes(Iterable<List<int>> parts) {
  final builder = BytesBuilder(copy: false);
  for (final part in parts) {
    builder.add(part);
  }
  return builder.toBytes();
}

/// u16be(byteLength) || utf8(value): makes concatenated variable-length
/// fields unambiguous inside associated data.
Uint8List lengthPrefixedUtf8(String value) {
  final bytes = utf8.encode(value);
  if (bytes.length > _maxLengthPrefixed) {
    throw ArgumentError.value(value.length, 'value', 'too long for a u16 length prefix');
  }
  return concatBytes([u16be(bytes.length), bytes]);
}

/// Whether [lengthPrefixedUtf8] can encode [value], so a field taken off the
/// wire can be rejected as data instead of surfacing as the encoder's error.
bool fitsLengthPrefix(String value) => utf8.encode(value).length <= _maxLengthPrefixed;

const int _maxLengthPrefixed = 0xFFFF;

/// Overwrites a buffer we own. Dart cannot guarantee the bytes were never
/// copied (GC moves, immutable Strings), so this only shortens how long the
/// secret stays in memory we control.
void zeroize(List<int>? buffer) {
  if (buffer == null) return;
  buffer.fillRange(0, buffer.length, 0);
}
