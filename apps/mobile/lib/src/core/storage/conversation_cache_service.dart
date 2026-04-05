import 'dart:convert';

import 'package:drift/drift.dart';

import '../../features/conversations/data/conversation_models.dart';
import '../crypto/crypto_engine.dart';
import '../security/local_data_cipher.dart';
import 'app_database.dart';

String buildArchiveQuerySnippet(String searchBody, String normalizedQuery) {
  final compactBody = searchBody.replaceAll(RegExp(r'\s+'), ' ').trim();
  final matchIndex = compactBody.indexOf(normalizedQuery);
  if (matchIndex < 0) {
    return compactBody.length <= 96
        ? compactBody
        : '${compactBody.substring(0, 96).trim()}...';
  }
  final start = (matchIndex - 24).clamp(0, compactBody.length);
  final end =
      (matchIndex + normalizedQuery.length + 56).clamp(0, compactBody.length);
  final prefix = start > 0 ? '... ' : '';
  final suffix = end < compactBody.length ? ' ...' : '';
  return '$prefix${compactBody.substring(start, end).trim()}$suffix';
}

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

class _ArchivedConversationMeta {
  const _ArchivedConversationMeta({
    required this.peerHandle,
    required this.peerDisplayName,
  });

  final String peerHandle;
  final String? peerDisplayName;
}

class AttachmentUploadDraft {
  static const Object _unset = Object();

  const AttachmentUploadDraft({
    required this.filename,
    required this.contentType,
    required this.sizeBytes,
    required this.sha256,
    this.tempFilePath,
    this.attachmentId,
    this.storageKey,
    this.uploadUrl,
    this.uploadHeaders = const <String, String>{},
    this.uploadExpiresAt,
    this.bytesUploaded = 0,
    this.lastUpdatedAt,
  });

  final String filename;
  final String contentType;
  final int sizeBytes;
  final String sha256;
  final String? tempFilePath;
  final String? attachmentId;
  final String? storageKey;
  final String? uploadUrl;
  final Map<String, String> uploadHeaders;
  final DateTime? uploadExpiresAt;
  final int bytesUploaded;
  final DateTime? lastUpdatedAt;

  bool get hasUploadTicket =>
      attachmentId != null &&
      storageKey != null &&
      uploadUrl != null &&
      uploadExpiresAt != null;

  bool get uploadTicketExpired =>
      uploadExpiresAt != null && !uploadExpiresAt!.isAfter(DateTime.now());

  AttachmentUploadDraft copyWith({
    String? filename,
    String? contentType,
    int? sizeBytes,
    String? sha256,
    Object? tempFilePath = _unset,
    Object? attachmentId = _unset,
    Object? storageKey = _unset,
    Object? uploadUrl = _unset,
    Map<String, String>? uploadHeaders,
    Object? uploadExpiresAt = _unset,
    int? bytesUploaded,
    Object? lastUpdatedAt = _unset,
  }) {
    return AttachmentUploadDraft(
      filename: filename ?? this.filename,
      contentType: contentType ?? this.contentType,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      sha256: sha256 ?? this.sha256,
      tempFilePath: identical(tempFilePath, _unset)
          ? this.tempFilePath
          : tempFilePath as String?,
      attachmentId: identical(attachmentId, _unset)
          ? this.attachmentId
          : attachmentId as String?,
      storageKey: identical(storageKey, _unset)
          ? this.storageKey
          : storageKey as String?,
      uploadUrl:
          identical(uploadUrl, _unset) ? this.uploadUrl : uploadUrl as String?,
      uploadHeaders: uploadHeaders ?? this.uploadHeaders,
      uploadExpiresAt: identical(uploadExpiresAt, _unset)
          ? this.uploadExpiresAt
          : uploadExpiresAt as DateTime?,
      bytesUploaded: bytesUploaded ?? this.bytesUploaded,
      lastUpdatedAt: identical(lastUpdatedAt, _unset)
          ? this.lastUpdatedAt
          : lastUpdatedAt as DateTime?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'sha256': sha256,
      'tempFilePath': tempFilePath,
      'attachmentId': attachmentId,
      'storageKey': storageKey,
      'uploadUrl': uploadUrl,
      'uploadHeaders': uploadHeaders,
      'uploadExpiresAt': uploadExpiresAt?.toIso8601String(),
      'bytesUploaded': bytesUploaded,
      'lastUpdatedAt': lastUpdatedAt?.toIso8601String(),
    };
  }

