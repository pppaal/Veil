import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';

import '../support/fake_relay.dart';
import '../support/memory_secure_store.dart';
import '../support/messenger_party.dart';

// The encrypted cache opens asynchronously. Consumers that watched it were
// rebuilt when it did, dropping whatever they held in memory.
void main() {
  late Completer<AppDatabase> database;
  late ProviderContainer container;

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = Completer<AppDatabase>();
    container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(SecureStorageService(MemorySecureStore())),
      appDatabaseFutureProvider.overrideWith((ref) => database.future),
      apiClientProvider.overrideWithValue(VeilApiClient(baseUrl: 'http://relay.invalid/v1')),
      realtimeServiceProvider.overrideWithValue(FakeRelayRealtime()),
      localNotificationServiceProvider.overrideWithValue(RecordingNotifications()),
      cryptoAdapterProvider.overrideWithValue(LibCryptoAdapter()),
    ]);
    addTearDown(container.dispose);
  });

  test('VeilMessengerController constructed once across cache resolution', () async {
    final controller = container.read(messengerControllerProvider);
    final session = container.read(appSessionProvider.notifier);

    database.complete(AppDatabase(NativeDatabase.memory()));
    expect(await container.read(conversationCacheProvider.future), isNotNull);

    expect(container.read(messengerControllerProvider), same(controller));
    expect(container.read(appSessionProvider.notifier), same(session));
  });

  test('cache writes made before the database opens land in it', () async {
    final handle = container.read(cacheHandleProvider)!;
    final written = handle.storeConversations([
      ConversationPreview(
        id: 'conv-early',
        peerHandle: 'selene',
        peerDisplayName: null,
        recipientBundle: const KeyBundle(
          userId: 'user-selene',
          deviceId: '',
          handle: 'selene',
          identityPublicKey: '',
          signedPrekeyBundle: '',
        ),
        lastEnvelope: null,
        updatedAt: DateTime.utc(2026, 4, 1),
      ),
    ]);

    database.complete(AppDatabase(NativeDatabase.memory()));
    await written;

    expect((await handle.readConversations()).single.id, 'conv-early');
  });
}
