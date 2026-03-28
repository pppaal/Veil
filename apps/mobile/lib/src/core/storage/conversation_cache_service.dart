import 'dart:convert';

import 'package:drift/drift.dart';

import '../../features/conversations/data/mock_messenger_repository.dart';
import '../crypto/crypto_engine.dart';
import 'app_database.dart';

abstract class ConversationCacheService {
  Future<List<ConversationPreview>> readConversations();

  Future<List<ChatMessage>> readMessages(String conversationId);

  Future<void> storeConversations(List<ConversationPreview> conversations);

  Future<void> storeMessages(String conversationId, List<ChatMessage> messages);

  Future<void> purgeExpiredMessages();
}

class DriftConversationCacheService implements ConversationCacheService {
  DriftConversationCacheService(this._db);

  final AppDatabase _db;

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

    return rows
        .map(
          (row) => ConversationPreview(
            id: row.id,
            peerHandle: row.peerHandle,
            peerDisplayName: row.peerDisplayName,
            recipientBundle: KeyBundle(
              userId: row.peerUserId ?? 'cached-user-${row.peerHandle}',
              deviceId: row.peerDeviceId ?? '',
              handle: row.peerHandle,
              identityPublicKey: row.peerIdentityPublicKey ?? '',
              signedPrekeyBundle: row.peerSignedPrekeyBundle ?? '',
            ),
            lastEnvelope: row.previewCiphertext == null ||
                    row.previewNonce == null ||
                    row.previewMessageType == null ||
                    row.previewSenderDeviceId == null
                ? null
                : CryptoEnvelope(
                    version: 'veil-envelope-v1-dev',
                    conversationId: row.id,
                    senderDeviceId: row.previewSenderDeviceId!,
                    recipientUserId: row.peerUserId ?? '',
                    ciphertext: row.previewCiphertext!,
                    nonce: row.previewNonce!,
                    messageKind: MessageKind.values.byName(row.previewMessageType!),
                    expiresAt: row.previewExpiresAt,
                    attachment: _decodeAttachment(row.previewAttachmentJson),
                  ),
            updatedAt: row.updatedAt,
          ),
        )
        .toList();
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

    return rows
        .map(
          (row) => ChatMessage(
            id: row.id,
            senderDeviceId: row.senderDeviceId,
            sentAt: row.receivedAt,
            envelope: CryptoEnvelope(
              version: 'veil-envelope-v1-dev',
              conversationId: row.conversationId,
              senderDeviceId: row.senderDeviceId,
              recipientUserId: '',
              ciphertext: row.ciphertext,
              nonce: row.nonce,
              messageKind: MessageKind.values.byName(row.messageType),
              expiresAt: row.expiresAt,
              attachment: _decodeAttachment(row.attachmentJson),
            ),
            expiresAt: row.expiresAt,
            isMine: false,
          ),
        )
        .toList();
  }

  @override
  Future<void> storeConversations(List<ConversationPreview> conversations) async {
    await _db.batch((batch) {
      for (final conversation in conversations) {
        final preview = conversation.lastEnvelope;
        batch.insert(
          _db.cachedConversations,
          CachedConversationsCompanion.insert(
            id: conversation.id,
            peerHandle: conversation.peerHandle,
            updatedAt: conversation.updatedAt,
            peerUserId: Value(conversation.recipientBundle.userId),
            peerDisplayName: Value(conversation.peerDisplayName),
            peerDeviceId: Value(conversation.recipientBundle.deviceId),
            peerIdentityPublicKey: Value(conversation.recipientBundle.identityPublicKey),
            peerSignedPrekeyBundle: Value(conversation.recipientBundle.signedPrekeyBundle),
            previewSenderDeviceId: Value(preview?.senderDeviceId),
            previewCiphertext: Value(preview?.ciphertext),
            previewNonce: Value(preview?.nonce),
            previewMessageType: Value(preview?.messageKind.name),
            previewAttachmentJson: Value(_encodeAttachment(preview?.attachment)),
            previewExpiresAt: Value(preview?.expiresAt),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  @override
  Future<void> storeMessages(String conversationId, List<ChatMessage> messages) async {
    await (_db.delete(_db.cachedMessages)
          ..where((table) => table.conversationId.equals(conversationId)))
        .go();

    await _db.batch((batch) {
      for (final message in messages) {
        batch.insert(
          _db.cachedMessages,
          CachedMessagesCompanion.insert(
            id: message.id,
            conversationId: message.envelope.conversationId,
            senderDeviceId: message.senderDeviceId,
            ciphertext: message.envelope.ciphertext,
            nonce: message.envelope.nonce,
            messageType: message.envelope.messageKind.name,
            attachmentJson: Value(_encodeAttachment(message.envelope.attachment)),
            receivedAt: message.sentAt,
            expiresAt: Value(message.expiresAt),
            isRead: const Value(false),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  @override
  Future<void> purgeExpiredMessages() async {
    final now = DateTime.now();
    await (_db.delete(_db.cachedMessages)
          ..where((table) => table.expiresAt.isSmallerThanValue(now)))
        .go();
  }

  String? _encodeAttachment(AttachmentReference? attachment) {
    if (attachment == null) {
      return null;
    }

    return jsonEncode({
      'attachmentId': attachment.attachmentId,
      'storageKey': attachment.storageKey,
      'contentType': attachment.contentType,
      'sizeBytes': attachment.sizeBytes,
      'sha256': attachment.sha256,
      'encryptedKey': attachment.encryptedKey,
      'nonce': attachment.nonce,
    });
  }

  AttachmentReference? _decodeAttachment(String? raw) {
    if (raw == null) {
      return null;
    }

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
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
}
