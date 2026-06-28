import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/veil_config.dart';
import 'one_time_link.dart';

/// Creates one-time secret links against the public `/s` API and assembles
/// the shareable URL pointing at the web viewer.
class OneTimeLinkService {
  OneTimeLinkService({http.Client? client, String? apiBaseUrl})
      : _client = client ?? http.Client(),
        _apiBaseUrl = apiBaseUrl ?? VeilConfig.apiBaseUrl;

  final http.Client _client;
  final String _apiBaseUrl;

  /// Encrypts [secret] on-device, stores only the ciphertext server-side, and
  /// returns the shareable link. The decryption key rides in the fragment and
  /// is never sent to the server.
  Future<String> createLink(String secret, {String? passphrase}) async {
    final sealed = await OneTimeLink.seal(secret, passphrase: passphrase);
    final response = await _client.post(
      Uri.parse('$_apiBaseUrl/s'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'ciphertext': sealed.blob}),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Link creation failed (${response.statusCode}).');
    }
    final id = (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
    // The web viewer is served at /demo/s.html on the API host (no /v1 prefix).
    final webBase = _apiBaseUrl.replaceFirst(RegExp(r'/v1/?$'), '');
    return '$webBase/demo/s.html#$id.${sealed.fragment}';
  }
}
