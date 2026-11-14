import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../../core/realtime/realtime_service.dart';

/// Who is typing where and who is online, from relay signals, and this
/// device's own typing signal.
///
/// A notifier of its own: these signals change every few seconds, and only
/// the widgets that show them should rebuild, not everything that watches
/// the messenger.
class PresenceTypingService extends ChangeNotifier {
  PresenceTypingService({
    required RealtimeService realtime,
    required bool Function() isConnected,
    required bool Function() typingIndicatorsEnabled,
    Duration remoteTypingTimeout = const Duration(seconds: 5),
    Duration localTypingIdle = const Duration(seconds: 3),
  })  : _realtime = realtime,
        _isConnected = isConnected,
        _typingIndicatorsEnabled = typingIndicatorsEnabled,
        _remoteTypingTimeout = remoteTypingTimeout,
        _localTypingIdle = localTypingIdle;

  final RealtimeService _realtime;
  final bool Function() _isConnected;
  // Read on every keystroke so a settings change applies at once.
  final bool Function() _typingIndicatorsEnabled;
  final Duration _remoteTypingTimeout;
  final Duration _localTypingIdle;

  final Map<String, String> _typingByConversation = {};
  // One per conversation: a peer typing in one chat must not cut short the
  // indicator of another.
  final Map<String, Timer> _typingTimeouts = {};
  final Set<String> _onlineUserIds = {};
  Timer? _localTypingIdleTimer;
  bool _localTypingActive = false;
  bool _disposed = false;

  String? typingHandleFor(String conversationId) => _typingByConversation[conversationId];

  bool isUserOnline(String userId) => _onlineUserIds.contains(userId);

  /// A peer started typing; the indicator clears by itself unless renewed.
  void typingStarted(String conversationId, String handle) {
    if (_disposed) return;
    _typingByConversation[conversationId] = handle;
    _typingTimeouts.remove(conversationId)?.cancel();
    _typingTimeouts[conversationId] = Timer(_remoteTypingTimeout, () => typingStopped(conversationId));
    notifyListeners();
  }

  void typingStopped(String conversationId) {
    if (_disposed) return;
    _typingTimeouts.remove(conversationId)?.cancel();
    _typingByConversation.remove(conversationId);
    notifyListeners();
  }

  void presenceChanged(String userId, {required bool online}) {
    if (_disposed) return;
    online ? _onlineUserIds.add(userId) : _onlineUserIds.remove(userId);
    notifyListeners();
  }

  /// The user typed in [conversationId]: tells peers once, and that it
  /// stopped after a pause.
  void localTyping(String conversationId) {
    if (!_isConnected() || !_typingIndicatorsEnabled()) return;
    if (!_localTypingActive) {
      _localTypingActive = true;
      _realtime.emit('typing.start', {'conversationId': conversationId});
    }
    _localTypingIdleTimer?.cancel();
    _localTypingIdleTimer = Timer(_localTypingIdle, () {
      _localTypingActive = false;
      _realtime.emit('typing.stop', {'conversationId': conversationId});
    });
  }

  /// The user sent in [conversationId], which ends their typing there.
  void localTypingEnded(String conversationId) {
    _localTypingIdleTimer?.cancel();
    if (_localTypingActive) {
      _localTypingActive = false;
      _realtime.emit('typing.stop', {'conversationId': conversationId});
    }
  }

  @override
  void dispose() {
    _disposed = true;
    for (final timer in _typingTimeouts.values) {
      timer.cancel();
    }
    _typingTimeouts.clear();
    _localTypingIdleTimer?.cancel();
    super.dispose();
  }
}
