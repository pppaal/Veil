import 'dart:convert';

import 'package:drift/drift.dart';

import '../../features/conversations/data/conversation_models.dart';
import '../crypto/crypto_engine.dart';
import '../security/local_data_cipher.dart';
import 'app_database.dart';

class ConversationPagingState {
  const ConversationPagingState({
    this.nextCursor,
    this.hasMoreHistory = true,
    this.lastSyncedAt,
  });

  final String? nextCursor;
  final bool hasMoreHistory;
  final DateTime? lastSyncedAt;
}

class PendingMessageRecord {
  const PendingMessageRecord({
    required this.clientMessageId,
    required this.conversationId,
    required this.senderDeviceId,
    required this.recipientUserId,
    required this.envelope,
    required this.createdAt,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.state = MessageDeliveryState.pending,
    this.errorMessage,
  });

  final String clientMessageId;
  final String conversationId;
  final String senderDeviceId;
  final String recipientUserId;
  final CryptoEnvelope envelope;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? lastAttemptAt;
  final MessageDeliveryState state;
  final String? errorMessage;

  PendingMessageRecord copyWith({
    int? retryCount,
    Object? lastAttemptAt = _unset,
    MessageDeliveryState? state,
    Object? errorMessage = _unset,
  }) {
    return PendingMessageRecord(
      clientMessageId: clientMessageId,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientUserId: recipientUserId,
      envelope: envelope,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt:
          identical(lastAttemptAt, _unset) ? this.lastAttemptAt : lastAttemptAt as DateTime?,
      state: state ?? this.state,
      errorMessage:
          identical(errorMessage, _unset) ? this.errorMessage : errorMessage as String?,
    );
  }

  static const _unset = Object();
}

abstract class ConversationCacheService {
  Future<List<ConversationPreview>> readConversations();

  Future<List<ChatMessage>> readMessages(String conversationId);

  Future<void> storeConversations(List<ConversationPreview> conversations);

  Future<void> storeMessages(String conversationId, List<ChatMessage> messages);

  Future<ConversationPagingState> readPagingState(String conversationId);

  Future<void> storePagingState(
    String conversationId, {
    String? nextCursor,
    required bool hasMoreHistory,
    DateTime? lastSyncedAt,
  });

  Future<List<PendingMessageRecord>> readPendingMessages();

  Future<void> upsertPendingMessage(PendingMessageRecord pending);

  Future<void> removePendingMessage(String clientMessageId);

  Future<void> purgeExpiredMessages();
}

class DriftConversationCacheService implements ConversationCacheService {
  DriftConversationCacheService(
    this._db, {
    LocalDataCipher? cipher,
  }) : _cipher = cipher;

  final AppDatabase _db;
  final LocalDataCipher? _cipher;

  @override
  Future<List<ConversationPreview>> readConversations() async {
    final query = _db.select(_db.cachedConversations)
      ..orderBy([
        (table) => OrderingTerm(
              expression: table.updatedAt,
              mode: OrderingMode.desc,
            ),
      ]);
    final rows = await query.get();
    final conversations = <ConversationPreview>[];

    for (final row in rows) {
      final peerUserId = await _decrypt(row.peerUserId);
      final peerDeviceId = await _decrypt(row.peerDeviceId);
      final peerIdentityPublicKey = await _decrypt(row.peerIdentityPublicKey);
      final peerSignedPrekeyBundle = await _decrypt(row.peerSignedPrekeyBundle);
      final previewSenderDeviceId = await _decrypt(row.previewSenderDeviceId);
      final previewCiphertext = await _decrypt(row.previewCiphertext);
      final previewNonce = await _decrypt(row.previewNonce);
      final previewAttachmentJson = await _decrypt(row.previewAttachmentJson);

      conversations.add(
        ConversationPreview(
          id: row.id,
          peerHandle: row.peerHandle,
          peerDisplayName: row.peerDisplayName,
          recipientBundle: KeyBundle(
            userId: peerUserId ?? 'cached-user-${row.peerHandle}',
            deviceId: peerDeviceId ?? '',
            handle: row.peerHandle,
            identityPublicKey: peerIdentityPublicKey ?? '',
            signedPrekeyBundle: peerSignedPrekeyBundle ?? '',
          ),
          lastEnvelope: row.previewMessageType == null ||
                  previewSenderDeviceId == null ||
                  previewCiphertext == null ||
                  previewNonce == null
              ? null
              : CryptoEnvelope(
                  version: devEnvelopeVersion,
                  conversationId: row.id,
                  senderDeviceId: previewSenderDeviceId,
                  recipientUserId: peerUserId ?? '',
                  ciphertext: previewCiphertext,
                  nonce: previewNonce,
                  messageKind: MessageKind.values.byName(row.previewMessageType!),
                  expiresAt: row.previewExpiresAt,
                  attachment: _decodeAttachment(previewAttachmentJson),
                ),
          updatedAt: row.updatedAt,
        ),
      );
    }

    return conversations;
  }

