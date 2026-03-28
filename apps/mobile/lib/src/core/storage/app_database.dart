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

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class CachedMessages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text().references(CachedConversations, #id)();
  TextColumn get senderDeviceId => text()();
  TextColumn get ciphertext => text()();
  TextColumn get nonce => text()();
  TextColumn get messageType => text()();
  TextColumn get attachmentJson => text().nullable()();
  DateTimeColumn get receivedAt => dateTime()();
  DateTimeColumn get expiresAt => dateTime().nullable()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(tables: [CachedConversations, CachedMessages])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
