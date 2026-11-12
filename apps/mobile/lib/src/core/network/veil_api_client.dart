import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/veil_config.dart';
import 'http_transport.dart';
import 'pinned_http_client.dart';
import 'server_clock.dart';
import 'token_refresh_gate.dart';
import 'veil_api_exception.dart';

export 'server_clock.dart' show ServerClock;
export 'veil_api_exception.dart';

class VeilApiClient {
  VeilApiClient({
    required this.baseUrl,
    http.Client? client,
    Future<String?> Function()? tokenRefresher,
    Duration requestTimeout = kDefaultRequestTimeout,
    Duration uploadTimeout = kDefaultUploadTimeout,
    http.Client? objectStorageClient,
    ObjectStoragePolicy? objectStoragePolicy,
    ServerClock? serverClock,
  })  : serverClock = serverClock ?? ServerClock(),
        _client = client ??
            buildPinnedHttpClient(
              allowedFingerprints: parsePinList(VeilConfig.tlsPins),
            ),
        _refreshGate =
            tokenRefresher == null ? null : TokenRefreshGate(tokenRefresher),
        _requestTimeout = requestTimeout,
        _uploadTimeout = uploadTimeout,
        _injectedObjectStorageClient = objectStorageClient,
        _objectStoragePolicy =
            objectStoragePolicy ?? ObjectStoragePolicy.fromEnvironment();

  final String baseUrl;

  /// The relay's time, learned from the `Date` header of every API
  /// response, refusals included.
  final ServerClock serverClock;
  final http.Client _client;
  // The refresher is resolved by the auth controller so the API client
  // doesn't need a hard reference to AppState. When a request comes back
  // 401, _authedRequest asks the gate for a fresh access token and replays
  // the original call once.
  final TokenRefreshGate? _refreshGate;
  final Duration _requestTimeout;
  final Duration _uploadTimeout;
  final http.Client? _injectedObjectStorageClient;
  final ObjectStoragePolicy _objectStoragePolicy;

  // Presigned upload URLs usually point at a different host than the API,
  // so uploads get their own client and pins. Built on first upload only.
  late final http.Client _objectStorageClient = _injectedObjectStorageClient ??
      buildPinnedHttpClient(
        allowedFingerprints: parsePinList(VeilConfig.objectStoragePins),
      );

