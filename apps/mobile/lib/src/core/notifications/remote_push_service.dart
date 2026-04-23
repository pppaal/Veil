import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Abstract interface for remote push (FCM/APNs) integrations.
///
/// The default implementation is [DisabledRemotePushService] which returns
/// `null` tokens and an inert stream. A concrete Firebase implementation can
/// be plugged in via [remotePushServiceProvider] override once Firebase is
/// set up on each platform (see docs/launch-runbook.md → remote push
/// integration steps).
abstract class RemotePushService {
  /// Platform-reported token. Returns `null` if remote push is disabled,
  /// permission was denied, or the platform has not yet issued a token.
  Future<String?> fetchToken();

  /// Stream of token refresh events. Each value is the new token.
  Stream<String> get tokenRefresh;

  /// Fires when a push payload is received and the app should refresh
  /// (e.g. fetch backfill for a conversation).
  Stream<RemotePushHint> get onMessage;

  /// Release underlying native resources.
  Future<void> dispose();
}

@immutable
class RemotePushHint {
  const RemotePushHint({required this.kind});

  /// Opaque wake signal. The push payload carries no conversation or message
  /// metadata — the app responds by running its normal unread backfill.
  final String kind;
}

/// Default implementation used when Firebase is not wired up. Keeps the
/// rest of the app compilable and functional without requiring Firebase
/// setup for dev / CI / widget tests.
class DisabledRemotePushService implements RemotePushService {
  DisabledRemotePushService();

  final _tokenController = StreamController<String>.broadcast();
  final _messageController = StreamController<RemotePushHint>.broadcast();

  @override
  Future<String?> fetchToken() async => null;

  @override
  Stream<String> get tokenRefresh => _tokenController.stream;

  @override
  Stream<RemotePushHint> get onMessage => _messageController.stream;

  @override
  Future<void> dispose() async {
    await _tokenController.close();
    await _messageController.close();
  }
}

final remotePushServiceProvider = Provider<RemotePushService>((ref) {
  final service = DisabledRemotePushService();
  ref.onDispose(() => service.dispose());
  return service;
});
