import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:veil_mobile/src/app/app_session_state.dart';
import 'package:veil_mobile/src/core/crypto/group_sender_keys.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/notifications/local_notification_service.dart';
import 'package:veil_mobile/src/core/security/local_data_cipher.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_temp_file_store.dart';
import 'package:veil_mobile/src/features/conversations/data/group_sender_key_coordinator.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import 'counting_crypto_adapter.dart';
import 'fake_relay.dart';

const _testCacheKey = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';

/// Records notifications instead of talking to the platform plugin.
class RecordingNotifications implements LocalNotificationService {
  final List<String> shownForConversations = [];

  @override
  Future<void> showMessageNotification({
    required String conversationId,
    required String title,
    required String body,
  }) async {
    shownForConversations.add(conversationId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One device on the fake relay: its own LibCryptoAdapter (and therefore its
/// own identity and ratchet state), an encrypted Drift cache over an
/// in-memory SQLite database, and a real VeilMessengerController. `restart`
/// replaces the controller and adapter while keeping the database and the
/// persisted ratchet snapshots, like an app relaunch.
class MessengerParty {
  MessengerParty._({
    required this.relay,
    required this.device,
    required this.database,
    required this.attachmentDirectory,
  });

  static Future<MessengerParty> join(
    FakeRelay relay, {
    required String handle,
    required String userId,
    required String deviceId,
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final identity = await LibCryptoAdapter().identity.generateDeviceIdentity(deviceId);
    final device = relay.addParty(RelayParty(
      handle: handle,
      userId: userId,
      deviceId: deviceId,
      identity: identity,
    ));
    final party = MessengerParty._(
      relay: relay,
      device: device,
      database: AppDatabase(NativeDatabase.memory()),
      attachmentDirectory: Directory.systemTemp.createTempSync('veil-party-$handle-'),
    );
    party._boot();
    return party;
  }

  final FakeRelay relay;
  final RelayParty device;
  final AppDatabase database;
  final Directory attachmentDirectory;
  final Map<String, Map<String, dynamic>> _ratchetSnapshots = {};
  final RecordingNotifications notifications = RecordingNotifications();

  late LibCryptoAdapter lib;
  late CountingCryptoAdapter crypto;
  late DriftConversationCacheService cache;
  late GroupSenderKeyCoordinator groupCrypto;
  late VeilMessengerController controller;
  int _tokenGeneration = 0;

  FakeRelayClient get api => relay.clientFor(device.handle);
  FakeRelayRealtime get realtime => relay.realtimeFor(device.handle);

  AppSessionState session({String? token}) => AppSessionState(
        accessToken: token ?? 'token-${device.handle}-$_tokenGeneration',
        userId: device.userId,
        deviceId: device.deviceId,
        handle: device.handle,
        displayName: device.handle,
        onboardingAccepted: true,
        locked: false,
        initializing: false,
      );

  Future<void> signIn() => controller.applySession(session());

  /// Same identity, new access token: what an automatic 401 refresh does.
  Future<void> refreshToken() {
    _tokenGeneration += 1;
    return controller.applySession(session());
  }

  Future<void> restart() async {
    await lib.flushPendingSnapshotWrites();
    controller.dispose();
    _boot();
    await signIn();
  }

  // The in-memory database is left for the garbage collector: a disposed
  // controller may still have a write in flight (a sync it already started),
  // and closing the database under it would turn that write into an
  // unhandled error attributed to whichever test runs next.
  Future<void> dispose() async {
    controller.dispose();
    if (attachmentDirectory.existsSync()) {
      attachmentDirectory.deleteSync(recursive: true);
    }
  }

  /// Bodies of every message in [conversationId], read the way the chat
  /// screen reads them.
  Future<List<String>> bodies(String conversationId) async {
    final messages = controller.messagesFor(conversationId);
    final decrypted = await Future.wait(messages.map(controller.decryptMessage));
    return decrypted.map((message) => message.body).toList();
  }

  void _boot() {
    lib = LibCryptoAdapter()
      ..setSessionPersistence(
        persister: (conversationId, snapshot) async => _ratchetSnapshots[conversationId] = snapshot,
      );
    crypto = CountingCryptoAdapter(lib);
    cache = DriftConversationCacheService(
      database,
      envelopeCodec: crypto.envelopeCodec,
      cipher: LocalDataCipher.forTesting(_testCacheKey),
    );
    final api = this.api;
    groupCrypto = GroupSenderKeyCoordinator(
      engine: GroupSenderKeyEngine(),
      sealer: GroupSenderKeySealer(resolveRecipientPrekey: LibIdentityKeys.resolveRemoteX25519),
      apiClient: api,
      keyBundleCodec: crypto.keyBundles,
      identityPrivateRefLoader: () async => device.identity.identityPrivateKeyRef,
      localX25519PrivateParser: LibIdentityKeys.localX25519Private,
      localEd25519SeedParser: LibIdentityKeys.localEd25519Seed,
    );
    controller = VeilMessengerController(
      apiClient: api,
      cryptoEngine: crypto.messaging,
      keyBundleCodec: crypto.keyBundles,
      envelopeCodec: crypto.envelopeCodec,
      sessionBootstrapper: crypto.sessions,
      realtimeService: realtime,
      cacheService: cache,
      attachmentTempFileStore: DefaultAttachmentTempFileStore(
        rootDirectoryFactory: () => attachmentDirectory,
      ),
      notificationService: notifications,
      identityPrivateRefLoader: () async => device.identity.identityPrivateKeyRef,
      sessionSnapshotRestorer: () => lib.restoreSessionsFromSnapshots(
        Map<String, Map<String, dynamic>>.of(_ratchetSnapshots),
      ),
      groupCrypto: groupCrypto,
    );
  }
}