  @override
  Future<List<ChatMessage>> readMessages(String conversationId) async {
    final query = _db.select(_db.cachedMessages)
      ..where((table) => table.conversationId.equals(conversationId))
      ..orderBy([
        (table) => OrderingTerm(
              expression: table.receivedAt,
              mode: OrderingMode.asc,
            ),
      ]);
    final rows = await query.get();
    final messages = <ChatMessage>[];

    for (final row in rows) {
      final senderDeviceId = await _decrypt(row.senderDeviceId);
      final ciphertext = await _decrypt(row.ciphertext);
      final nonce = await _decrypt(row.nonce);
      final attachmentJson = await _decrypt(row.attachmentJson);

      if (senderDeviceId == null || ciphertext == null || nonce == null) {
        continue;
      }

      messages.add(
        ChatMessage(
          id: row.id,
          clientMessageId: row.clientMessageId,
          senderDeviceId: senderDeviceId,
          sentAt: row.receivedAt,
          envelope: CryptoEnvelope(
            version: devEnvelopeVersion,
            conversationId: row.conversationId,
            senderDeviceId: senderDeviceId,
            recipientUserId: '',
            ciphertext: ciphertext,
            nonce: nonce,
            messageKind: MessageKind.values.byName(row.messageType),
            expiresAt: row.expiresAt,
            attachment: _decodeAttachment(attachmentJson),
          ),
          conversationOrder: row.conversationOrder,
          deliveryState: _decodeDeliveryState(
            state: row.deliveryState,
            deliveredAt: row.deliveredAt,
            readAt: row.readAt,
          ),
          deliveredAt: row.deliveredAt,
          readAt: row.readAt,
          expiresAt: row.expiresAt,
          isMine: false,
        ),
      );
    }

    return messages;
  }

