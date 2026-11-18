import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/cache_handle.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';

void main() {
  final record = MessageContentRecord(
    messageKey: 'srv:m-1',
    conversationId: 'conv-1',
    body: 'hello',
    kind: MessageKind.text,
    status: MessageContentStatus.ok,
    createdAt: DateTime.utc(2026, 11, 1),
    updatedAt: DateTime.utc(2026, 11, 1),
  );

  test('a database that cannot be opened leaves the app running without a cache', () async {
    final handle = CacheHandle(() async => throw StateError('the database cannot be opened'));

    expect(await handle.readConversations(), isEmpty);
    expect(await handle.readPendingMessages(), isEmpty);
    await handle.storeConversations(const []);
    // Opened content still reaches the screen for as long as the app runs.
    await handle.put(record);
    expect((await handle.get(record.messageKey))?.body, 'hello');

    // Signing out still clears what this run kept.
    await handle.clearAll();
    expect(await handle.get(record.messageKey), isNull);
  });

  test('without the database no content counts as unqueued: there is no queue to compare it with', () async {
    final handle = CacheHandle(() async => throw StateError('the database cannot be opened'));
    await handle.put(MessageContentRecord(
      messageKey: localMessageContentKey('client-1'),
      conversationId: 'conv-1',
      clientMessageId: 'client-1',
      body: 'never queued',
      kind: MessageKind.text,
      status: MessageContentStatus.ok,
      createdAt: DateTime.utc(2026, 11, 1),
      updatedAt: DateTime.utc(2026, 11, 1),
    ));
    expect(await handle.unqueuedOutbound(), isEmpty);
  });
}
