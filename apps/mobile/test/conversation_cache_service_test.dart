import 'dart:convert';
import 'dart:io';

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
      sessionState: ConversationSessionState(
        sessionLocator: 'session://conv-1/mock-locator',
        sessionEnvelopeVersion: 'veil-envelope-v1-dev',
        requiresLocalPersistence: true,
        sessionSchemaVersion: 1,
        localDeviceId: 'device-local',
        remoteDeviceId: 'device-selene',
        remoteIdentityFingerprint: 'fingerprint-selene',
        bootstrappedAt: DateTime.utc(2026, 3, 30, 9, 59, 0),
        auditHint: 'mock-session-bootstrap',
      ),
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
    final restoredConversation = (await cache.readConversations()).single;

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
    expect(
      restoredConversation.sessionState?.sessionSchemaVersion,
      1,
    );
    expect(
      restoredConversation.sessionState?.localDeviceId,
      'device-local',
    );
    expect(
      restoredConversation.sessionState?.remoteDeviceId,
      'device-selene',
    );
    expect(
      restoredConversation.sessionState?.remoteIdentityFingerprint,
      'fingerprint-selene',
    );
  });

  test('a sealed attachment draft survives a restart with its wrapped key', () async {
    const sealed = AttachmentReference(
      attachmentId: '',
      storageKey: '',
      contentType: 'application/pdf',
      sizeBytes: 2064,
      sha256: 'cipher-hash',
      encryptedKey: 'wrapped-content-key',
      nonce: 'content-nonce.wrap-nonce',
      algorithmHint: 'x25519-aes256gcm',
    );
    await cache.upsertPendingMessage(PendingMessageRecord(
      clientMessageId: 'client-file',
      conversationId: 'conv-1',
      senderDeviceId: 'device-local',
      recipientUserId: 'user-selene',
      envelope: const CryptoEnvelope(
        version: 'veil-envelope-v1-dev',
        conversationId: 'conv-1',
        senderDeviceId: 'device-local',
        recipientUserId: 'user-selene',
        ciphertext: 'opaque-file',
        nonce: 'nonce-file',
        messageKind: MessageKind.file,
      ),
      createdAt: DateTime.utc(2026, 4, 1),
      state: MessageDeliveryState.uploading,
      attachmentUploadDraft: AttachmentUploadDraft(
        filename: 'brief.pdf',
        contentType: 'application/pdf',
        sizeBytes: 2064,
        sha256: 'ab' * 32,
        tempFilePath: '/tmp/brief.blob.sealed',
        sealedReference: sealed,
      ),
    ));

    final draft = (await cache.readPendingMessages()).single.attachmentUploadDraft!;

    expect(draft.tempFilePath, '/tmp/brief.blob.sealed');
    expect(draft.sealedReference!.encryptedKey, 'wrapped-content-key');
    expect(draft.sealedReference!.nonce, 'content-nonce.wrap-nonce');
    expect(draft.sealedReference!.sha256, 'cipher-hash');
    expect(draft.sealedReference!.sizeBytes, 2064);
    expect(draft.sealedReference!.algorithmHint, 'x25519-aes256gcm');
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

  test('searches decrypted content of cached messages on this device',
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

    await cache.put(_content('msg-archive-1', 'conv-3', 'orion archive keyword'));
    await cache.put(_content(
      'msg-archive-2',
      'conv-3',
      'archive placeholder',
      status: MessageContentStatus.failed,
    ));

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
        isMine: false,
      ),
    ]);
    await cache.put(_content('msg-mine', 'conv-search', 'meeting dossier'));
    await cache.put(_content(
      'msg-theirs-file',
      'conv-search',
      'meeting attachment',
      kind: MessageKind.file,
    ));

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
      expect(
        fileResults.items.single.bodySnippet.toLowerCase(),
        contains('meeting'),
      );
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
          isMine: true,
        ),
      ),
    );
    for (var index = 0; index < 3; index++) {
      await cache.put(_content('msg-page-$index', 'conv-paged', 'archive keyword $index'));
    }

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

  test('searchMessageArchive is case-insensitive and ranks stronger local matches first',
      () async {
    final now = DateTime.now();
    await cache.storeConversations([
      ConversationPreview(
        id: 'conv-ranked',
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

    await cache.storeMessages(
      'conv-ranked',
      [
        ChatMessage(
          id: 'msg-ranked-1',
          senderDeviceId: 'device-local',
          sentAt: now.subtract(const Duration(minutes: 2)),
          envelope: const CryptoEnvelope(
            version: 'veil-envelope-v1-dev',
            conversationId: 'conv-ranked',
            senderDeviceId: 'device-local',
            recipientUserId: 'user-selene',
            ciphertext: 'opaque-ranked-1',
            nonce: 'nonce-ranked-1',
            messageKind: MessageKind.text,
          ),
          isMine: true,
        ),
        ChatMessage(
          id: 'msg-ranked-2',
          senderDeviceId: 'device-local',
          sentAt: now.subtract(const Duration(minutes: 1)),
          envelope: const CryptoEnvelope(
            version: 'veil-envelope-v1-dev',
            conversationId: 'conv-ranked',
            senderDeviceId: 'device-local',
            recipientUserId: 'user-selene',
            ciphertext: 'opaque-ranked-2',
            nonce: 'nonce-ranked-2',
            messageKind: MessageKind.text,
          ),
          isMine: true,
        ),
        ChatMessage(
          id: 'msg-ranked-3',
          senderDeviceId: 'device-local',
          sentAt: now,
          envelope: const CryptoEnvelope(
            version: 'veil-envelope-v1-dev',
            conversationId: 'conv-ranked',
            senderDeviceId: 'device-local',
            recipientUserId: 'user-selene',
            ciphertext: 'opaque-ranked-3',
            nonce: 'nonce-ranked-3',
            messageKind: MessageKind.text,
          ),
          isMine: true,
        ),
      ],
    );
    await cache.put(_content('msg-ranked-1', 'conv-ranked', 'Orbit'));
    await cache.put(_content('msg-ranked-2', 'conv-ranked', 'A relay window into orbit mechanics'));
    await cache.put(_content('msg-ranked-3', 'conv-ranked', 'Telemetry for the ORBIT relay'));

    final results = await cache.searchMessageArchive(
      query: const MessageSearchQuery(query: 'orbit', limit: 3),
      currentDeviceId: 'device-local',
    );

    expect(
      results.items.map((item) => item.messageId).toList(),
      ['msg-ranked-1', 'msg-ranked-3', 'msg-ranked-2'],
    );
    expect(results.items.first.bodySnippet, 'Orbit');
    expect(results.items[1].bodySnippet.toLowerCase(), contains('orbit'));
  });

  test('searchMessageArchive paging keeps same-timestamp matches reachable', () async {
    final now = DateTime.now();
    await cache.storeConversations([
      ConversationPreview(
        id: 'conv-same-time',
        peerHandle: 'lyra',
        peerDisplayName: 'Lyra',
        recipientBundle: const KeyBundle(
          userId: 'user-lyra',
          deviceId: 'device-lyra',
          handle: 'lyra',
          identityPublicKey: 'pub-lyra',
          signedPrekeyBundle: 'prekey-lyra',
        ),
        lastEnvelope: null,
        updatedAt: now,
      ),
    ]);

    await cache.storeMessages(
      'conv-same-time',
      [
        ChatMessage(
          id: 'msg-same-a',
          senderDeviceId: 'device-local',
          sentAt: now,
          envelope: const CryptoEnvelope(
            version: 'veil-envelope-v1-dev',
            conversationId: 'conv-same-time',
            senderDeviceId: 'device-local',
            recipientUserId: 'user-lyra',
            ciphertext: 'opaque-same-a',
            nonce: 'nonce-same-a',
            messageKind: MessageKind.text,
          ),
          isMine: true,
        ),
        ChatMessage(
          id: 'msg-same-b',
          senderDeviceId: 'device-local',
          sentAt: now,
          envelope: const CryptoEnvelope(
            version: 'veil-envelope-v1-dev',
            conversationId: 'conv-same-time',
            senderDeviceId: 'device-local',
            recipientUserId: 'user-lyra',
            ciphertext: 'opaque-same-b',
            nonce: 'nonce-same-b',
            messageKind: MessageKind.text,
          ),
          isMine: true,
        ),
      ],
    );
    await cache.put(_content('msg-same-a', 'conv-same-time', 'orbit first'));
    await cache.put(_content('msg-same-b', 'conv-same-time', 'orbit second'));

    final firstPage = await cache.searchMessageArchive(
      query: const MessageSearchQuery(query: 'orbit', limit: 1),
      currentDeviceId: 'device-local',
    );
    final secondPage = await cache.searchMessageArchive(
      query: MessageSearchQuery(
        query: 'orbit',
        limit: 1,
        beforeSentAt: firstPage.nextBeforeSentAt,
        beforeMessageId: firstPage.nextBeforeMessageId,
      ),
      currentDeviceId: 'device-local',
    );

    expect(firstPage.items, hasLength(1));
    expect(secondPage.items, hasLength(1));
    expect(
      {firstPage.items.single.messageId, secondPage.items.single.messageId},
      {'msg-same-a', 'msg-same-b'},
    );
  });

  test('message content round trip is field-encrypted at rest', () async {
    cache = DriftConversationCacheService(
      database,
      envelopeCodec: createDefaultCryptoAdapter().envelopeCodec,
      cipher: LocalDataCipher.forTesting(
        base64Url.encode(List<int>.filled(32, 9)).replaceAll('=', ''),
      ),
    );
    const attachment = AttachmentReference(
      attachmentId: 'att-9',
      storageKey: 'attachments/att-9/blob',
      contentType: 'image/png',
      sizeBytes: 64,
      sha256: 'cipher-hash',
      encryptedKey: 'wrapped-key',
      nonce: 'content-nonce.wrap-nonce',
      algorithmHint: 'x25519-aes256gcm',
    );
    final expiry = DateTime.utc(2026, 5, 1, 12, 0, 0, 250);
    await cache.put(_content(
      'srv-9',
      'conv-9',
      'confidential body',
      kind: MessageKind.image,
      attachment: attachment,
      innerExpiresAt: expiry,
    ));

    final row = await database
        .customSelect(
          "SELECT body, attachment_json, kind, status FROM message_contents WHERE message_key = 'srv-9'",
        )
        .getSingle();
    expect(row.data['body'], isNot(contains('confidential')));
    expect(row.data['attachment_json'], isNot(contains('att-9')));
    expect(row.data['kind'], isNot(MessageKind.image.name));
    expect(row.data['status'], 'ok');

    final restored = await cache.get('srv-9');
    expect(restored!.body, 'confidential body');
    expect(restored.kind, MessageKind.image);
    expect(restored.status, MessageContentStatus.ok);
    expect(restored.attachment!.attachmentId, 'att-9');
    expect(restored.attachment!.encryptedKey, 'wrapped-key');
    expect(restored.attachment!.nonce, 'content-nonce.wrap-nonce');
    expect(restored.innerExpiresAt!.isAtSameMomentAs(expiry), isTrue);
    expect((await cache.getMany(['srv-9', 'srv-missing'])).keys, ['srv-9']);
  });

  test('rekey local content to server id', () async {
    await cache.put(_content(
      localMessageContentKey('client-1'),
      'conv-1',
      'my own words',
      clientMessageId: 'client-1',
    ));
    // A failed attempt to open our own echoed envelope must not win.
    await cache.put(_content(
      'srv-1',
      'conv-1',
      '[Decryption failed]',
      status: MessageContentStatus.failed,
    ));

    await cache.rekeyLocalToServer(clientMessageId: 'client-1', serverMessageId: 'srv-1');

    expect(await cache.get(localMessageContentKey('client-1')), isNull);
    final rekeyed = await cache.get('srv-1');
    expect(rekeyed!.body, 'my own words');
    expect(rekeyed.status, MessageContentStatus.ok);
    expect(rekeyed.serverMessageId, 'srv-1');
    expect(rekeyed.clientMessageId, 'client-1');
    expect(
      await cache.searchCachedMessageIds(conversationId: 'conv-1', query: 'own'),
      ['srv-1'],
    );
  });

  test('final content under a relayed id is never replaced by a later put', () async {
    // The one decrypt of srv-2 opened it; a later outcome, e.g. a replayed
    // attempt racing the sender's own rekey, must not overwrite it.
    await cache.put(_content('srv-2', 'conv-1', 'opened once'));
    await cache.put(_content(
      'srv-2',
      'conv-1',
      '[Replayed or out-of-window message]',
      status: MessageContentStatus.replayed,
    ));
    expect((await cache.get('srv-2'))!.body, 'opened once');

    // A row still waiting for key material takes its retry's outcome.
    await cache.put(_content('srv-3', 'conv-1', '[waiting]', status: MessageContentStatus.awaitingKey));
    await cache.put(_content('srv-3', 'conv-1', 'opened on retry'));
    expect((await cache.get('srv-3'))!.body, 'opened on retry');

    // The sender may restage its own outbound content.
    final local = localMessageContentKey('client-2');
    await cache.put(_content(local, 'conv-1', 'staged', clientMessageId: 'client-2'));
    await cache.put(_content(local, 'conv-1', 'staged with attachment', clientMessageId: 'client-2'));
    expect((await cache.get(local))!.body, 'staged with attachment');
  });

  test('values sealed under another cache key are skipped, not thrown', () async {
    LocalDataCipher cipherFor(int byte) =>
        LocalDataCipher.forTesting(base64Url.encode(List<int>.filled(32, byte)).replaceAll('=', ''));
    final codec = createDefaultCryptoAdapter().envelopeCodec;
    final writer = DriftConversationCacheService(database, envelopeCodec: codec, cipher: cipherFor(1));
    await writer.storeConversations([_conversation('conv-old-key')]);
    await writer.put(_content('srv-old-key', 'conv-old-key', 'sealed under the old key'));

    final reader = DriftConversationCacheService(database, envelopeCodec: codec, cipher: cipherFor(2));

    expect(await reader.readConversations(), isEmpty);
    expect(await reader.get('srv-old-key'), isNull);
    expect(await reader.getMany(['srv-old-key']), isEmpty);
  });

  test('expired, retired and wiped content is deleted', () async {
    final now = DateTime.now();
    await cache.put(_content(
      'srv-inner',
      'conv-1',
      'gone at inner time',
      innerExpiresAt: now.subtract(const Duration(seconds: 1)),
    ));
    await cache.put(_content('srv-outer', 'conv-1', 'gone with its message'));
    await cache.put(_content('srv-retired', 'conv-1', 'expired by the caller'));
    await cache.put(_content('srv-kept', 'conv-1', 'still here'));
    await cache.storeConversations([_conversation('conv-1')]);
    await cache.storeMessages('conv-1', [
      ChatMessage(
        id: 'srv-outer',
        senderDeviceId: 'device-peer',
        sentAt: now.subtract(const Duration(minutes: 1)),
        expiresAt: now.subtract(const Duration(seconds: 1)),
        envelope: const CryptoEnvelope(
          version: 'veil-envelope-v1-dev',
          conversationId: 'conv-1',
          senderDeviceId: 'device-peer',
          recipientUserId: 'user-local',
          ciphertext: 'opaque-outer',
          nonce: 'nonce-outer',
          messageKind: MessageKind.text,
        ),
      ),
    ]);

    await cache.purgeExpiredMessages();
    await cache.deleteExpired(now, messageKeys: ['srv-retired']);

    const keys = ['srv-inner', 'srv-outer', 'srv-retired', 'srv-kept'];
    expect((await cache.getMany(keys)).keys, ['srv-kept']);
    expect(await cache.retiredAmong(keys), {'srv-inner', 'srv-outer', 'srv-retired'});
    await cache.clearAll();
    expect(await cache.get('srv-kept'), isNull);
    expect(await cache.retiredAmong(keys), isEmpty);
  });

  test('a retired key never takes content again and is forgotten after the retention window', () async {
    final now = DateTime.now();
    await cache.deleteExpired(now, messageKeys: ['srv-late']);

    // A decrypt that was still running when its message expired.
    await cache.put(_content('srv-late', 'conv-1', 'must not come back'));
    expect(await cache.get('srv-late'), isNull);

    await database.customStatement(
      'UPDATE retired_messages SET retired_at = ?',
      [now.subtract(retiredMessageRetention + const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000],
    );
    await cache.purgeExpiredMessages();
    expect(await cache.retiredAmong(['srv-late']), isEmpty);
  });

  test('inner expiries are read without decrypting content', () async {
    final expiry = DateTime.utc(2026, 5, 1, 12, 0, 0, 250);
    await cache.put(_content('srv-timed', 'conv-1', 'timed', innerExpiresAt: expiry));
    await cache.put(_content('srv-forever', 'conv-1', 'untimed'));

    final expiries = await cache.innerExpiries(['srv-timed', 'srv-forever', 'srv-missing']);

    expect(expiries.keys, ['srv-timed']);
    expect(expiries['srv-timed']!.isAtSameMomentAs(expiry), isTrue);
  });

  test('migration 8 to 9 creates table', () async {
    final legacy = AppDatabase(NativeDatabase.memory(setup: (raw) {
      for (final statement in _schemaVersion8) {
        raw.execute(statement);
      }
      raw.execute(
        "INSERT INTO cached_conversations (id, peer_handle, updated_at) VALUES ('conv-old', 'h', 1)",
      );
      raw.execute(
        'INSERT INTO cached_messages (id, conversation_id, sender_device_id, ciphertext, '
        "nonce, message_type, search_body, received_at) VALUES ('msg-old', 'conv-old', 'd', "
        "'c', 'n', 'text', 'legacy plaintext copy', 1)",
      );
      raw.execute('PRAGMA user_version = 8');
    }));
    addTearDown(legacy.close);

    final tables = await legacy
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    expect(tables.map((row) => row.data['name']), containsAll(['message_contents', 'retired_messages']));
    final triggers = await legacy
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'trigger'")
        .get();
    expect(triggers.map((row) => row.data['name']), contains('message_contents_skip_retired'));
    final conversationColumns =
        await legacy.customSelect('PRAGMA table_info(cached_conversations)').get();
    expect(
      conversationColumns.map((row) => row.data['name']),
      containsAll(['session_remote_identity_public_key', 'identity_mismatch_pending']),
    );
    final migratedMessage = await legacy
        .customSelect("SELECT search_body FROM cached_messages WHERE id = 'msg-old'")
        .getSingle();
    expect(migratedMessage.data['search_body'], isNull);

    final migratedCache = DriftConversationCacheService(
      legacy,
      envelopeCodec: createDefaultCryptoAdapter().envelopeCodec,
    );
    expect((await migratedCache.readConversations()).single.identityMismatchPending, isFalse);
    await migratedCache.put(_content('srv-new', 'conv-old', 'first row after upgrade'));
    expect((await migratedCache.get('srv-new'))!.body, 'first row after upgrade');
  });

  test('deleteConversation runs wal checkpoint', () async {
    final directory = Directory.systemTemp.createTempSync('veil-wal-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final databaseFile = File('${directory.path}/cache.sqlite');
    final walDatabase = AppDatabase(NativeDatabase(
      databaseFile,
      setup: (raw) => raw.execute('PRAGMA journal_mode = WAL;'),
    ));
    addTearDown(walDatabase.close);
    final walCache = DriftConversationCacheService(
      walDatabase,
      envelopeCodec: createDefaultCryptoAdapter().envelopeCodec,
    );
    await walCache.put(_content('srv-wal', 'conv-wal', 'shred me'));
    await walCache.put(_content('srv-other', 'conv-other', 'keep me'));
    final wal = File('${databaseFile.path}-wal');
    expect(wal.lengthSync(), greaterThan(0));

    await walCache.deleteConversation('conv-wal');

    expect(await walCache.get('srv-wal'), isNull);
    expect((await walCache.get('srv-other'))!.body, 'keep me');
    // TRUNCATE leaves no copy of the deleted pages in the write-ahead log.
    expect(wal.lengthSync(), 0);
  });

  test('normalizeArchiveSearchBody compacts whitespace and caps indexed size', () {
    final normalized = normalizeArchiveSearchBody(
      'orbit   relay\n\n${List.filled(1300, 'x').join()}',
    );

    expect(normalized.startsWith('orbit relay'), isTrue);
    expect(normalized.contains('\n'), isFalse);
    expect(normalized.length, lessThanOrEqualTo(maxArchiveSearchBodyLength));
  });
}

MessageContentRecord _content(
  String messageKey,
  String conversationId,
  String body, {
  MessageKind kind = MessageKind.text,
  MessageContentStatus status = MessageContentStatus.ok,
  String? clientMessageId,
  AttachmentReference? attachment,
  DateTime? innerExpiresAt,
}) {
  return MessageContentRecord(
    messageKey: messageKey,
    conversationId: conversationId,
    clientMessageId: clientMessageId,
    serverMessageId: messageKey.startsWith('local:') ? null : messageKey,
    body: body,
    kind: kind,
    attachment: attachment,
    innerExpiresAt: innerExpiresAt,
    status: status,
    createdAt: DateTime.utc(2026, 4, 1),
    updatedAt: DateTime.utc(2026, 4, 1),
  );
}

ConversationPreview _conversation(String id) => ConversationPreview(
      id: id,
      peerHandle: 'peer',
      peerDisplayName: 'Peer',
      recipientBundle: const KeyBundle(
        userId: 'user-peer',
        deviceId: 'device-peer',
        handle: 'peer',
        identityPublicKey: 'pub-peer',
        signedPrekeyBundle: 'prekey-peer',
      ),
      lastEnvelope: null,
      updatedAt: DateTime.utc(2026, 4, 1),
    );

// Tables exactly as schema version 8 created them.
const _schemaVersion8 = [
  'CREATE TABLE "cached_conversations" ("id" TEXT NOT NULL, "peer_user_id" TEXT NULL, '
      '"peer_handle" TEXT NOT NULL, "peer_display_name" TEXT NULL, "peer_device_id" TEXT NULL, '
      '"peer_identity_public_key" TEXT NULL, "peer_signed_prekey_bundle" TEXT NULL, '
      '"updated_at" INTEGER NOT NULL, "preview_sender_device_id" TEXT NULL, '
      '"preview_ciphertext" TEXT NULL, "preview_nonce" TEXT NULL, "preview_message_type" TEXT NULL, '
      '"preview_attachment_json" TEXT NULL, "preview_envelope_version" TEXT NULL, '
      '"preview_expires_at" INTEGER NULL, "session_locator" TEXT NULL, '
      '"session_envelope_version" TEXT NULL, "session_requires_local_persistence" TEXT NULL, '
      '"session_schema_version" INTEGER NULL, "session_local_device_id" TEXT NULL, '
      '"session_remote_device_id" TEXT NULL, "session_remote_identity_fingerprint" TEXT NULL, '
      '"session_audit_hint" TEXT NULL, "session_bootstrapped_at" TEXT NULL, '
      '"pagination_cursor" TEXT NULL, "has_more_history" INTEGER NOT NULL DEFAULT 1 '
      'CHECK ("has_more_history" IN (0, 1)), "last_synced_at" INTEGER NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "cached_messages" ("id" TEXT NOT NULL, "conversation_id" TEXT NOT NULL '
      'REFERENCES cached_conversations (id), "client_message_id" TEXT NULL, '
      '"sender_device_id" TEXT NOT NULL, "ciphertext" TEXT NOT NULL, "nonce" TEXT NOT NULL, '
      '"message_type" TEXT NOT NULL, "attachment_json" TEXT NULL, "envelope_version" TEXT NULL, '
      '"search_body" TEXT NULL, "conversation_order" INTEGER NULL, "received_at" INTEGER NOT NULL, '
      '"expires_at" INTEGER NULL, "delivery_state" TEXT NOT NULL DEFAULT \'sent\', '
      '"delivered_at" INTEGER NULL, "read_at" INTEGER NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "pending_messages" ("client_message_id" TEXT NOT NULL, '
      '"conversation_id" TEXT NOT NULL, "sender_device_id" TEXT NOT NULL, '
      '"recipient_user_id" TEXT NOT NULL, "ciphertext" TEXT NOT NULL, "nonce" TEXT NOT NULL, '
      '"message_type" TEXT NOT NULL, "attachment_json" TEXT NULL, "envelope_version" TEXT NULL, '
      '"created_at" INTEGER NOT NULL, "expires_at" INTEGER NULL, '
      '"retry_count" INTEGER NOT NULL DEFAULT 0, "last_attempt_at" INTEGER NULL, '
      '"next_retry_at" INTEGER NULL, "state" TEXT NOT NULL DEFAULT \'pending\', '
      '"error_message" TEXT NULL, PRIMARY KEY ("client_message_id"))',
];
