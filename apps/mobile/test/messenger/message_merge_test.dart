import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/message_merge.dart';

final _base = DateTime.utc(2026, 4, 1, 12);

ChatMessage _message(
  String id, {
  String? clientMessageId,
  int? order,
  MessageDeliveryState state = MessageDeliveryState.sent,
  DateTime? deliveredAt,
  DateTime? readAt,
  DateTime? expiresAt,
  int minute = 0,
}) =>
    ChatMessage(
      id: id,
      clientMessageId: clientMessageId,
      senderDeviceId: 'dev-atlas',
      sentAt: _base.add(Duration(minutes: minute)),
      conversationOrder: order,
      deliveryState: state,
      deliveredAt: deliveredAt,
      readAt: readAt,
      expiresAt: expiresAt,
      isMine: true,
      envelope: CryptoEnvelope(
        version: 'veil-envelope-v2',
        conversationId: 'conv-1',
        senderDeviceId: 'dev-atlas',
        recipientUserId: 'user-selene',
        ciphertext: 'ct-$id',
        nonce: 'n-$id',
        messageKind: MessageKind.text,
      ),
    );

void main() {
  test('ack replaces optimistic', () {
    final optimistic = _message('local-c1', clientMessageId: 'c1', state: MessageDeliveryState.pending, minute: 1);
    final failedOther = _message('local-c2', clientMessageId: 'c2', state: MessageDeliveryState.failed, minute: 2);
    final acked = _message('srv-1', clientMessageId: 'c1', order: 7, minute: 1);

    final merged = mergeMessageCollections([optimistic, failedOther], [acked]);

    expect(merged.map((message) => message.id), ['srv-1', 'local-c2'],
        reason: 'the relay copy takes the place of the optimistic one; an unacked send stays');
    expect(merged.first.deliveryState, MessageDeliveryState.sent);
  });

  test('a later page keeps fields the relay copy leaves out', () {
    final local = _message('srv-1', clientMessageId: 'c1', order: 3);
    final relayed = _message('srv-1', order: null);

    final merged = mergeMessageCollections([local], [relayed]).single;

    expect(merged.clientMessageId, 'c1');
    expect(merged.conversationOrder, 3);
  });

  test('out-of-order receipts', () {
    final readFirst = _message(
      'srv-1',
      order: 1,
      state: MessageDeliveryState.read,
      deliveredAt: _base.add(const Duration(minutes: 1)),
      readAt: _base.add(const Duration(minutes: 2)),
    );
    // A stale page from before the read: delivered only, older timestamp.
    final staleDelivered = _message(
      'srv-1',
      order: 1,
      state: MessageDeliveryState.delivered,
      deliveredAt: _base,
    );

    final merged = mergeMessageCollections([readFirst], [staleDelivered]).single;

    expect(merged.deliveryState, MessageDeliveryState.read);
    expect(merged.readAt, readFirst.readAt);
    expect(merged.deliveredAt, readFirst.deliveredAt, reason: 'receipts only move forward');
  });

  test('expiry only ever shortens', () {
    final clamped = _message('srv-1', order: 1, expiresAt: _base.add(const Duration(minutes: 5)));
    final extended = _message('srv-1', order: 1, expiresAt: _base.add(const Duration(hours: 1)));
    final stripped = _message('srv-1', order: 1);

    expect(mergeMessageCollections([clamped], [extended]).single.expiresAt, clamped.expiresAt);
    expect(mergeMessageCollections([clamped], [stripped]).single.expiresAt, clamped.expiresAt);
    expect(withInnerExpiry(stripped, clamped.expiresAt).expiresAt, clamped.expiresAt);
    expect(identical(withInnerExpiry(clamped, null), clamped), isTrue);
  });

  test('relayed messages sort by conversation order, local ones after them', () {
    final pending = _message('local-c9', clientMessageId: 'c9', state: MessageDeliveryState.pending, minute: 0);
    final merged = mergeMessageCollections(
      [pending],
      [_message('srv-2', order: 2, minute: 5), _message('srv-1', order: 1, minute: 9)],
    );

    expect(merged.map((message) => message.id), ['srv-1', 'srv-2', 'local-c9']);
  });

  test('a later copy cannot change who sent a message or where', () {
    final known = _message('srv-1', order: 1);
    final relabelled = ChatMessage(
      id: 'srv-1',
      senderDeviceId: 'dev-selene',
      sentAt: known.sentAt,
      conversationOrder: 1,
      deliveredAt: _base.add(const Duration(minutes: 2)),
      isMine: false,
      envelope: CryptoEnvelope(
        version: 'veil-envelope-v2',
        conversationId: 'conv-2',
        senderDeviceId: 'dev-selene',
        recipientUserId: 'user-atlas',
        ciphertext: 'ct-other',
        nonce: 'n-other',
        messageKind: MessageKind.text,
      ),
    );

    final merged = mergeServerMessage(known, relabelled);

    expect(merged.senderDeviceId, 'dev-atlas');
    expect(merged.isMine, isTrue);
    expect(merged.envelope, same(known.envelope));
    // Receipts still move forward.
    expect(merged.deliveredAt, relabelled.deliveredAt);
    expect(merged.deliveryState, MessageDeliveryState.delivered);
  });
}
