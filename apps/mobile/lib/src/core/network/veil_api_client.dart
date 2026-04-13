import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  Future<Map<String, dynamic>> addReaction(
    String accessToken,
    String messageId,
    String emoji,
  ) async {
    return _post('/messages/$messageId/reactions', {'emoji': emoji}, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> removeReaction(
    String accessToken,
    String messageId,
  ) async {
    return _delete('/messages/$messageId/reactions', accessToken: accessToken);
  }

  // Group and channel endpoints

  Future<Map<String, dynamic>> createGroup(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    return _post('/conversations/group', body, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> createChannel(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    return _post('/conversations/channel', body, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> updateGroupMeta(
    String accessToken,
    String conversationId,
    Map<String, dynamic> body,
  ) async {
    return _post('/conversations/$conversationId/meta', body, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> addMember(
    String accessToken,
    String conversationId,
    Map<String, dynamic> body,
  ) async {
    return _post('/conversations/$conversationId/members', body, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> removeMember(
    String accessToken,
    String conversationId,
    String userId,
  ) async {
    return _delete('/conversations/$conversationId/members/$userId', accessToken: accessToken);
  }

  // Profile and contacts endpoints

  Future<Map<String, dynamic>> getProfile(String accessToken) async {
    return _get('/profile', accessToken: accessToken);
  }

  Future<Map<String, dynamic>> updateProfile(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    return _patch('/profile', body, accessToken: accessToken);
  }

  Future<List<dynamic>> getContacts(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/contacts'),
      headers: _headers(accessToken),
    );
    return _decodeList(response);
  }

  Future<Map<String, dynamic>> addContact(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    return _post('/contacts', body, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> removeContact(
    String accessToken,
    String handle,
  ) async {
    return _delete('/contacts/$handle', accessToken: accessToken);
  }

  // Stories endpoints

  Future<List<dynamic>> getStories(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/stories'),
      headers: _headers(accessToken),
    );
    return _decodeList(response);
  }

  Future<Map<String, dynamic>> createStory(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    return _post('/stories', body, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> viewStory(
    String accessToken,
    String storyId,
  ) async {
    return _post('/stories/$storyId/view', const {}, accessToken: accessToken);
  }

  // Call endpoints

  Future<Map<String, dynamic>> initiateCall(
    String accessToken,
    Map<String, dynamic> body,
  ) async {
    return _post('/calls/initiate', body, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> endCall(
    String accessToken,
    String callId,
  ) async {
    return _post('/calls/$callId/end', const {}, accessToken: accessToken);
  }

  Future<List<dynamic>> getCallHistory(String accessToken) async {
    final response = await _client.get(
      Uri.parse('$baseUrl/calls'),
      headers: _headers(accessToken),
    );
    return _decodeList(response);
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

  Future<void> uploadEncryptedBlobFile({
    required String uploadUrl,
    required Map<String, dynamic> headers,
    required File file,
    void Function(int sentBytes, int totalBytes)? onProgress,
    AttachmentUploadCancellationSignal? cancellationSignal,
  }) async {
    final dedicatedClient = http.Client();
    var canceled = false;
    cancellationSignal?.register(() {
      canceled = true;
      dedicatedClient.close();
    });
    final totalBytes = await file.length();
    final request = http.StreamedRequest('PUT', Uri.parse(uploadUrl));
    request.headers.addAll(headers.map((key, value) => MapEntry(key, value.toString())));
    request.headers.putIfAbsent('Content-Length', () => '$totalBytes');
    request.contentLength = totalBytes;

    unawaited(() async {
      var sentBytes = 0;
      try {
        await for (final chunk in file.openRead()) {
          if (canceled) {
            throw const _AttachmentUploadCanceled();
          }
          request.sink.add(chunk);
          sentBytes += chunk.length;
          onProgress?.call(sentBytes, totalBytes);
        }
      } catch (_) {
        // The client side maps cancellation/transport errors from send().
      } finally {
        await request.sink.close();
      }
    }());

    late final http.StreamedResponse streamedResponse;
    try {
      streamedResponse = await dedicatedClient.send(request);
    } catch (_) {
      dedicatedClient.close();
      if (canceled || (cancellationSignal?.isCanceled ?? false)) {
        throw VeilApiException(
          'Attachment upload canceled.',
          code: 'attachment_upload_canceled',
        );
      }
      throw VeilApiException(
        'Attachment upload failed: network unavailable',
        code: 'attachment_upload_failed',
      );
    }

    final response = await http.Response.fromStream(streamedResponse);
    dedicatedClient.close();

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

  Future<Map<String, dynamic>> listDevices(String accessToken) async {
    return _get('/devices', accessToken: accessToken);
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

  Future<Map<String, dynamic>> _delete(
    String path, {
    String? accessToken,
  }) async {
    final response = await _client.delete(
      Uri.parse('$baseUrl$path'),
      headers: _headers(accessToken),
    );
    return _decodeMap(response);
  }

  Future<Map<String, dynamic>> _patch(
    String path,
    Map<String, dynamic> body, {
    String? accessToken,
  }) async {
    final response = await _client.patch(
      Uri.parse('$baseUrl$path'),
      headers: _headers(accessToken),
      body: jsonEncode(body),
    );
    return _decodeMap(response);
  }

  List<dynamic> _decodeList(http.Response response) {
    final decoded = _decode(response);
    if (decoded is List<dynamic>) {
      return decoded;
    }
    throw VeilApiException('Unexpected response shape');
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
        return 'This device is no longer trusted for this VEIL account.';
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
      case 'attachment_upload_canceled':
        return 'Attachment upload was canceled on this device.';
      case 'attachment_upload_invalid':
        return 'This attachment was rejected by the relay policy.';
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

class AttachmentUploadCancellationSignal {
  final List<void Function()> _listeners = <void Function()>[];
  bool _canceled = false;

  bool get isCanceled => _canceled;

  void register(void Function() listener) {
    if (_canceled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void cancel() {
    if (_canceled) {
      return;
    }
    _canceled = true;
    for (final listener in List<void Function()>.from(_listeners)) {
      listener();
    }
    _listeners.clear();
  }
}

class _AttachmentUploadCanceled implements Exception {
  const _AttachmentUploadCanceled();
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
