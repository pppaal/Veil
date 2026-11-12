import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_services.dart';

import '../support/messenger_services_fixture.dart';

/// POST /messages, recording what was sent in which order. A send waits
/// for [gate] when one is set, and fails with [failures] for the ids there.
class _RelayApi extends VeilApiClient {
  _RelayApi() : super(baseUrl: 'http://relay.invalid/v1');

  final List<String> sent = [];
  final Map<String, Object> failures = {};
  Completer<void>? gate;
  int _order = 0;

  @override
  Future<Map<String, dynamic>> sendMessage(String accessToken, Map<String, dynamic> body) async {
    final clientMessageId = body['clientMessageId'] as String;
    sent.add(clientMessageId);
    await gate?.future;
    final failure = failures.remove(clientMessageId);
    if (failure != null) throw failure;
    return {
      'message': relayedMessageJson(
        body['envelope'] as Map<String, dynamic>,
        id: 'srv-$clientMessageId',
        clientMessageId: clientMessageId,
        order: ++_order,
      ),
    };
  }
}

PendingMessageRecord _pending(String clientMessageId, {required int second}) => PendingMessageRecord(
      clientMessageId: clientMessageId,
      conversationId: 'conv-1',
      senderDeviceId: 'dev-atlas',
      recipientUserId: 'user-selene',
      createdAt: DateTime.utc(2026, 4, 1, 12, 0, second),
      envelope: CryptoEnvelope(
        version: 'veil-envelope-v2',
        conversationId: 'conv-1',
        senderDeviceId: 'dev-atlas',
        recipientUserId: 'user-selene',
        ciphertext: 'ct-$clientMessageId',
        nonce: 'n-$clientMessageId',
        messageKind: MessageKind.text,
      ),
    );

void main() {
  late _RelayApi api;
  late MessengerServices services;

  setUp(() {
    api = _RelayApi();
    services = messengerServicesFixture(api: api);
  });

  tearDown(() => services.dispose());

  test('drain ordering', () async {
    services.outbox.restore([
      _pending('c-third', second: 30),
      _pending('c-first', second: 10),
      _pending('c-second', second: 20),
    ]);

    await services.outbox.drain();

    expect(api.sent, ['c-first', 'c-second', 'c-third'], reason: 'oldest first, whatever order they were queued in');
    expect(services.outbox.hasPendingWork, isFalse);
    expect(services.store.messagesOf('conv-1').map((message) => message.id), ['srv-c-first', 'srv-c-second', 'srv-c-third']);
  });

  test('no double drain', () async {
    services.outbox.restore([_pending('c-1', second: 1), _pending('c-2', second: 2)]);
    api.gate = Completer<void>();

    final first = services.outbox.drain();
    await Future<void>.delayed(Duration.zero);
    final second = services.outbox.drain(ignoreRetrySchedule: true);
    await second;
    expect(api.sent, ['c-1'], reason: 'the second drain returned without starting another send');

    api.gate!.complete();
    await first;
    expect(api.sent, ['c-1', 'c-2'], reason: 'each message went out once');
    expect(services.outbox.hasPendingWork, isFalse);
  });

  test('timeout does not block subsequent sends', () async {
    services.outbox.restore([_pending('c-slow', second: 1), _pending('c-next', second: 2)]);
    api.failures['c-slow'] = VeilApiException('timed out', code: 'network_timeout');
    final started = DateTime.now();

    await services.outbox.drain();

    expect(api.sent, ['c-slow', 'c-next']);
    final messages = services.store.messagesOf('conv-1');
    expect(messages.map((message) => message.id), contains('srv-c-next'));
    final retried = services.outbox.nextRetryAt('conv-1');
    expect(retried, isNotNull, reason: 'the timed-out send waits for its retry');
    expect(retried!.isAfter(started), isTrue);
    expect(
      messages.singleWhere((message) => message.clientMessageId == 'c-slow').deliveryState,
      MessageDeliveryState.pending,
      reason: 'a transient failure stays queued, not failed',
    );
    expect(services.ops.errorMessage, 'timed out');

    await services.outbox.retry('conv-1');
    expect(api.sent, ['c-slow', 'c-next', 'c-slow']);
    expect(services.outbox.hasPendingWork, isFalse);
  });

  test('a rejection the relay would repeat fails the message for the user', () async {
    services.outbox.restore([_pending('c-stale', second: 1)]);
    api.failures['c-stale'] = VeilApiException('stale', statusCode: 409, code: 'group_epoch_stale');

    await services.outbox.drain();
    await services.outbox.drain(ignoreRetrySchedule: true);

    expect(api.sent, ['c-stale'], reason: 'a failed send waits for the user, not the schedule');
    expect(services.store.pendingCountFor('conv-1'), 1);
    expect(services.outbox.nextRetryAt('conv-1'), isNull);
  });
}
