import 'dart:convert';
import 'dart:typed_data';

import '../crypto_engine.dart';

/// The authenticated plaintext inside every 1:1 frame, shared by all
/// adapters so they cannot drift apart again.
///
/// v2 (compact, all keys always present, fixed order):
///   {"pv":2,"b":body,"k":kind,"x":expiresAtMs|null,"att":null|{id,ck,n,d,ct,sz,alg}}
///
/// Legacy v1 frames carry {"body","kind","expiresAt"(ISO),"att"} with either
/// the short attachment keys (id, sk, ct, ...) or the long ones
/// (attachmentId, storageKey, ...); the decoder accepts all of them.

const int innerPayloadVersion = 2;

class InnerPayload {
  const InnerPayload({required this.body, required this.kind, this.expiresAt, this.attachment});

  final String body;
  final MessageKind kind;
  final DateTime? expiresAt;
  final AttachmentReference? attachment;

  Uint8List encode() {
    final attachment = this.attachment;
    return utf8.encode(json.encode({
      'pv': innerPayloadVersion,
      'b': body,
      'k': kind.name,
      'x': expiresAt?.millisecondsSinceEpoch,
      'att': attachment == null
          ? null
          : {
              'id': attachment.attachmentId,
              'ck': attachment.encryptedKey,
              'n': attachment.nonce,
              'd': attachment.sha256,
              'ct': attachment.contentType,
              'sz': attachment.sizeBytes,
              'alg': attachment.algorithmHint,
            },
    }));
  }

  /// The shape v1 peers parse; only used on legacy sessions.
  Uint8List encodeLegacy() {
    final attachment = this.attachment;
    return utf8.encode(json.encode({
      'body': body,
      'kind': kind.name,
      if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
      if (attachment != null)
        'att': {
          'id': attachment.attachmentId,
          'sk': attachment.storageKey,
          'ct': attachment.contentType,
          'sz': attachment.sizeBytes,
          'h': attachment.sha256,
          'ek': attachment.encryptedKey,
          'n': attachment.nonce,
          if (attachment.algorithmHint != null) 'ah': attachment.algorithmHint,
        },
    }));
  }

  /// Throws [FormatException] when the bytes are not a payload object.
  static InnerPayload decode(List<int> bytes, {required MessageKind fallbackKind}) {
    final decoded = json.decode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('inner payload is not a JSON object');
    }
    final isV2 = decoded['pv'] == innerPayloadVersion;
    final kindName = decoded[isV2 ? 'k' : 'kind'];
    return InnerPayload(
      body: decoded[isV2 ? 'b' : 'body'] as String? ?? '',
      kind: MessageKind.values.firstWhere((k) => k.name == kindName, orElse: () => fallbackKind),
      expiresAt: isV2 ? _fromMillis(decoded['x']) : _fromIso(decoded['expiresAt']),
      attachment: _decodeAttachment(decoded['att']),
    );
  }

  static DateTime? _fromMillis(Object? value) => value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

  static DateTime? _fromIso(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;

  static AttachmentReference? _decodeAttachment(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    String text(String key, [String fallback = '']) => raw[key] as String? ?? fallback;
    int size(String key) => (raw[key] as num?)?.toInt() ?? 0;
    if (raw.containsKey('ck')) {
      return AttachmentReference(
        attachmentId: text('id'),
        storageKey: '',
        contentType: text('ct', 'application/octet-stream'),
        sizeBytes: size('sz'),
        sha256: text('d'),
        encryptedKey: text('ck'),
        nonce: text('n'),
        algorithmHint: raw['alg'] as String?,
      );
    }
    if (raw.containsKey('attachmentId')) {
      return AttachmentReference(
        attachmentId: text('attachmentId'),
        storageKey: text('storageKey'),
        contentType: text('contentType', 'application/octet-stream'),
        sizeBytes: size('sizeBytes'),
        sha256: text('sha256'),
        encryptedKey: text('encryptedKey'),
        nonce: text('nonce'),
        algorithmHint: raw['algorithmHint'] as String?,
      );
    }
    return AttachmentReference(
      attachmentId: text('id'),
      storageKey: text('sk'),
      contentType: text('ct', 'application/octet-stream'),
      sizeBytes: size('sz'),
      sha256: text('h'),
      encryptedKey: text('ek'),
      nonce: text('n'),
      algorithmHint: raw['ah'] as String?,
    );
  }
}
