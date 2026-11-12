import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:veil_mobile/src/app/app_session_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/group_sender_keys.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/network/keys_api.dart';
import 'package:veil_mobile/src/core/notifications/local_notification_service.dart';
import 'package:veil_mobile/src/core/security/local_data_cipher.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_temp_file_store.dart';
import 'package:veil_mobile/src/features/conversations/data/group_sender_key_coordinator.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_peer_bindings.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/envelope_version_policy.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/prekey_maintenance.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import 'counting_crypto_adapter.dart';
import 'fake_relay.dart';
import 'memory_secure_store.dart';

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
/// in-memory SQLite database, a keystore holding its identity pins, and a
/// real VeilMessengerController. `restart` replaces the controller and
/// adapter while keeping the database, the keystore, the persisted ratchet
/// snapshots, the prekeys and the device identity, like an app relaunch.
class MessengerParty {
  MessengerParty._({
    required this.relay,
    required this.device,
    required this.database,
    required this.attachmentDirectory,
    required this.maintainPrekeys,
  });

  /// With [maintainPrekeys] the device publishes one-time prekeys and
  /// rotates its signed prekey whenever it signs in, as the app does. It is
  /// opt-in because generating a pool costs every test that does not need it.
  static Future<MessengerParty> join(
    FakeRelay relay, {
    required String handle,
    required String userId,
    required String deviceId,
    bool maintainPrekeys = false,
  }) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    // The identity comes from the adapter this device first boots with, as
    // on a real phone. A protocol v2 adapter answers PreKey frames only with
    // the identity and prekeys it generated or is handed by its loader, so
    // an identity minted by a throwaway adapter leaves the device unable to
    // accept any session.
    final adapter = LibCryptoAdapter();
    final identity = await adapter.identity.generateDeviceIdentity(deviceId);
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
      maintainPrekeys: maintainPrekeys,
    );
    party._boot(adapter);
    return party;
  }

  final FakeRelay relay;
  final RelayParty device;
  final AppDatabase database;
  final Directory attachmentDirectory;
  final bool maintainPrekeys;
  final SecureStorageService keystore = SecureStorageService(MemorySecureStore());
  final LocalPrekeyStore prekeyStore = InMemoryLocalPrekeyStore();
  late final TrustedIdentityResolver pins =
      TrustedIdentityResolver(store: TrustedIdentityStore(keystore.scoped(SecureScope.identity)));
  final Map<String, Map<String, dynamic>> _ratchetSnapshots = {};
  final RecordingNotifications notifications = RecordingNotifications();

  late LibCryptoAdapter lib;
  late CountingCryptoAdapter crypto;
  late DriftConversationCacheService cache;
  late GroupSenderKeyCoordinator groupCrypto;
  late IdentityTrust trust;
  late VeilMessengerController controller;
  int _tokenGeneration = 0;

  // Bound when the party boots, so a later device move for the same handle
  // leaves this device talking to its own (now silent) socket and client.
  late final FakeRelayClient api = relay.clientFor(device.handle);
  late final FakeRelayRealtime realtime = relay.realtimeFor(device.handle);

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
    _boot(LibCryptoAdapter());
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

  void _boot(LibCryptoAdapter adapter) {
    lib = adapter
      ..setSessionPersistence(
        persister: (conversationId, snapshot) async => _ratchetSnapshots[conversationId] = snapshot,
      )
      ..setLocalPrekeyStore(prekeyStore)
      ..setLocalIdentityLoader(() async => device.identity.identityPrivateKeyRef)
      ..setRemoteIdentityVerifier((claim) => controller.verifyRemoteIdentity(claim));
    crypto = CountingCryptoAdapter(lib);
    cache = DriftConversationCacheService(
      database,
      envelopeCodec: crypto.envelopeCodec,
      cipher: LocalDataCipher.forTesting(_testCacheKey),
    );
    final api = this.api;
    final keys = KeysApi(api, crypto.keyBundles);
    trust = IdentityTrust(pins, decisions: keystore.scoped(SecureScope.identity));
    groupCrypto = GroupSenderKeyCoordinator(
      engine: GroupSenderKeyEngine(),
      sealer: GroupSenderKeySealer(resolveRecipientPrekey: LibIdentityKeys.resolveRemoteX25519),
      apiClient: api,
      keys: keys,
      identityPrivateRefLoader: () async => device.identity.identityPrivateKeyRef,
      localX25519PrivateParser: LibIdentityKeys.localX25519Private,
      localEd25519SeedParser: LibIdentityKeys.localEd25519Seed,
      conversationLookup: (conversationId) => controller.conversationById(conversationId),
      onKeysChanged: (conversationId) => controller.onGroupKeysChanged(conversationId),
      trustCheck: trust.admit,
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
      sessionSnapshotRestorer: () => lib.restoreSessionsFromSnapshots(
        Map<String, Map<String, dynamic>>.of(_ratchetSnapshots),
      ),
      groupCrypto: groupCrypto,
      keysApi: keys,
      identityTrust: trust,
      envelopeVersions: EnvelopeVersionPolicy(store: keystore.scoped(SecureScope.conversationPolicy)),
      peerBindings: ConversationPeerBindings(store: keystore.scoped(SecureScope.conversationPolicy)),
      prekeyMaintenance: maintainPrekeys
          ? PrekeyMaintenance(prekeys: lib, keys: keys, persistIdentityRef: (_) async {})
          : null,
    );
  }
}
