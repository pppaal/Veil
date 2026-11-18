import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/domain/conversation_read_mark.dart';
import 'package:veil_mobile/src/core/security/local_data_cipher.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_persistence.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_state_store.dart';

// How read marks reach the encrypted cache: through the persistence's
// debounced writer, like paging, with the baseline marker deleted in the
// same write as the marks the first list set.

const _cacheKey = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';

/// The real cache, recording each write and failing the next [failures].
class _Cache extends DriftConversationCacheService {
  _Cache(super.db) : super(envelopeCodec: createDefaultCryptoAdapter().envelopeCodec, cipher: LocalDataCipher.forTesting(_cacheKey));

  final List<ConversationCacheChanges> writes = [];
  int failures = 0;

  @override
  Future<void> writeChanges(ConversationCacheChanges changes) async {
    writes.add(changes);
    if (failures > 0) {
      failures -= 1;
      throw StateError('disk full');
    }
    return super.writeChanges(changes);
  }
}

/// Hears what the store tells observers about read marks.
class _Observer implements MessengerStateObserver, ReadMarkObserver {
  final List<String> marks = [];
  int baselines = 0;

  @override
  void conversationsChanged() {}

  @override
  void messagesChanged(String conversationId) {}

  @override
  void pagingChanged(String conversationId) {}

  @override
  void readMarkChanged(String conversationId) => marks.add(conversationId);

  @override
  void baselineSpent() => baselines += 1;
}

const _short = Duration(milliseconds: 5);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase database;
  late _Cache cache;
  late int listenerCalls;
  late MessengerStateStore store;
  late MessengerPersistence persistence;

  MessengerPersistence persistenceFor(MessengerStateStore store) =>
      MessengerPersistence(cache: cache, store: store, debounce: _short, maxDelay: _short * 4);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    cache = _Cache(database);
    listenerCalls = 0;
    store = MessengerStateStore(onChanged: () => listenerCalls += 1);
    persistence = persistenceFor(store);
    store.addObserver(persistence);
    final cached = await persistence.hydrate();
    store.hydrate(conversations: const [], messages: const {}, snapshot: cached!.snapshot);
  });

  tearDown(() async {
    persistence.dispose();
    await database.close();
  });

  Future<void> debounced() => Future<void>.delayed(_short * 8);

  test('a mark is written by the debounced flush and read back at the next start', () async {
    expect(store.baselinePending, isTrue, reason: 'a new database holds the marker');
    store.setReadMark('conv-1', const ConversationReadMark(readThrough: 7));
    store.setReadMark('conv-2', const ConversationReadMark(readThrough: 3, markedUnread: true));
    expect(cache.writes, isEmpty, reason: 'nothing is written before the debounce');
    await debounced();
    expect(cache.writes, hasLength(1));

    final next = MessengerStateStore(onChanged: () {});
    final reader = persistenceFor(next);
    final cached = await reader.hydrate();
    next.hydrate(conversations: const [], messages: const {}, snapshot: cached!.snapshot);
    expect(next.readMarkOf('conv-1'), const ConversationReadMark(readThrough: 7));
    expect(next.readMarkOf('conv-2'), const ConversationReadMark(readThrough: 3, markedUnread: true));
    expect(next.baselinePending, isTrue, reason: 'no list spent the marker yet');
    reader.dispose();
  });

  test('a mark whose batch failed is written by the next flush', () async {
    cache.failures = 1;
    store.setReadMark('conv-1', const ConversationReadMark(readThrough: 2));
    await debounced();
    expect(cache.writes, hasLength(1));
    expect((await cache.readSnapshot()).readMarks, isEmpty);

    await persistence.flush();
    expect(cache.writes.last.readMarks, {'conv-1': const ConversationReadMark(readThrough: 2)});
    expect((await cache.readSnapshot()).readMarks['conv-1'], const ConversationReadMark(readThrough: 2));
  });

  test('a wipe forgets the marks not yet written', () async {
    store.setReadMark('conv-1', const ConversationReadMark(readThrough: 2));
    await cache.clearAll();
    await persistence.flush();
    await debounced();
    final snapshot = await cache.readSnapshot();
    expect(snapshot.readMarks, isEmpty);
    expect(snapshot.baselinePending, isTrue, reason: 'the wipe puts the marker back');
  });

  test('a new identity starts over: the previous one\'s marks are not written', () async {
    store.setReadMark('conv-1', const ConversationReadMark(readThrough: 2));
    persistence.reset();
    await persistence.flush();
    await debounced();
    expect((await cache.readSnapshot()).readMarks, isEmpty);
  });

  test('setting a mark tells the observers once and asks for one listener call', () async {
    final observer = _Observer();
    store.addObserver(observer);
    listenerCalls = 0;
    store.setReadMark('conv-1', const ConversationReadMark(readThrough: 4));
    store.setReadMark('conv-1', const ConversationReadMark(readThrough: 4));
    expect(observer.marks, ['conv-1'], reason: 'the same mark again changes nothing');
    expect(listenerCalls, 0, reason: 'the listener runs after the step');
    await Future<void>.delayed(Duration.zero);
    expect(listenerCalls, 1);
  });

  test('the marker goes in the same write as the marks the first list set', () async {
    final observer = _Observer();
    store.addObserver(observer);
    store.spendBaseline({
      'conv-1': const ConversationReadMark(readThrough: 5),
      'conv-2': const ConversationReadMark(readThrough: 9),
    });
    expect(store.baselinePending, isFalse);
    expect(observer.baselines, 1);
    await debounced();

    expect(cache.writes, hasLength(1));
    expect(cache.writes.single.consumeBaselineMarker, isTrue);
    expect(cache.writes.single.readMarks.keys.toSet(), {'conv-1', 'conv-2'});
    final snapshot = await cache.readSnapshot();
    expect(snapshot.baselinePending, isFalse);
    expect(snapshot.readMarks, hasLength(2));

    // Spent once: later writes do not delete it again.
    store.setReadMark('conv-1', const ConversationReadMark(readThrough: 6));
    await debounced();
    expect(cache.writes.last.consumeBaselineMarker, isFalse);
  });

  test('an empty first list spends the marker with a write of its own', () async {
    store.spendBaseline(const {});
    await debounced();
    expect(cache.writes.single.consumeBaselineMarker, isTrue);
    expect(cache.writes.single.readMarks, isEmpty);
    expect((await cache.readSnapshot()).baselinePending, isFalse);
  });

  test('a failed write keeps the marker to delete with the next one', () async {
    cache.failures = 1;
    store.spendBaseline({'conv-1': const ConversationReadMark(readThrough: 1)});
    await debounced();
    expect((await cache.readSnapshot()).baselinePending, isTrue);
    await persistence.flush();
    expect(cache.writes.last.consumeBaselineMarker, isTrue);
    expect((await cache.readSnapshot()).baselinePending, isFalse);
  });
}
