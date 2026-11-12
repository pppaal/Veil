import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError;
import 'package:drift/drift.dart';

import '../crypto/crypto_engine.dart';
import '../domain/chat_message.dart';
import '../domain/conversation_preview.dart';
import '../domain/message_search.dart';
import '../security/local_data_cipher.dart';
import 'app_database.dart';

const int maxArchiveSearchBodyLength = 1024;

String normalizeArchiveSearchBody(String searchBody) {
  final compact = searchBody.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (compact.length <= maxArchiveSearchBodyLength) {
    return compact;
  }
  return compact.substring(0, maxArchiveSearchBodyLength).trim();
}

int findArchiveQueryIndex(String searchBody, String normalizedQuery) {
  if (normalizedQuery.isEmpty) {
    return -1;
  }
  final compactBody = normalizeArchiveSearchBody(searchBody);
  return compactBody.toLowerCase().indexOf(normalizedQuery);
}

int archiveSearchRankingScore(String searchBody, String normalizedQuery) {
  final compactBody = normalizeArchiveSearchBody(searchBody);
  final lowerBody = compactBody.toLowerCase();
  final matchIndex = lowerBody.indexOf(normalizedQuery);
  if (matchIndex < 0) {
    return 1 << 20;
  }
  if (lowerBody == normalizedQuery) {
    return 0;
  }
  if (lowerBody.startsWith(normalizedQuery)) {
    return 100 + matchIndex;
  }
  if (matchIndex > 0 && _isArchiveWordBoundary(compactBody[matchIndex - 1])) {
    return 200 + matchIndex;
  }
  return 300 + matchIndex;
}

bool _isArchiveWordBoundary(String character) {
  const boundaries = <String>{
    ' ',
    '\t',
    '\n',
    '-',
    '_',
    ',',
    '.',
    ';',
    ':',
    '!',
    '?',
    '(',
    ')',
    '[',
    ']',
    '{',
    '}',
    '\'',
    '"',
    '/',
    '\\',
  };
  return boundaries.contains(character);
}

