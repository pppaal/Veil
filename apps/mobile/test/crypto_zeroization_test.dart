import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

// Validates the primitive the adapter's _wipeKey relies on: destroying a
// SecretKey zeroes/invalidates its bytes so it can no longer be used. The
// adapter wipes transient per-message keys (after encrypt/decrypt) and
// skipped message keys (on eviction/clear) on top of this.
void main() {
  test('destroy() makes a SecretKey unusable (best-effort wipe)', () async {
    final key = SecretKey(List<int>.filled(32, 0x5A));

    final before = await key.extractBytes();
    expect(before, hasLength(32));
    expect(before.every((b) => b == 0x5A), isTrue);

    key.destroy();

    // After destroy the key must not yield usable bytes (sync- or async-
    // thrown are both acceptable).
    var threw = false;
    try {
      await key.extractBytes();
    } catch (_) {
      threw = true;
    }
    expect(threw, isTrue, reason: 'destroyed key must not extract bytes');
  });
}
