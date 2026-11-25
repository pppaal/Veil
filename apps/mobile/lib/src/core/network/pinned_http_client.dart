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
// Pins are matched against the server's leaf certificate, the one whose key
// signed the TLS handshake. dart:io exposes no other certificate of the chain
// reliably, so intermediate and root pins are not supported. A pin is a base64
// SHA-256 fingerprint with an optional kind prefix:
//   spki:<b64>  hash of the leaf's DER subjectPublicKeyInfo. Preferred: it
//               survives certificate renewal as long as the server keeps its
//               key pair, which matters with ~60-day ACME leaf rotation (ACME
//               clients generate a new key on renewal unless told to reuse it,
//               e.g. certbot --reuse-key).
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

  /// Leaf fingerprint the server presented, or null when the connection
  /// offered no certificate at all (plaintext).
  final String? fingerprint;

  @override
  String toString() => fingerprint == null
      ? 'TLS certificate pinning refused a connection to $host that '
          'presented no certificate.'
      : 'TLS certificate pin mismatch for $host (observed leaf fingerprint '
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

/// Decides whether a leaf certificate matches the configured pins.
class CertificatePinVerifier {
  factory CertificatePinVerifier(Iterable<String> pins) {
    final spki = <String>{};
    final leaf = <String>{};
    for (final pin in pins) {
      if (pin.startsWith(_spkiPrefix)) {
        spki.add(_checkedFingerprint(pin, pin.substring(_spkiPrefix.length)));
      } else if (pin.startsWith(_leafPrefix)) {
        leaf.add(_checkedFingerprint(pin, pin.substring(_leafPrefix.length)));
      } else {
        leaf.add(_checkedFingerprint(pin, pin));
      }
    }
    return CertificatePinVerifier._(spki, leaf);
  }

  CertificatePinVerifier._(this._spki, this._leaf);

  final Set<String> _spki;
  final Set<String> _leaf;

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

  /// Returns [value] when it is a canonical base64 SHA-256 digest. Anything
  /// else (a foreign prefix such as 'sha256/', a hex digest, a truncated
  /// paste) can never match, so failing loudly beats shipping a build that
  /// locks every client out.
  static String _checkedFingerprint(String pin, String value) {
    try {
      final digest = base64Decode(value);
      // Re-encoding also rejects the URL-safe alphabet and unpadded forms,
      // which can never equal a computed fingerprint.
      if (digest.length == 32 && base64Encode(digest) == value) {
        return value;
      }
    } on FormatException {
      // Reported below with the whole pin.
    }
    throw FormatException('TLS pin is not a base64 SHA-256 fingerprint', pin);
  }
}

/// Returns a dart:io [HttpClient] that only talks to servers whose leaf
/// certificate matches one of [pins], or null when [pins] is empty so the
/// caller keeps the platform trust store (dev builds have no stable cert).
/// A mismatch fails the request with [PinnedCertificateException] before any
/// request byte, bearer token included, is written to the connection.
HttpClient? buildPinnedDartIoHttpClient(
  Set<String> pins, {
  Duration connectionTimeout = _defaultConnectionTimeout,
}) {
  final verifier = CertificatePinVerifier(pins);
  if (!verifier.hasPins) {
    return null;
  }
  return HttpClient()
    ..connectionTimeout = connectionTimeout
    // The pin check lives in the connection factory. Through a proxy,
    // HttpClient would secure the CONNECT tunnel itself, past that check.
    // dart:io ignores the Android and iOS proxy settings anyway.
    ..findProxy = _directConnection
    ..connectionFactory = _PinnedTlsConnector(verifier).connect;
}

/// Returns an HTTP client pinned to [allowedFingerprints]; without pins it
/// trusts the platform root store.
http.Client buildPinnedHttpClient({
  required Set<String> allowedFingerprints,
  Duration connectionTimeout = _defaultConnectionTimeout,
}) {
  return IOClient(
    buildPinnedDartIoHttpClient(
          allowedFingerprints,
          connectionTimeout: connectionTimeout,
        ) ??
        (HttpClient()..connectionTimeout = connectionTimeout),
  );
}

String _directConnection(Uri _) => 'DIRECT';

/// Opens the TLS connections of a pinned [HttpClient] and checks the leaf
/// certificate once the handshake completes, before HttpClient receives the
/// socket.
///
/// HttpClient.badCertificateCallback cannot do this: dart:io calls it with
/// the certificate at which chain verification stopped, which for a server
/// sending leaf + intermediate is the intermediate, never the leaf.
class _PinnedTlsConnector {
  _PinnedTlsConnector(this._verifier);

  final CertificatePinVerifier _verifier;

  // No trusted roots: the pin is the whole trust decision, so a pinned
  // self-signed relay works and no platform CA can vouch for an unpinned key.
  final SecurityContext _context = SecurityContext(withTrustedRoots: false);

  Future<ConnectionTask<Socket>> connect(
    Uri url,
    String? proxyHost,
    int? proxyPort,
  ) async {
    if (!url.isScheme('https')) {
      // A plaintext connection cannot prove it holds a pinned key, and it
      // would carry the bearer token in the clear.
      throw PinnedCertificateException(url.host, null);
    }
    final task = await SecureSocket.startConnect(
      url.host,
      url.port,
      context: _context,
      // Without roots every chain fails verification; the leaf is checked
      // once the handshake is done instead.
      onBadCertificate: _deferToLeafCheck,
    );
    var canceled = false;
    final socket = task.socket.then((socket) {
      if (canceled) {
        // HttpClient gave up (connection timeout or forced close) while the
        // handshake was in flight, which cancel() cannot interrupt.
        socket.destroy();
        throw const SocketException('Connection attempt cancelled');
      }
      return _checkLeaf(socket, url.host);
    });
    return ConnectionTask.fromSocket(socket, () {
      canceled = true;
      task.cancel();
    });
  }

  SecureSocket _checkLeaf(SecureSocket socket, String host) {
    final leaf = socket.peerCertificate;
    if (leaf != null && _verifier.matches(leaf)) {
      return socket;
    }
    socket.destroy();
    throw PinnedCertificateException(
      host,
      leaf == null ? null : computeLeafFingerprint(leaf),
    );
  }

  static bool _deferToLeafCheck(X509Certificate _) => true;
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
