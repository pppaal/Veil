import 'dart:async';

import '../../../../core/network/veil_api_client.dart';
import 'message_content_service.dart';
import 'messenger_api_mapper.dart';
import 'messenger_operation_runner.dart';
import 'messenger_persistence.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';

/// Expires messages at min(inner, outer) expiry and keeps each
/// conversation's disappearing timer.
///
/// One one-shot timer is armed for the next expiry of anything loaded or
/// listed, and re-armed whenever the state changes; nothing ticks while
/// nothing is due.
class DisappearingMessagesService implements MessengerStateObserver {
  DisappearingMessagesService({
    required MessengerStateStore store,
    required MessageContentService contents,
    required MessengerPersistence persistence,
    required MessengerSessionContext session,
    required VeilApiClient apiClient,
    required MessengerApiMapper mapper,
    required MessengerOperationRunner ops,
    DateTime Function() now = DateTime.now,
  })  : _store = store,
        _contents = contents,
        _persistence = persistence,
        _session = session,
        _apiClient = apiClient,
        _mapper = mapper,
        _ops = ops,
        _now = now;

  final MessengerStateStore _store;
  final MessageContentService _contents;
  final MessengerPersistence _persistence;
  final MessengerSessionContext _session;
  final VeilApiClient _apiClient;
  final MessengerApiMapper _mapper;
  final MessengerOperationRunner _ops;
  final DateTime Function() _now;
  Timer? _timer;
  DateTime? _armedFor;
  bool _rearmScheduled = false;
  bool _disposed = false;

  @override
  void conversationsChanged() => _scheduleRearm();

  @override
  void messagesChanged(String conversationId) => _scheduleRearm();

  @override
  void pagingChanged(String conversationId) {}

  /// Drops everything that expired by now, its content and cached rows
  /// included, and arms the timer for what expires next.
  Future<void> reconcile() async {
    final now = _now();
    final (:expired, :changed) = _store.removeExpired(now);
    if (changed) {
      if (expired.isNotEmpty) await _contents.deleteExpired(now, expired);
      await _persistence.purgeExpired(now);
    }
    _rearm();
  }

  /// Sets the default timer for messages sent in [conversationId]; locally
  /// only without a relay session.
  Future<void> setTimer(String conversationId, int? seconds) async {
    final session = _session.authed;
    if (session == null) {
      applyTimer(conversationId, seconds);
      return;
    }
    try {
      final response = await _apiClient.setDisappearingTimer(session.accessToken, conversationId, seconds);
      final applied = _mapper.appliedTimer(response, requested: seconds) ?? (throw StateError('Unexpected response shape'));
      applyTimer(conversationId, applied.seconds);
    } catch (error) {
      await _ops.fail(error);
      rethrow;
    }
  }

  void applyTimer(String conversationId, int? seconds) {
    _store.updateConversation(
      conversationId,
      (conversation) => conversation.disappearingTimerSeconds == seconds
          ? conversation
          : conversation.copyWith(disappearingTimerSeconds: seconds),
    );
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }

  // Many changes land in one step (a page of messages, each decrypt); the
  // next expiry is looked up once for all of them.
  void _scheduleRearm() {
    if (_rearmScheduled || _disposed) return;
    _rearmScheduled = true;
    scheduleMicrotask(() {
      _rearmScheduled = false;
      _rearm();
    });
  }

  void _rearm() {
    if (_disposed) return;
    final next = _store.nextExpiry();
    if (next == _armedFor && (_timer?.isActive ?? false)) return;
    _timer?.cancel();
    _timer = null;
    _armedFor = next;
    if (next == null) return;
    final delay = next.difference(_now());
    _timer = Timer(delay.isNegative ? Duration.zero : _toWholeMilliseconds(delay), () => unawaited(reconcile()));
  }

  // Timer drops the sub-millisecond part of a delay, so it would fire just
  // before the expiry, find nothing due and re-arm until it passed.
  static Duration _toWholeMilliseconds(Duration delay) =>
      Duration(milliseconds: (delay.inMicroseconds + Duration.microsecondsPerMillisecond - 1) ~/ Duration.microsecondsPerMillisecond);
}
