import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:veil_mobile/src/app/app_session_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/group_sender_keys.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/network/keys_api.dart';
import 'package:veil_mobile/src/core/notifications/local_notification_service.dart';
import 'package:veil_mobile/src/core/security/local_data_cipher.dart';
import 'package:veil_mobile/src/core/storage/app_database.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/core/storage/media_index.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_storage_paths.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_temp_file_store.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_names.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_nicknames.dart';
import 'package:veil_mobile/src/features/conversations/data/group_sender_key_coordinator.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_peer_bindings.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/envelope_version_policy.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/prekey_maintenance.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/features/conversations/presentation/peer_names.dart';
import 'package:veil_mobile/src/features/safety/application/contact_trust.dart';
import 'package:veil_mobile/src/features/safety/application/silenced_notifications.dart';
import 'package:veil_mobile/src/features/safety/application/verified_accounts.dart';
import 'package:veil_mobile/src/features/safety/data/contact_trust_store.dart';

import 'counting_crypto_adapter.dart';
import 'fake_relay.dart';
import 'memory_secure_store.dart';

const _testCacheKey = 'AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8';

/// Records notifications instead of talking to the platform plugin.
class RecordingNotifications implements LocalNotificationService {
  final List<String> shownForConversations = [];
  final List<String> cancelledForConversations = [];

  /// Every notification raised, with the title and body the lock screen
  /// would show.
  final List<({String conversationId, String title, String body})> shown = [];

  @override
  Future<void> showMessageNotification({
    required String conversationId,
    required String title,
    required String body,
  }) async {
    shownForConversations.add(conversationId);
    shown.add((conversationId: conversationId, title: title, body: body));
  }