String buildArchiveQuerySnippet(String searchBody, String normalizedQuery) {
  final compactBody = normalizeArchiveSearchBody(searchBody);
  final matchIndex = findArchiveQueryIndex(compactBody, normalizedQuery);
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
    this.sealedReference,
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
  // Set once the staged file has been replaced by its ciphertext; carries
  // the wrapped content key the recipient needs.
  final AttachmentReference? sealedReference;

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
    AttachmentReference? sealedReference,
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
      sealedReference: sealedReference ?? this.sealedReference,
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
      if (sealedReference case final reference?)
        'sealedReference': {
          'attachmentId': reference.attachmentId,
          'storageKey': reference.storageKey,
          'contentType': reference.contentType,
          'sizeBytes': reference.sizeBytes,
          'sha256': reference.sha256,
          'encryptedKey': reference.encryptedKey,
          'nonce': reference.nonce,
          'algorithmHint': reference.algorithmHint,
        },
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
      sealedReference: switch (json['sealedReference']) {
        final Map<String, dynamic> reference => AttachmentReference(
            attachmentId: reference['attachmentId'] as String,
            storageKey: reference['storageKey'] as String,
            contentType: reference['contentType'] as String,
            sizeBytes: reference['sizeBytes'] as int,
            sha256: reference['sha256'] as String,
            encryptedKey: reference['encryptedKey'] as String,
            nonce: reference['nonce'] as String,
            algorithmHint: reference['algorithmHint'] as String?,
          ),
        _ => null,
      },
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

/// Result of the single decrypt a message ever gets. Ratchet message keys
/// are single-use, so the stored status decides whether a row may ever be
/// decrypted again.
enum MessageContentStatus {
  ok('ok', DecryptStatus.ok),
  failed('failed', DecryptStatus.failed),
  replayed('replayed', DecryptStatus.replayed),
  awaitingKey('awaiting_key', DecryptStatus.awaitingKey),
  sessionMissing('session_missing', DecryptStatus.sessionMissing),
  identityRejected('identity_rejected', DecryptStatus.identityRejected),
  legacyUnauthenticated('legacy_unauthenticated', DecryptStatus.legacyUnauthenticated);

  const MessageContentStatus(this.storageName, this.decryptStatus);

  final String storageName;
  final DecryptStatus decryptStatus;

  /// Final rows are never decrypted again. The others are retried only when
  /// key material or trust for their conversation changes: a rejected
  /// identity reopens once the user approves it.
  bool get isFinal => this == ok || this == failed || this == replayed || this == legacyUnauthenticated;

  static MessageContentStatus fromStorageName(String name) => values.firstWhere(
        (status) => status.storageName == name,
        orElse: () => failed,
      );

  static MessageContentStatus of(DecryptStatus status) =>
      values.firstWhere((candidate) => candidate.decryptStatus == status);
}

const _localMessageContentKeyPrefix = 'local:';

/// Content key of an outbound message before the relay assigns its id.
String localMessageContentKey(String clientMessageId) => '$_localMessageContentKeyPrefix$clientMessageId';

/// Whether a write may replace content stored under [messageKey] whose
/// status is [existing]. Content under a relayed id is the outcome of its
/// one decrypt, so a final row there changes only through
/// rekeyLocalToServer, which brings the sender's own plaintext; a later
/// decrypt outcome racing that rekey must not overwrite it. Outbound rows
/// under local keys stay replaceable by their sender.
bool mayReplaceMessageContent(String messageKey, MessageContentStatus existing) =>
    messageKey.startsWith(_localMessageContentKeyPrefix) || !existing.isFinal;

class MessageContentRecord {
  const MessageContentRecord({
    required this.messageKey,
    required this.conversationId,
    required this.body,
    required this.kind,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.clientMessageId,
    this.serverMessageId,
    this.attachment,
    this.innerExpiresAt,
  });

  final String messageKey;
  final String conversationId;
  final String? clientMessageId;
  final String? serverMessageId;
  final String body;
  final MessageKind kind;
  final AttachmentReference? attachment;
  // Expiry from the authenticated inner payload; the outer, server-supplied
  // expiresAt lives on the cached message.
  final DateTime? innerExpiresAt;
  final MessageContentStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  DecryptedMessage toDecryptedMessage() => DecryptedMessage(
        body: body,
        messageKind: kind,
        expiresAt: innerExpiresAt,
        attachment: attachment,
        status: status.decryptStatus,
      );
}

/// Text a message can be found by. Built only from decrypted content, so
/// searching never needs a crypto call.
String searchableContentText(MessageContentRecord record) => [
      record.body,
      if (record.attachment != null) record.attachment!.contentType,
    ].join(' ');

/// Durable store for decrypted message content. Implemented by the Drift
/// cache; kept separate from [ConversationCacheService] so the many cache
/// fakes in tests are unaffected, and callers check for it with `is`.
abstract class MessageContentStore {
  /// Stores [record] unless its key is retired, or holds content that
  /// [mayReplaceMessageContent] protects.
  Future<void> put(MessageContentRecord record);

  Future<MessageContentRecord?> get(String messageKey);

  Future<Map<String, MessageContentRecord>> getMany(Iterable<String> messageKeys);

  /// Inner expiries of those [messageKeys] that have one. Reads no encrypted
  /// column, so it stays cheap over a whole conversation.
  Future<Map<String, DateTime>> innerExpiries(Iterable<String> messageKeys);

  /// Moves an outbound message's content from its local key to the id the
  /// relay acked it under.
  Future<void> rekeyLocalToServer({
    required String clientMessageId,
    required String serverMessageId,
  });

  Future<void> deleteConversation(String conversationId);

  /// Deletes rows whose inner expiry has passed, plus [messageKeys]: content
  /// the caller has retired, i.e. messages it expired at min(inner, outer)
  /// or outbound text that was never queued. Every deleted key is remembered
  /// as retired, and content for a retired key is never stored again.
  Future<void> deleteExpired(DateTime now, {Iterable<String> messageKeys});

  /// Those [messageKeys] this device has already retired.
  Future<Set<String>> retiredAmong(Iterable<String> messageKeys);
}

/// How long retired message ids are remembered: longer than the relay may
/// hold any ciphertext (30 days), so it can never serve one back afterwards.
const retiredMessageRetention = Duration(days: 31);

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

class DriftConversationCacheService implements ConversationCacheService, MessageContentStore {
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
      final sessionLocalDeviceId = await _decrypt(row.sessionLocalDeviceId);
      final sessionRemoteDeviceId = await _decrypt(row.sessionRemoteDeviceId);
      final sessionRemoteIdentityFingerprint =
          await _decrypt(row.sessionRemoteIdentityFingerprint);
      final sessionAuditHint = await _decrypt(row.sessionAuditHint);
      final sessionBootstrappedAt =
          await _decrypt(row.sessionBootstrappedAt);
      final sessionRemoteIdentityPublicKey =
          await _decrypt(row.sessionRemoteIdentityPublicKey);

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
                  version: row.previewEnvelopeVersion ??
                      _envelopeCodec.defaultEnvelopeVersion,
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
                  row.sessionSchemaVersion == null ||
                  sessionLocalDeviceId == null ||
                  sessionRemoteDeviceId == null ||
                  sessionRemoteIdentityFingerprint == null ||
                  sessionBootstrappedAt == null
              ? null
              : ConversationSessionState(
                  sessionLocator: sessionLocator,
                  sessionEnvelopeVersion: sessionEnvelopeVersion,
                  requiresLocalPersistence:
                      sessionRequiresLocalPersistence == 'true',
                  sessionSchemaVersion: row.sessionSchemaVersion!,
                  localDeviceId: sessionLocalDeviceId,
                  remoteDeviceId: sessionRemoteDeviceId,
                  remoteIdentityFingerprint: sessionRemoteIdentityFingerprint,
                  bootstrappedAt: DateTime.parse(sessionBootstrappedAt),
                  auditHint: sessionAuditHint,
                  remoteIdentityPublicKey: sessionRemoteIdentityPublicKey ?? '',
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
            version: row.envelopeVersion ?? _envelopeCodec.defaultEnvelopeVersion,
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
          previewEnvelopeVersion: Value(preview?.version),
          previewExpiresAt: Value(preview?.expiresAt),
          sessionLocator:
              Value(await _encrypt(conversation.sessionState?.sessionLocator)),
          sessionEnvelopeVersion: Value(await _encrypt(
              conversation.sessionState?.sessionEnvelopeVersion)),
          sessionRequiresLocalPersistence: Value(await _encrypt(
            conversation.sessionState?.requiresLocalPersistence.toString(),
          )),
          sessionSchemaVersion:
              Value(conversation.sessionState?.sessionSchemaVersion),
          sessionLocalDeviceId: Value(
              await _encrypt(conversation.sessionState?.localDeviceId)),
          sessionRemoteDeviceId: Value(
              await _encrypt(conversation.sessionState?.remoteDeviceId)),
          sessionRemoteIdentityFingerprint: Value(await _encrypt(
              conversation.sessionState?.remoteIdentityFingerprint)),
          sessionAuditHint:
              Value(await _encrypt(conversation.sessionState?.auditHint)),
          sessionBootstrappedAt: Value(await _encrypt(
            conversation.sessionState?.bootstrappedAt.toIso8601String(),
          )),
          sessionRemoteIdentityPublicKey: Value(await _encrypt(
              conversation.sessionState?.remoteIdentityPublicKey)),
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
          envelopeVersion: Value(message.envelope.version),
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
            version: row.envelopeVersion ?? _envelopeCodec.defaultEnvelopeVersion,
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
            envelopeVersion: Value(pending.envelope.version),
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

  // Search reads decrypted content rows directly, so there is no separate
  // plaintext index to maintain.
  @override
  Future<void> indexMessageBody({
    required String conversationId,
    required String messageId,
    required String searchableBody,
  }) async {}

  @override
  Future<List<String>> searchCachedMessageIds({
    required String conversationId,
    required String query,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final rows = await (_db.select(_db.messageContents)
          ..where((table) =>
              table.conversationId.equals(conversationId) &
              table.status.equals(MessageContentStatus.ok.storageName)))
        .get();
    final matches = <String>[];
    for (final row in rows) {
      final record = await _decodeContent(row);
      if (record == null ||
          !normalizeArchiveSearchBody(searchableContentText(record))
              .toLowerCase()
              .contains(normalizedQuery)) {
        continue;
      }
      matches.add(record.messageKey == localMessageContentKey(record.clientMessageId ?? '')
          ? 'local-${record.clientMessageId}'
          : record.messageKey);
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
                  table.receivedAt.isSmallerOrEqualValue(beforeSentAt);
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

    final contents = await getMany(rows.map((row) => row.id));
    final results = <MessageSearchResult>[];
    final ranked = <({int score, MessageSearchResult result})>[];
    for (final row in rows) {
      final conversation = conversationsById[row.conversationId];
      final content = contents[row.id];
      if (conversation == null ||
          content == null ||
          content.status != MessageContentStatus.ok) {
        continue;
      }
      final senderDeviceId = await _decrypt(row.senderDeviceId);
      if (senderDeviceId == null) {
        continue;
      }
      final searchBody = searchableContentText(content);
      if (query.beforeSentAt != null &&
          row.receivedAt.isAtSameMomentAs(query.beforeSentAt!) &&
          query.beforeMessageId != null &&
          row.id.compareTo(query.beforeMessageId!) >= 0) {
        continue;
      }
      final rankingScore = archiveSearchRankingScore(searchBody, normalizedQuery);
      if (rankingScore >= (1 << 20)) {
        continue;
      }
      if (!_messageTypeMatchesFilter(content.kind.name, query.typeFilter)) {
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

      ranked.add((
        score: rankingScore,
        result: MessageSearchResult(
          conversationId: row.conversationId,
          messageId: row.id,
          peerHandle: conversation.peerHandle,
          peerDisplayName: conversation.peerDisplayName,
          sentAt: row.receivedAt,
          messageKind: content.kind,
          isMine: isMine,
          bodySnippet: buildArchiveQuerySnippet(searchBody, normalizedQuery),
          conversationOrder: row.conversationOrder,
        ),
      ));
    }

    ranked.sort((a, b) {
      final scoreCompare = a.score.compareTo(b.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      final sentAtCompare = b.result.sentAt.compareTo(a.result.sentAt);
      if (sentAtCompare != 0) {
        return sentAtCompare;
      }
      return b.result.messageId.compareTo(a.result.messageId);
    });

    for (final entry in ranked.take(query.limit)) {
      results.add(entry.result);
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
    await _db.transaction(() async {
      // Content goes with its message, including messages that expire while
      // they are not loaded in memory.
      final expiredMessageIds = await (_db.selectOnly(_db.cachedMessages)
            ..addColumns([_db.cachedMessages.id])
            ..where(_db.cachedMessages.expiresAt.isSmallerThanValue(now)))
          .map((row) => row.read(_db.cachedMessages.id)!)
          .get();
      await _retireExpiredContent(now, alsoRetire: expiredMessageIds);
      await (_db.delete(_db.cachedMessages)
            ..where((table) => table.expiresAt.isSmallerThanValue(now)))
          .go();
      await (_db.delete(_db.pendingMessages)
            ..where((table) => table.expiresAt.isSmallerThanValue(now)))
          .go();
      await (_db.delete(_db.retiredMessages)
            ..where((table) =>
                table.retiredAt.isSmallerThanValue(now.subtract(retiredMessageRetention))))
          .go();
    });
  }

  @override
  Future<void> clearAll() async {
    await _db.transaction(() async {
      await _db.delete(_db.messageContents).go();
      await _db.delete(_db.retiredMessages).go();
      await _db.delete(_db.pendingMessages).go();
      await _db.delete(_db.cachedMessages).go();
      await _db.delete(_db.cachedConversations).go();
    });
    await _db.customStatement('VACUUM');
    await _truncateWriteAheadLog();
  }

  @override
  Future<void> put(MessageContentRecord record) async {
    final row = MessageContentsCompanion.insert(
      messageKey: record.messageKey,
      conversationId: record.conversationId,
      clientMessageId: Value(record.clientMessageId),
      serverMessageId: Value(record.serverMessageId),
      body: await _requireEncryptedValue(record.body),
      attachmentJson: Value(await _encrypt(_encodeAttachment(record.attachment))),
      kind: await _requireEncryptedValue(record.kind.name),
      innerExpiresAt: Value(record.innerExpiresAt?.millisecondsSinceEpoch),
      status: record.status.storageName,
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
    );
    final protectedStatuses = [
      for (final status in MessageContentStatus.values)
        if (!mayReplaceMessageContent(record.messageKey, status)) status.storageName,
    ];
    // Rows for retired keys are dropped by a trigger (see AppDatabase).
    await _db.into(_db.messageContents).insert(
          row,
          onConflict: DoUpdate(
            (_) => row,
            where: protectedStatuses.isEmpty ? null : (old) => old.status.isNotIn(protectedStatuses),
          ),
        );
  }

  @override
  Future<MessageContentRecord?> get(String messageKey) async {
    final row = await (_db.select(_db.messageContents)
          ..where((table) => table.messageKey.equals(messageKey)))
        .getSingleOrNull();
    return row == null ? null : _decodeContent(row);
  }

  @override
  Future<Map<String, MessageContentRecord>> getMany(
    Iterable<String> messageKeys,
  ) async {
    final records = <String, MessageContentRecord>{};
    for (final chunk in _chunked(messageKeys)) {
      final rows = await (_db.select(_db.messageContents)
            ..where((table) => table.messageKey.isIn(chunk)))
          .get();
      for (final row in rows) {
        final record = await _decodeContent(row);
        if (record != null) {
          records[record.messageKey] = record;
        }
      }
    }
    return records;
  }

  @override
  Future<Map<String, DateTime>> innerExpiries(Iterable<String> messageKeys) async {
    final expiries = <String, DateTime>{};
    for (final chunk in _chunked(messageKeys)) {
      final query = _db.selectOnly(_db.messageContents)
        ..addColumns([_db.messageContents.messageKey, _db.messageContents.innerExpiresAt])
        ..where(
          _db.messageContents.messageKey.isIn(chunk) &
              _db.messageContents.innerExpiresAt.isNotNull(),
        );
      for (final row in await query.get()) {
        expiries[row.read(_db.messageContents.messageKey)!] =
            DateTime.fromMillisecondsSinceEpoch(row.read(_db.messageContents.innerExpiresAt)!);
      }
    }
    return expiries;
  }

  @override
  Future<void> rekeyLocalToServer({
    required String clientMessageId,
    required String serverMessageId,
  }) async {
    final localKey = localMessageContentKey(clientMessageId);
    await _db.transaction(() async {
      final local = await (_db.select(_db.messageContents)
            ..where((table) => table.messageKey.equals(localKey)))
          .getSingleOrNull();
      if (local == null) {
        return;
      }
      // The sender's own plaintext wins over anything recorded under the
      // server id, such as a failed attempt to open our own echoed envelope.
      await (_db.delete(_db.messageContents)
            ..where((table) => table.messageKey.equals(serverMessageId)))
          .go();
      await (_db.update(_db.messageContents)
            ..where((table) => table.messageKey.equals(localKey)))
          .write(
        MessageContentsCompanion(
          messageKey: Value(serverMessageId),
          serverMessageId: Value(serverMessageId),
          updatedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  @override
  Future<void> deleteConversation(String conversationId) async {
    await (_db.delete(_db.messageContents)
          ..where((table) => table.conversationId.equals(conversationId)))
        .go();
    await _truncateWriteAheadLog();
  }

  // secure_delete scrubs freed pages in the database file, but copies of
  // them can still sit in the write-ahead log until it is checkpointed.
  Future<void> _truncateWriteAheadLog() =>
      _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

  @override
  Future<void> deleteExpired(
    DateTime now, {
    Iterable<String> messageKeys = const [],
  }) =>
      _db.transaction(() => _retireExpiredContent(now, alsoRetire: messageKeys));

  @override
  Future<Set<String>> retiredAmong(Iterable<String> messageKeys) async {
    final retired = <String>{};
    for (final chunk in _chunked(messageKeys)) {
      final query = _db.selectOnly(_db.retiredMessages)
        ..addColumns([_db.retiredMessages.messageKey])
        ..where(_db.retiredMessages.messageKey.isIn(chunk));
      retired.addAll(await query.map((row) => row.read(_db.retiredMessages.messageKey)!).get());
    }
    return retired;
  }

  // Deletes content whose inner expiry has passed, plus [alsoRetire], and
  // remembers every one of those keys as retired.
  Future<void> _retireExpiredContent(
    DateTime now, {
    required Iterable<String> alsoRetire,
  }) async {
    final innerExpired = await (_db.selectOnly(_db.messageContents)
          ..addColumns([_db.messageContents.messageKey])
          ..where(_db.messageContents.innerExpiresAt.isSmallerOrEqualValue(now.millisecondsSinceEpoch)))
        .map((row) => row.read(_db.messageContents.messageKey)!)
        .get();
    for (final chunk in _chunked([...innerExpired, ...alsoRetire])) {
      await (_db.delete(_db.messageContents)
            ..where((table) => table.messageKey.isIn(chunk)))
          .go();
      await _db.batch(
        (batch) => batch.insertAll(
          _db.retiredMessages,
          [
            for (final key in chunk)
              RetiredMessagesCompanion.insert(messageKey: key, retiredAt: now),
          ],
          mode: InsertMode.insertOrIgnore,
        ),
      );
    }
  }

  Future<MessageContentRecord?> _decodeContent(MessageContent row) async {
    final body = await _decrypt(row.body);
    final kind = await _decrypt(row.kind);
    if (body == null || kind == null) {
      return null;
    }
    return MessageContentRecord(
      messageKey: row.messageKey,
      conversationId: row.conversationId,
      clientMessageId: row.clientMessageId,
      serverMessageId: row.serverMessageId,
      body: body,
      kind: MessageKind.values.byName(kind),
      attachment: _decodeAttachment(await _decrypt(row.attachmentJson)),
      innerExpiresAt: row.innerExpiresAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row.innerExpiresAt!),
      status: MessageContentStatus.fromStorageName(row.status),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  // Keeps IN (...) lists well below SQLite's bound-parameter limit on long
  // histories.
  static Iterable<List<String>> _chunked(Iterable<String> keys) sync* {
    final unique = keys.toSet().toList(growable: false);
    for (var start = 0; start < unique.length; start += 500) {
      yield unique.sublist(start, min(start + 500, unique.length));
    }
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
    // A value that does not open under this device's key (malformed, or
    // sealed under a key since replaced) is treated as absent, so one bad
    // row is skipped instead of failing the whole read.
    try {
      return await cipher.decryptString(value);
    } on FormatException {
      return null;
    } on SecretBoxAuthenticationError {
      return null;
    }
  }

  Future<String> _requireEncryptedValue(String value) async {
    final encrypted = await _encrypt(value);
    return encrypted ?? value;
  }

}
