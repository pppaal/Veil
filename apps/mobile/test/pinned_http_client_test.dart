import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/network/pinned_http_client.dart';

// pin_fixture_*.pem live in test/transport/fixtures/ (self-signed, keys
// discarded). The expected fingerprints were computed with OpenSSL 3.0 when
// the fixtures were generated, independently of the Dart code under test:
//   SPKI: openssl x509 -in F -pubkey -noout | openssl pkey -pubin -outform der
//           | openssl dgst -sha256 -binary | base64
//   leaf: openssl x509 -in F -outform der | openssl dgst -sha256 -binary | base64
const _ecSpkiPin = 'tNsbXtI0gVw80AwhaKT80P196yi3fO+WjXBfmligOE8=';
const _ecLeafPin = 'D4pGj8n0Mzu/Trl0/Hd8dSPTMzJNIRfdViV/HNXBJck=';
const _rsaSpkiPin = 'cHyjuX7zny7ERZx+b/vm5oGBeSyHWNlHih4Ibhg2Y9c=';
const _rsaLeafPin = 'ERPZvUMia6bzY7OVp/PehYEpvWZsDzkgFMyVOtx2k60=';

class _FixtureCertificate extends Fake implements X509Certificate {
  _FixtureCertificate.fromPemFile(String path)
      : der = base64Decode(
          File(path)
              .readAsLinesSync()
              .where((line) => !line.startsWith('-----'))
              .join(),
        );

  @override
  final Uint8List der;
}

void main() {
  final ecCert =
      _FixtureCertificate.fromPemFile('test/transport/fixtures/pin_fixture_ec.pem');
  final rsaCert =
      _FixtureCertificate.fromPemFile('test/transport/fixtures/pin_fixture_rsa.pem');

  group('parsePinList', () {
    test('empty string yields an empty set', () {
      expect(parsePinList(''), isEmpty);
      expect(parsePinList('   '), isEmpty);
    });

    test('comma separated pins are parsed with whitespace trimmed', () {
      expect(parsePinList(' aaa ,spki:bbb, leaf:ccc '), {'aaa', 'spki:bbb', 'leaf:ccc'});
    });

    test('empty entries between commas are discarded', () {
      expect(parsePinList('aaa,,bbb,'), {'aaa', 'bbb'});
    });

    test('duplicate pins deduplicate into the set', () {
      expect(parsePinList('aaa,aaa,bbb'), {'aaa', 'bbb'});
    });
  });

  group('fingerprints', () {
    test('spki pin matches fixture certificate', () {
      // EC P-256 has a short-form SPKI length, RSA-2048 a long-form one.
      expect(computeSpkiFingerprint(ecCert), _ecSpkiPin);
      expect(computeSpkiFingerprint(rsaCert), _rsaSpkiPin);
      expect(CertificatePinVerifier({'spki:$_ecSpkiPin'}).matches(ecCert), isTrue);
      expect(CertificatePinVerifier({'spki:$_ecSpkiPin'}).matches(rsaCert), isFalse);
    });

    test('leaf prefix and legacy pins accepted', () {
      expect(computeLeafFingerprint(ecCert), _ecLeafPin);
      expect(CertificatePinVerifier({'leaf:$_ecLeafPin'}).matches(ecCert), isTrue);
      expect(CertificatePinVerifier({_ecLeafPin}).matches(ecCert), isTrue);
      expect(CertificatePinVerifier({_ecLeafPin}).matches(rsaCert), isFalse);
      expect(
        CertificatePinVerifier({'spki:$_ecSpkiPin', 'leaf:$_rsaLeafPin'}).matches(rsaCert),
        isTrue,
      );
    });

    test('a leaf hash is not accepted as an spki pin', () {
      expect(CertificatePinVerifier({'spki:$_ecLeafPin'}).matches(ecCert), isFalse);
    });

    test('unknown pin prefixes are rejected loudly', () {
      expect(
        () => CertificatePinVerifier({'sha256:$_ecSpkiPin'}),
        throwsFormatException,
      );
      // OkHttp's pin syntax: '/' is base64, so only the length gives it away.
      expect(
        () => CertificatePinVerifier({'sha256/$_ecSpkiPin'}),
        throwsFormatException,
      );
    });

    test('pins that are not a canonical base64 SHA-256 are rejected', () {
      final digest = base64Decode(_ecSpkiPin);
      final hex = digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      for (final malformed in [
        'spki:$hex',
        'spki:${base64Url.encode(digest)}',
        'leaf:${_ecLeafPin.replaceAll('=', '')}',
        _ecLeafPin.substring(0, 40),
        'spki:${base64Encode(digest.sublist(0, 20))}',
      ]) {
        expect(
          () => CertificatePinVerifier({malformed}),
          throwsFormatException,
          reason: malformed,
        );
      }
    });

    test('malformed certificate DER is a FormatException, never a match', () {
      final truncated = Uint8List.sublistView(ecCert.der, 0, 40);
      expect(() => subjectPublicKeyInfoDer(truncated), throwsFormatException);
      expect(
        () => subjectPublicKeyInfoDer(Uint8List.fromList([0x02, 0x01, 0x00])),
        throwsFormatException,
      );
    });
  });

  // Which certificate the pins are checked against, and that a mismatch stops
  // the request before it is sent, needs a real TLS server with a real chain:
  // see test/transport/pinned_tls_handshake_test.dart.
  group('client factories', () {
    test('no pins -> null client', () {
      expect(buildPinnedDartIoHttpClient(const {}), isNull);
      expect(buildPinnedDartIoHttpClient(parsePinList('  ')), isNull);
    });

    test('pins produce a dart:io client for the WebSocket upgrade', () {
      final client = buildPinnedDartIoHttpClient({'spki:$_ecSpkiPin'});
      expect(client, isA<HttpClient>());
      client!.close(force: true);
    });

    test('a malformed pin fails when the client is built, not on first use', () {
      expect(
        () => buildPinnedHttpClient(allowedFingerprints: {'sha256/$_ecSpkiPin'}),
        throwsFormatException,
      );
    });
  });
}
