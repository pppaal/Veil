import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

// TLS certificate pinning.
//
// Without pinning, a MITM who compromises (or coerces) any CA trusted by the
// platform root store can transparently intercept traffic to the API host.
// Pinning moves trust off the platform root store and onto a small set of
// SHA-256 DER fingerprints shipped in the app binary (typically provided via
// `--dart-define VEIL_TLS_PINS=...`).
//
// Wire format of a pin is the base64-encoded SHA-256 of the leaf certificate's
// full DER bytes — i.e. `openssl x509 -in cert.pem -outform DER | sha256sum`.
// Leaf-DER pinning (vs. SPKI pinning) is a deliberate trade-off: the `dart:io`
// X509Certificate API exposes `.der` directly, so we can pin without parsing
// DER ourselves. The operator is responsible for adding a new pin BEFORE
// rotating the server's certificate — otherwise clients lock themselves out.

class PinnedCertificateException implements Exception {
  const PinnedCertificateException(this.host, this.fingerprint);
  final String host;
  final String fingerprint;
  @override
  String toString() =>
      'TLS certificate pin mismatch for $host (observed fingerprint '
      '$fingerprint is not in the trusted pin set).';
}

String computeLeafFingerprint(X509Certificate cert) {
  return base64Encode(sha256.convert(cert.der).bytes);
}

/// Parses a comma-separated list of base64 SHA-256 leaf-cert pins. Empty
/// entries and surrounding whitespace are trimmed. Returns an empty set if
/// [raw] is empty, which signals the caller to skip pinning.
Set<String> parsePinList(String raw) {
  if (raw.trim().isEmpty) {
    return const <String>{};
  }
  return raw
      .split(',')
      .map((pin) => pin.trim())
      .where((pin) => pin.isNotEmpty)
      .toSet();
}

/// Returns an HTTP client that only completes TLS handshakes whose leaf
/// certificate's SHA-256 fingerprint matches one of [allowedFingerprints].
///
/// When [allowedFingerprints] is empty, returns a plain [http.Client] —
/// callers can use this to gate pinning on a config switch so dev builds
/// (which don't have a stable cert to pin against) still work.
http.Client buildPinnedHttpClient({
  required Set<String> allowedFingerprints,
  Duration connectionTimeout = const Duration(seconds: 15),
}) {
  if (allowedFingerprints.isEmpty) {
    return http.Client();
  }

  // `withTrustedRoots: false` strips the platform root store so that EVERY
  // connection has to pass our badCertificateCallback — which is the only
  // place we get the peer certificate. Without this, platform-trusted certs
  // bypass the callback entirely, defeating the pin.
  final context = SecurityContext(withTrustedRoots: false);
  final httpClient = HttpClient(context: context)
    ..connectionTimeout = connectionTimeout
    ..badCertificateCallback = (cert, host, port) {
      final fingerprint = computeLeafFingerprint(cert);
      return allowedFingerprints.contains(fingerprint);
    };
  return IOClient(httpClient);
}
