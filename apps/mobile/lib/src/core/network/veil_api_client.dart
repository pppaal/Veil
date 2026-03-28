import 'dart:convert';

import 'package:http/http.dart' as http;

class VeilApiClient {
  VeilApiClient({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> register(Map<String, dynamic> body) async {
    return _post('/auth/register', body);
  }

  Future<Map<String, dynamic>> challenge(Map<String, dynamic> body) async {
    return _post('/auth/challenge', body);
  }

  Future<Map<String, dynamic>> verify(Map<String, dynamic> body) async {
    return _post('/auth/verify', body);
  }

  Future<Map<String, dynamic>> getKeyBundle(String handle) async {
    return _get('/users/$handle/key-bundle');
  }

  Future<List<dynamic>> getConversations(String accessToken) async {
    return _getList('/conversations', accessToken: accessToken);
  }

  Future<Map<String, dynamic>> createDirectConversation(
    String accessToken,
    String peerHandle,
  ) async {
    return _post(
      '/conversations/direct',
      {'peerHandle': peerHandle},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> getMessages(
    String accessToken,
    String conversationId,
  ) async {
    return _get('/conversations/$conversationId/messages', accessToken: accessToken);
  }

  Future<Map<String, dynamic>> sendMessage(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    return _post('/messages', body, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> markRead(
    String accessToken,
    String messageId,
  ) async {
    return _post('/messages/$messageId/read', const {}, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> createUploadTicket(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    return _post('/attachments/upload-ticket', body, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> completeUpload(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    return _post('/attachments/complete', body, accessToken: accessToken);
  }

  Future<void> uploadEncryptedPlaceholder({
    required String uploadUrl,
    required Map<String, dynamic> headers,
    required String filename,
  }) async {
    final response = await _client.put(
      Uri.parse(uploadUrl),
      headers: {
        ...headers.map((key, value) => MapEntry(key, value.toString())),
        'Content-Type': 'application/octet-stream',
      },
      body: utf8.encode('VEIL::$filename::encrypted-placeholder'),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VeilApiException('Attachment upload failed: HTTP ${response.statusCode}');
    }
  }

  Future<Map<String, dynamic>> getDownloadTicket(
    String accessToken,
    String attachmentId,
  ) async {
    return _get('/attachments/$attachmentId/download-ticket', accessToken: accessToken);
  }

  Future<Map<String, dynamic>> initTransfer(
    String accessToken,
    String oldDeviceId,
  ) async {
    return _post(
      '/device-transfer/init',
      {'oldDeviceId': oldDeviceId},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> approveTransfer(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    return _post('/device-transfer/approve', body, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> completeTransfer(Map<String, dynamic> body) async {
    return _post('/device-transfer/complete', body);
  }

  Future<Map<String, dynamic>> revokeDevice(
    String accessToken,
    String deviceId,
  ) async {
    return _post(
      '/devices/revoke',
      {'deviceId': deviceId},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    String? accessToken,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers(accessToken),
    );
    return _decodeMap(response);
  }

  Future<List<dynamic>> _getList(
    String path, {
    String? accessToken,
  }) async {
    final response = await _client.get(
      Uri.parse('$baseUrl$path'),
      headers: _headers(accessToken),
    );
    final decoded = _decode(response) as List<dynamic>;
    return decoded;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async {
    final response = await _client.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers(accessToken),
      body: jsonEncode(body),
    );
    return _decodeMap(response);
  }

  Map<String, String> _headers(String? accessToken) {
    return {
      'Content-Type': 'application/json',
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };
  }

  Map<String, dynamic> _decodeMap(http.Response response) {
    final decoded = _decode(response);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    throw VeilApiException('Unexpected response shape');
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VeilApiException(
        'HTTP ${response.statusCode}: ${response.body}',
      );
    }
    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(response.body);
  }
}

class VeilApiException implements Exception {
  VeilApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
