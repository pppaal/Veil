import 'dart:async';

import '../../../../core/config/veil_config.dart';
import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/notifications/local_notification_service.dart';
import '../../../../core/realtime/realtime_events.dart';
import '../../../../core/realtime/realtime_service.dart';
import 'conversation_crypto_router.dart';
import 'conversation_sync_service.dart';
import 'disappearing_messages_service.dart';
import 'message_content_service.dart';
import 'messenger_api_mapper.dart';
import 'messenger_operation_runner.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';
import 'outbox_service.dart';
import 'presence_typing_service.dart';
import 'receipt_service.dart';

/// The realtime link: connects with the session's token, follows the
/// connection, and hands each contract event, validated and typed, to the
/// service it concerns.
class RealtimeEventRouter {
  RealtimeEventRouter({
    required RealtimeService realtime,
    required MessengerSessionContext session,
    required MessengerStateStore store,
    required MessengerApiMapper mapper,
    required MessageContentService contents,
    required MessengerOperationRunner ops,
    required ReceiptService receipts,
    required PresenceTypingService presence,
    required ConversationSyncService sync,
    required DisappearingMessagesService disappearing,
    required ConversationCryptoRouter crypto,
    required OutboxService outbox,
    required LocalNotificationService? notifications,
    required Future<String?> Function(String staleToken) refreshAccessToken,
  })  : _realtime = realtime,
        _session = session,
        _store = store,
        _mapper = mapper,
        _contents = contents,
        _ops = ops,
        _receipts = receipts,
        _presence = presence,
        _sync = sync,
        _disappearing = disappearing,
        _crypto = crypto,
        _outbox = outbox,
        _notifications = notifications,
        _refreshAccessToken = refreshAccessToken {
    _realtime.onServerDisconnect = _onServerDisconnect;
  }

  static const _firstRecoveryDelay = Duration(seconds: 1);
  static const _maxRecoveryDelay = Duration(seconds: 60);

  final RealtimeService _realtime;
  final MessengerSessionContext _session;
  final MessengerStateStore _store;
  final MessengerApiMapper _mapper;
  final MessageContentService _contents;
  final MessengerOperationRunner _ops;
  final ReceiptService _receipts;
  final PresenceTypingService _presence;
  final ConversationSyncService _sync;
  final DisappearingMessagesService _disappearing;
  final ConversationCryptoRouter _crypto;
  final OutboxService _outbox;
  final LocalNotificationService? _notifications;
  final Future<String?> Function(String staleToken) _refreshAccessToken;
  bool _connected = false;
  Timer? _recovery;
  Duration _recoveryDelay = _firstRecoveryDelay;
  // Bumped whenever this side disconnects, so a recovery started before it
  // does not connect again.
  bool _refreshConversationsOnConnect = true;

  int _epoch = 0;

  bool get connected => _connected;

  Future<void> connect() async {
    final session = _session.authed;
    if (_connected || session == null) return;
    _connectWith(session.accessToken);
  }

  void _connectWith(String accessToken) {
    _realtime.connect(
      baseUrl: VeilConfig.realtimeUrl,
      accessToken: accessToken,
      onConnectionChanged: _onConnectionChanged,
      onEvent: (name, payload) => unawaited(_dispatch(name, payload)),
    );
  }

  void disconnect() {
    _epoch += 1;
    _cancelRecovery();
    _realtime.disconnect();
    _connected = false;
  }

  // The relay closed the socket, as it does when the token it authenticated
  // with expires, and socket.io will not reconnect on its own. Reconnect with
  // a fresh token, backing off while the relay keeps closing it.
  void _onServerDisconnect() {
    _connected = false;
    if (_session.isClosed || _session.authed == null || _recovery != null) return;
    final epoch = _epoch;
    _recovery = Timer(_recoveryDelay, () => unawaited(_recover(epoch)));
    final doubled = _recoveryDelay * 2;
    _recoveryDelay = doubled > _maxRecoveryDelay ? _maxRecoveryDelay : doubled;
  }

