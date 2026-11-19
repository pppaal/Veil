import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/domain/chat_message.dart';
import 'package:veil_mobile/src/core/domain/conversation_read_mark.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/read_state_service.dart';

// What a chat counts as unread (unreadCountOf), without a messenger: the
// rule of spec D42 on hand-built messages.

final _now = DateTime.utc(2026, 4, 7, 10, 20);

ChatMessage _message(
  String id, {
  int? order,
  bool mine = false,
  MessageKind kind = MessageKind.text,
  MessageDeliveryState state = MessageDeliveryState.sent,
  DateTime? expiresAt,
}) =>
    ChatMessage(
      id: id,
      senderDeviceId: mine ? 'dev-me' : 'dev-peer',
      sentAt: _now.subtract(const Duration(minutes: 5)),
      conversationOrder: order,
      deliveryState: state,
      expiresAt: expiresAt,
      isMine: mine,
      envelope: CryptoEnvelope(
        version: 'v2',
        conversationId: 'conv-1',
        senderDeviceId: mine ? 'dev-me' : 'dev-peer',
        recipientUserId: 'user-me',
        ciphertext: 'c-$id',
        nonce: 'n-$id',
        messageKind: kind,
      ),
    );

ChatMessage _notice(String id, int order) => _message('$localNoticeIdPrefix$id', order: order, kind: MessageKind.system);

int _count(List<ChatMessage> messages, [ConversationReadMark? mark]) => unreadCountOf(messages, mark, now: _now);

void main() {
  test('incoming relayed messages above the mark count, and nothing at or below it', () {
    final messages = [for (var order = 1; order <= 6; order++) _message('m$order', order: order)];
    expect(_count(messages, const ConversationReadMark(readThrough: 4)), 2);
    expect(_count(messages, const ConversationReadMark(readThrough: 6)), 0);
    expect(_count(messages, const ConversationReadMark(readThrough: 0)), 6);
  });

  test('with no mark, or a mark that read nothing, every incoming message counts', () {
    final messages = [for (var order = 1; order <= 3; order++) _message('m$order', order: order)];
    expect(_count(messages), 3);
    expect(_count(messages, const ConversationReadMark(markedUnread: true)), 3);
  });

  test('own messages, pending and failed ones never count', () {
    final messages = [
      _message('m1', order: 1),
      _message('mine', order: 2, mine: true),
      _message('pending', mine: true, state: MessageDeliveryState.pending),
      _message('failed', mine: true, state: MessageDeliveryState.failed),
      _message('incoming-pending', state: MessageDeliveryState.pending),
      _message('incoming-failed', order: 3, state: MessageDeliveryState.failed),
    ];
    expect(_count(messages), 1);
  });

  test('local notices of an identity change, a timer and members never count', () {
    final messages = [
      _message('m1', order: 1),
      _notice('identity', 1),
      _notice('timer', 1),
      _notice('members', 1),
      _message('m2', order: 2),
    ];
    expect(_count(messages), 2);
    expect(_count(messages, const ConversationReadMark(readThrough: 1)), 1);
  });

  test('reactions and system lines (a screenshot notice) never count', () {
    final messages = [
      _message('m1', order: 1),
      _message('reaction', order: 2, kind: MessageKind.reaction),
      _message('screenshot', order: 3, kind: MessageKind.system),
      _message('photo', order: 4, kind: MessageKind.image),
      _message('file', order: 5, kind: MessageKind.file),
    ];
    expect(_count(messages), 3);
  });

  test('a message expired at now does not count; one expiring later does', () {
    final messages = [
      _message('gone', order: 1, expiresAt: _now.subtract(const Duration(seconds: 1))),
      _message('at-now', order: 2, expiresAt: _now),
      _message('later', order: 3, expiresAt: _now.add(const Duration(minutes: 1))),
    ];
    expect(_count(messages), 1);
  });

  test('a message the relay gave no order counts only while nothing was read', () {
    final messages = [_message('m1', order: 1), _message('unordered')];
    expect(_count(messages), 2);
    expect(_count(messages, const ConversationReadMark(readThrough: 1)), 0);
    expect(_count(messages, const ConversationReadMark(readThrough: 0)), 1);
  });

  test('the walk stops at the first ordered message at or below the mark', () {
    // Older messages above the mark cannot sit below it in a sorted list,
    // so one that does (a broken order) is not reached.
    final messages = [_message('stray', order: 9), _message('m1', order: 1), _message('m2', order: 2)];
    expect(_count(messages, const ConversationReadMark(readThrough: 1)), 1);
  });
}
