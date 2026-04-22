import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Derives a 60-digit "safety number" from two Ed25519 identity public keys.
///
/// Both sides must compute the same number, so the inputs are sorted
/// lexicographically before hashing. The hash is SHA-512 over the concatenated
/// sorted keys; we then chunk the first 60 bytes into 12 groups of 5 bytes,
/// each interpreted as a 40-bit big-endian integer and reduced modulo 10^5
/// to yield five decimal digits per chunk.
///
/// Output: `"12345 67890 12345 67890 12345 67890 12345 67890 12345 67890 12345 67890"`
/// (12 space-separated groups of five digits, 60 digits total).
///
/// The caller is responsible for passing *identity* (Ed25519) public key bytes.
/// This function does no trust-on-first-use storage and has no side effects.
class SafetyNumberResult {
  const SafetyNumberResult({
    required this.digits,
    required this.groups,
  });

  /// Continuous 60-digit string, no separators.
  final String digits;

  /// 12 groups of 5 digits each, ready for UI rendering.
  final List<String> groups;

  /// Space-separated display form.
  String get spaced => groups.join(' ');
}

Future<SafetyNumberResult> computeSafetyNumber({
  required List<int> localIdentityPublicKey,
  required List<int> peerIdentityPublicKey,
}) async {
  if (localIdentityPublicKey.isEmpty || peerIdentityPublicKey.isEmpty) {
    throw ArgumentError('identity key bytes must be non-empty');
  }

  final sorted = _sortedConcatenation(
    localIdentityPublicKey,
    peerIdentityPublicKey,
  );
  final hash = await Sha512().hash(sorted);
  final bytes = Uint8List.fromList(hash.bytes);

  final groups = <String>[];
  for (var i = 0; i < 12; i++) {
    final offset = i * 5;
    final chunk = bytes.sublist(offset, offset + 5);
    var value = 0;
    for (final b in chunk) {
      value = (value << 8) | b;
    }
    final digit = (value % 100000).toString().padLeft(5, '0');
    groups.add(digit);
  }
  return SafetyNumberResult(
    digits: groups.join(),
    groups: groups,
  );
}

Uint8List _sortedConcatenation(List<int> a, List<int> b) {
  final first = _lexLessOrEqual(a, b) ? a : b;
  final second = identical(first, a) ? b : a;
  return Uint8List.fromList(<int>[...first, ...second]);
}

bool _lexLessOrEqual(List<int> a, List<int> b) {
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    if (a[i] < b[i]) return true;
    if (a[i] > b[i]) return false;
  }
  return a.length <= b.length;
}

/// Parses a b64url-encoded identity public key (without padding, as VEIL
/// stores them) into raw bytes.
List<int> decodeIdentityPublicKeyB64(String encoded) {
  final padded = encoded.padRight(
    encoded.length + ((4 - encoded.length % 4) % 4),
    '=',
  );
  return base64Url.decode(padded);
}
