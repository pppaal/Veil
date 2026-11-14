/// Protocol v2 wire frame (docs/crypto-envelope-spec.md §v2):
///
///   0x02 || type || [PreKey header (168)] || ratchetPub(32) || u32 PN
///        || u32 N || ciphertext || tag(16)
///
/// type 0x01 = PreKey (initiator not yet acknowledged), 0x02 = Normal.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../bytes.dart';
import '../x3dh/x3dh_handshake.dart';
import 'aead.dart';

const String envelopeVersionV2 = 'veil-envelope-v2';
const String frameAadLabelV4 = 'veil-frame-aad-v4';
const int frameVersionByte = 0x02;
const int frameTypePreKey = 0x01;
const int frameTypeNormal = 0x02;

class FrameV2 {
  FrameV2._({
    required this.header,
    required this.preKey,
    required this.ratchetPublic,
    required this.previousCounter,
    required this.counter,
    required this.sealed,
  });

  /// Everything before the ciphertext; bound verbatim into the AAD.
  final Uint8List header;
  final PreKeyHeader? preKey;
  final Uint8List ratchetPublic;
  final int previousCounter;
  final int counter;
  // ciphertext || tag
  final Uint8List sealed;

  static Uint8List encodeHeader({
    required Uint8List? preKeyHeader,
    required List<int> ratchetPublic,
    required int previousCounter,
    required int counter,
  }) =>
      concatBytes([
        [frameVersionByte, preKeyHeader == null ? frameTypeNormal : frameTypePreKey],
        if (preKeyHeader != null) preKeyHeader,
        ratchetPublic,
        u32be(previousCounter),
        u32be(counter),
      ]);

  static FrameV2 decode(List<int> bytes) {
    if (bytes.length < 2 || bytes[0] != frameVersionByte) {
      throw const FormatException('not a v2 frame');
    }
    final type = bytes[1];
    if (type != frameTypePreKey && type != frameTypeNormal) {
      throw const FormatException('unknown v2 frame type');
    }
    final preKeyLength = type == frameTypePreKey ? PreKeyHeader.encodedLength : 0;
    final ratchetOffset = 2 + preKeyLength;
    final headerLength = ratchetOffset + 32 + 4 + 4;
    if (bytes.length < headerLength + gcmTagLength) {
      throw const FormatException('v2 frame truncated');
    }
    return FrameV2._(
      header: Uint8List.fromList(bytes.sublist(0, headerLength)),
      preKey: type == frameTypePreKey ? PreKeyHeader.decode(bytes, 2) : null,
      ratchetPublic: Uint8List.fromList(bytes.sublist(ratchetOffset, ratchetOffset + 32)),
      previousCounter: readU32be(bytes, ratchetOffset + 32),
      counter: readU32be(bytes, ratchetOffset + 36),
      sealed: Uint8List.fromList(bytes.sublist(headerLength)),
    );
  }
}

/// AAD = "veil-frame-aad-v4" || lp(version) || lp(conversationId)
///       || lp(senderDeviceId) || lp(messageKind) || header || AD
///
/// Binds every routing field the server relays in clear, so re-labelling a
/// frame (another conversation, sender, kind or version) breaks the tag.
/// expiresAt is deliberately absent: the server may clamp the outer value,
/// and the authenticated expiry travels inside the payload.
Uint8List buildFrameAadV4({
  required String version,
  required String conversationId,
  required String senderDeviceId,
  required String messageKind,
  required List<int> header,
  required List<int> associatedData,
}) =>
    concatBytes([
      utf8.encode(frameAadLabelV4),
      lengthPrefixedUtf8(version),
      lengthPrefixedUtf8(conversationId),
      lengthPrefixedUtf8(senderDeviceId),
      lengthPrefixedUtf8(messageKind),
      header,
      associatedData,
    ]);
