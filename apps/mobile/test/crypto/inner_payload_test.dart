import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/payload/inner_payload.dart';

// An authenticated peer can still send a payload of the wrong shape. Every
// such payload must surface as a FormatException, which the session cipher
// reports as DecryptStatus.failed / malformed_payload, never as a crash.
void main() {
  InnerPayload decode(Map<String, dynamic> json) =>
      InnerPayload.decode(utf8.encode(jsonEncode(json)), fallbackKind: MessageKind.text);

  test('well-formed v2 payload decodes', () {
    final payload = decode({
      'pv': 2,
      'b': 'hi',
      'k': 'file',
      'x': null,
      'att': {'id': 'a1', 'ck': 'key', 'n': 'nonce', 'd': 'digest', 'ct': 'image/png', 'sz': 3, 'alg': 'aes256gcm-v2'},
    });
    expect(payload.body, 'hi');
    expect(payload.kind, MessageKind.file);
    expect(payload.attachment!.sizeBytes, 3);
    expect(payload.attachment!.algorithmHint, 'aes256gcm-v2');
  });

  test('fields of the wrong type are malformed, not a crash', () {
    final malformed = <Map<String, dynamic>>[
      {'pv': 2, 'b': 5, 'k': 'text', 'x': null, 'att': null},
      {'body': ['not', 'text'], 'kind': 'text'},
      {
        'pv': 2,
        'b': '',
        'k': 'file',
        'x': null,
        'att': {'id': 7, 'ck': 'key'},
      },
      {
        'pv': 2,
        'b': '',
        'k': 'file',
        'x': null,
        'att': {'id': 'a1', 'ck': 'key', 'sz': 'big'},
      },
      {
        'pv': 2,
        'b': '',
        'k': 'file',
        'x': null,
        'att': {'id': 'a1', 'ck': 'key', 'alg': false},
      },
      {
        'body': '',
        'att': {'attachmentId': 'a1', 'encryptedKey': 1},
      },
    ];
    for (final json in malformed) {
      expect(() => decode(json), throwsFormatException, reason: jsonEncode(json));
    }
  });
}
