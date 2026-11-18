import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/domain/chat_message.dart';
import 'package:veil_mobile/src/core/domain/conversation_read_mark.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/message_content_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_state_store.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/read_state_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/receipt_service.dart';

// Where the unread divider says the unread messages start (spec D48), on a
// store filled by hand: above the first unread message when it is loaded,
// and "Unread messages" above the oldest loaded one when the relay said the
// history goes further back than the first unread one.

const _conv = 'conv-1';
final _now = DateTime.utc(2026, 4, 7, 10, 20);

ChatMessage _message(int order) => ChatMessage(
      id: 'm$order',
      senderDeviceId: 'dev-peer',
      sentAt: _now.subtract(const Duration(minutes: 5)),
      conversationOrder: order,
      deliveryState: MessageDeliveryState.sent,
      isMine: false,
      envelope: CryptoEnvelope(
        version: 'v2',
        conversationId: _conv,
        senderDeviceId: 'dev-peer',
        recipientUserId: 'user-me',
        ciphertext: 'c-$order',
        nonce: 'n-$order',
        messageKind: MessageKind.text,
      ),
    );

// Taking a divider sends nothing and opens nothing.
class _Unused implements ReceiptService, MessageContentService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  // The loaded messages [from] to [through], read through [readThrough]
  // (no mark when null), with a history page that says there is more
  // ([moreHistory]), none, or no page at all ([paged] false: only live
  // messages came in).
  UnreadDivider? divider({
    required int from,
    required int through,
    int? readThrough,
    bool paged = true,
    bool moreHistory = true,
  }) {
    final store = MessengerStateStore(onChanged: () {});
    final unused = _Unused();
    final reads = ReadStateService(
      store: store,
      receipts: unused,
      notifications: null,
      contents: unused,
      receiptsWithheld: (_) => false,
      now: () => _now,
    );
    if (readThrough != null) store.setReadMark(_conv, ConversationReadMark(readThrough: readThrough));
    store.setMessages(_conv, [for (var order = from; order <= through; order++) _message(order)]);
    if (paged) store.setPaging(_conv, ConversationPagingState(nextCursor: moreHistory ? 'older' : null, hasMoreHistory: moreHistory));
    final viewer = Object();
    reads.beginViewing(_conv, viewer: viewer);
    return reads.dividerFor(_conv, viewer: viewer);
  }

  test('a history that goes further back than what is loaded hides the first unread: "Unread messages"', () {
    // Read through 10; 51 to 100 loaded, and the relay has older ones.
    final shown = divider(from: 51, through: 100, readThrough: 10)!;
    expect(shown.olderThanLoaded, isTrue);
    expect(shown.firstMessageId, 'm51', reason: 'above the oldest loaded unread message');
    expect(shown.count, 50);
  });

  test('with nothing read at all, a history with more to load hides the first unread too', () {
    expect(divider(from: 51, through: 100)!.olderThanLoaded, isTrue);
  });

  test('the first unread loaded, right after the mark, is counted', () {
    final shown = divider(from: 11, through: 60, readThrough: 10)!;
    expect(shown.olderThanLoaded, isFalse);
    expect((shown.count, shown.firstMessageId), (50, 'm11'));
  });

  test('a history the relay said is all loaded is counted, however far the mark is', () {
    expect(divider(from: 51, through: 100, readThrough: 10, moreHistory: false)!.olderThanLoaded, isFalse);
  });

  test('live messages with no history page are taken as the whole chat', () {
    expect(divider(from: 51, through: 100, readThrough: 10, paged: false)!.olderThanLoaded, isFalse);
  });
}
