import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

void main() {
  late AppDatabase database;
  late DriftConversationCacheService cache;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    cache = DriftConversationCacheService(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('persists pending outbox items and restores paging state', () async {
    final conversation = ConversationPreview(
      id: 'conv-1',
      peerHandle: 'selene',
      peerDisplayName: 'Selene',
      recipientBundle: const KeyBundle(
        userId: 'user-selene',
        deviceId: 'device-selene',
        handle: 'selene',
        identityPublicKey: 'pub-selene',
        signedPrekeyBundle: 'prekey-selene',
      ),
      lastEnvelope: null,
      updatedAt: DateTime.utc(2026, 3, 30, 10, 0, 0),
    );

    await cache.storeConversations([conversation]);
    await cache.storePagingState(
      'conv-1',
      nextCursor: 'msg-cursor-2',
      hasMoreHistory: true,
      lastSyncedAt: DateTime.utc(2026, 3, 30, 10, 5, 0),
    );

    final pending = PendingMessageRecord(
      clientMessageId: 'client-msg-1',
      conversationId: 'conv-1',
      senderDeviceId: 'device-local',
      recipientUserId: 'user-selene',
      envelope: const CryptoEnvelope(
        version: 'veil-envelope-v1-dev',
        conversationId: 'conv-1',
        senderDeviceId: 'device-local',
        recipientUserId: 'user-selene',
        ciphertext: 'opaque-1',
        nonce: 'nonce-1',
        messageKind: MessageKind.text,
      ),
      createdAt: DateTime.utc(2026, 3, 30, 10, 6, 0),
      retryCount: 2,
      state: MessageDeliveryState.failed,
      errorMessage: 'Relay unavailable',
    );

    await cache.upsertPendingMessage(pending);

    final restoredPending = await cache.readPendingMessages();
    final paging = await cache.readPagingState('conv-1');

    expect(restoredPending, hasLength(1));
    expect(restoredPending.first.clientMessageId, 'client-msg-1');
    expect(restoredPending.first.retryCount, 2);
    expect(restoredPending.first.state, MessageDeliveryState.failed);
    expect(restoredPending.first.errorMessage, 'Relay unavailable');
    expect(paging.nextCursor, 'msg-cursor-2');
    expect(paging.hasMoreHistory, isTrue);
    expect(
      paging.lastSyncedAt?.isAtSameMomentAs(DateTime.utc(2026, 3, 30, 10, 5, 0)),
      isTrue,
    );
  });

  test('restores message ordering and delivery states from cache', () async {
    const baseEnvelope = CryptoEnvelope(
      version: 'veil-envelope-v1-dev',
      conversationId: 'conv-2',
      senderDeviceId: 'device-local',
      recipientUserId: 'user-icarus',
      ciphertext: 'opaque-2',
      nonce: 'nonce-2',
      messageKind: MessageKind.text,
    );

    await cache.storeConversations([
      ConversationPreview(
        id: 'conv-2',
        peerHandle: 'icarus',
        peerDisplayName: 'Icarus',
        recipientBundle: const KeyBundle(
          userId: 'user-icarus',
          deviceId: 'device-icarus',
          handle: 'icarus',
          identityPublicKey: 'pub-icarus',
          signedPrekeyBundle: 'prekey-icarus',
        ),
        lastEnvelope: baseEnvelope,
        updatedAt: DateTime.utc(2026, 3, 30, 11, 0, 0),
      ),
    ]);

    await cache.storeMessages('conv-2', [
      ChatMessage(
        id: 'msg-1',
        clientMessageId: 'client-a',
        senderDeviceId: 'device-local',
        sentAt: DateTime.utc(2026, 3, 30, 11, 0, 0),
        envelope: baseEnvelope,
        conversationOrder: 1,
        deliveryState: MessageDeliveryState.sent,
        isMine: true,
      ),
      ChatMessage(
        id: 'msg-2',
        clientMessageId: 'client-b',
        senderDeviceId: 'device-local',
        sentAt: DateTime.utc(2026, 3, 30, 11, 1, 0),
        envelope: baseEnvelope,
        conversationOrder: 2,
        deliveryState: MessageDeliveryState.read,
        deliveredAt: DateTime.utc(2026, 3, 30, 11, 1, 5),
        readAt: DateTime.utc(2026, 3, 30, 11, 1, 10),
        isMine: true,
      ),
    ]);

    final restored = await cache.readMessages('conv-2');

    expect(restored.map((message) => message.id).toList(), ['msg-1', 'msg-2']);
    expect(restored.last.conversationOrder, 2);
    expect(restored.last.deliveryState, MessageDeliveryState.read);
    expect(
      restored.last.deliveredAt?.isAtSameMomentAs(DateTime.utc(2026, 3, 30, 11, 1, 5)),
      isTrue,
    );
    expect(
      restored.last.readAt?.isAtSameMomentAs(DateTime.utc(2026, 3, 30, 11, 1, 10)),
      isTrue,
    );
  });
}
