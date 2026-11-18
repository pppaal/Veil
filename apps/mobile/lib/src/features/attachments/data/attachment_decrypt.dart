import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as hashing;
import 'package:flutter/foundation.dart';

import '../../../core/crypto/attachment/attachment_cipher_v2.dart';
import '../../../core/crypto/bytes.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../domain/attachment_rules.dart';

// Opening a sealed attachment, off the UI isolate. Each function hands a
// background isolate the blob's path, and the isolate reads the sealed file
// itself: no ciphertext crosses the isolate boundary, and the plaintext
// comes back only as a photo's bytes (moved, not copied) or, for a file,
// written straight to its target and answered with its length.

/// Why a sealed attachment did not open.
enum AttachmentOpenFailure {
  /// The blob is not the one the pointer names (its SHA-256 digest), or it
  /// does not open with the pointer's key (AES-GCM).
  integrity,

  /// It opened, but a photo's bytes are not a JPEG, PNG or WebP.
  unsupported,
}

class AttachmentOpenException implements Exception {
  const AttachmentOpenException(this.failure);

  final AttachmentOpenFailure failure;

  @override
  String toString() => 'AttachmentOpenException(${failure.name})';
}

/// How many decrypts were started in this process: a prefetch must never
/// start one.
@visibleForTesting
int debugAttachmentDecrypts = 0;

/// The photo sealed in the blob at [blobPath], decrypted with [reference]
/// (pointer v2: digest first, in constant time, then AES-GCM). Throws an
/// [AttachmentOpenException]: [AttachmentOpenFailure.unsupported] when the
/// bytes do not sniff as a JPEG, PNG or WebP, whatever the pointer claims.
Future<Uint8List> openPhoto(AttachmentReference reference, String blobPath) async {
  debugAttachmentDecrypts += 1;
  final moved = await Isolate.run(() => _openPhoto(reference, blobPath));
  return moved.materialize().asUint8List();
}

/// Decrypts the file sealed in the blob at [blobPath] into [targetPath]
/// and returns its length.
Future<int> openFileTo(AttachmentReference reference, String blobPath, String targetPath) {
  debugAttachmentDecrypts += 1;
  return Isolate.run(() => _openFileTo(reference, blobPath, targetPath));
}

/// Whether the SHA-256 of the blob at [blobPath] is [digest] (base64url, a
/// pointer's `d`), compared in constant time. Nothing is decrypted.
Future<bool> digestMatches(String blobPath, String digest) => Isolate.run(() => _digestMatches(blobPath, digest));

/// What an encoded photo's header says it is (its size in pixels), read by
/// the engine without decoding a single pixel; null when the engine cannot
/// read it.
Future<({int width, int height})?> readImageHeader(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return (width: descriptor.width, height: descriptor.height);
  } catch (_) {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Whether [bytes] are a photo this version draws (D34): they sniff as a
/// JPEG, PNG or WebP and their header is within the render limits. Nothing
/// is decoded.
Future<bool> isDrawablePhoto(Uint8List bytes) async {
  final type = sniffImageType(bytes);
  if (type == null) return false;
  final header = await readImageHeader(bytes);
  return header != null && withinRenderLimits(type, header.width, header.height);
}

Future<TransferableTypedData> _openPhoto(AttachmentReference reference, String blobPath) async {
  final plaintext = await _open(reference, blobPath);
  if (sniffImageType(plaintext) == null) {
    plaintext.fillRange(0, plaintext.length, 0);
    throw const AttachmentOpenException(AttachmentOpenFailure.unsupported);
  }
  return TransferableTypedData.fromList([plaintext]);
}

Future<int> _openFileTo(AttachmentReference reference, String blobPath, String targetPath) async {
  final plaintext = await _open(reference, blobPath);
  try {
    File(targetPath).writeAsBytesSync(plaintext, flush: true);
    return plaintext.length;
  } finally {
    plaintext.fillRange(0, plaintext.length, 0);
  }
}

bool _digestMatches(String blobPath, String digest) {
  final sealed = File(blobPath).readAsBytesSync();
  return _hashMatches(sealed, digest);
}

bool _hashMatches(List<int> sealed, String digest) {
  final Uint8List expected;
  try {
    expected = b64uDecode(digest);
  } on FormatException {
    return false;
  }
  return constantTimeEquals(hashing.sha256.convert(sealed).bytes, expected);
}

Future<Uint8List> _open(AttachmentReference reference, String blobPath) async {
  final sealed = File(blobPath).readAsBytesSync();
  if (!_hashMatches(sealed, reference.sha256)) {
    throw const AttachmentOpenException(AttachmentOpenFailure.integrity);
  }
  final List<int> plaintext;
  try {
    plaintext = await decryptAttachmentV2(reference: reference, ciphertext: sealed);
  } catch (_) {
    // A wrong key, nonce or AAD, or padding that is not there: the words
    // never say which.
    throw const AttachmentOpenException(AttachmentOpenFailure.integrity);
  }
  return plaintext is Uint8List ? plaintext : Uint8List.fromList(plaintext);
}
