import 'dart:async';

import '../../../../core/crypto/crypto_engine.dart';
import '../../../../core/domain/conversation_read_mark.dart';
import '../../../../core/notifications/local_notification_service.dart';
import '../conversation_models.dart';
import 'message_content_service.dart';
import 'messenger_state_store.dart';
import 'receipt_service.dart';

/// Kinds that never count as unread and never take a read receipt: a
/// reaction changes a message already seen, and a system line (a peer's
/// screenshot notice) is about the chat, not a message to read.
const Set<MessageKind> _notCounted = {MessageKind.reaction, MessageKind.system};

/// How many of [messages] are unread under [mark], on the expiry clock's
/// [now]: messages of someone else that are relayed, not local notices, not
/// pending or failed, of a kind that counts, not expired, and newer than
/// what was read. With no mark (or nothing read) every such message counts,
/// and only then one the relay gave no order.
///
/// Walks from the newest message and stops at the first ordered one at or
/// below the mark, so it costs the unread messages, not the history.
int unreadCountOf(List<ChatMessage> messages, ConversationReadMark? mark, {required DateTime now}) {
  final readThrough = mark?.readThrough;
  var count = 0;
  for (final message in messages.reversed) {
    final order = message.conversationOrder;
    if (readThrough != null && order != null && order <= readThrough && !message.isLocalNotice) break;
    if (_countable(message, now) && (order != null || readThrough == null)) count += 1;
  }
  return count;
}

bool _countable(ChatMessage message, DateTime now) =>
    !message.isMine &&
    !message.isLocalNotice &&
    !message.isPending &&
    !message.hasFailed &&
    !_notCounted.contains(message.envelope.messageKind) &&
    !(message.expiresAt != null && !message.expiresAt!.isAfter(now));

/// Where a chat's "unread messages" divider goes, as it stood when the
/// chat screen began showing it: above [firstMessageId], saying [count];
/// or, when the first unread message is older than what is loaded
/// ([olderThanLoaded]), "Unread messages" above the oldest loaded one.
class UnreadDivider {
  const UnreadDivider({required this.count, required this.firstMessageId, required this.olderThanLoaded});

  final int count;
  final String firstMessageId;
  final bool olderThanLoaded;
}

// One screen's view of a chat: the divider it took, or still to take when
// nothing was loaded yet.
class _View {
  _View(this.divider, {required this.taken});

  UnreadDivider? divider;
  bool taken;
}

/// What has been read on this phone, and what the Chats list counts.
///
/// One read mark per conversation (ConversationReadMark), kept by the store
/// and written by MessengerPersistence; counts are derived from it and the
/// loaded messages. What is on screen is read: the mark moves to the newest
/// loaded relayed message when a chat becomes active and with every batch
/// of messages merged into the active chat, once per microtask. Each move
/// cancels the chat's notification and sends at most one read receipt, for
/// the newest message of someone else it covered whose content opened, of
/// a kind that counts. No receipt goes while [receiptsWithheld] says so,
/// though the mark still moves, and none is sent later for what was read
/// then. Older history never moves the mark.
class ReadStateService implements MessengerStateObserver, ReadMarkObserver {
  ReadStateService({
    required MessengerStateStore store,
    required ReceiptService receipts,
    required LocalNotificationService? notifications,
    required MessageContentService contents,
    required this.receiptsWithheld,
    required DateTime Function() now,
  })  : _store = store,
        _receipts = receipts,
        _notifications = notifications,
        _contents = contents,
        _now = now;

  final MessengerStateStore _store;
  final ReceiptService _receipts;
  final LocalNotificationService? _notifications;
  final MessageContentService _contents;
  // The expiry clock: an expired message is not counted.
  final DateTime Function() _now;

  /// Whether no read receipt may go for [conversationId] now: who its peer
  /// is waits for the user, or it is a 1:1 with someone blocked
  /// (MessengerServices.receiptsWithheld).
  final bool Function(String conversationId) receiptsWithheld;

  final Map<String, int> _counts = {};
  final Set<String> _advanceScheduled = {};
  final Map<String, Map<Object, _View>> _views = {};
  // A divider the lock took off screen with its chat, for the screen that
  // unlock puts back.
  final Map<String, _View> _parked = {};
  // Bumped by [clear]: a receipt still being looked up belongs to the
  // identity that left.
  int _generation = 0;

