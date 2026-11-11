import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

// TLS certificate pinning.
//
// Without pinning, a MITM who compromises (or coerces) any CA trusted by the
// platform root store can transparently intercept traffic to the API host.
// Pinning moves trust off the platform root store and onto a small set of
// SHA-256 fingerprints shipped in the app binary (typically provided via
// `--dart-define VEIL_TLS_PINS=...`).
//
// A pin is a base64 SHA-256 fingerprint with an optional kind prefix:
//   spki:<b64>  hash of the DER subjectPublicKeyInfo. Preferred: it survives
//               certificate renewal as long as the server keeps its key pair,
//               which matters with ~60-day ACME leaf rotation.
//               openssl x509 -pubkey -noout | openssl pkey -pubin -outform der
//                 | openssl dgst -sha256 -binary | base64
//   leaf:<b64>  hash of the full leaf certificate DER. An unprefixed pin is a
//               leaf pin, which keeps pins configured before SPKI support valid.
//               openssl x509 -outform DER | openssl dgst -sha256 -binary | base64
// Either way the operator must ship the next pin BEFORE rotating the key or
// certificate, otherwise clients lock themselves out.

const _defaultConnectionTimeout = Duration(seconds: 15);
const _spkiPrefix = 'spki:';
const _leafPrefix = 'leaf:';

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

/// Base64 SHA-256 of the certificate's DER-encoded subjectPublicKeyInfo.
/// Throws [FormatException] when the certificate DER cannot be walked.
String computeSpkiFingerprint(X509Certificate cert) {
  return base64Encode(sha256.convert(subjectPublicKeyInfoDer(cert.der)).bytes);
}

/// Extracts the complete subjectPublicKeyInfo TLV from an X.509 certificate.
///
/// dart:io exposes only the certificate DER, and parsing it with a full ASN.1
/// library would add a dependency for one field. This walks just far enough:
/// Certificate -> tbsCertificate -> [version] serial signature issuer
/// validity subject -> subjectPublicKeyInfo (RFC 5280 section 4.1).
Uint8List subjectPublicKeyInfoDer(Uint8List certificateDer) {
  final certificate = _DerReader(certificateDer).read(_derSequence);
  final tbsCertificate = _DerReader(certificate.content).read(_derSequence);
  final fields = _DerReader(tbsCertificate.content);
  if (fields.nextTag == _derExplicitVersion) {
    fields.read(_derExplicitVersion);
  }
  fields
    ..read(_derInteger) // serialNumber
    ..read(_derSequence) // signature
    ..read(_derSequence) // issuer
    ..read(_derSequence) // validity
    ..read(_derSequence); // subject
  return fields.read(_derSequence).encoded;
}

/// Parses a comma-separated pin list. Empty entries and surrounding
/// whitespace are trimmed. Returns an empty set if [raw] is empty, which
/// signals the caller to skip pinning.
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

/// Decides whether a peer certificate matches the configured pins, and
/// remembers each rejection so the HTTP layer can report a pin mismatch
/// instead of a generic handshake failure.
class CertificatePinVerifier {
  factory CertificatePinVerifier(Iterable<String> pins) {
    final spki = <String>{};
    final leaf = <String>{};
    for (final pin in pins) {
      if (pin.startsWith(_spkiPrefix)) {
        spki.add(pin.substring(_spkiPrefix.length));
      } else if (pin.startsWith(_leafPrefix)) {
        leaf.add(pin.substring(_leafPrefix.length));
      } else if (pin.contains(':')) {
        // Base64 never contains ':', so this is a typo'd or foreign prefix
        // (e.g. 'sha256/'). Failing loudly beats shipping a pin that can
        // never match.
        throw FormatException('Unsupported TLS pin prefix', pin);
      } else {
        leaf.add(pin);
      }
    }
    return CertificatePinVerifier._(spki, leaf);
  }

  CertificatePinVerifier._(this._spki, this._leaf);

  final Set<String> _spki;
  final Set<String> _leaf;
  final Map<String, String> _rejectedFingerprintByOrigin = <String, String>{};

  bool get hasPins => _spki.isNotEmpty || _leaf.isNotEmpty;

  bool matches(X509Certificate cert) {
    if (_leaf.contains(computeLeafFingerprint(cert))) {
      return true;
    }
    if (_spki.isEmpty) {
      return false;
    }
    try {
      return _spki.contains(computeSpkiFingerprint(cert));
    } on FormatException {
      return false;
    }
  }

