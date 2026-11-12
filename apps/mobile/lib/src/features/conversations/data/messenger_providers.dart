import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/app_session_state.dart';
import '../../../app/session/session_providers.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/crypto/group_sender_keys.dart';
import '../../../core/crypto/lib_crypto_adapter.dart';
import '../../../core/di/core_providers.dart';
import '../../../core/identity/trusted_identity_resolver.dart';
import '../../../core/identity/trusted_identity_store.dart';
import '../../../core/network/keys_api.dart';
import '../../../core/storage/secure_storage_service.dart';
import '../../attachments/data/attachment_providers.dart';
import '../../device_transfer/data/device_transfer_providers.dart';
import '../../settings/data/privacy_preferences_provider.dart';
import 'group_sender_key_coordinator.dart';
import 'messenger/conversation_peer_bindings.dart';
import 'messenger/envelope_version_policy.dart';
import 'messenger/identity_trust.dart';
import 'messenger/legacy_trust_migration.dart';
import 'messenger/prekey_maintenance.dart';
import 'veil_messenger_controller.dart';

final keysApiProvider = Provider<KeysApi>((ref) {
  return KeysApi(ref.read(apiClientProvider), ref.read(cryptoAdapterProvider).keyBundles);
});

/// Contact identity pins, and the identity changes the user has not decided
/// yet or declined, kept in the keystore and wiped with the device.
/// What earlier builds knew is migrated in before any decision is made,
/// reading the cache directly: the messenger decrypts and looks keys up as
/// soon as it applies a session. A cache that cannot be read fails the
/// migration (to be tried again) rather than reading as empty, which would
/// finish it with nothing carried over.
final identityTrustProvider = Provider<IdentityTrust>((ref) {
  final storage = ref.read(secureStorageProvider);
  final resolver = TrustedIdentityResolver(store: TrustedIdentityStore(storage.scoped(SecureScope.identity)));
  final trust = IdentityTrust(
    resolver,
    decisions: storage.scoped(SecureScope.identity),
    prepare: () => migrateLegacyTrust(
      storage: storage,
      resolver: resolver,
      readConversations: () async {
        final cache = await openConversationCache(ref);
        return cache == null ? const [] : cache.readConversations();
      },
    ),
  );
  ref.onDispose(trust.dispose);
  return trust;
});