  /// Unread messages in [conversationId] (unreadCountOf).
  int unreadCount(String conversationId) => _counts[conversationId] ??=
      unreadCountOf(_store.messagesOf(conversationId), _store.readMarkOf(conversationId), now: _now());

  /// What has been read of [conversationId] on this phone, if anything.
  ConversationReadMark? readMarkOf(String conversationId) => _store.readMarkOf(conversationId);

  /// Whether the user marked [conversationId] unread.
  bool markedUnread(String conversationId) => _store.readMarkOf(conversationId)?.markedUnread ?? false;

  /// Whether the Chats row shows [conversationId] as unread.
  bool isUnread(String conversationId) => markedUnread(conversationId) || unreadCount(conversationId) > 0;

  /// How many listed chats are unread, those [excluded] says left out.
  int unreadChats({required bool Function(String conversationId) excluded}) => _store.conversations
      .where((conversation) => !excluded(conversation.id) && isUnread(conversation.id))
      .length;

  /// The conversation the user is looking at right now, or null. Becoming
  /// active reads it.
  void setActive(String? conversationId) {
    _store.activeConversationId = conversationId;
    if (conversationId == null) return;
    _parked.removeWhere((parkedId, _) => parkedId != conversationId);
    _scheduleAdvance(conversationId);
  }

  /// "Mark as read" on a Chats row: what opening the chat would do, through
  /// the list's last message when it names a newer one than is loaded.
  void markRead(String conversationId) =>
      _advance(conversationId, listedOrder: _store.conversationById(conversationId)?.lastMessageOrder);

  /// "Mark as unread" on a Chats row: the flag only. Nothing is sent and
  /// nothing withdrawn.
  void markUnread(String conversationId) {
    final mark = _store.readMarkOf(conversationId);
    _store.setReadMark(conversationId, ConversationReadMark(readThrough: mark?.readThrough, markedUnread: true));
  }

  /// A chat screen ([viewer]) began showing [conversationId]: the divider
  /// is taken now, before the chat is read, unless this viewer has one.
  /// It stays while the screen shows the chat, whatever comes and goes
  /// over it, and is gone the next time.
  void beginViewing(String conversationId, {required Object viewer}) {
    final views = _views.putIfAbsent(conversationId, () => {});
    if (views.containsKey(viewer)) return;
    views[viewer] = _parked.remove(conversationId) ?? _take(conversationId);
  }

  /// The divider [viewer] took for [conversationId], if any.
  UnreadDivider? dividerFor(String conversationId, {required Object viewer}) =>
      _views[conversationId]?[viewer]?.divider;

  /// [viewer] stopped showing [conversationId]. With [keep] (the lock took
  /// the chat off screen) its divider waits for the screen unlock puts back.
  void endViewing(String conversationId, {required Object viewer, bool keep = false}) {
    final views = _views[conversationId];
    final view = views?.remove(viewer);
    if (views != null && views.isEmpty) _views.remove(conversationId);
    if (keep && view != null) _parked[conversationId] = view;
  }

  /// Forgets everything held for the identity that left.
  void clear() {
    _generation += 1;
    _counts.clear();
    _advanceScheduled.clear();
    _views.clear();
    _parked.clear();
  }

  // On the first successful relay list after a start that found the
  // baseline marker (a new account, or one moved to this phone), every
  // listed conversation without a mark is read through its last message.
  @override
  void conversationsChanged() {
    if (!_store.baselinePending || !_store.listedByRelay) return;
    _store.spendBaseline({
      for (final conversation in _store.conversations)
        if (_store.readMarkOf(conversation.id) == null && conversation.lastMessageOrder != null)
          conversation.id: ConversationReadMark(readThrough: conversation.lastMessageOrder),
    });
  }

  @override
  void messagesChanged(String conversationId) {
    // A screen that began showing the chat before anything was loaded
    // takes its divider now, before the chat is read.
    for (final view in _views[conversationId]?.values ?? const <_View>[]) {
      if (!view.taken) view.divider = _take(conversationId).divider;
    }
    final before = _counts[conversationId];
    final after = _counts[conversationId] =
        unreadCountOf(_store.messagesOf(conversationId), _store.readMarkOf(conversationId), now: _now());
    if (conversationId == _store.activeConversationId) {
      _scheduleAdvance(conversationId);
    } else if (after == 0 && (before ?? 1) > 0 && !markedUnread(conversationId)) {
      // What was unread expired or went: its notification goes too.
      unawaited(_notifications?.cancelConversation(conversationId));
    }
  }

