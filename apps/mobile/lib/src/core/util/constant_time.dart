/// Compares two byte sequences without an early exit on the first differing
/// byte, so the comparison time does not reveal how much of a secret or a
/// verification code matched. Lengths are not treated as secret.
bool constantTimeBytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
