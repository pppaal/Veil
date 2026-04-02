import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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
    {String? cursor,
    int limit = 50,}
  ) async {
    final query = <String, String>{
      'limit': '$limit',
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    final uri = Uri.parse('$baseUrl/conversations/$conversationId/messages')
        .replace(queryParameters: query);
    final response = await _client.get(
      uri,
      headers: _headers(accessToken),
    );
    return _decodeMap(response);
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
    final random = Random.secure();
    final body = Uint8List.fromList(List<int>.generate(2048, (_) => random.nextInt(256)));
    final response = await _client.put(
      Uri.parse(uploadUrl),
      headers: headers.map((key, value) => MapEntry(key, value.toString())),
      body: body,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VeilApiException(
        'Attachment upload failed: HTTP ${response.statusCode}',
        code: 'attachment_upload_failed',
        statusCode: response.statusCode,
      );
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

  Future<Map<String, dynamic>> claimTransfer(Map<String, dynamic> body) async {
    return _post('/device-transfer/claim', body);
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
      throw _errorFromResponse(response);
    }
    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }
    return jsonDecode(response.body);
  }

  VeilApiException _errorFromResponse(http.Response response) {
    final status = response.statusCode;
    if (response.body.isEmpty) {
      return VeilApiException('Request failed: HTTP $status', statusCode: status);
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final code = decoded['code'] as String?;
        final message = decoded['message'];
        if (message is String && message.trim().isNotEmpty) {
          return VeilApiException(
            _normalizeErrorMessage(message.trim(), status, code: code),
            code: code,
            statusCode: status,
          );
        }
        if (message is List && message.isNotEmpty) {
          return VeilApiException(
            _normalizeErrorMessage(message.first.toString(), status, code: code),
            code: code,
            statusCode: status,
          );
        }
        final error = decoded['error'];
        if (error is String && error.trim().isNotEmpty) {
          return VeilApiException(
            _normalizeErrorMessage(error.trim(), status, code: code),
            code: code,
            statusCode: status,
          );
        }
      }
    } catch (_) {
      // Fall through to the generic message.
    }

    return VeilApiException('Request failed: HTTP $status', statusCode: status);
  }

  String _normalizeErrorMessage(String message, int status, {String? code}) {
    switch (code) {
      case 'challenge_invalid':
        return 'This challenge is no longer valid. Request a new one.';
      case 'device_not_active':
        return 'This device is no longer the active VEIL device.';
      case 'invalid_device_signature':
        return 'This device proof was rejected.';
      case 'transfer_session_inactive':
        return 'This transfer session is no longer active.';
      case 'transfer_token_invalid':
        return 'This transfer token is invalid.';
      case 'transfer_claim_required':
        return 'A matching new-device claim is required first.';
      case 'transfer_approval_required':
        return 'The old device must approve this exact new-device claim first.';
      case 'transfer_completion_invalid':
        return 'This new device could not prove the final transfer handoff.';
    }

    if (message.contains('peer handle')) {
      return 'That handle is not available for a direct chat.';
    }
    if (message.contains('already exists') || message.contains('has already been taken')) {
      return 'That handle is already claimed.';
    }
    if (message.contains('Invalid handle') || message.contains('handle')) {
      if (status == 400 || status == 422) {
        return 'Choose a valid handle using letters, numbers, and underscores.';
      }
    }
    return message;
  }
}

class VeilApiException implements Exception {
  VeilApiException(this.message, {this.code, this.statusCode});

  final String message;
  final String? code;
  final int? statusCode;

  @override
  String toString() => message;
}

String? extractVeilApiErrorCode(Object error) {
  if (error is VeilApiException) {
    return error.code;
  }
  return null;
}
