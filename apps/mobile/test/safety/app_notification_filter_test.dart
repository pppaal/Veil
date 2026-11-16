import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_temp_file_store.dart';
import 'package:veil_mobile/src/features/safety/data/conversation_mutes.dart';
import 'package:veil_mobile/src/features/safety/data/safety_providers.dart';

import '../support/async_wait.dart';
import '../support/fake_relay.dart';
import '../support/memory_secure_store.dart';
import '../support/messenger_party.dart';

// The notifications the app's own messenger raises, as messengerControllerProvider
// builds it: no notification for a muted chat, nor for a 1:1 with someone the
// user blocked; every other chat notifies as before.

/// The app's session controller, signed in as alice.
class _Session extends AppSessionController {
  _Session(super.storage, super.api, super.adapter) {
    state = const AppSessionState(
      accessToken: 'token-alice',
      userId: 'user-alice',
      deviceId: 'dev-alice',
      handle: 'alice',
      onboardingAccepted: true,
      privacyConsentAccepted: true,
      locked: false,
      initializing: false,
    );
  }
}

void main() {
  late FakeRelay relay;
  late RecordingNotifications notifications;
  late ProviderContainer container;
  final sealer = createDefaultCryptoAdapter();

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    relay = FakeRelay();
    for (final handle in ['alice', 'bob', 'carol', 'dave']) {
      relay.addParty(RelayParty(
        handle: handle,
        userId: 'user-$handle',
        deviceId: 'dev-$handle',
        identity: await sealer.identity.generateDeviceIdentity('dev-$handle'),
      ));
    }
    relay.addDirect('conv-bob', 'alice', 'bob');
    relay.addDirect('conv-carol', 'alice', 'carol');
    relay.addDirect('conv-dave', 'alice', 'dave');
    relay.addGroup('conv-team', ['alice', 'bob', 'dave'], useSenderKeys: false);

    notifications = RecordingNotifications();
    final storage = SecureStorageService(MemorySecureStore());
    final api = relay.clientFor('alice');
    final adapter = createDefaultCryptoAdapter();
    final attachments = Directory.systemTemp.createTempSync('veil-notification-filter-');
    addTearDown(() => attachments.deleteSync(recursive: true));
    container = ProviderContainer(overrides: [
      attachmentTempFileStoreProvider.overrideWithValue(
        DefaultAttachmentTempFileStore(rootDirectoryFactory: () => attachments),
      ),
      secureStorageProvider.overrideWithValue(storage),
      appDatabaseFutureProvider.overrideWith((ref) async => AppDatabase(NativeDatabase.memory())),
      apiClientProvider.overrideWithValue(api),
      realtimeServiceProvider.overrideWithValue(relay.realtimeFor('alice')),
      localNotificationServiceProvider.overrideWithValue(notifications),
      cryptoAdapterProvider.overrideWithValue(adapter),
      appSessionProvider.overrideWith((ref) => _Session(storage, api, adapter)),
    ]);
    addTearDown(container.dispose);
  });

  // Stored by the relay now, as it took it from [sender].
  Future<Map<String, dynamic>> take(String sender, String conversationId, String body) async {
    final envelope = await sealer.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: 'dev-$sender',
      recipientUserId: 'user-alice',
      body: body,
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-alice',
        deviceId: 'dev-alice',
        handle: 'alice',
        identityPublicKey: 'ik',
        signedPrekeyBundle: 'spk',
      ),
    );
    return relay.inject(
      senderHandle: sender,
      conversationId: conversationId,
      envelope: sealer.envelopeCodec.encodeApiEnvelope(envelope),
    );
  }

  // What the relay pushes to alice's open socket for a message it took.
  Future<void> arrive(Map<String, dynamic> message) async {
    relay.realtimeFor('alice').deliver('message.new', Map<String, dynamic>.of(message));
    await settle();
  }

  test('the app raises no notification for a muted chat or a 1:1 with someone blocked, and does for the rest', () async {
    final messenger = container.read(messengerControllerProvider);
    await waitFor(() => messenger.conversations.length == 4, reason: 'the chats were not listed');

    final mutes = container.read(conversationMutesProvider);
    expect(await mutes.mute('conv-bob', MuteDuration.oneHour), isTrue);
    expect(await mutes.mute('conv-team', MuteDuration.always), isTrue);
    // Carol's message was taken before the block; the relay refuses what
    // she sends after it, but this one still arrives.
    final beforeBlock = await take('carol', 'conv-carol', 'sent before the block');
    expect(await container.read(blockedAccountsProvider).block('user-carol', handle: 'carol'), isTrue);

    await arrive(await take('bob', 'conv-bob', 'while muted'));
    await arrive(await take('dave', 'conv-team', 'in the muted group'));
    await arrive(beforeBlock);
    expect(notifications.shownForConversations, isEmpty, reason: 'a muted or blocked chat notified');
    expect(messenger.messagesFor('conv-carol'), hasLength(1), reason: 'the blocked peer\'s message is kept');

    await arrive(await take('dave', 'conv-dave', 'not muted'));
    expect(notifications.shownForConversations, ['conv-dave']);

    expect(await mutes.unmute('conv-bob'), isTrue);
    await arrive(await take('bob', 'conv-bob', 'unmuted'));
    expect(notifications.shownForConversations, ['conv-dave', 'conv-bob']);
  });
}
