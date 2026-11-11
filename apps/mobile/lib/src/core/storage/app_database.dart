import 'package:drift/drift.dart';

part 'app_database.g.dart';

class CachedConversations extends Table {
  TextColumn get id => text()();
  TextColumn get peerUserId => text().nullable()();
  TextColumn get peerHandle => text()();
  TextColumn get peerDisplayName => text().nullable()();
  TextColumn get peerDeviceId => text().nullable()();
  TextColumn get peerIdentityPublicKey => text().nullable()();
  TextColumn get peerSignedPrekeyBundle => text().nullable()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get previewSenderDeviceId => text().nullable()();
  TextColumn get previewCiphertext => text().nullable()();
  TextColumn get previewNonce => text().nullable()();
  TextColumn get previewMessageType => text().nullable()();
  TextColumn get previewAttachmentJson => text().nullable()();
  // Envelope `version` of the preview message (e.g. veil-group-v1). Null for
  // rows written before schema 8; readers fall back to the adapter default.
  TextColumn get previewEnvelopeVersion => text().nullable()();
  DateTimeColumn get previewExpiresAt => dateTime().nullable()();
  TextColumn get sessionLocator => text().nullable()();
  TextColumn get sessionEnvelopeVersion => text().nullable()();
  TextColumn get sessionRequiresLocalPersistence => text().nullable()();
  IntColumn get sessionSchemaVersion => integer().nullable()();
  TextColumn get sessionLocalDeviceId => text().nullable()();
  TextColumn get sessionRemoteDeviceId => text().nullable()();
  TextColumn get sessionRemoteIdentityFingerprint => text().nullable()();
  TextColumn get sessionAuditHint => text().nullable()();
  TextColumn get sessionBootstrappedAt => text().nullable()();
  TextColumn get sessionRemoteIdentityPublicKey => text().nullable()();
  TextColumn get paginationCursor => text().nullable()();
  BoolColumn get hasMoreHistory =>
      boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CachedMessages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId =>
      text().references(CachedConversations, #id)();
  TextColumn get clientMessageId => text().nullable()();
  TextColumn get senderDeviceId => text()();
  TextColumn get ciphertext => text()();
  TextColumn get nonce => text()();
  TextColumn get messageType => text()();
  TextColumn get attachmentJson => text().nullable()();
  TextColumn get envelopeVersion => text().nullable()();
  TextColumn get searchBody => text().nullable()();
  IntColumn get conversationOrder => integer().nullable()();
  DateTimeColumn get receivedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  TextColumn get deliveryState => text().withDefault(const Constant('sent'))();
  DateTimeColumn get deliveredAt => dateTime().nullable()();
  DateTimeColumn get readAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class PendingMessages extends Table {
  TextColumn get clientMessageId => text()();
  TextColumn get conversationId => text()();
  TextColumn get senderDeviceId => text()();
  TextColumn get recipientUserId => text()();
  TextColumn get ciphertext => text()();
  TextColumn get nonce => text()();
  TextColumn get messageType => text()();
  TextColumn get attachmentJson => text().nullable()();
  TextColumn get envelopeVersion => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  TextColumn get errorMessage => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {clientMessageId};
}

// Decrypted content of a message, written by the one decrypt that message
// ever gets (or, for outbound messages, before it is encrypted). Ratchet
// message keys are single-use, so this row is the only way to show the
// message again. body and attachment_json are field-encrypted.
class MessageContents extends Table {
  // Server message id, or 'local:<clientMessageId>' until the relay acks.
  TextColumn get messageKey => text()();
  TextColumn get conversationId => text()();
  TextColumn get clientMessageId => text().nullable()();
  TextColumn get serverMessageId => text().nullable()();
  TextColumn get body => text()();
  TextColumn get attachmentJson => text().nullable()();
  TextColumn get kind => text()();
  // Epoch milliseconds: DateTime columns keep whole seconds, which would let
  // a stored timer end up to a second away from the sealed one.
  IntColumn get innerExpiresAt => integer().nullable()();
  TextColumn get status => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {messageKey};
}

// Messages this device has already expired. Their content is gone and their
// message keys are spent, so a copy the relay serves again (outer expiry
// stripped, or a retention sweep running late) must be dropped, not decrypted
// a second time. Holds ids only and forgets them once the relay can no longer
// hold the ciphertext.
class RetiredMessages extends Table {
  TextColumn get messageKey => text()();
  DateTimeColumn get retiredAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {messageKey};
}

@DriftDatabase(tables: [
  CachedConversations,
  CachedMessages,
  PendingMessages,
  MessageContents,
  RetiredMessages,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
          await _createIndexes();
          await _createRetirementGuard();
        },
        onUpgrade: (migrator, from, to) async {
          if (from < 2) {
            await migrator.createAll();
          }
          if (from < 3) {
            await migrator.addColumn(
                pendingMessages, pendingMessages.nextRetryAt);
          }
          if (from < 4) {
            await customStatement(
              'ALTER TABLE cached_messages ADD COLUMN search_body TEXT',
            );
          }
          if (from < 5) {
            await customStatement('DROP TABLE IF EXISTS pending_messages');
            await customStatement('DROP TABLE IF EXISTS cached_messages');
            await customStatement('DROP TABLE IF EXISTS cached_conversations');
            await migrator.createAll();
          }
          if (from < 6) {
            await customStatement(
              'ALTER TABLE cached_conversations ADD COLUMN session_locator TEXT',
            );
            await customStatement(
              'ALTER TABLE cached_conversations ADD COLUMN session_envelope_version TEXT',
            );
            await customStatement(
              'ALTER TABLE cached_conversations ADD COLUMN session_requires_local_persistence TEXT',
            );
            await customStatement(
              'ALTER TABLE cached_conversations ADD COLUMN session_audit_hint TEXT',
            );
            await customStatement(
              'ALTER TABLE cached_conversations ADD COLUMN session_bootstrapped_at TEXT',
            );
          }
          if (from < 7) {
            await customStatement(
              'ALTER TABLE cached_conversations ADD COLUMN session_schema_version INTEGER',
            );
            await customStatement(
              'ALTER TABLE cached_conversations ADD COLUMN session_local_device_id TEXT',
            );
            await customStatement(
              'ALTER TABLE cached_conversations ADD COLUMN session_remote_device_id TEXT',
            );
            await customStatement(
              'ALTER TABLE cached_conversations ADD COLUMN session_remote_identity_fingerprint TEXT',
            );
          }
          if (from < 8) {
            // Group Sender Keys: cached rows must remember which envelope
            // format a ciphertext uses so a restart routes group frames to
            // the group engine instead of the 1:1 ratchet.
            await customStatement(
              'ALTER TABLE cached_conversations ADD COLUMN preview_envelope_version TEXT',
            );
            await customStatement(
              'ALTER TABLE cached_messages ADD COLUMN envelope_version TEXT',
            );
            await customStatement(
              'ALTER TABLE pending_messages ADD COLUMN envelope_version TEXT',
            );
          }
          if (from < 9) {
            await migrator.createTable(messageContents);
            await migrator.createTable(retiredMessages);
            await migrator.addColumn(
              cachedConversations,
              cachedConversations.sessionRemoteIdentityPublicKey,
            );
            // Search now reads message_contents; drop the old per-message
            // copies of decrypted text instead of leaving them unread.
            await customStatement('UPDATE cached_messages SET search_body = NULL');
            await _createRetirementGuard();
          }
          if (from == 9) {
            // Schema 9 flagged identity changes per conversation; the pin
            // table in the keystore decides them now.
            await customStatement('ALTER TABLE cached_conversations DROP COLUMN identity_mismatch_pending');
          }
          await _createIndexes();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA secure_delete = ON');
        },
      );

  // A decrypt still in flight when its message expired must not write the
  // plaintext back, whichever code path does the insert.
  Future<void> _createRetirementGuard() => customStatement(
        'CREATE TRIGGER IF NOT EXISTS message_contents_skip_retired '
        'BEFORE INSERT ON message_contents '
        'WHEN EXISTS (SELECT 1 FROM retired_messages WHERE message_key = NEW.message_key) '
        'BEGIN SELECT RAISE(IGNORE); END',
      );

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS cached_conversations_updated_idx '
      'ON cached_conversations (updated_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS cached_messages_conversation_received_idx '
      'ON cached_messages (conversation_id, received_at ASC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS cached_messages_conversation_order_idx '
      'ON cached_messages (conversation_id, conversation_order ASC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS cached_messages_client_message_idx '
      'ON cached_messages (client_message_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS pending_messages_state_created_idx '
      'ON pending_messages (state, created_at ASC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS pending_messages_next_retry_idx '
      'ON pending_messages (next_retry_at ASC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS pending_messages_conversation_idx '
      'ON pending_messages (conversation_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS message_contents_conversation_status_idx '
      'ON message_contents (conversation_id, status)',
    );
  }
}