  /// Authenticated JSON calls, so feature APIs can live in their own files.
  /// A missing token fails with code 'unauthorized' instead of a null-check
  /// crash when the session is torn down while a call is being prepared.
  Future<Map<String, dynamic>> getJson(
    String path, {
    required String? accessToken,
    Map<String, String>? query,
  }) async {
    return _get(path, accessToken: _requireToken(accessToken), query: query);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    required String? accessToken,
    Object? body,
  }) async {
    return _post(
      path,
      body ?? const <String, dynamic>{},
      accessToken: _requireToken(accessToken),
    );
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    required String? accessToken,
    Object? body,
  }) async {
    return _put(
      path,
      body ?? const <String, dynamic>{},
      accessToken: _requireToken(accessToken),
    );
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    required String? accessToken,
    Object? body,
  }) async {
    return _delete(path, body: body, accessToken: _requireToken(accessToken));
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> body) async {
    return _post('/auth/register', body);
  }

  Future<Map<String, dynamic>> challenge(Map<String, dynamic> body) async {
    return _post('/auth/challenge', body);
  }

  Future<Map<String, dynamic>> verify(Map<String, dynamic> body) async {
    return _post('/auth/verify', body);
  }

  Future<Map<String, dynamic>> refreshAuth(String refreshToken) async {
    return _post('/auth/refresh', {'refreshToken': refreshToken});
  }

  Future<Map<String, dynamic>> logoutAuth(
    String accessToken, {
    String? refreshToken,
  }) async {
    return _post(
      '/auth/logout',
      {if (refreshToken != null) 'refreshToken': refreshToken},
      accessToken: accessToken,
    );
  }

  // /conversations returns {items, nextCursor} per the contracts package, not
  // a raw array — the original _getList shape was a stale assumption.
  Future<Map<String, dynamic>> getConversations(String accessToken) async {
    return _get('/conversations', accessToken: accessToken);
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
    return _get(
      '/conversations/$conversationId/messages',
      accessToken: accessToken,
      query: {
        'limit': '$limit',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
  }

  Future<Map<String, dynamic>> setDisappearingTimer(
    String accessToken,
    String conversationId,
    int? seconds,
  ) async {
    return _post(
      '/conversations/$conversationId/timer',
      {'seconds': seconds},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> listBlockedUsers(String accessToken) async {
    return _get('/safety/blocks', accessToken: accessToken);
  }

  Future<Map<String, dynamic>> blockUser(
    String accessToken,
    String userId,
  ) async {
    return _post('/safety/blocks', {'userId': userId}, accessToken: accessToken);
  }

  Future<Map<String, dynamic>> unblockUser(
    String accessToken,
    String userId,
  ) async {
    return _delete('/safety/blocks/$userId', accessToken: accessToken);
  }

  Future<Map<String, dynamic>> setConversationMute(
    String accessToken,
    String conversationId, {
    int? mutedForSeconds,
    required bool unmute,
  }) async {
    return _post(
      '/safety/mutes/$conversationId',
      {
        'mutedForSeconds': unmute ? null : mutedForSeconds,
      },
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> fileAbuseReport(
    String accessToken, {
    required String reportedUserId,
    required String reason,
    String? conversationId,
    String? messageId,
    String? note,
  }) async {
    return _post(
      '/safety/reports',
      {
        'reportedUserId': reportedUserId,
        'reason': reason,
        if (conversationId != null) 'conversationId': conversationId,
        if (messageId != null) 'messageId': messageId,
        if (note != null) 'note': note,
      },
      accessToken: accessToken,
    );
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

  // Group Sender Keys relay (opaque to the server; see
  // docs/group-sender-keys-design.md → "Protocol additions").

  Future<Map<String, dynamic>> distributeGroupKeys(
    String accessToken,
    String conversationId, {
    required int epoch,
    required List<Map<String, dynamic>> distributions,
  }) async {
    return _post(
      '/conversations/group/$conversationId/key-distribute',
      {'epoch': epoch, 'distributions': distributions},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> getGroupKeyDistributions(
    String accessToken,
    String conversationId,
  ) async {
    return _get(
      '/conversations/group/$conversationId/key-distributions',
      accessToken: accessToken,
    );
  }

  // Profile and contacts endpoints

  Future<Map<String, dynamic>> getPublicProfile(
    String accessToken,
    String handle,
  ) async {
    return _get('/profile/$handle', accessToken: accessToken);
  }

  Future<List<dynamic>> getContacts(String accessToken) async {
    return _getList('/contacts', accessToken: accessToken);
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
    return _getList('/stories', accessToken: accessToken);
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
    return _getList('/calls', accessToken: accessToken);
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
    final uri = _objectStoragePolicy.checkUploadUrl(uploadUrl);
    // Built before the guard: malformed VEIL_OBJECT_STORAGE_PINS must fail
    // here, not leave an idle timer and a half-fed body behind.
    final client = _objectStorageClient;
    final totalBytes = await file.length();
    final guard = UploadGuard(idleTimeout: _uploadTimeout);
    cancellationSignal?.register(guard.cancel);
    final request = http.AbortableStreamedRequest(
      'PUT',
      uri,
      abortTrigger: guard.abortTrigger,
    )
      ..headers.addAll(
        headers.map((key, value) => MapEntry(key, value.toString())),
      )
      ..contentLength = totalBytes;
    request.headers.putIfAbsent('Content-Length', () => '$totalBytes');

    var sentBytes = 0;
    // addStream (unlike add) honours backpressure, so a chunk is counted only
    // when the connection takes it and the idle watchdog measures real
    // network progress rather than how fast the file was read.
    final body = file.openRead().takeWhile((_) => !guard.isStopped).map((chunk) {
      sentBytes += chunk.length;
      guard.reportProgress();
      onProgress?.call(sentBytes, totalBytes);
      return chunk;
    });
    unawaited(
      request.sink
          .addStream(body)
          // A read failure truncates the body; send() then fails on the
          // length mismatch and that error is the one reported.
          .catchError((Object _) {})
          .whenComplete(request.sink.close),
    );

    final http.Response response;
    try {
      response = await guard.run(
        client.send(request).then(http.Response.fromStream),
      );
    } on VeilApiException {
      rethrow;
    } catch (error) {
      if (guard.isCanceled) {
        throw VeilApiException(
          'Attachment upload canceled.',
          code: 'attachment_upload_canceled',
        );
      }
      throw transportFailure(error) ??
          VeilApiException(
            'Attachment upload failed: network unavailable',
            code: 'attachment_upload_failed',
          );
    }

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

  Future<Map<String, dynamic>> updatePushToken(
    String accessToken,
    String pushToken,
  ) async {
    return _post(
      '/devices/push-token',
      {'pushToken': pushToken},
      accessToken: accessToken,
    );
  }

  Future<Map<String, dynamic>> clearPushToken(String accessToken) async {
    return _delete('/devices/push-token', accessToken: accessToken);
  }

  Future<Map<String, dynamic>> deleteAccount(String accessToken) async {
    return _delete('/account', accessToken: accessToken);
  }

  Future<Map<String, dynamic>> _get(
    String path, {
    String? accessToken,
    Map<String, String>? query,
  }) async {
    return _decodeMap(
      await _authedRequest('GET', path, accessToken: accessToken, query: query),
    );
  }

  Future<List<dynamic>> _getList(
    String path, {
    String? accessToken,
  }) async {
    return _decodeList(
      await _authedRequest('GET', path, accessToken: accessToken),
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Object body, {
    String? accessToken,
  }) async {
    return _decodeMap(
      await _authedRequest('POST', path, accessToken: accessToken, body: body),
    );
  }

  Future<Map<String, dynamic>> _put(
    String path,
    Object body, {
    String? accessToken,
  }) async {
    return _decodeMap(
      await _authedRequest('PUT', path, accessToken: accessToken, body: body),
    );
  }

  Future<Map<String, dynamic>> _delete(
    String path, {
    String? accessToken,
    Object? body,
  }) async {
    return _decodeMap(
      await _authedRequest('DELETE', path, accessToken: accessToken, body: body),
    );
  }

  String _requireToken(String? accessToken) {
    if (accessToken == null || accessToken.isEmpty) {
      throw VeilApiException(
        'Authenticated API session required.',
        code: 'unauthorized',
      );
    }
    return accessToken;
  }

  // One request with a one-shot 401 → refresh → replay. We only refresh when
  // the caller actually had a token; refresh and unauthed calls are passed
  // straight through. Concurrent 401s share one refresh through the gate,
  // and when it fails each caller surfaces its original 401.
  Future<http.Response> _authedRequest(
    String method,
    String path, {
    String? accessToken,
    Object? body,
    Map<String, String>? query,
  }) async {
    final base = Uri.parse('$baseUrl$path');
    final uri = query == null || query.isEmpty
        ? base
        : base.replace(queryParameters: query);
    final initial = await _send(method, uri, accessToken: accessToken, body: body);
    final gate = _refreshGate;
    if (initial.statusCode != 401 ||
        accessToken == null ||
        accessToken.isEmpty ||
        gate == null) {
      return initial;
    }
    final fresh = await gate.replacementFor(accessToken);
    if (fresh == null) {
      return initial;
    }
    return _send(method, uri, accessToken: fresh, body: body);
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    String? accessToken,
    Object? body,
  }) async {
    final abort = Completer<void>();
    final request = http.AbortableRequest(method, uri, abortTrigger: abort.future)
      ..headers.addAll(_headers(accessToken));
    if (body != null) {
      request.body = jsonEncode(body);
    }
    try {
      final response = await _client.send(request).then(http.Response.fromStream).timeout(_requestTimeout);
      serverClock.observe(response.headers['date']);
      return response;
    } catch (error) {
      final failure = transportFailure(error);
      if (failure == null) {
        rethrow;
      }
      if (error is TimeoutException) {
        // Release the stalled connection instead of letting it linger in
        // the shared client's pool.
        abort.complete();
      }
      throw failure;
    }
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
