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

@DriftDatabase(tables: [CachedConversations, CachedMessages, PendingMessages])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
          await _createIndexes();
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
          await _createIndexes();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await customStatement('PRAGMA secure_delete = ON');
        },
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
  }
}