  @override
  Future<void> cancelConversation(String conversationId) async {
    cancelledForConversations.add(conversationId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The encrypted Drift cache, able to refuse content writes on request, as
/// a full disk or an unavailable keychain would.
class FlakyContentCache extends DriftConversationCacheService {
  FlakyContentCache(super.db, {required super.envelopeCodec, super.cipher});

  int failContentPuts = 0;

  /// How many queued-message writes to refuse next; each refused record is
  /// kept in [refusedPending].
  int failPendingWrites = 0;
  final List<PendingMessageRecord> refusedPending = [];

  /// How many queued-message deletes to refuse next.
  int failPendingRemovals = 0;

  @override
  Future<void> removePendingMessage(String clientMessageId) {
    if (failPendingRemovals > 0) {
      failPendingRemovals -= 1;
      throw StateError('queued message delete failed');
    }
    return super.removePendingMessage(clientMessageId);
  }

  @override
  Future<void> put(MessageContentRecord record) {
    if (failContentPuts > 0) {
      failContentPuts -= 1;
      throw StateError('content write failed');
    }
    return super.put(record);
  }

  @override
  Future<void> upsertPendingMessage(PendingMessageRecord pending) {
    if (failPendingWrites > 0) {
      failPendingWrites -= 1;
      refusedPending.add(pending);
      throw StateError('queued message write failed');
    }
    return super.upsertPendingMessage(pending);
  }
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
    required this.requests,
    required LocalNotificationService Function(RecordingNotifications recorder)? notificationsFor,
  }) : _notificationsFor = notificationsFor;

  /// With [maintainPrekeys] the device publishes one-time prekeys and
  /// rotates its signed prekey whenever it signs in, as the app does. It is
  /// opt-in because generating a pool costs every test that does not need it.
  ///
  /// With [requests] the device keeps message requests as the app does
  /// ([contactTrust], wired to receipts, typing, fetches, sends and
  /// notifications); off by default, so older tests keep their meaning.
  static Future<MessengerParty> join(
    FakeRelay relay, {
    required String handle,
    required String userId,
    required String deviceId,
    bool maintainPrekeys = false,
    bool requests = false,
    LocalNotificationService Function(RecordingNotifications recorder)? notificationsFor,
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
      requests: requests,
      notificationsFor: notificationsFor,
    );
    party._boot(adapter);
    return party;
  }

  final FakeRelay relay;
  final RelayParty device;
  final AppDatabase database;
  final Directory attachmentDirectory;
  final bool maintainPrekeys;
  final bool requests;

  /// The device's attachment folders, every root under [attachmentDirectory]
  /// (the iOS system temporary folder too, swept as on iOS), so purges and
  /// sweeps run for real. Kept across restarts, as the phone's are.
  late final AttachmentStoragePaths attachmentPaths = AttachmentStoragePaths(
    temporaryRoot: () async => Directory('${attachmentDirectory.path}/tmp')..createSync(recursive: true),
    supportRoot: () async => Directory('${attachmentDirectory.path}/support')..createSync(recursive: true),
    systemTempRoot: () => Directory('${attachmentDirectory.path}/system-tmp')..createSync(recursive: true),
    sweepSystemTemp: true,
  );

  /// The media index, kept across restarts as the encrypted database is.
  final MediaIndex mediaIndex = MemoryMediaIndex();
  final SecureStorageService keystore = SecureStorageService(MemorySecureStore());
  final LocalPrekeyStore prekeyStore = InMemoryLocalPrekeyStore();
  late final TrustedIdentityResolver pins =
      TrustedIdentityResolver(store: TrustedIdentityStore(keystore.scoped(SecureScope.identity)));
  final Map<String, Map<String, dynamic>> _ratchetSnapshots = {};
  final RecordingNotifications notifications = RecordingNotifications();

  /// The device's read receipts setting, read on every use as the app's is.
  bool readReceipts = true;

  /// What the messenger raises notifications through, given what records
  /// them (as the app wraps the platform service); the recorder itself
  /// when unset.
  final LocalNotificationService Function(RecordingNotifications recorder)? _notificationsFor;

  /// Ratchet snapshot writes to refuse, as a keychain does once its keys
  /// are evicted after the device locks.
  int failSnapshotWrites = 0;

  late LibCryptoAdapter lib;
  late CountingCryptoAdapter crypto;
  late FlakyContentCache cache;
  late GroupSenderKeyCoordinator groupCrypto;
  late IdentityTrust trust;
  late VeilMessengerController controller;

  /// With [requests]: who each account is and which chats are requests.
  late ContactTrust contactTrust;
  late VerifiedAccounts verifiedAccounts;

  /// The nicknames on this device, kept in its keystore across restarts.
  late final ContactNameBook names = ContactNameBook(ContactNicknames(keystore.scoped(SecureScope.contacts)));

  /// The trust layer's clock; a test moves it to play days passing.
  DateTime Function() clock = DateTime.now;

  /// How many reads of the trust document to refuse next, as a keystore
  /// that cannot be reached does; and the waits before each retry.
  int failTrustReads = 0;
  List<Duration> trustRetryDelays = const [Duration(seconds: 1), Duration(seconds: 5), Duration(seconds: 30)];

  /// The lines the trust layer logged.
  final List<String> trustLog = [];
  int _tokenGeneration = 0;

  /// What the next boot's trust layer runs before it reads anything back,
  /// as the app migrates earlier pins once its database opened. A test that
  /// holds it back sees the trust layer prepare only after sign-in.
  Future<void> Function()? trustPreparation;

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

  /// [whileClosed] runs after the old controller is gone and before the new
  /// one starts: what happens on the relay while the app is not running.
  Future<void> restart({Future<void> Function()? whileClosed}) async {
    await lib.flushPendingSnapshotWrites();
    if (requests) {
      await contactTrust.flush();
      contactTrust.dispose();
    }
    controller.dispose();
    await whileClosed?.call();
    _boot(LibCryptoAdapter());
    await signIn();
  }

  // The in-memory database is left for the garbage collector: a disposed
  // controller may still have a write in flight (a sync it already started),
  // and closing the database under it would turn that write into an
  // unhandled error attributed to whichever test runs next.
  Future<void> dispose() async {
    if (requests) contactTrust.dispose();
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
        persister: (conversationId, snapshot) async {
          if (failSnapshotWrites > 0) {
            failSnapshotWrites -= 1;
            throw StateError('errSecInteractionNotAllowed');
          }
          _ratchetSnapshots[conversationId] = snapshot;
        },
      )
      ..setLocalPrekeyStore(prekeyStore)
      ..setLocalIdentityLoader(() async => device.identity.identityPrivateKeyRef)
      ..setRemoteIdentityVerifier((claim) => controller.verifyRemoteIdentity(claim));
    crypto = CountingCryptoAdapter(lib);
    cache = FlakyContentCache(
      database,
      envelopeCodec: crypto.envelopeCodec,
      cipher: LocalDataCipher.forTesting(_testCacheKey),
    );
    final api = this.api;
    final keys = KeysApi(api, crypto.keyBundles);
    trust = IdentityTrust(pins, decisions: keystore.scoped(SecureScope.identity), prepare: trustPreparation);
    if (requests) {
      verifiedAccounts = VerifiedAccounts(trust);
      contactTrust = ContactTrust(
        store: ContactTrustStore(
          _RefusingReads(keystore.scoped(SecureScope.conversationPolicy), this),
          wipesBegun: () => keystore.wipesBegun,
        ),
        verified: verifiedAccounts,
        clock: () => clock(),
        retryDelays: trustRetryDelays,
        log: trustLog.add,
      );
    }
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
      attachmentTempFileStore: DefaultAttachmentTempFileStore(paths: attachmentPaths),
      attachmentPaths: attachmentPaths,
      mediaIndex: mediaIndex,
      notificationService: _notificationsFor?.call(notifications) ??
          (requests
              ? SilencedNotifications(notifications, isSilenced: (_) => false, isRequest: contactTrust.isRequest)
              : notifications),
      readReceiptsEnabled: () => readReceipts,
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
      withheldByUser: requests ? contactTrust.withholds : null,
      onOwnSend: requests ? contactTrust.noteOwnSend : null,
    );
    if (requests) {
      final controller = this.controller;
      contactTrust.attach(
        controller,
        trustEvents: trust.events,
        savedName: (userId, handle) => peerNamesFor(controller, names.nicknames).accountName(userId, handle),
        nicknames: () => {
          for (final MapEntry(:key, :value) in names.nicknames.entries) key: (name: value.name, userId: value.userId),
        },
        nicknamesChanged: names,
      );
    }
  }

  /// Saves [nickname] for [handle] on this device, naming [userId].
  Future<void> saveNickname(String handle, String nickname, {required String userId}) async {
    await names.write(handle, nickname, anew: true);
    await names.claim({handle.toLowerCase(): userId});
  }
}

// The trust document's keystore scope, refusing reads while the party says.
class _RefusingReads implements IdentityKeyValueBackend {
  _RefusingReads(this._inner, this._party);

  final IdentityKeyValueBackend _inner;
  final MessengerParty _party;

  @override
  Future<String?> read(String key) {
    if (_party.failTrustReads > 0) {
      _party.failTrustReads -= 1;
      throw StateError('keystore unavailable');
    }
    return _inner.read(key);
  }

  @override
  Future<void> write(String key, String value) => _inner.write(key, value);

  @override
  Future<void> delete(String key) => _inner.delete(key);
}
