import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/errors/user_facing_error.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_services.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/retry_policy.dart';

import '../support/messenger_services_fixture.dart';

/// POST /messages, recording what was sent in which order. A send waits
/// for [gate] when one is set, and fails with [failures] for the ids there.
/// A send of an id in [stalled] goes over the real transport to a relay
/// that never answers, so it times out as a slow relay makes it.
class _RelayApi extends VeilApiClient {
  _RelayApi()
      : super(
          baseUrl: 'http://relay.invalid/v1',
          client: MockClient((_) => Completer<http.Response>().future),
          requestTimeout: stallTimeout,
        );

  static const stallTimeout = Duration(milliseconds: 50);

  final List<String> sent = [];
  final Map<String, Object> failures = {};
  final Set<String> stalled = {};
  // While set, every send fails as an unreachable network makes it.
  bool offline = false;
  Completer<void>? gate;
  int _order = 0;

  @override
  Future<Map<String, dynamic>> sendMessage(String accessToken, Map<String, dynamic> body) async {
    final clientMessageId = body['clientMessageId'] as String;
    sent.add(clientMessageId);
    if (offline) throw VeilApiException('The server is unreachable.', code: 'network_unavailable');
    if (stalled.remove(clientMessageId)) return super.sendMessage(accessToken, body);
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

PendingMessageRecord _pending(String clientMessageId, {required int second, int queueOrder = 0}) => PendingMessageRecord(
      clientMessageId: clientMessageId,
      conversationId: 'conv-1',
      senderDeviceId: 'dev-atlas',
      recipientUserId: 'user-selene',
      createdAt: DateTime.utc(2026, 4, 1, 12, 0, second),
      queueOrder: queueOrder,
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

  test('restored records that tie on the whole second go by queue number, not by the order the cache gave them',
      () async {
    // Both come back from the cache at 12:00:05 (DateTime columns keep whole
    // seconds), the text first: a progress write of the upload rewrote its
    // row behind the text's. The upload was queued first, so it holds the
    // lower number.
    services.outbox.restore([
      _pending('c-text', second: 5, queueOrder: 2),
      _pending('c-upload', second: 5, queueOrder: 1),
    ]);

    await services.outbox.drain();

    expect(api.sent, ['c-upload', 'c-text'], reason: 'the upload was queued before the text');
    expect(services.outbox.hasPendingWork, isFalse);
  });

  test('the outbox hands out strictly increasing queue numbers, above every restored one', () async {
    // A real cache, so the numbers are read back the way a restart reads them.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final adapter = createDefaultCryptoAdapter();
    final cache = DriftConversationCacheService(AppDatabase(NativeDatabase.memory()), envelopeCodec: adapter.envelopeCodec);
    final cached = messengerServicesFixture(api: api, cache: cache, crypto: adapter);
    addTearDown(cached.dispose);
    // A group seals to its own bundle, with no directory lookup to fake.
    await cached.store.replaceConversations(
      [
        ConversationPreview(
          id: 'group-1',
          peerHandle: 'moving-day',
          peerDisplayName: null,
          recipientBundle:
              const KeyBundle(userId: '', deviceId: '', handle: 'moving-day', identityPublicKey: 'pub', signedPrekeyBundle: 'spk'),
          lastEnvelope: null,
          updatedAt: DateTime.utc(2026, 4, 1, 12),
          type: ConversationType.group,
        ),
      ],
      bound: const {},
      pin: (merged) async => (merged, <String>[]),
    );
    api.gate = Completer<void>();
    Future<int> numberOf(String body) async {
      final before = {for (final record in await cache.readPendingMessages()) record.clientMessageId};
      expect(await cached.outbox.send(conversationId: 'group-1', body: body, messageKind: MessageKind.text), isTrue);
      final added = (await cache.readPendingMessages()).where((record) => !before.contains(record.clientMessageId)).single;
      return added.queueOrder;
    }

    final first = await numberOf('one');
    final second = await numberOf('two');
    expect(first, greaterThan(0));
    expect(second, greaterThan(first));

    // A restart brings the queue back from the cache, here one of a long-lived install.
    cached.outbox.restore([
      _pending('c-kept-a', second: 1, queueOrder: second + 40),
      _pending('c-kept-b', second: 1, queueOrder: second + 41),
    ]);
    final third = await numberOf('three');
    expect(third, greaterThan(second + 41), reason: 'queued after everything restored');

    // A sign-out forgets the queue, not the numbers already handed out.
    cached.outbox.clear();
    expect(await numberOf('four'), greaterThan(third));
    api.gate!.complete();
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
    api.stalled.add('c-slow');
    final started = DateTime.now();

    await services.outbox.drain();

    expect(DateTime.now().difference(started), greaterThanOrEqualTo(_RelayApi.stallTimeout),
        reason: 'the first send waited for the relay until it timed out');
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
    expect(services.ops.errorMessage, UserFacingErrorCode.networkTimeout.sentence);

    await services.outbox.retry('conv-1');
    expect(api.sent, ['c-slow', 'c-next', 'c-slow']);
    expect(services.outbox.hasPendingWork, isFalse);
  });

  test('an outage longer than the attempt budget leaves the message queued, and it goes out once back online',
      () async {
    services.outbox.restore([_pending('c-offline', second: 1)]);
    api.offline = true;

    for (var attempt = 0; attempt < maxAutomaticRetryAttempts + 2; attempt++) {
      await services.outbox.drain(ignoreRetrySchedule: true);
    }
    expect(api.sent, hasLength(maxAutomaticRetryAttempts + 2));
    final queued = services.store.messagesOf('conv-1').single;
    expect(queued.deliveryState, MessageDeliveryState.pending, reason: 'still queued, not failed');
    expect(services.outbox.nextRetryAt('conv-1'), isNotNull);

    // The network returns: the reconnect drain sends it, no tap needed.
    api.offline = false;
    await services.outbox.drain(ignoreRetrySchedule: true);
    expect(services.outbox.hasPendingWork, isFalse);
    expect(services.store.messagesOf('conv-1').single.id, 'srv-c-offline');
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
