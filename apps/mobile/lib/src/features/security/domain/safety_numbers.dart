import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../../../core/util/base64url.dart';
import '../../../core/util/constant_time.dart';

// ---------------------------------------------------------------------------
// Safety numbers v2 (Signal NumericFingerprint construction), the only
// construction this app implements and the one the web client computes.
//
// The unversioned v1 hashed the two raw keys once, so it neither bound a key
// to the user it belongs to nor carried a version that would let the
// construction change without silently changing every number; it was
// removed. In v2 each party's half is an iterated SHA-512 over
// (version || key || userId), and the version is also the first byte after
// the magic in the QR payload. Shared vectors live in
// packages/shared/test-vectors/safety-number-v2.json
// (scripts/safety-number-vectors.mjs).
// ---------------------------------------------------------------------------

/// Version of the safety-number construction below.
const int kSafetyNumberVersion = 2;

/// SHA-512 rounds per fingerprint half; makes grinding a key whose number
/// collides with a victim's expensive (Signal uses the same count).
const int _kFingerprintIterations = 5200;
const int _kIdentityKeyLength = 32;
final List<int> _kQrMagic = utf8.encode('VEILSN');

/// One party's 30-digit half of a safety number: h = SHA-512(u16be(version)
/// || key || utf8(userId)), then [_kFingerprintIterations] rounds of
/// h = SHA-512(h || key); the first 30 bytes of h, as six big-endian 40-bit
/// chunks, each reduced mod 100000 and zero-padded to five digits.
///
/// Only [kSafetyNumberVersion] is defined; [version] is a parameter so that
/// an upgrade (and the tests guarding it) changes every number visibly.
String computeSafetyFingerprint({
  required int version,
  required List<int> identityKey,
  required String userId,
}) {
  if (version < 0 || version > 0xFFFF) {
    throw ArgumentError.value(version, 'version', 'must fit in u16');
  }
  _requireIdentityKey(identityKey);
  if (userId.isEmpty) throw ArgumentError('userId must be non-empty');
  var hash = crypto.sha512
      .convert([(version >> 8) & 0xFF, version & 0xFF, ...identityKey, ...utf8.encode(userId)])
      .bytes;
  for (var i = 0; i < _kFingerprintIterations; i++) {
    hash = crypto.sha512.convert([...hash, ...identityKey]).bytes;
  }
  final digits = StringBuffer();
  for (var chunk = 0; chunk < 6; chunk++) {
    var value = 0;
    for (final byte in hash.sublist(chunk * 5, chunk * 5 + 5)) {
      value = value * 256 + byte;
    }
    digits.write((value % 100000).toString().padLeft(5, '0'));
  }
  return digits.toString();
}

/// The 60-digit v2 safety number for a conversation between two identities.
/// Both sides compute the same value: the halves are ordered with the
/// lexicographically smaller first.
String computeSafetyNumberV2({
  required String localUserId,
  required List<int> localIdentityKey,
  required String remoteUserId,
  required List<int> remoteIdentityKey,
}) {
  final local = computeSafetyFingerprint(
    version: kSafetyNumberVersion,
    identityKey: localIdentityKey,
    userId: localUserId,
  );
  final remote = computeSafetyFingerprint(
    version: kSafetyNumberVersion,
    identityKey: remoteIdentityKey,
    userId: remoteUserId,
  );
  return local.compareTo(remote) <= 0 ? '$local$remote' : '$remote$local';
}

/// Splits a 60-digit safety number into the 12 groups of five shown in UI.
List<String> formatSafetyNumber(String digits) {
  if (!RegExp(r'^\d{60}$').hasMatch(digits)) {
    throw ArgumentError.value(digits, 'digits', 'must be exactly 60 decimal digits');
  }
  return [for (var i = 0; i < 60; i += 5) digits.substring(i, i + 5)];
}

/// The QR code this device shows for verification:
/// b64url("VEILSN" || version || localKey(32) || u8 len || localUserId ||
/// remoteKey(32) || u8 len || remoteUserId).
String encodeSafetyQrPayload({
  required String localUserId,
  required List<int> localIdentityKey,
  required String remoteUserId,
  required List<int> remoteIdentityKey,
}) =>
    base64UrlNoPadEncode(_qrPayloadBytes(
      firstUserId: localUserId,
      firstKey: localIdentityKey,
      secondUserId: remoteUserId,
      secondKey: remoteIdentityKey,
    ));

/// Outcome of comparing a scanned safety QR code with our own view.
enum SafetyQrVerification {
  /// The peer sees exactly the identities we see.
  verified,

  /// Same format, different identities: a key or user substitution, or the
  /// wrong contact's code. Must hard-fail in UI.
  mismatch,

  /// A safety-number version we do not implement.
  unsupportedVersion,

  /// Not a VEIL safety QR code at all.
  malformed,
}

/// Checks a QR payload scanned from the peer's screen. The peer encodes
/// itself as "local", so the payload must equal ours with the roles swapped;
/// the comparison runs in constant time.
SafetyQrVerification verifyScannedSafetyQr({
  required String scannedPayload,
  required String localUserId,
  required List<int> localIdentityKey,
  required String remoteUserId,
  required List<int> remoteIdentityKey,
}) {
  final Uint8List scanned;
  try {
    scanned = base64UrlNoPadDecode(scannedPayload);
  } on FormatException {
    return SafetyQrVerification.malformed;
  }
  final magicLength = _kQrMagic.length;
  if (scanned.length <= magicLength ||
      !constantTimeBytesEqual(scanned.sublist(0, magicLength), _kQrMagic)) {
    return SafetyQrVerification.malformed;
  }
  if (scanned[magicLength] != kSafetyNumberVersion) {
    return SafetyQrVerification.unsupportedVersion;
  }
  final expected = _qrPayloadBytes(
    firstUserId: remoteUserId,
    firstKey: remoteIdentityKey,
    secondUserId: localUserId,
    secondKey: localIdentityKey,
  );
  return constantTimeBytesEqual(scanned, expected)
      ? SafetyQrVerification.verified
      : SafetyQrVerification.mismatch;
}

Uint8List _qrPayloadBytes({
  required String firstUserId,
  required List<int> firstKey,
  required String secondUserId,
  required List<int> secondKey,
}) {
  _requireIdentityKey(firstKey);
  _requireIdentityKey(secondKey);
  return (BytesBuilder(copy: false)
        ..add(_kQrMagic)
        ..addByte(kSafetyNumberVersion)
        ..add(firstKey)
        ..add(_lengthPrefixedUserId(firstUserId))
        ..add(secondKey)
        ..add(_lengthPrefixedUserId(secondUserId)))
      .toBytes();
}

List<int> _lengthPrefixedUserId(String userId) {
  final bytes = utf8.encode(userId);
  if (bytes.isEmpty || bytes.length > 0xFF) {
    throw ArgumentError.value(userId, 'userId', 'must be 1..255 UTF-8 bytes');
  }
  return [bytes.length, ...bytes];
}

void _requireIdentityKey(List<int> key) {
  if (key.length != _kIdentityKeyLength) {
    throw ArgumentError('identity key must be $_kIdentityKeyLength bytes, got ${key.length}');
  }
}