  factory AttachmentUploadDraft.fromJson(Map<String, dynamic> json) {
    return AttachmentUploadDraft(
      filename: json['filename'] as String,
      contentType: json['contentType'] as String,
      sizeBytes: json['sizeBytes'] as int,
      sha256: json['sha256'] as String,
      tempFilePath: json['tempFilePath'] as String?,
      attachmentId: json['attachmentId'] as String?,
      storageKey: json['storageKey'] as String?,
      uploadUrl: json['uploadUrl'] as String?,
      uploadHeaders: (json['uploadHeaders'] as Map<String, dynamic>? ??
              const <String, dynamic>{})
          .map((key, value) => MapEntry(key, value.toString())),
      uploadExpiresAt: json['uploadExpiresAt'] == null
          ? null
          : DateTime.parse(json['uploadExpiresAt'] as String),
      bytesUploaded: json['bytesUploaded'] as int? ?? 0,
      lastUpdatedAt: json['lastUpdatedAt'] == null
          ? null
          : DateTime.parse(json['lastUpdatedAt'] as String),
    );
  }

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
    this.nextRetryAt,
    this.state = MessageDeliveryState.pending,
    this.errorMessage,
    this.attachmentUploadDraft,
  });

  final String clientMessageId;
  final String conversationId;
  final String senderDeviceId;
  final String recipientUserId;
  final CryptoEnvelope envelope;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? lastAttemptAt;
  final DateTime? nextRetryAt;
  final MessageDeliveryState state;
  final String? errorMessage;
  final AttachmentUploadDraft? attachmentUploadDraft;

  PendingMessageRecord copyWith({
    int? retryCount,
    Object? lastAttemptAt = _unset,
    Object? nextRetryAt = _unset,
    MessageDeliveryState? state,
    Object? errorMessage = _unset,
    Object? attachmentUploadDraft = _unset,
    CryptoEnvelope? envelope,
  }) {
    return PendingMessageRecord(
      clientMessageId: clientMessageId,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientUserId: recipientUserId,
      envelope: envelope ?? this.envelope,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: identical(lastAttemptAt, _unset)
          ? this.lastAttemptAt
          : lastAttemptAt as DateTime?,
      nextRetryAt: identical(nextRetryAt, _unset)
          ? this.nextRetryAt
          : nextRetryAt as DateTime?,
      state: state ?? this.state,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      attachmentUploadDraft: identical(attachmentUploadDraft, _unset)
          ? this.attachmentUploadDraft
          : attachmentUploadDraft as AttachmentUploadDraft?,
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

  Future<void> indexMessageBody({
    required String conversationId,
    required String messageId,
    required String searchableBody,
  });

  Future<List<String>> searchCachedMessageIds({
    required String conversationId,
    required String query,
  });

  Future<MessageSearchPage> searchMessageArchive({
    required MessageSearchQuery query,
    required String currentDeviceId,
  });

  Future<void> purgeExpiredMessages();

  Future<void> clearAll();
}

class DriftConversationCacheService implements ConversationCacheService {
  DriftConversationCacheService(
    this._db, {
    required CryptoEnvelopeCodec envelopeCodec,
    LocalDataCipher? cipher,
  })  : _cipher = cipher,
        _envelopeCodec = envelopeCodec;

  final AppDatabase _db;
  final LocalDataCipher? _cipher;
  final CryptoEnvelopeCodec _envelopeCodec;

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
      final peerHandle = await _decrypt(row.peerHandle);
      if (peerHandle == null) {
        continue;
      }

      final peerDisplayName = await _decrypt(row.peerDisplayName);
      final peerUserId = await _decrypt(row.peerUserId);
      final peerDeviceId = await _decrypt(row.peerDeviceId);
      final peerIdentityPublicKey = await _decrypt(row.peerIdentityPublicKey);
      final peerSignedPrekeyBundle = await _decrypt(row.peerSignedPrekeyBundle);
      final previewSenderDeviceId = await _decrypt(row.previewSenderDeviceId);
      final previewCiphertext = await _decrypt(row.previewCiphertext);
      final previewNonce = await _decrypt(row.previewNonce);
      final previewMessageType = await _decrypt(row.previewMessageType);
      final previewAttachmentJson = await _decrypt(row.previewAttachmentJson);
      final sessionLocator = await _decrypt(row.sessionLocator);
      final sessionEnvelopeVersion =
          await _decrypt(row.sessionEnvelopeVersion);
      final sessionRequiresLocalPersistence =
          await _decrypt(row.sessionRequiresLocalPersistence);
      final sessionAuditHint = await _decrypt(row.sessionAuditHint);
      final sessionBootstrappedAt =
          await _decrypt(row.sessionBootstrappedAt);

      conversations.add(
        ConversationPreview(
          id: row.id,
          peerHandle: peerHandle,
          peerDisplayName: peerDisplayName,
          recipientBundle: KeyBundle(
            userId: peerUserId ?? 'cached-user-$peerHandle',
            deviceId: peerDeviceId ?? '',
            handle: peerHandle,
            identityPublicKey: peerIdentityPublicKey ?? '',
            signedPrekeyBundle: peerSignedPrekeyBundle ?? '',
          ),
          lastEnvelope: previewMessageType == null ||
                  previewSenderDeviceId == null ||
                  previewCiphertext == null ||
                  previewNonce == null
              ? null
              : CryptoEnvelope(
                  version: _envelopeCodec.defaultEnvelopeVersion,
                  conversationId: row.id,
                  senderDeviceId: previewSenderDeviceId,
                  recipientUserId: peerUserId ?? '',
                  ciphertext: previewCiphertext,
                  nonce: previewNonce,
                  messageKind: MessageKind.values.byName(previewMessageType),
                  expiresAt: row.previewExpiresAt,
                  attachment: _decodeAttachment(previewAttachmentJson),
                ),
          updatedAt: row.updatedAt,
          sessionState: sessionLocator == null ||
                  sessionEnvelopeVersion == null ||
                  sessionRequiresLocalPersistence == null ||
                  sessionBootstrappedAt == null
              ? null
              : ConversationSessionState(
                  sessionLocator: sessionLocator,
                  sessionEnvelopeVersion: sessionEnvelopeVersion,
                  requiresLocalPersistence:
                      sessionRequiresLocalPersistence == 'true',
                  bootstrappedAt: DateTime.parse(sessionBootstrappedAt),
                  auditHint: sessionAuditHint,
                ),
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
      final messageType = await _decrypt(row.messageType);
      final attachmentJson = await _decrypt(row.attachmentJson);
      final searchBody = await _decrypt(row.searchBody);

      if (senderDeviceId == null ||
          ciphertext == null ||
          nonce == null ||
          messageType == null) {
        continue;
      }

      messages.add(
        ChatMessage(
          id: row.id,
          clientMessageId: row.clientMessageId,
          senderDeviceId: senderDeviceId,
          sentAt: row.receivedAt,
          envelope: CryptoEnvelope(
            version: _envelopeCodec.defaultEnvelopeVersion,
            conversationId: row.conversationId,
            senderDeviceId: senderDeviceId,
            recipientUserId: '',
            ciphertext: ciphertext,
            nonce: nonce,
            messageKind: MessageKind.values.byName(messageType),
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
          searchableBody: searchBody,
          isMine: false,
        ),
      );
    }

    return messages;
  }

  @override
  Future<void> storeConversations(
      List<ConversationPreview> conversations) async {
    final existingRows = await _db.select(_db.cachedConversations).get();
    final existingById = {for (final row in existingRows) row.id: row};
    final rows = <CachedConversationsCompanion>[];

    for (final conversation in conversations) {
      final preview = conversation.lastEnvelope;
      final existing = existingById[conversation.id];
      rows.add(
        CachedConversationsCompanion.insert(
          id: conversation.id,
          peerHandle: await _requireEncryptedValue(conversation.peerHandle),
          updatedAt: conversation.updatedAt,
          peerUserId:
              Value(await _encrypt(conversation.recipientBundle.userId)),
          peerDisplayName: Value(await _encrypt(conversation.peerDisplayName)),
          peerDeviceId:
              Value(await _encrypt(conversation.recipientBundle.deviceId)),
          peerIdentityPublicKey: Value(
              await _encrypt(conversation.recipientBundle.identityPublicKey)),
          peerSignedPrekeyBundle: Value(
              await _encrypt(conversation.recipientBundle.signedPrekeyBundle)),
          previewSenderDeviceId: Value(await _encrypt(preview?.senderDeviceId)),
          previewCiphertext: Value(await _encrypt(preview?.ciphertext)),
          previewNonce: Value(await _encrypt(preview?.nonce)),
          previewMessageType: Value(await _encrypt(preview?.messageKind.name)),
          previewAttachmentJson:
              Value(await _encrypt(_encodeAttachment(preview?.attachment))),
          previewExpiresAt: Value(preview?.expiresAt),
          sessionLocator:
              Value(await _encrypt(conversation.sessionState?.sessionLocator)),
          sessionEnvelopeVersion: Value(await _encrypt(
              conversation.sessionState?.sessionEnvelopeVersion)),
          sessionRequiresLocalPersistence: Value(await _encrypt(
            conversation.sessionState?.requiresLocalPersistence.toString(),
          )),
          sessionAuditHint:
              Value(await _encrypt(conversation.sessionState?.auditHint)),
          sessionBootstrappedAt: Value(await _encrypt(
            conversation.sessionState?.bootstrappedAt.toIso8601String(),
          )),
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
  Future<void> storeMessages(
      String conversationId, List<ChatMessage> messages) async {
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
          messageType:
              await _requireEncryptedValue(message.envelope.messageKind.name),
          attachmentJson: Value(
              await _encrypt(_encodeAttachment(message.envelope.attachment))),
          searchBody: Value(await _encrypt(message.searchableBody)),
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
      final messageType = await _decrypt(row.messageType);
      final attachmentJson = await _decrypt(row.attachmentJson);
      final errorMessage = await _decrypt(row.errorMessage);

      if (senderDeviceId == null ||
          recipientUserId == null ||
          ciphertext == null ||
          nonce == null ||
          messageType == null) {
        continue;
      }

      pendingMessages.add(
        PendingMessageRecord(
          clientMessageId: row.clientMessageId,
          conversationId: row.conversationId,
          senderDeviceId: senderDeviceId,
          recipientUserId: recipientUserId,
          envelope: CryptoEnvelope(
            version: _envelopeCodec.defaultEnvelopeVersion,
            conversationId: row.conversationId,
            senderDeviceId: senderDeviceId,
            recipientUserId: recipientUserId,
            ciphertext: ciphertext,
            nonce: nonce,
            messageKind: MessageKind.values.byName(messageType),
            expiresAt: row.expiresAt,
            attachment: _decodeAttachment(attachmentJson),
          ),
          createdAt: row.createdAt,
          retryCount: row.retryCount,
          lastAttemptAt: row.lastAttemptAt,
          nextRetryAt: row.nextRetryAt,
          state: _deliveryStateFromString(row.state),
          errorMessage: errorMessage,
          attachmentUploadDraft: _decodeAttachmentUploadDraft(attachmentJson),
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
            senderDeviceId:
                await _requireEncryptedValue(pending.senderDeviceId),
            recipientUserId:
                await _requireEncryptedValue(pending.recipientUserId),
            ciphertext:
                await _requireEncryptedValue(pending.envelope.ciphertext),
            nonce: await _requireEncryptedValue(pending.envelope.nonce),
            messageType:
                await _requireEncryptedValue(pending.envelope.messageKind.name),
            attachmentJson:
                Value(await _encrypt(_encodePendingAttachmentPayload(pending))),
            createdAt: pending.createdAt,
            expiresAt: Value(pending.envelope.expiresAt),
            retryCount: Value(pending.retryCount),
            lastAttemptAt: Value(pending.lastAttemptAt),
            nextRetryAt: Value(pending.nextRetryAt),
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
  Future<void> indexMessageBody({
    required String conversationId,
    required String messageId,
    required String searchableBody,
  }) async {
    await (_db.update(_db.cachedMessages)
          ..where(
            (table) =>
                table.conversationId.equals(conversationId) &
                table.id.equals(messageId),
          ))
        .write(
      CachedMessagesCompanion(
        searchBody: Value(await _encrypt(searchableBody)),
      ),
    );
  }

  @override
  Future<List<String>> searchCachedMessageIds({
    required String conversationId,
    required String query,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final rows = await (_db.select(_db.cachedMessages)
          ..where((table) => table.conversationId.equals(conversationId)))
        .get();
    final matches = <String>[];
    for (final row in rows) {
      final searchBody = await _decrypt(row.searchBody);
      if (searchBody == null || !searchBody.contains(normalizedQuery)) {
        continue;
      }
      matches.add(row.id);
    }
    return matches;
  }

  @override
  Future<MessageSearchPage> searchMessageArchive({
    required MessageSearchQuery query,
    required String currentDeviceId,
  }) async {
    final normalizedQuery = query.normalizedQuery;
    if (normalizedQuery.isEmpty) {
      return const MessageSearchPage(items: <MessageSearchResult>[]);
    }

    final conversationRows = await _db.select(_db.cachedConversations).get();
    final conversationsById = <String, _ArchivedConversationMeta>{};
    for (final row in conversationRows) {
      if (query.conversationId != null && row.id != query.conversationId) {
        continue;
      }
      final peerHandle = await _decrypt(row.peerHandle);
      if (peerHandle == null) {
        continue;
      }
      conversationsById[row.id] = _ArchivedConversationMeta(
        peerHandle: peerHandle,
        peerDisplayName: await _decrypt(row.peerDisplayName),
      );
    }
    if (conversationsById.isEmpty) {
      return const MessageSearchPage(items: <MessageSearchResult>[]);
    }

    final cutoff = query.resolveCutoff(DateTime.now());
    final rows = await (_db.select(_db.cachedMessages)
          ..where((table) {
            Expression<bool> expression = table.conversationId
                .isIn(conversationsById.keys.toList(growable: false));
            if (cutoff != null) {
              expression =
                  expression & table.receivedAt.isBiggerOrEqualValue(cutoff);
            }
            if (query.beforeSentAt case final beforeSentAt?) {
              expression = expression &
                  table.receivedAt.isSmallerThanValue(beforeSentAt);
            }
            return expression;
          })
          ..orderBy([
            (table) => OrderingTerm(
                  expression: table.receivedAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();

    final results = <MessageSearchResult>[];
    for (final row in rows) {
      final conversation = conversationsById[row.conversationId];
      if (conversation == null) {
        continue;
      }
      final senderDeviceId = await _decrypt(row.senderDeviceId);
      final searchBody = await _decrypt(row.searchBody);
      final messageType = await _decrypt(row.messageType);
      if (senderDeviceId == null || searchBody == null || messageType == null) {
        continue;
      }
      if (query.beforeSentAt != null &&
          row.receivedAt.isAtSameMomentAs(query.beforeSentAt!) &&
          query.beforeMessageId != null &&
          row.id.compareTo(query.beforeMessageId!) >= 0) {
        continue;
      }
      if (!searchBody.contains(normalizedQuery)) {
        continue;
      }
      if (!_messageTypeMatchesFilter(messageType, query.typeFilter)) {
        continue;
      }

      final isMine = senderDeviceId == currentDeviceId;
      switch (query.senderFilter) {
        case MessageSearchSenderFilter.all:
          break;
        case MessageSearchSenderFilter.mine:
          if (!isMine) {
            continue;
          }
          break;
        case MessageSearchSenderFilter.theirs:
          if (isMine) {
            continue;
          }
          break;
      }

      results.add(
        MessageSearchResult(
          conversationId: row.conversationId,
          messageId: row.id,
          peerHandle: conversation.peerHandle,
          peerDisplayName: conversation.peerDisplayName,
          sentAt: row.receivedAt,
          messageKind: MessageKind.values.byName(messageType),
          isMine: isMine,
          bodySnippet: buildArchiveQuerySnippet(searchBody, normalizedQuery),
          conversationOrder: row.conversationOrder,
        ),
      );

      if (results.length >= query.limit) {
        break;
      }
    }

    if (results.length < query.limit) {
      return MessageSearchPage(items: results);
    }

    final last = results.last;
    return MessageSearchPage(
      items: results,
      nextBeforeSentAt: last.sentAt,
      nextBeforeMessageId: last.messageId,
    );
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

  @override
  Future<void> clearAll() async {
    await _db.transaction(() async {
      await _db.delete(_db.pendingMessages).go();
      await _db.delete(_db.cachedMessages).go();
      await _db.delete(_db.cachedConversations).go();
    });
    await _db.customStatement('VACUUM');
  }

  bool _messageTypeMatchesFilter(
    String messageType,
    MessageSearchTypeFilter filter,
  ) {
    switch (filter) {
      case MessageSearchTypeFilter.all:
        return true;
      case MessageSearchTypeFilter.text:
        return messageType == MessageKind.text.name;
      case MessageSearchTypeFilter.media:
        return messageType == MessageKind.image.name ||
            messageType == MessageKind.file.name;
      case MessageSearchTypeFilter.file:
        return messageType == MessageKind.file.name;
      case MessageSearchTypeFilter.system:
        return messageType == MessageKind.system.name;
    }
  }

  String? _encodeAttachment(AttachmentReference? attachment) {
    if (attachment == null) {
      return null;
    }

    return jsonEncode({
      'kind': 'reference',
      'value': _envelopeCodec.encodeAttachmentReference(attachment),
    });
  }

  AttachmentReference? _decodeAttachment(String? raw) {
    if (raw == null) {
      return null;
    }

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded['kind'] == 'reference') {
      return _envelopeCodec.decodeAttachmentReference(
        decoded['value'] as Map<String, dynamic>,
      );
    }
    if (decoded['kind'] == 'upload-draft') {
      return null;
    }
    if (decoded.containsKey('encryption')) {
      return _envelopeCodec.decodeAttachmentReference(decoded);
    }

    return AttachmentReference(
      attachmentId: decoded['attachmentId'] as String,
      storageKey: decoded['storageKey'] as String,
      contentType: decoded['contentType'] as String,
      sizeBytes: decoded['sizeBytes'] as int,
      sha256: decoded['sha256'] as String,
      encryptedKey: decoded['encryptedKey'] as String,
      nonce: decoded['nonce'] as String,
      algorithmHint: decoded['algorithmHint'] as String?,
    );
  }

  String? _encodePendingAttachmentPayload(PendingMessageRecord pending) {
    if (pending.attachmentUploadDraft != null) {
      return jsonEncode({
        'kind': 'upload-draft',
        'value': pending.attachmentUploadDraft!.toJson(),
      });
    }

    return _encodeAttachment(pending.envelope.attachment);
  }

  AttachmentUploadDraft? _decodeAttachmentUploadDraft(String? raw) {
    if (raw == null) {
      return null;
    }

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded['kind'] == 'upload-draft') {
      return AttachmentUploadDraft.fromJson(
          decoded['value'] as Map<String, dynamic>);
    }
    return null;
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
    try {
      return await cipher.decryptString(value);
    } on FormatException {
      return null;
    }
  }

  Future<String> _requireEncryptedValue(String value) async {
    final encrypted = await _encrypt(value);
    return encrypted ?? value;
  }

}