  /// Shaped as [HttpClient.badCertificateCallback].
  bool verify(X509Certificate cert, String host, int port) {
    if (matches(cert)) {
      return true;
    }
    _rejectedFingerprintByOrigin['$host:$port'] = computeLeafFingerprint(cert);
    return false;
  }

  /// Returns (and forgets) the leaf fingerprint rejected for [url]'s origin.
  String? takeRejection(Uri url) {
    return _rejectedFingerprintByOrigin.remove('${url.host}:${url.port}');
  }
}

/// Returns a dart:io [HttpClient] that only completes TLS handshakes whose
/// certificate matches one of [pins], or null when [pins] is empty so the
/// caller keeps the platform trust store (dev builds have no stable cert).
HttpClient? buildPinnedDartIoHttpClient(
  Set<String> pins, {
  Duration connectionTimeout = _defaultConnectionTimeout,
}) {
  final verifier = CertificatePinVerifier(pins);
  if (!verifier.hasPins) {
    return null;
  }
  return _pinnedHttpClient(verifier, connectionTimeout);
}

/// Returns an HTTP client pinned to [allowedFingerprints]; without pins it
/// trusts the platform root store.
http.Client buildPinnedHttpClient({
  required Set<String> allowedFingerprints,
  Duration connectionTimeout = _defaultConnectionTimeout,
}) {
  final verifier = CertificatePinVerifier(allowedFingerprints);
  if (!verifier.hasPins) {
    return IOClient(HttpClient()..connectionTimeout = connectionTimeout);
  }
  return PinnedHttpClient(
    IOClient(_pinnedHttpClient(verifier, connectionTimeout)),
    verifier,
  );
}

HttpClient _pinnedHttpClient(
  CertificatePinVerifier verifier,
  Duration connectionTimeout,
) {
  // `withTrustedRoots: false` strips the platform root store so that EVERY
  // connection has to pass our badCertificateCallback — which is the only
  // place we get the peer certificate. Without this, platform-trusted certs
  // bypass the callback entirely, defeating the pin.
  return HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..connectionTimeout = connectionTimeout
    ..badCertificateCallback = verifier.verify;
}

/// Surfaces pin rejections as [PinnedCertificateException]. dart:io reports
/// a rejected certificate as a plain [HandshakeException], which callers
/// could not tell apart from a flaky network.
class PinnedHttpClient extends http.BaseClient {
  PinnedHttpClient(this._inner, this._verifier);

  final http.Client _inner;
  final CertificatePinVerifier _verifier;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      return await _inner.send(request);
    } on HandshakeException {
      final fingerprint = _verifier.takeRejection(request.url);
      if (fingerprint != null) {
        throw PinnedCertificateException(request.url.host, fingerprint);
      }
      rethrow;
    }
  }

  @override
  void close() => _inner.close();
}

const _derInteger = 0x02;
const _derSequence = 0x30;
const _derExplicitVersion = 0xa0;

class _DerElement {
  const _DerElement(this.encoded, this.content);

  final Uint8List encoded;
  final Uint8List content;
}

class _DerReader {
  _DerReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  int? get nextTag => _offset < _bytes.length ? _bytes[_offset] : null;

  _DerElement read(int expectedTag) {
    final start = _offset;
    final tag = _nextByte();
    if (tag != expectedTag) {
      throw FormatException('Unexpected DER tag', _bytes, start);
    }
    var length = _nextByte();
    if (length & 0x80 != 0) {
      final lengthBytes = length & 0x7f;
      // Zero means indefinite length, which DER forbids; more than four
      // bytes would describe an element larger than any certificate.
      if (lengthBytes == 0 || lengthBytes > 4) {
        throw FormatException('Unsupported DER length', _bytes, start);
      }
      length = 0;
      for (var i = 0; i < lengthBytes; i++) {
        length = (length << 8) | _nextByte();
      }
    }
    final contentStart = _offset;
    final end = contentStart + length;
    if (end > _bytes.length) {
      throw FormatException('Truncated DER element', _bytes, start);
    }
    _offset = end;
    return _DerElement(
      Uint8List.sublistView(_bytes, start, end),
      Uint8List.sublistView(_bytes, contentStart, end),
    );
  }

  int _nextByte() {
    if (_offset >= _bytes.length) {
      throw FormatException('Truncated DER element', _bytes, _offset);
    }
    return _bytes[_offset++];
  }
}
