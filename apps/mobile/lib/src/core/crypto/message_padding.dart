import 'dart:typed_data';

/// Length padding for message plaintext, applied just before AES-GCM so the
/// ciphertext length reveals only a coarse bucket instead of the exact
/// message size. Without this the server (and any network observer) learns
/// the plaintext length of every message — enough to fingerprint content and
/// behaviour even though the bytes stay encrypted.
///
/// Scheme: ISO/IEC 7816-4 delimiter (`0x80` then `0x00` filler) up to the
/// next [bucketFor] size. The delimiter makes unpadding unambiguous
/// regardless of plaintext content — including plaintext that itself ends in
/// `0x00` or `0x80` (UTF-8 continuation) bytes — because we strip trailing
/// zeros and then exactly one `0x80`.
class MessagePadding {
  MessagePadding._();

  /// Smallest bucket. Every message is at least this many bytes, so short
  /// messages ("ok", "응", a reaction) are indistinguishable by size.
  static const int minBucket = 256;

  /// Granularity for messages larger than the doubling ladder's top.
  static const int stepBucket = 65536; // 64 KiB

  /// Smallest bucket that can hold [n] bytes: powers of two from [minBucket]
  /// up to [stepBucket], then multiples of [stepBucket].
  static int bucketFor(int n) {
    var b = minBucket;
    while (b < n && b < stepBucket) {
      b <<= 1;
    }
    if (n <= b) {
      return b;
    }
    return ((n + stepBucket - 1) ~/ stepBucket) * stepBucket;
  }

  /// Pad [data] to a bucket. Always appends at least the `0x80` delimiter, so
  /// the output length is `bucketFor(data.length + 1)`.
  static Uint8List pad(List<int> data) {
    final target = bucketFor(data.length + 1);
    final out = Uint8List(target); // zero-filled by default
    out.setRange(0, data.length, data);
    out[data.length] = 0x80;
    return out;
  }

  /// Reverse [pad]. Lenient by design: input with no valid `0x80` delimiter is
  /// returned unchanged, so a receiver can read both padded and legacy
  /// unpadded plaintext during a rollout. (Legacy UTF-8 JSON ends in `}` —
  /// never `0x00`, never a bare trailing `0x80` — so there is no ambiguity.)
  static Uint8List unpad(List<int> padded) {
    var i = padded.length - 1;
    while (i >= 0 && padded[i] == 0x00) {
      i--;
    }
    if (i < 0 || padded[i] != 0x80) {
      return Uint8List.fromList(padded); // not padded — legacy path
    }
    return Uint8List.fromList(padded.sublist(0, i));
  }
}