  @override
  Future<void> storeConversations(List<ConversationPreview> conversations) async {
    final existingRows = await _db.select(_db.cachedConversations).get();
    final existingById = {for (final row in existingRows) row.id: row};
    final rows = <CachedConversationsCompanion>[];

    for (final conversation in conversations) {
      final preview = conversation.lastEnvelope;
      final existing = existingById[conversation.id];
      rows.add(
        CachedConversationsCompanion.insert(
          id: conversation.id,
          peerHandle: conversation.peerHandle,
          updatedAt: conversation.updatedAt,
          peerUserId: Value(await _encrypt(conversation.recipientBundle.userId)),
          peerDisplayName: Value(conversation.peerDisplayName),
          peerDeviceId: Value(await _encrypt(conversation.recipientBundle.deviceId)),
          peerIdentityPublicKey:
              Value(await _encrypt(conversation.recipientBundle.identityPublicKey)),
          peerSignedPrekeyBundle:
              Value(await _encrypt(conversation.recipientBundle.signedPrekeyBundle)),
          previewSenderDeviceId: Value(await _encrypt(preview?.senderDeviceId)),
          previewCiphertext: Value(await _encrypt(preview?.ciphertext)),
          previewNonce: Value(await _encrypt(preview?.nonce)),
          previewMessageType: Value(preview?.messageKind.name),
          previewAttachmentJson: Value(await _encrypt(_encodeAttachment(preview?.attachment))),
          previewExpiresAt: Value(preview?.expiresAt),
          paginationCursor: Value(existing?.paginationCursor),
          hasMoreHistory: Value(existing?.hasMoreHistory ?? true),
          lastSyncedAt: Value(existing?.lastSyncedAt),
        ),
      );
    }

    await _db.batch((batch) {
      for (final row in rows) {
        batch.insert(
          _db.cachedConversations,
          row,
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  @override
  Future<void> storeMessages(String conversationId, List<ChatMessage> messages) async {
    final rows = <CachedMessagesCompanion>[];

    for (final message in messages) {
      rows.add(
        CachedMessagesCompanion.insert(
          id: message.id,
          conversationId: message.envelope.conversationId,
          clientMessageId: Value(message.clientMessageId),
          senderDeviceId: await _requireEncryptedValue(message.senderDeviceId),
          ciphertext: await _requireEncryptedValue(message.envelope.ciphertext),
          nonce: await _requireEncryptedValue(message.envelope.nonce),
          messageType: message.envelope.messageKind.name,
          attachmentJson: Value(await _encrypt(_encodeAttachment(message.envelope.attachment))),
          conversationOrder: Value(message.conversationOrder),
          receivedAt: message.sentAt,
          expiresAt: Value(message.expiresAt),
          deliveryState: Value(message.deliveryState.name),
          deliveredAt: Value(message.deliveredAt),
          readAt: Value(message.readAt),
        ),
      );
    }

    await _db.transaction(() async {
      await (_db.delete(_db.cachedMessages)
            ..where((table) => table.conversationId.equals(conversationId)))
          .go();

      await _db.batch((batch) {
        for (final row in rows) {
          batch.insert(
            _db.cachedMessages,
            row,
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    });
  }

  @override
  Future<ConversationPagingState> readPagingState(String conversationId) async {
    final row = await (_db.select(_db.cachedConversations)
          ..where((table) => table.id.equals(conversationId)))
        .getSingleOrNull();
    if (row == null) {
      return const ConversationPagingState();
    }

    return ConversationPagingState(
      nextCursor: row.paginationCursor,
      hasMoreHistory: row.hasMoreHistory,
      lastSyncedAt: row.lastSyncedAt,
    );
  }

  @override
  Future<void> storePagingState(
    String conversationId, {
    String? nextCursor,
    required bool hasMoreHistory,
    DateTime? lastSyncedAt,
  }) async {
    await (_db.update(_db.cachedConversations)
          ..where((table) => table.id.equals(conversationId)))
        .write(
      CachedConversationsCompanion(
        paginationCursor: Value(nextCursor),
        hasMoreHistory: Value(hasMoreHistory),
        lastSyncedAt: Value(lastSyncedAt),
      ),
    );
  }

  @override
  Future<List<PendingMessageRecord>> readPendingMessages() async {
    final query = _db.select(_db.pendingMessages)
      ..orderBy([
        (table) => OrderingTerm(
              expression: table.createdAt,
              mode: OrderingMode.asc,
            ),
      ]);
    final rows = await query.get();
    final pendingMessages = <PendingMessageRecord>[];

    for (final row in rows) {
      final senderDeviceId = await _decrypt(row.senderDeviceId);
      final recipientUserId = await _decrypt(row.recipientUserId);
      final ciphertext = await _decrypt(row.ciphertext);
      final nonce = await _decrypt(row.nonce);
      final attachmentJson = await _decrypt(row.attachmentJson);
      final errorMessage = await _decrypt(row.errorMessage);

      if (senderDeviceId == null || recipientUserId == null || ciphertext == null || nonce == null) {
        continue;
      }

      pendingMessages.add(
        PendingMessageRecord(
          clientMessageId: row.clientMessageId,
          conversationId: row.conversationId,
          senderDeviceId: senderDeviceId,
          recipientUserId: recipientUserId,
          envelope: CryptoEnvelope(
            version: devEnvelopeVersion,
            conversationId: row.conversationId,
            senderDeviceId: senderDeviceId,
            recipientUserId: recipientUserId,
            ciphertext: ciphertext,
            nonce: nonce,
            messageKind: MessageKind.values.byName(row.messageType),
            expiresAt: row.expiresAt,
            attachment: _decodeAttachment(attachmentJson),
          ),
          createdAt: row.createdAt,
          retryCount: row.retryCount,
          lastAttemptAt: row.lastAttemptAt,
          state: _deliveryStateFromString(row.state),
          errorMessage: errorMessage,
        ),
      );
    }

    return pendingMessages;
  }

  @override
  Future<void> upsertPendingMessage(PendingMessageRecord pending) async {
    await _db.into(_db.pendingMessages).insert(
          PendingMessagesCompanion.insert(
            clientMessageId: pending.clientMessageId,
            conversationId: pending.conversationId,
            senderDeviceId: await _requireEncryptedValue(pending.senderDeviceId),
            recipientUserId: await _requireEncryptedValue(pending.recipientUserId),
            ciphertext: await _requireEncryptedValue(pending.envelope.ciphertext),
            nonce: await _requireEncryptedValue(pending.envelope.nonce),
            messageType: pending.envelope.messageKind.name,
            attachmentJson: Value(await _encrypt(_encodeAttachment(pending.envelope.attachment))),
            createdAt: pending.createdAt,
            expiresAt: Value(pending.envelope.expiresAt),
            retryCount: Value(pending.retryCount),
            lastAttemptAt: Value(pending.lastAttemptAt),
            state: Value(pending.state.name),
            errorMessage: Value(await _encrypt(pending.errorMessage)),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  @override
  Future<void> removePendingMessage(String clientMessageId) {
    return (_db.delete(_db.pendingMessages)
          ..where((table) => table.clientMessageId.equals(clientMessageId)))
        .go();
  }

  @override
  Future<void> purgeExpiredMessages() async {
    final now = DateTime.now();
    await (_db.delete(_db.cachedMessages)
          ..where((table) => table.expiresAt.isSmallerThanValue(now)))
        .go();
    await (_db.delete(_db.pendingMessages)
          ..where((table) => table.expiresAt.isSmallerThanValue(now)))
        .go();
  }

  String? _encodeAttachment(AttachmentReference? attachment) {
    if (attachment == null) {
      return null;
    }

    return jsonEncode(attachment.toApiJson());
  }

  AttachmentReference? _decodeAttachment(String? raw) {
    if (raw == null) {
      return null;
    }

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded.containsKey('encryption')) {
      return AttachmentReference.fromApiJson(decoded);
    }

    return AttachmentReference(
      attachmentId: decoded['attachmentId'] as String,
      storageKey: decoded['storageKey'] as String,
      contentType: decoded['contentType'] as String,
      sizeBytes: decoded['sizeBytes'] as int,
      sha256: decoded['sha256'] as String,
      encryptedKey: decoded['encryptedKey'] as String,
      nonce: decoded['nonce'] as String,
    );
  }

  MessageDeliveryState _decodeDeliveryState({
    required String state,
    required DateTime? deliveredAt,
    required DateTime? readAt,
  }) {
    if (readAt != null) {
      return MessageDeliveryState.read;
    }
    if (deliveredAt != null) {
      return MessageDeliveryState.delivered;
    }
    return _deliveryStateFromString(state);
  }

  MessageDeliveryState _deliveryStateFromString(String state) {
    return MessageDeliveryState.values.firstWhere(
      (value) => value.name == state,
      orElse: () => MessageDeliveryState.pending,
    );
  }

  Future<String?> _encrypt(String? value) async {
    final cipher = _cipher;
    if (cipher == null || value == null) {
      return value;
    }
    return cipher.encryptString(value);
  }

  Future<String?> _decrypt(String? value) async {
    final cipher = _cipher;
    if (cipher == null || value == null) {
      return value;
    }
    return cipher.decryptString(value);
  }

  Future<String> _requireEncryptedValue(String value) async {
    final encrypted = await _encrypt(value);
    return encrypted ?? value;
  }
}
