import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../config/veil_config.dart';

class MockDeviceAuthProof {
  const MockDeviceAuthProof._();

  static String build({
    required String challenge,
    required String authPublicKey,
    required String deviceId,
  }) {
    final input =
        '$challenge:$authPublicKey:$deviceId:${VeilConfig.mockAuthSharedSecret}';
    return base64Url.encode(sha256.convert(utf8.encode(input)).bytes).replaceAll('=', '');
  }
}
