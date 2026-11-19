import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/core/storage/media_index.dart';

// Schema 12: the read marks and the media index, the baseline marker row,
// and the upgrade from 11 that seeds each conversation's mark from what is
// already on the phone.

const _newTables = ['conversation_read_marks', 'media_blobs'];

/// What a schema 11 database holds: today's schema without the two tables
/// schema 12 added (and their indexes) and without the queue number schema
/// 13 added to pending_messages.
Future<List<String>> _schema11() async {
  final current = AppDatabase(NativeDatabase.memory());
  final rows = await current
      .customSelect("SELECT type, name, tbl_name, sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' "
          "ORDER BY CASE type WHEN 'table' THEN 0 WHEN 'index' THEN 1 ELSE 2 END")
      .get();
  await current.close();
  final statements = [
    for (final row in rows)
      if (!_newTables.contains(row.data['tbl_name']))
        (row.data['sql'] as String).replaceFirst(RegExp(r'"queue_order" INTEGER NOT NULL DEFAULT 0,\s*'), ''),
  ];
  expect(statements.join(), isNot(contains('conversation_read_marks')));
  expect(statements.join(), isNot(contains('media_blobs')));
  expect(statements.join(), isNot(contains('queue_order')));
  return statements;
}

Future<Set<String>> _tables(AppDatabase database) async => {
      for (final row in await database.customSelect("SELECT name FROM sqlite_master WHERE type = 'table'").get())
        row.data['name'] as String,
    };

