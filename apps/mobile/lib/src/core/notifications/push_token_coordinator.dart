import 'dart:async';

import 'package:flutter/foundation.dart';

import '../network/veil_api_client.dart';
import 'remote_push_service.dart';

/// Listens for session authentication changes and keeps the server's
/// stored push token for the current device up to date. All operations
/// are best-effort; token-sync failures must not block sign-in or the
/// message path.
class PushTokenCoordinator {
  PushTokenCoordinator({
    required this.apiClient,
    required this.pushService,
  });

  final VeilApiClient apiClient;
  final RemotePushService pushService;

  StreamSubscription<String>? _refreshSub;
  String? _lastSyncedToken;
  String? _currentAccessToken;

  /// Called once a valid [accessToken] is known for the active session.
  Future<void> bind(String accessToken) async {
    _currentAccessToken = accessToken;
    _refreshSub ??= pushService.tokenRefresh.listen(_onRefresh);

    final token = await pushService.fetchToken();
    if (token == null || token.isEmpty) {
      return;
    }
    await _sync(token);
  }

  /// Called when the session is cleared. Clears the server-side token
  /// so a lost/stolen device can no longer receive push metadata.
  Future<void> unbind() async {
    final token = _currentAccessToken;
    _currentAccessToken = null;
    _lastSyncedToken = null;
    if (token == null) {
      return;
    }
    try {
      await apiClient.clearPushToken(token);
    } catch (error, stack) {
      debugPrint('push token clear failed: $error\n$stack');
    }
  }

  Future<void> dispose() async {
    await _refreshSub?.cancel();
    _refreshSub = null;
  }

  Future<void> _onRefresh(String token) async {
    if (_currentAccessToken == null || token.isEmpty) {
      return;
    }
    await _sync(token);
  }

  Future<void> _sync(String token) async {
    final accessToken = _currentAccessToken;
    if (accessToken == null) {
      return;
    }
    if (_lastSyncedToken == token) {
      return;
    }
    try {
      await apiClient.updatePushToken(accessToken, token);
      _lastSyncedToken = token;
    } catch (error, stack) {
      debugPrint('push token sync failed: $error\n$stack');
    }
  }
}

