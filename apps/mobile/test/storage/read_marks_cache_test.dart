import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/domain/conversation_read_mark.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';

// Read marks in the encrypted cache (Drift): written with the other rows,
// read back in the one snapshot, and the baseline marker kept apart from
// them.

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  late AppDatabase database;
  late DriftConversationCacheService cache;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    cache = DriftConversationCacheService(database, envelopeCodec: createDefaultCryptoAdapter().envelopeCodec);
  });

  tearDown(() => database.close());

  test('marks written with writeChanges come back with readSnapshot, updated in place', () async {
    await cache.writeChanges(const ConversationCacheChanges(readMarks: {
      'conv-1': ConversationReadMark(readThrough: 12),
      'conv-2': ConversationReadMark(markedUnread: true),
    }));
    var snapshot = await cache.readSnapshot();
    expect(snapshot.readMarks, {
      'conv-1': const ConversationReadMark(readThrough: 12),
      'conv-2': const ConversationReadMark(markedUnread: true),
    });

    await cache.writeChanges(const ConversationCacheChanges(readMarks: {
      'conv-2': ConversationReadMark(readThrough: 4),
    }));
    snapshot = await cache.readSnapshot();
    expect(snapshot.readMarks['conv-2'], const ConversationReadMark(readThrough: 4));
    expect(snapshot.readMarks['conv-1'], const ConversationReadMark(readThrough: 12));
  });

  test('the marker reads as baselinePending, never as a mark, and goes in the write that consumes it', () async {
    var snapshot = await cache.readSnapshot();
    expect(snapshot.baselinePending, isTrue, reason: 'a new database holds the marker');
    expect(snapshot.readMarks, isEmpty);
    expect(snapshot.readMarks.containsKey(baselineReadMarkId), isFalse);

    // Nothing writes a mark under the marker's id.
    await cache.writeChanges(const ConversationCacheChanges(readMarks: {
      baselineReadMarkId: ConversationReadMark(readThrough: 3),
      'conv-1': ConversationReadMark(readThrough: 3),
    }));
    snapshot = await cache.readSnapshot();
    expect(snapshot.baselinePending, isTrue);
    expect(snapshot.readMarks.keys, ['conv-1']);

    await cache.writeChanges(const ConversationCacheChanges(
      readMarks: {'conv-2': ConversationReadMark(readThrough: 8)},
      consumeBaselineMarker: true,
    ));
    snapshot = await cache.readSnapshot();
    expect(snapshot.baselinePending, isFalse);
    expect(snapshot.readMarks.keys.toSet(), {'conv-1', 'conv-2'});
  });

  test('a change that only consumes the marker is not empty', () {
    expect(const ConversationCacheChanges().isEmpty, isTrue);
    expect(const ConversationCacheChanges(consumeBaselineMarker: true).isEmpty, isFalse);
    expect(const ConversationCacheChanges(readMarks: {'conv-1': ConversationReadMark()}).isEmpty, isFalse);
  });

  test('clearAll forgets every mark and brings the marker back', () async {
    await cache.writeChanges(const ConversationCacheChanges(
      readMarks: {'conv-1': ConversationReadMark(readThrough: 2)},
      consumeBaselineMarker: true,
    ));
    expect((await cache.readSnapshot()).baselinePending, isFalse);

    await cache.clearAll();
    final snapshot = await cache.readSnapshot();
    expect(snapshot.readMarks, isEmpty);
    expect(snapshot.baselinePending, isTrue);
  });
}