  Future<void> _recover(int epoch) async {
    _recovery = null;
    final session = _session.authed;
    if (epoch != _epoch || _session.isClosed || session == null || _connected) return;
    final fresh = await _refreshAccessToken(session.accessToken);
    // Null: the session cannot be refreshed, which the sign-out path owns.
    if (fresh == null || epoch != _epoch || _session.isClosed || _session.authed == null || _connected) return;
    // The refreshed session also reaches applyToken; connecting here does
    // not wait for it.
    _connectWith(fresh);
  }

  void _cancelRecovery() {
    _recovery?.cancel();
    _recovery = null;
    _recoveryDelay = _firstRecoveryDelay;
  }

  /// Reconnects; with [refreshConversations] false the resync after it
  /// fetches message history without refetching the conversation list.
  Future<void> reconnect({required bool refreshConversations}) async {
    disconnect();
    _refreshConversationsOnConnect = refreshConversations;
    _store.changed();
    await connect();
  }

  /// Same identity, new token: only the socket needs it. Every cache and
  /// the ratchet state stay valid, so the resync skips the list.
  Future<void> applyToken(String accessToken) async {
    _refreshConversationsOnConnect = false;
    if (_connected) {
      _realtime.updateAuth(accessToken);
    } else {
      await connect();
    }
  }

  void _onConnectionChanged(bool connected) {
    _connected = connected;
    if (connected) {
      _recoveryDelay = _firstRecoveryDelay;
      _ops.clearRelayInterruption();
    } else {
      _ops.noteRelayInterrupted(hasQueuedSends: _outbox.hasPendingWork);
    }
    _store.changed();
    if (connected) {
      _sync.scheduleSyncHint(refreshConversations: _refreshConversationsOnConnect);
      _refreshConversationsOnConnect = true;
      unawaited(_outbox.drain(ignoreRetrySchedule: true));
    }
  }

  Future<void> _dispatch(String name, Object? payload) async {
    switch (RealtimeEvent.tryParse(name, payload)) {
      case MessageNewEvent(:final summary):
        await _onMessage(summary);
      case MessageDeliveredEvent(:final messageId, :final deliveredAt):
        _receipts.apply(messageId, deliveredAt: deliveredAt);
      case MessageReadEvent(:final messageId, :final readAt):
        _receipts.apply(messageId, readAt: readAt);
      case TypingEvent(started: true, :final conversationId, :final handle):
        _presence.typingStarted(conversationId, handle);
      case TypingEvent(started: false, :final conversationId):
        _presence.typingStopped(conversationId);
      case PresenceUpdateEvent(:final userId, :final online):
        _presence.presenceChanged(userId, online: online);
      case ConversationSyncEvent(:final conversationId):
        _sync.scheduleSyncHint(conversationId: conversationId);
      case ConversationTimerChangedEvent(:final conversationId, :final disappearingTimerSeconds):
        _disappearing.applyTimer(conversationId, disappearingTimerSeconds);
      case GroupKeyDistributionEvent():
        _crypto.handleKeyDistribution(payload as Map<String, dynamic>);
      case final GroupEpochBumpedEvent event:
        unawaited(_crypto.handleEpochBumped(event));
      // Deprecated and never emitted (contract C9). Reactions are
      // authenticated only inside the ratchet; a relay event names whatever
      // reactor the server likes, so it is never applied.
      case MessageReactionEvent():
      case UnknownRealtimeEvent():
      case null:
        break;
    }
  }

  Future<void> _onMessage(Map<String, dynamic> summary) async {
    final message = _mapper.message(summary, localDeviceId: _session.deviceId);
    if (message == null || message.isLocalNotice || (await _contents.withoutRetired([message])).isEmpty) return;
    final conversationId = message.envelope.conversationId;
    _store.mergeMessages(conversationId, [message]);
    unawaited(_contents.ingestAll([message]));
    if (!message.isMine && conversationId == _store.activeConversationId) {
      await _receipts.markRead(message.id);
    } else if (!message.isMine && message.envelope.messageKind != MessageKind.reaction) {
      // A reaction updates a message already seen. Trusting the relay's
      // label costs nothing: it could withhold the message.
      unawaited(_notifications?.showMessageNotification(
        conversationId: conversationId,
        title: 'VEIL',
        body: 'New encrypted message',
      ));
    }
    _sync.scheduleSyncHint(conversationId: conversationId);
  }
}