Future<Map<String, int?>> _marks(AppDatabase database) async => {
      for (final row in await database
          .customSelect('SELECT conversation_id, read_through_order, marked_unread FROM conversation_read_marks')
          .get())
        row.data['conversation_id'] as String: row.data['read_through_order'] as int?,
    };

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  test('the upgrade from 11 creates both tables, seeds each mark with its newest order, and writes the marker', () async {
    final schema11 = await _schema11();
    final legacy = AppDatabase(NativeDatabase.memory(setup: (raw) {
      for (final statement in schema11) {
        raw.execute(statement);
      }
      for (final id in ['conv-sam', 'conv-mia', 'conv-empty', 'conv-unordered']) {
        raw.execute("INSERT INTO cached_conversations (id, peer_handle, updated_at) VALUES ('$id', 'h', 1)");
      }
      void message(String id, String conversation, int? order) => raw.execute(
            'INSERT INTO cached_messages (id, conversation_id, sender_device_id, ciphertext, nonce, message_type, '
            "conversation_order, received_at) VALUES ('$id', '$conversation', 'd', 'c', 'n', 'text', "
            "${order ?? 'NULL'}, 1)",
          );
      message('m1', 'conv-sam', 3);
      message('m2', 'conv-sam', 17);
      message('m3', 'conv-sam', null); // a local notice has no order
      message('m4', 'conv-sam', 9);
      message('m5', 'conv-mia', 1);
      message('m6', 'conv-unordered', null);
      raw.execute('PRAGMA user_version = 11');
    }));
    addTearDown(legacy.close);

    expect(await _tables(legacy), containsAll(_newTables));
    expect(await _marks(legacy), {
      'conv-sam': 17,
      'conv-mia': 1,
      baselineReadMarkId: null,
    });
    final marker = await legacy
        .customSelect("SELECT marked_unread FROM conversation_read_marks WHERE conversation_id = '$baselineReadMarkId'")
        .getSingle();
    expect(marker.data['marked_unread'], 0);
    final mediaIndexes = await legacy
        .customSelect("SELECT sql FROM sqlite_master WHERE tbl_name = 'media_blobs' AND type IN ('table', 'index')")
        .get();
    expect(mediaIndexes.map((row) => row.data['sql']).join(), contains('UNIQUE ("conversation_id", "attachment_id", "digest")'));
    // The upgrade went on to 13: the queue number is there too.
    final pendingColumns = await legacy.customSelect('PRAGMA table_info(pending_messages)').get();
    expect(pendingColumns.map((row) => row.data['name']), contains('queue_order'));
    // What was there before still reads.
    final cache = DriftConversationCacheService(legacy, envelopeCodec: createDefaultCryptoAdapter().envelopeCodec);
    expect((await cache.readMessages('conv-sam')).map((message) => message.id), containsAll(['m1', 'm2', 'm3', 'm4']));
  });

  test('a fresh database has both tables and the marker', () async {
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    expect(await _tables(fresh), containsAll(_newTables));
    expect(await _marks(fresh), {baselineReadMarkId: null});
    expect(await fresh.select(fresh.mediaBlobs).get(), isEmpty);
  });

  test('clearAll empties both tables and leaves only the marker', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final cache = DriftConversationCacheService(database, envelopeCodec: createDefaultCryptoAdapter().envelopeCodec);
    await database.customStatement('DELETE FROM conversation_read_marks');
    await database.customStatement(
      "INSERT INTO conversation_read_marks (conversation_id, read_through_order, marked_unread) VALUES ('conv-sam', 4, 1)",
    );
    await DriftMediaIndex(database).put(MediaIndexEntry(
      fileName: 'a' * 64,
      conversationId: 'conv-sam',
      attachmentId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
      digest: 'd',
      sizeBytes: 10,
      lastUsedAt: DateTime.utc(2026, 4, 7),
    ));

    await cache.clearAll();

    expect(await _marks(database), {baselineReadMarkId: null});
    expect(await database.select(database.mediaBlobs).get(), isEmpty);
    // A second wipe keeps one marker.
    await cache.clearAll();
    expect(await _marks(database), {baselineReadMarkId: null});
  });

  test('the media index round-trips on the database', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final index = DriftMediaIndex(database);
    const photo = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
    const file = '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d';
    final used = DateTime.utc(2026, 4, 7, 9, 0, 0, 123);
    final first = MediaIndexEntry(
      fileName: 'a' * 64,
      conversationId: 'Conv-Sam',
      attachmentId: photo.toUpperCase(),
      digest: 'digest-one',
      sizeBytes: 1024,
      lastUsedAt: used,
    );
    await index.put(first);
    await index.put(MediaIndexEntry(
      fileName: 'b' * 64,
      conversationId: 'conv-sam',
      attachmentId: file,
      digest: 'digest-two',
      sizeBytes: 2048,
      expiresAt: DateTime.utc(2026, 4, 8),
      lastUsedAt: used,
    ));

    final found = (await index.find('conv-sam', photo, 'digest-one'))!;
    expect(found.conversationId, 'conv-sam');
    expect(found.attachmentId, photo);
    expect(found.sizeBytes, 1024);
    expect(found.expiresAt, isNull);
    expect(found.lastUsedAt.isAtSameMomentAs(used), isTrue, reason: 'kept to the millisecond');
    expect(await index.find('CONV-SAM', photo.toUpperCase(), 'digest-one'), isNotNull);
    expect(await index.find('conv-sam', photo, 'digest-other'), isNull);

    final expiry = DateTime.utc(2026, 4, 9, 12, 30, 0, 456);
    await index.setExpiry('conv-sam', photo, expiry);
    expect((await index.find('conv-sam', photo, 'digest-one'))!.expiresAt!.isAtSameMomentAs(expiry), isTrue);
    await index.setExpiry('conv-sam', photo, null);
    expect((await index.find('conv-sam', photo, 'digest-one'))!.expiresAt, isNull);

    final later = used.add(const Duration(minutes: 3));
    await index.touch('a' * 64, later);
    expect((await index.find('conv-sam', photo, 'digest-one'))!.lastUsedAt.isAtSameMomentAs(later), isTrue);

    // The same blob indexed again under a new file replaces the old row.
    await index.put(MediaIndexEntry(
      fileName: 'c' * 64,
      conversationId: 'conv-sam',
      attachmentId: photo,
      digest: 'digest-one',
      sizeBytes: 1024,
      lastUsedAt: later,
    ));
    expect((await index.all()).map((entry) => entry.fileName), unorderedEquals(['b' * 64, 'c' * 64]));

    await index.remove('b' * 64);
    expect((await index.all()).single.fileName, 'c' * 64);
    await index.clear();
    expect(await index.all(), isEmpty);
  });

  test('a deferred index uses the database once it opens, and memory while it cannot', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    var available = false;
    final index = DeferredMediaIndex(() async => available ? database : throw StateError('locked'));
    final entry = MediaIndexEntry(
      fileName: 'd' * 64,
      conversationId: 'conv-sam',
      attachmentId: '3f2504e0-4f89-41d3-9a0c-0305e82c3301',
      digest: 'd',
      sizeBytes: 1,
      lastUsedAt: DateTime.utc(2026, 4, 7),
    );
    await index.put(entry);
    expect(await index.all(), [entry]);
    expect(await database.select(database.mediaBlobs).get(), isEmpty);

    available = true;
    await index.put(entry.copyWith(lastUsedAt: DateTime.utc(2026, 4, 8)));
    expect((await database.select(database.mediaBlobs).get()).single.fileName, 'd' * 64);
  });
}
