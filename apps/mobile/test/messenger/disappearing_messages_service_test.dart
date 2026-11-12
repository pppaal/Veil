import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/disappearing_messages_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/message_content_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_api_mapper.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_operation_runner.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_persistence.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_session_context.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_state_store.dart';

final _start = DateTime.utc(2026, 4, 1, 12);

ChatMessage _message(String id, {DateTime? expiresAt}) => ChatMessage(
      id: id,
      senderDeviceId: 'dev-selene',
      sentAt: _start,
      conversationOrder: int.parse(id.split('-').last),
      expiresAt: expiresAt,
      envelope: CryptoEnvelope(
        version: 'veil-envelope-v2',
        conversationId: 'conv-1',
        senderDeviceId: 'dev-selene',
        recipientUserId: 'user-atlas',
        ciphertext: 'ct-$id',
        nonce: 'n-$id',
        messageKind: MessageKind.text,
      ),
    );

/// A store and the service over it, on a clock that follows fake time.
(MessengerStateStore, DisappearingMessagesService) _service(FakeAsync async) {
  final store = MessengerStateStore(onChanged: () {});
  final service = DisappearingMessagesService(
    store: store,
    contents: MessageContentService(
      cache: null,
      decrypt: (_) => throw StateError('nothing is decrypted here'),
      onContentStored: (_, __) {},
    ),
    persistence: MessengerPersistence(cache: null, store: store),
    session: MessengerSessionContext(),
    apiClient: VeilApiClient(baseUrl: 'http://relay.invalid/v1'),
    mapper: MessengerApiMapper(createDefaultCryptoAdapter().envelopeCodec),
    ops: MessengerOperationRunner(onChanged: () {}),
    now: () => _start.add(async.elapsed),
  );
  store.addObserver(service);
  return (store, service);
}

void main() {
  test('no periodic timers when nothing expires', () {
    fakeAsync((async) {
      final (store, service) = _service(async);
      store.setMessages('conv-1', [_message('srv-1'), _message('srv-2')]);
      service.reconcile();
      async.flushMicrotasks();

      expect(async.periodicTimerCount, 0);
      expect(async.pendingTimers, isEmpty, reason: 'nothing is due, so nothing waits');

      async.elapse(const Duration(hours: 1));
      expect(store.messagesOf('conv-1'), hasLength(2));
      service.dispose();
    });
  });

  test('fires at next expiry', () {
    fakeAsync((async) {
      final (store, service) = _service(async);
      store.setMessages('conv-1', [
        _message('srv-1', expiresAt: _start.add(const Duration(seconds: 10))),
        _message('srv-2', expiresAt: _start.add(const Duration(seconds: 25))),
        _message('srv-3'),
      ]);
      async.flushMicrotasks();
      expect(async.pendingTimers, hasLength(1), reason: 'one timer, for the earliest expiry');
      expect(async.periodicTimerCount, 0);

      async.elapse(const Duration(seconds: 9));
      expect(store.messagesOf('conv-1').map((message) => message.id), ['srv-1', 'srv-2', 'srv-3']);

      async.elapse(const Duration(seconds: 1));
      expect(store.messagesOf('conv-1').map((message) => message.id), ['srv-2', 'srv-3']);
      expect(async.pendingTimers, hasLength(1), reason: 're-armed for the next expiry');

      async.elapse(const Duration(seconds: 15));
      expect(store.messagesOf('conv-1').map((message) => message.id), ['srv-3']);
      expect(async.pendingTimers, isEmpty);
      service.dispose();
    });
  });

  test('a sooner expiry arriving later re-arms the timer for it', () {
    fakeAsync((async) {
      final (store, service) = _service(async);
      store.setMessages('conv-1', [_message('srv-1', expiresAt: _start.add(const Duration(minutes: 5)))]);
      async.flushMicrotasks();

      store.setMessages('conv-1', [
        ...store.messagesOf('conv-1'),
        _message('srv-2', expiresAt: _start.add(const Duration(seconds: 3))),
      ]);
      async.elapse(const Duration(seconds: 3));

      expect(store.messagesOf('conv-1').map((message) => message.id), ['srv-1']);
      expect(async.pendingTimers, hasLength(1));
      service.dispose();
    });
  });
}
