import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/storage/conversation_cache_service.dart';
import '../conversation_models.dart';
import 'messenger_session_context.dart';
import 'messenger_state_store.dart';
import 'reactions.dart';

/// Encrypts and queues one message; false when that failed.
typedef EnvelopeSender = Future<bool> Function({
  required String conversationId,
  required String body,
  required MessageKind messageKind,
});

/// Reactions travel end to end as messages of kind reaction; the relay sees
/// neither the target nor the emoji. They live only in those messages, so
/// the ledger is rebuilt from them and shown on the messages they target.
class ReactionService {
  ReactionService({
    required MessengerStateStore store,
    required MessengerSessionContext session,
    required EnvelopeSender send,
  })  : _store = store,
        _session = session,
        _send = send;

  final MessengerStateStore _store;
  final MessengerSessionContext _session;
  final EnvelopeSender _send;
  final ReactionLedger _ledger = ReactionLedger();

  /// [messages] with the reactions recorded for them.
  List<ChatMessage> decorate(String conversationId, List<ChatMessage> messages) =>
      _ledger.decorate(conversationId, messages);

  /// Adds [emoji] to [message], or withdraws it if it is already this
  /// user's reaction.
  Future<void> toggle(ChatMessage message, String emoji) async {
    final myUserId = _session.userId;
    final conversationId = message.envelope.conversationId;
    if (myUserId == null ||
        message.isPending ||
        message.hasFailed ||
        message.isLocalNotice ||
        !ReactionPayload.isAcceptableEmoji(emoji)) {
      return;
    }
    final add = _ledger.emojiOf(conversationId, message.id, myUserId) != emoji;
    final sentAt = DateTime.now();
    // Shown only once queued: a send the trust layer refused, or that failed
    // to encrypt, never reaches the peer.
    final queued = await _send(
      conversationId: conversationId,
      body: ReactionPayload(target: message.id, emoji: emoji, add: add).encode(),
      messageKind: MessageKind.reaction,
    );
    if (!queued) return;
    _record(
      conversationId,
      target: message.id,
      reactor: myUserId,
      emoji: emoji,
      add: add,
      position: ReactionPosition(conversationOrder: null, sentAt: sentAt),
    );
  }

  /// Applies an opened reaction [message] to its target in the same
  /// conversation; the reaction message itself never renders.
  void applyOpened(ChatMessage message, MessageContentRecord content) {
    final payload = ReactionPayload.tryDecode(content.body);
    final reactor = message.isMine ? _session.userId : _reactorOf(message);
    if (payload == null || reactor == null) return;
    _record(
      content.conversationId,
      target: payload.target,
      reactor: reactor,
      emoji: payload.emoji,
      add: payload.add,
      position: ReactionPosition(conversationOrder: message.conversationOrder, sentAt: message.sentAt),
    );
  }

  void clear() => _ledger.clear();

  // Group frames name a device, not a user, so in groups a device reacts.
  String? _reactorOf(ChatMessage message) {
    final conversation = _store.conversationById(message.envelope.conversationId);
    if (conversation == null) return null;
    return conversation.type == ConversationType.direct
        ? conversation.recipientBundle.userId
        : 'device:${message.senderDeviceId}';
  }

  void _record(
    String conversationId, {
    required String target,
    required String reactor,
    required String emoji,
    required bool add,
    required ReactionPosition position,
  }) {
    final changed = _ledger.apply(
      conversationId: conversationId,
      target: target,
      reactor: reactor,
      emoji: emoji,
      add: add,
      position: position,
    );
    if (!changed || !_store.hasMessagesLoaded(conversationId)) return;
    _store.setMessages(conversationId, _ledger.decorate(conversationId, _store.messagesOf(conversationId)));
  }
}
