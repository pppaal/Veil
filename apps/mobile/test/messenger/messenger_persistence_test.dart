import 'dart:async';
import 'dart:math';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';
import 'package:veil_mobile/src/core/security/local_data_cipher.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_peer_bindings.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_persistence.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_state_store.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import '../support/messenger_services_fixture.dart';

const _cacheKey = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';

/// The real encrypted cache, counting its writes.
class _CountingCache extends DriftConversationCacheService {
  _CountingCache(super.db, {required super.envelopeCodec}) : super(cipher: LocalDataCipher.forTesting(_cacheKey));

  int bulkWrites = 0;
  int wholeConversationWrites = 0;

  @override
  Future<void> writeChanges(ConversationCacheChanges changes) {
    bulkWrites += 1;
    return super.writeChanges(changes);
  }

  @override
  Future<void> storeMessages(String conversationId, List<ChatMessage> messages) {
    wholeConversationWrites += 1;
    return super.storeMessages(conversationId, messages);
  }
}

/// A relay with one 1:1 holding [history] in a single page.
class _HistoryApi extends VeilApiClient {
  _HistoryApi(this.history) : super(baseUrl: 'http://relay.invalid/v1');

  final List<Map<String, dynamic>> history;

  @override
  Future<Map<String, dynamic>> getConversations(String accessToken) async => {
        'items': [
          {
            'id': 'conv-1',
            'type': 'direct',
            'createdAt': DateTime.utc(2026, 4, 1).toIso8601String(),
            'members': [
              {'userId': 'user-atlas', 'handle': 'atlas', 'displayName': null},
              {'userId': 'user-selene', 'handle': 'selene', 'displayName': null},
            ],
            'lastMessage': null,
            'disappearingTimerSeconds': null,
          },
        ],
      };

  @override
  Future<Map<String, dynamic>> getMessages(String accessToken, String conversationId,
          {String? cursor, int limit = 50}) async =>
      {'items': history, 'nextCursor': null};
}

class _SilentRealtime extends RealtimeService {
  @override
  void connect({
    required String baseUrl,
    required String accessToken,
    required void Function(String event, dynamic payload) onEvent,
    void Function(bool connected)? onConnectionChanged,
  }) {}

  @override
  void disconnect() {}
}

/// A cache whose every write takes a random time before it is applied to
/// [rows]; [regressions] records any write that put a row back to an older
/// version than the one it held.
class _SlowCache implements ConversationCacheService, IncrementalConversationCache {
  _SlowCache(this._random);

  final Random _random;
  final Map<String, ChatMessage> rows = {};
  final List<String> regressions = [];

  Future<void> _delay() => Future<void>.delayed(Duration(microseconds: _random.nextInt(4000)));

  @override
  Future<void> writeChanges(ConversationCacheChanges changes) async {
    await _delay();
    for (final id in changes.replacedConversationIds) {
      rows.removeWhere((_, message) => message.envelope.conversationId == id);
    }
    changes.deletedMessageIds.forEach(rows.remove);
    for (final message in changes.messages) {
      final before = rows[message.id];
      if (before != null && message.readAt!.isBefore(before.readAt!)) regressions.add(message.id);
      rows[message.id] = message;
    }
  }

  @override
  Future<ConversationCacheSnapshot> readSnapshot() async => const ConversationCacheSnapshot();

  @override
  Future<List<PendingMessageRecord>> readPendingMessages() async => const [];

