import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/security/local_data_cipher.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

void main() {
  late AppDatabase database;
  late DriftConversationCacheService cache;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    cache = DriftConversationCacheService(
      database,
      envelopeCodec: createDefaultCryptoAdapter().envelopeCodec,
    );
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
      paging.lastSyncedAt
          ?.isAtSameMomentAs(DateTime.utc(2026, 3, 30, 10, 5, 0)),
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
      restored.last.deliveredAt
          ?.isAtSameMomentAs(DateTime.utc(2026, 3, 30, 11, 1, 5)),
      isTrue,
    );
    expect(
      restored.last.readAt
          ?.isAtSameMomentAs(DateTime.utc(2026, 3, 30, 11, 1, 10)),
      isTrue,
    );
  });

  test('indexes cached message bodies for device-local archive search',
      () async {
    await cache.storeConversations([
      ConversationPreview(
        id: 'conv-3',
        peerHandle: 'orion',
        peerDisplayName: 'Orion',
        recipientBundle: const KeyBundle(
          userId: 'user-orion',
          deviceId: 'device-orion',
          handle: 'orion',
          identityPublicKey: 'pub-orion',
          signedPrekeyBundle: 'prekey-orion',
        ),
        lastEnvelope: null,
        updatedAt: DateTime.utc(2026, 4, 2, 9, 0, 0),
      ),
    ]);

    await cache.storeMessages('conv-3', [
      ChatMessage(
        id: 'msg-archive-1',
        senderDeviceId: 'device-local',
        sentAt: DateTime.utc(2026, 4, 2, 9, 0, 0),
        envelope: const CryptoEnvelope(
          version: 'veil-envelope-v1-dev',
          conversationId: 'conv-3',
          senderDeviceId: 'device-local',
          recipientUserId: 'user-orion',
          ciphertext: 'opaque-archive',
          nonce: 'nonce-archive',
          messageKind: MessageKind.text,
        ),
        isMine: true,
      ),
    ]);

    await cache.indexMessageBody(
      conversationId: 'conv-3',
      messageId: 'msg-archive-1',
      searchableBody: 'orion archive keyword',
    );

    final matches = await cache.searchCachedMessageIds(
      conversationId: 'conv-3',
      query: 'archive',
    );

    expect(matches, ['msg-archive-1']);
  });

  test('encrypts sensitive cache metadata at rest', () async {
    final cipher = await LocalDataCipher.fromBase64Key(
      base64Url.encode(List<int>.filled(32, 7)).replaceAll('=', ''),
    );
    cache = DriftConversationCacheService(
      database,
      envelopeCodec: createDefaultCryptoAdapter().envelopeCodec,
      cipher: cipher,
    );

    await cache.storeConversations([
      ConversationPreview(
        id: 'conv-secure',
        peerHandle: 'selene',
        peerDisplayName: 'Selene',
        recipientBundle: const KeyBundle(
          userId: 'user-selene',
          deviceId: 'device-selene',
          handle: 'selene',
          identityPublicKey: 'pub-selene',
          signedPrekeyBundle: 'prekey-selene',
        ),
        lastEnvelope: const CryptoEnvelope(
          version: 'veil-envelope-v1-dev',
          conversationId: 'conv-secure',
          senderDeviceId: 'device-selene',
          recipientUserId: 'user-local',
          ciphertext: 'opaque-secure',
          nonce: 'nonce-secure',
          messageKind: MessageKind.text,
        ),
        updatedAt: DateTime.utc(2026, 4, 3, 8, 0, 0),
      ),
    ]);

    await cache.storeMessages('conv-secure', [
      ChatMessage(
        id: 'msg-secure',
        senderDeviceId: 'device-selene',
        sentAt: DateTime.utc(2026, 4, 3, 8, 1, 0),
        envelope: const CryptoEnvelope(
          version: 'veil-envelope-v1-dev',
          conversationId: 'conv-secure',
          senderDeviceId: 'device-selene',
          recipientUserId: 'user-local',
          ciphertext: 'opaque-secure',
          nonce: 'nonce-secure',
          messageKind: MessageKind.text,
        ),
      ),
    ]);

    final conversationRow = await database
        .customSelect(
          "SELECT peer_handle, peer_display_name, preview_message_type FROM cached_conversations WHERE id = 'conv-secure'",
        )
        .getSingle();
    final messageRow = await database
        .customSelect(
          "SELECT message_type FROM cached_messages WHERE id = 'msg-secure'",
        )
        .getSingle();

    expect(conversationRow.data['peer_handle'], isNot('selene'));
    expect(conversationRow.data['peer_display_name'], isNot('Selene'));
    expect(conversationRow.data['preview_message_type'],
        isNot(MessageKind.text.name));
    expect(messageRow.data['message_type'], isNot(MessageKind.text.name));
  });

  test('searchMessageArchive applies sender, type, and date filters locally',
      () async {
    final now = DateTime.now();
    await cache.storeConversations([
      ConversationPreview(
        id: 'conv-search',
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
        updatedAt: now,
      ),
    ]);

    await cache.storeMessages('conv-search', [
      ChatMessage(
        id: 'msg-mine',
        senderDeviceId: 'device-local',
        sentAt: now.subtract(const Duration(days: 2)),
        envelope: const CryptoEnvelope(
          version: 'veil-envelope-v1-dev',
          conversationId: 'conv-search',
          senderDeviceId: 'device-local',
          recipientUserId: 'user-selene',
          ciphertext: 'opaque-a',
          nonce: 'nonce-a',
          messageKind: MessageKind.text,
        ),
        searchableBody: 'meeting dossier',
        isMine: true,
      ),
      ChatMessage(
        id: 'msg-theirs-file',
        senderDeviceId: 'device-selene',
        sentAt: now.subtract(const Duration(days: 1)),
        envelope: const CryptoEnvelope(
          version: 'veil-envelope-v1-dev',
          conversationId: 'conv-search',
          senderDeviceId: 'device-selene',
          recipientUserId: 'user-local',
          ciphertext: 'opaque-b',
          nonce: 'nonce-b',
          messageKind: MessageKind.file,
        ),
        searchableBody: 'meeting attachment',
        isMine: false,
      ),
    ]);

    final mineResults = await cache.searchMessageArchive(
      query: const MessageSearchQuery(
        query: 'meeting',
        senderFilter: MessageSearchSenderFilter.mine,
      ),
      currentDeviceId: 'device-local',
    );
    final fileResults = await cache.searchMessageArchive(
      query: const MessageSearchQuery(
        query: 'meeting',
        typeFilter: MessageSearchTypeFilter.file,
        dateFilter: MessageSearchDateFilter.last7Days,
      ),
      currentDeviceId: 'device-local',
    );

    expect(mineResults.items.map((item) => item.messageId).toList(), ['msg-mine']);
    expect(fileResults.items.map((item) => item.messageId).toList(),
        ['msg-theirs-file']);
    expect(fileResults.items.single.isMine, isFalse);
  });

  test('searchMessageArchive returns paged results for larger local archives',
      () async {
    final now = DateTime.now();
    await cache.storeConversations([
      ConversationPreview(
        id: 'conv-paged',
        peerHandle: 'orion',
        peerDisplayName: 'Orion',
        recipientBundle: const KeyBundle(
          userId: 'user-orion',
          deviceId: 'device-orion',
          handle: 'orion',
          identityPublicKey: 'pub-orion',
          signedPrekeyBundle: 'prekey-orion',
        ),
        lastEnvelope: null,
        updatedAt: now,
      ),
    ]);

    await cache.storeMessages(
      'conv-paged',
      List<ChatMessage>.generate(
        3,
        (index) => ChatMessage(
          id: 'msg-page-$index',
          senderDeviceId: 'device-local',
          sentAt: now.subtract(Duration(minutes: index)),
          envelope: CryptoEnvelope(
            version: 'veil-envelope-v1-dev',
            conversationId: 'conv-paged',
            senderDeviceId: 'device-local',
            recipientUserId: 'user-orion',
            ciphertext: 'opaque-$index',
            nonce: 'nonce-$index',
            messageKind: MessageKind.text,
          ),
          searchableBody: 'archive keyword $index',
          isMine: true,
        ),
      ),
    );

    final firstPage = await cache.searchMessageArchive(
      query: const MessageSearchQuery(query: 'archive', limit: 2),
      currentDeviceId: 'device-local',
    );
    final secondPage = await cache.searchMessageArchive(
      query: MessageSearchQuery(
        query: 'archive',
        limit: 2,
        beforeSentAt: firstPage.nextBeforeSentAt,
        beforeMessageId: firstPage.nextBeforeMessageId,
      ),
      currentDeviceId: 'device-local',
    );

    expect(firstPage.items, hasLength(2));
    expect(firstPage.hasMore, isTrue);
    expect(secondPage.items, hasLength(1));
    expect(secondPage.items.single.messageId, 'msg-page-2');
  });
}
