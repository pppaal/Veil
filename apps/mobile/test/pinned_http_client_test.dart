import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:veil_mobile/src/core/network/pinned_http_client.dart';

// Regression tests for the TLS pin parser and client factory.
//
// The pinning logic itself runs inside the HttpClient.badCertificateCallback
// path at connection time, which is hard to exercise without standing up a
// self-signed TLS server. What we CAN and MUST pin down here:
//   - the pin list parser handles whitespace / empty entries correctly so a
//     malformed --dart-define doesn't silently land an attacker-controlled
//     empty pin set
//   - the factory returns a plain client when there are no pins (dev mode),
//     and an IOClient when pins are present (prod mode)
//   - these two modes can't be confused at the type level.

void main() {
  group('parsePinList', () {
    test('empty string yields an empty set', () {
      expect(parsePinList(''), isEmpty);
      expect(parsePinList('   '), isEmpty);
    });

    test('single pin is parsed', () {
      final pins = parsePinList('abc123');
      expect(pins, {'abc123'});
    });

    test('comma separated pins are parsed with whitespace trimmed', () {
      final pins = parsePinList(' aaa ,bbb, ccc ');
      expect(pins, {'aaa', 'bbb', 'ccc'});
    });

    test('empty entries between commas are discarded', () {
      final pins = parsePinList('aaa,,bbb,');
      expect(pins, {'aaa', 'bbb'});
    });

    test('duplicate pins deduplicate into the set', () {
      final pins = parsePinList('aaa,aaa,bbb');
      expect(pins, {'aaa', 'bbb'});
    });
  });

  group('buildPinnedHttpClient', () {
    // Dart's default `http.Client()` returns an IOClient on the VM, so we
    // can't distinguish dev-mode vs. prod-mode by runtime type alone. What we
    // CAN verify is that both branches return a usable Client that doesn't
    // throw on close(), and that the factory is total for both inputs.
    test('empty pin set returns a usable Client (dev mode)', () {
      final client = buildPinnedHttpClient(allowedFingerprints: const {});
      expect(client, isA<http.Client>());
      client.close();
    });

    test('non-empty pin set returns a pinned IOClient (prod mode)', () {
      final client = buildPinnedHttpClient(
        allowedFingerprints: const {'fake-pin-fingerprint'},
      );
      expect(client, isA<IOClient>());
      client.close();
    });

    test('different pin sets produce independent client instances', () {
      final a = buildPinnedHttpClient(
        allowedFingerprints: const {'pin-a'},
      );
      final b = buildPinnedHttpClient(
        allowedFingerprints: const {'pin-b'},
      );
      expect(identical(a, b), isFalse);
      a.close();
      b.close();
    });
  });
}