  @override
  void pagingChanged(String conversationId) {}

  @override
  void readMarkChanged(String conversationId) => _counts[conversationId] =
      unreadCountOf(_store.messagesOf(conversationId), _store.readMarkOf(conversationId), now: _now());

  @override
  void baselineSpent() {}

  void _scheduleAdvance(String conversationId) {
    if (!_advanceScheduled.add(conversationId)) return;
    scheduleMicrotask(() {
      if (!_advanceScheduled.remove(conversationId)) return;
      if (conversationId == _store.activeConversationId) _advance(conversationId);
    });
  }

  // Moves the mark to the newest loaded relayed message (or [listedOrder]
  // when newer), clears "marked unread", cancels the notification and
  // sends the one receipt. Holds no state across an await: the receipt is
  // looked up after the mark moved, and re-entering from the receipt's own
  // readAt finds nothing newer.
  void _advance(String conversationId, {int? listedOrder}) {
    final mark = _store.readMarkOf(conversationId);
    final messages = _store.messagesOf(conversationId);
    final readThrough = mark?.readThrough;
    int? newest = listedOrder;
    for (final message in messages) {
      final order = message.conversationOrder;
      if (order != null && !message.isLocalNotice && (newest == null || order > newest)) newest = order;
    }
    final moves = newest != null && (readThrough == null || newest > readThrough);
    if (!moves && !(mark?.markedUnread ?? false)) return;
    final now = _now();
    final covered = [
      for (final message in messages)
        if (!message.isMine &&
            !message.isLocalNotice &&
            message.conversationOrder != null &&
            (readThrough == null || message.conversationOrder! > readThrough) &&
            !(message.expiresAt != null && !message.expiresAt!.isAfter(now)))
          message,
    ];
    _store.setReadMark(conversationId, ConversationReadMark(readThrough: moves ? newest : readThrough));
    unawaited(_notifications?.cancelConversation(conversationId));
    if (covered.isEmpty || !_receipts.enabled || receiptsWithheld(conversationId)) return;
    unawaited(_sendReceipt(conversationId, covered));
  }

  // The receipt goes for the newest of [covered] whose content opened and
  // whose opened kind counts; a frame still opening is waited for.
  Future<void> _sendReceipt(String conversationId, List<ChatMessage> covered) async {
    final generation = _generation;
    for (final message in covered.reversed) {
      final DecryptedMessage opened;
      try {
        opened = await _contents.read(message);
      } catch (_) {
        continue;
      }
      if (generation != _generation) return;
      if (opened.status != DecryptStatus.ok || _notCounted.contains(opened.messageKind)) continue;
      if (receiptsWithheld(conversationId)) return;
      await _receipts.markRead(message.id);
      return;
    }
  }

  _View _take(String conversationId) {
    if (!_store.hasMessagesLoaded(conversationId)) return _View(null, taken: false);
    final mark = _store.readMarkOf(conversationId);
    final readThrough = mark?.readThrough;
    final messages = _store.messagesOf(conversationId);
    final now = _now();
    final counted = [
      for (final message in messages)
        if (_countable(message, now) &&
            (readThrough == null
                ? true
                : message.conversationOrder != null && message.conversationOrder! > readThrough))
          message,
    ];
    if (counted.isEmpty) return _View(null, taken: true);
    int? oldestLoaded;
    for (final message in messages) {
      final order = message.conversationOrder;
      if (order != null && (oldestLoaded == null || order < oldestLoaded)) oldestLoaded = order;
    }
    // Only a history the relay said goes further back hides older unread
    // messages; one never paged (live messages only) is taken as whole.
    final olderThanLoaded = _store.hasPagingFor(conversationId) &&
        _store.pagingFor(conversationId).hasMoreHistory &&
        (readThrough == null || (oldestLoaded != null && oldestLoaded > readThrough + 1));
    return _View(
      UnreadDivider(count: counted.length, firstMessageId: counted.first.id, olderThanLoaded: olderThanLoaded),
      taken: true,
    );
  }
}