final messengerControllerProvider =
    ChangeNotifierProvider<VeilMessengerController>((ref) {
  final notificationService = ref.read(localNotificationServiceProvider);
  final secureStorage = ref.read(secureStorageProvider);
  final cryptoAdapter = ref.read(cryptoAdapterProvider);
  final keys = ref.read(keysApiProvider);
  final trust = ref.read(identityTrustProvider);
  final privacy = ref.read(privacyPreferencesProvider);
  // Bound below; the group coordinator reaches the controller only after
  // both exist.
  late final VeilMessengerController controller;

  // Double Ratchet session persistence: wire the adapter's after-mutate
  // callback to secure storage, and build a restorer that rehydrates
  // snapshots into memory on first authenticated applySession.
  Future<void> Function()? sessionRestorer;
  GroupSenderKeyCoordinator? groupCrypto;
  // Adapters that publish their own prekeys keep the directory stocked.
  final prekeyMaintenance = cryptoAdapter is PrekeyManager
      ? PrekeyMaintenance(
          prekeys: cryptoAdapter as PrekeyManager,
          keys: keys,
          persistIdentityRef: secureStorage.replaceIdentityPrivateRef,
        )
      : null;
  if (cryptoAdapter is LibCryptoAdapter) {
    cryptoAdapter
      ..setSessionPersistence(
        persister: (conversationId, snapshot) =>
            secureStorage.writeSessionSnapshot(conversationId, snapshot),
      )
      // The responder side of the v2 handshake needs the persisted identity
      // and the prekey private halves it published.
      ..setLocalIdentityLoader(() => secureStorage.readIdentityPrivateRef())
      ..setLocalPrekeyStore(SecureStorageLocalPrekeyStore(secureStorage))
      // Inbound handshakes face the same identity pins as outbound ones.
      ..setRemoteIdentityVerifier((claim) => controller.verifyRemoteIdentity(claim));

    // Group Sender Keys ride on the same identity material as the 1:1
    // ratchet (X25519 prekey for sealing, Ed25519 identity for authorship),
    // so they are only wired when the lib adapter is active.
    final groupEngine = GroupSenderKeyEngine(
      persister: (groupId, snapshot) =>
          secureStorage.writeGroupSenderKeySnapshot(groupId, snapshot),
    );
    groupCrypto = GroupSenderKeyCoordinator(
      engine: groupEngine,
      sealer: GroupSenderKeySealer(
        resolveRecipientPrekey: LibIdentityKeys.resolveRemoteX25519,
      ),
      apiClient: ref.read(apiClientProvider),
      keys: keys,
      identityPrivateRefLoader: () => secureStorage.readIdentityPrivateRef(),
      localX25519PrivateParser: LibIdentityKeys.localX25519Private,
      localEd25519SeedParser: LibIdentityKeys.localEd25519Seed,
      conversationLookup: (conversationId) => controller.conversationById(conversationId),
      onKeysChanged: (conversationId) => controller.onGroupKeysChanged(conversationId),
      trustCheck: trust.admit,
    );

    sessionRestorer = () async {
      final snapshots = await secureStorage.readAllSessionSnapshots();
      if (snapshots.isNotEmpty) {
        await cryptoAdapter.restoreSessionsFromSnapshots(snapshots);
      }
      final groupSnapshots = await secureStorage.readAllGroupSenderKeySnapshots();
      if (groupSnapshots.isNotEmpty) {
        await groupEngine.restoreFromSnapshots(groupSnapshots);
      }
    };
  }

  controller = VeilMessengerController(
    apiClient: ref.read(apiClientProvider),
    cryptoEngine: ref.read(messagingCryptoProvider),
    keyBundleCodec: cryptoAdapter.keyBundles,
    envelopeCodec: cryptoAdapter.envelopeCodec,
    sessionBootstrapper: cryptoAdapter.sessions,
    realtimeService: ref.read(realtimeServiceProvider),
    // A stable handle, read lazily: watching the cache provider rebuilt the
    // controller once the database opened, which dropped in-flight state
    // such as attachment transfers.
    cacheService: ref.read(cacheHandleProvider),
    attachmentTempFileStore: ref.read(attachmentTempFileStoreProvider),
    notificationService: notificationService,
    onSecurityException: (error) async {
      await ref
          .read(appSessionProvider.notifier)
          .handleSecurityException(error);
    },
    sessionSnapshotRestorer: sessionRestorer,
    groupCrypto: groupCrypto,
    readReceiptsEnabled: () => privacy.sendReadReceipts,
    typingIndicatorsEnabled: () => privacy.sendTypingIndicators,
    keysApi: keys,
    identityTrust: trust,
    envelopeVersions: EnvelopeVersionPolicy(store: secureStorage.scoped(SecureScope.conversationPolicy)),
    peerBindings: ConversationPeerBindings(store: secureStorage.scoped(SecureScope.conversationPolicy)),
    prekeyMaintenance: prekeyMaintenance,
    deviceTransfer: ref.read(deviceTransferControllerProvider),
  );

  final pushCoordinator = ref.read(pushTokenCoordinatorProvider);

  ref.listen<AppSessionState>(appSessionProvider, (previous, next) {
    unawaited(controller.applySession(next));
    final wasAuthed = previous?.isAuthenticated ?? false;
    if (next.isAuthenticated && next.accessToken != null) {
      unawaited(pushCoordinator.bind(next.accessToken!));
    } else if (wasAuthed && !next.isAuthenticated) {
      unawaited(pushCoordinator.unbind());
    }
  });

  final initial = ref.read(appSessionProvider);
  unawaited(controller.applySession(initial));
  if (initial.isAuthenticated && initial.accessToken != null) {
    unawaited(pushCoordinator.bind(initial.accessToken!));
  }
  // ChangeNotifierProvider disposes the controller itself; a second dispose
  // here used to trip ChangeNotifier's disposed assertion.
  return controller;
});