  @override
  Future<void> purgeExpiredMessages() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ConversationPreview _conversation(String id) => ConversationPreview(
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
      lastEnvelope: null,
      updatedAt: DateTime.utc(2026, 4, 1),
    );

ChatMessage _version(String id, int version) => ChatMessage(
      id: id,
      senderDeviceId: 'dev-selene',
      sentAt: DateTime.utc(2026, 4, 1, 12),
      conversationOrder: int.parse(id.split('-').last),
      readAt: DateTime.utc(2026, 4, 1, 12).add(Duration(seconds: version)),
      deliveryState: MessageDeliveryState.read,
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

void main() {
  test('opening a 200-message chat and decrypting all causes at most 2 bulk writes', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final adapter = createDefaultCryptoAdapter();
    final innerExpiry = DateTime.now().add(const Duration(hours: 1));
    final history = <Map<String, dynamic>>[];
    for (var order = 1; order <= 200; order++) {
      final envelope = await adapter.messaging.encryptMessage(
        conversationId: 'conv-1',
        senderDeviceId: 'dev-selene',
        recipientUserId: 'user-atlas',
        body: 'message $order',
        messageKind: MessageKind.text,
        recipientBundle: const KeyBundle(
          userId: 'user-atlas',
          deviceId: 'dev-atlas',
          handle: 'atlas',
          identityPublicKey: 'ik-atlas',
          signedPrekeyBundle: 'spk-atlas',
        ),
        expiresAt: innerExpiry,
      );
      // The relay strips the outer expiry; decrypting clamps every message
      // to the sealed one, so each decrypt changes its row.
      history.add(relayedMessageJson(
        {...adapter.envelopeCodec.encodeApiEnvelope(envelope), 'expiresAt': null},
        id: 'srv-$order',
        order: order,
        senderDeviceId: 'dev-selene',
      ));
    }
    final database = AppDatabase(NativeDatabase.memory());
    final cache = _CountingCache(database, envelopeCodec: adapter.envelopeCodec);
    final controller = VeilMessengerController(
      apiClient: _HistoryApi(history),
      cryptoEngine: adapter.messaging,
      keyBundleCodec: adapter.keyBundles,
      envelopeCodec: adapter.envelopeCodec,
      sessionBootstrapper: adapter.sessions,
      realtimeService: _SilentRealtime(),
      cacheService: cache,
      peerBindings: ConversationPeerBindings(),
    );
    addTearDown(controller.dispose);
    await controller.applySession(fixtureSession);
    await controller.flushPendingWrites();
    cache.bulkWrites = 0;

    await controller.loadConversationMessages('conv-1');
    final shown = await Future.wait(controller.messagesFor('conv-1').map(controller.decryptMessage));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await controller.flushPendingWrites();

    expect(shown, hasLength(200));
    expect(shown.every((message) => message.isOk), isTrue);
    expect(controller.messagesFor('conv-1').every((message) => message.expiresAt != null), isTrue);
    expect(cache.bulkWrites, inInclusiveRange(1, 2));
    expect(cache.wholeConversationWrites, 0, reason: 'only changed rows are written');
    final stored = await cache.readMessages('conv-1');
    expect(stored, hasLength(200));
    expect(stored.every((message) => message.expiresAt != null), isTrue, reason: 'the clamped expiry reached the cache');
  });

  test('randomized write delays never persist stale state', () async {
    for (final seed in [1, 2, 3, 4, 5]) {
      final random = Random(seed);
      final cache = _SlowCache(random);
      final store = MessengerStateStore(onChanged: () {});
      final persistence = MessengerPersistence(
        cache: cache,
        store: store,
        debounce: const Duration(milliseconds: 1),
        maxDelay: const Duration(milliseconds: 5),
      );
      store.addObserver(persistence);
      await store.replaceConversations(
        [_conversation('conv-1')],
        bound: const {},
        pin: (merged) async => (merged, <String>[]),
      );

      // Versions only grow, also across a removal and a re-add, so any
      // write that lowers one carries stale state.
      final versions = <String, int>{};
      final present = <String>{};
      for (var step = 0; step < 300; step++) {
        final id = 'srv-${random.nextInt(25)}';
        if (random.nextInt(10) == 0 && present.remove(id)) {
          store.setMessages('conv-1', [
            for (final message in store.messagesOf('conv-1'))
              if (message.id != id) message,
          ]);
        } else {
          final version = (versions[id] ?? 0) + 1;
          versions[id] = version;
          present.add(id);
          store.setMessages('conv-1', [
            for (final message in store.messagesOf('conv-1'))
              if (message.id != id) message,
            _version(id, version),
          ]);
        }
        if (random.nextInt(4) == 0) unawaited(persistence.flush());
        if (random.nextInt(8) == 0) await Future<void>.delayed(Duration(microseconds: random.nextInt(3000)));
      }
      await persistence.flush();

      expect(cache.regressions, isEmpty, reason: 'seed $seed: a slower, older write landed over a newer one');
      expect(
        {for (final MapEntry(key: id, value: message) in cache.rows.entries) id: message.readAt},
        {for (final message in store.messagesOf('conv-1')) message.id: message.readAt},
        reason: 'seed $seed: the cache ends with exactly the state in memory',
      );
      persistence.dispose();
    }
  });
}
