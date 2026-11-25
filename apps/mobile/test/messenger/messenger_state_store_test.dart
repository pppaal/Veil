import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_session_context.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_state_store.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/receipt_service.dart';

import '../support/messenger_services_fixture.dart';

final _base = DateTime.utc(2026, 4, 1, 12);

ConversationPreview _conversation(String id, {DateTime? previewExpiresAt}) => ConversationPreview(
      id: id,
      peerHandle: 'selene',
      peerDisplayName: null,
      recipientBundle: const KeyBundle(
        userId: 'user-selene',
        deviceId: '',
        handle: 'selene',
        identityPublicKey: '',
        signedPrekeyBundle: '',
      ),
      lastEnvelope: previewExpiresAt == null ? null : _envelope(id, 'preview', expiresAt: previewExpiresAt),
      updatedAt: _base,
    );

CryptoEnvelope _envelope(String conversationId, String id, {DateTime? expiresAt}) => CryptoEnvelope(
      version: 'veil-envelope-v2',
      conversationId: conversationId,
      senderDeviceId: 'dev-selene',
      recipientUserId: 'user-atlas',
      ciphertext: 'ct-$id',
      nonce: 'n-$id',
      messageKind: MessageKind.text,
      expiresAt: expiresAt,
    );

ChatMessage _message(String id, {int order = 1, DateTime? expiresAt}) => ChatMessage(
      id: id,
      senderDeviceId: 'dev-selene',
      sentAt: _base.add(Duration(minutes: order)),
      conversationOrder: order,
      expiresAt: expiresAt,
      envelope: _envelope('conv-1', id),
    );

class _RecordingObserver implements MessengerStateObserver {
  int conversations = 0;
  final List<String> messages = [];
  final List<String> paging = [];

  @override
  void conversationsChanged() => conversations += 1;

  @override
  void messagesChanged(String conversationId) => messages.add(conversationId);

  @override
  void pagingChanged(String conversationId) => paging.add(conversationId);
}

Future<void> _listed(MessengerStateStore store, List<ConversationPreview> conversations) =>
    store.replaceConversations(conversations, bound: const {}, pin: (merged) async => (merged, <String>[]));

void main() {
  test('notifications are coalesced per microtask', () async {
    var notifications = 0;
    final store = MessengerStateStore(onChanged: () => notifications += 1);
    await _listed(store, [_conversation('conv-1')]);
    await Future<void>.delayed(Duration.zero);
    notifications = 0;

    store.mergeMessages('conv-1', [_message('srv-1')]);
    store.mergeMessages('conv-1', [_message('srv-2', order: 2)]);
    store.updateMessagesWhere((message) => message.id == 'srv-1', (message) => message.copyWith(searchableBody: 'x'));
    expect(notifications, 0, reason: 'nothing is told mid-step');

    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);
  });

  test('merging moves the preview to the latest message and tells observers', () async {
    final observer = _RecordingObserver();
    final store = MessengerStateStore(onChanged: () {})..addObserver(observer);
    await _listed(store, [_conversation('conv-1'), _conversation('conv-2')]);

    store.mergeMessages('conv-1', [_message('srv-1', order: 9)]);

    expect(store.conversations.first.id, 'conv-1', reason: 'the conversation with the newest message comes first');
    expect(store.conversationById('conv-1')!.lastEnvelope!.ciphertext, 'ct-srv-1');
    expect(observer.messages, ['conv-1']);
    expect(observer.conversations, greaterThanOrEqualTo(2));
    expect(() => store.requireConversation('conv-missing'), throwsStateError);
  });

  test('updateMessagesWhere reports a change only when a message changed', () async {
    final observer = _RecordingObserver();
    final store = MessengerStateStore(onChanged: () {})..addObserver(observer);
    store.setMessages('conv-1', [_message('srv-1')]);
    observer.messages.clear();

    expect(store.updateMessagesWhere((message) => message.id == 'srv-1', (message) => message), isFalse);
    expect(observer.messages, isEmpty);
    expect(
      store.updateMessagesWhere(
        (message) => message.id == 'srv-1',
        (message) => message.copyWith(deliveryState: MessageDeliveryState.read),
      ),
      isTrue,
    );
    expect(store.messagesOf('conv-1').single.deliveryState, MessageDeliveryState.read);
    expect(observer.messages, ['conv-1']);
  });

  test('removeExpired drops expired messages and the expired previews of unloaded conversations', () async {
    final store = MessengerStateStore(onChanged: () {});
    await _listed(store, [
      _conversation('conv-1'),
      _conversation('conv-2', previewExpiresAt: _base.add(const Duration(minutes: 1))),
    ]);
    store.setMessages('conv-1', [
      _message('srv-1', expiresAt: _base.add(const Duration(minutes: 1))),
      _message('srv-2', order: 2, expiresAt: _base.add(const Duration(hours: 1))),
    ]);

    expect(store.nextExpiry(), _base.add(const Duration(minutes: 1)));
    final (:expired, :changed) = store.removeExpired(_base.add(const Duration(minutes: 2)));

    expect(changed, isTrue);
    expect(expired.map((message) => message.id), ['srv-1']);
    expect(store.messagesOf('conv-1').map((message) => message.id), ['srv-2']);
    expect(store.conversationById('conv-2')!.lastEnvelope, isNull);
    expect(store.nextExpiry(), _base.add(const Duration(hours: 1)));
  });

  group('receipts', () {
    late MessengerStateStore store;
    late ReceiptService receipts;
    var readReceipts = true;

    setUp(() {
      readReceipts = true;
      final session = MessengerSessionContext()..diff(fixtureSession);
      late final ReceiptService service;
      store = MessengerStateStore(onChanged: () {}, decorate: (_, messages) => service.applyBacklog(messages));
      service = ReceiptService(
        store: store,
        session: session,
        apiClient: VeilApiClient(baseUrl: 'http://relay.invalid/v1'),
        readReceiptsEnabled: () => readReceipts,
      );
      receipts = service;
    });

    test('a receipt for a message not loaded yet applies once it arrives', () {
      receipts.apply('srv-1', readAt: _base.add(const Duration(minutes: 5)));

      store.mergeMessages('conv-1', [_message('srv-1')]);

      expect(store.messagesOf('conv-1').single.deliveryState, MessageDeliveryState.read);
    });

    test('with read receipts off a read shows as delivered', () {
      readReceipts = false;
      store.setMessages('conv-1', [_message('srv-1')]);

      receipts.apply('srv-1', readAt: _base.add(const Duration(minutes: 5)));

      final message = store.messagesOf('conv-1').single;
      expect(message.deliveryState, MessageDeliveryState.delivered);
      expect(message.readAt, isNull);
      expect(message.deliveredAt, _base.add(const Duration(minutes: 5)));
    });
  });
}
