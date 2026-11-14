import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:veil_mobile/src/app/app_state.dart';
import 'package:veil_mobile/src/app/router/app_router.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart' show LibCryptoAdapter;
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/security/app_lock_service.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_peer_bindings.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_providers.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../../support/fake_relay.dart';
import '../../support/memory_secure_store.dart';
import 'layout_seed.dart';

// The app as one layout case sees it: the real route table, theme and
// localizations over the test fakes (FakeRelay, a mock-keyed messenger,
// memory stores), signed in as atlas or signed out, with seeded content.

const selfHandle = 'atlas';
const peerHandle = 'selene';

/// The conversation the chat, safety-number and attachment cases open.
const chatConversationId = 'conv-selene';

/// A peer nobody has written to yet, and the conversation with them.
const emptyChatPeerHandle = 'mira';
const emptyChatConversationId = 'conv-$emptyChatPeerHandle';

/// The conversation whose messages disappear after a day.
const timerChatPeerHandle = 'rowan';
const timerChatConversationId = 'conv-$timerChatPeerHandle';

/// Real identity keys, generated once per run: safety numbers take 32-byte
/// keys, and generating them costs real time no single case should pay.
class LayoutIdentities {
  LayoutIdentities._(this.adapter, this.self, this.peer);

  /// VEIL's own adapter, so the security screens name the crypto a real
  /// build runs. Only its identity half is used here.
  final LibCryptoAdapter adapter;
  final DeviceIdentityMaterial self;
  final DeviceIdentityMaterial peer;

  static Future<LayoutIdentities> generate() async {
    final adapter = LibCryptoAdapter();
    return LayoutIdentities._(
      adapter,
      await adapter.identity.generateDeviceIdentity('dev-$selfHandle'),
      await LibCryptoAdapter().identity.generateDeviceIdentity('dev-$peerHandle'),
    );
  }
}

/// What the account looks like when a case opens its screen.
enum LayoutAccount {
  /// No account on this device yet; consent and onboarding not accepted.
  signedOut,

  /// Signed in and unlocked, with conversations.
  signedIn,

  /// Signed in and unlocked, with no conversation yet.
  signedInEmpty,

  /// Signed in, behind the app lock.
  locked,
}

/// Things a chat can be asked to show on top of its messages.
class ChatAttention {
  const ChatAttention({this.identityChanged = false, this.failedSends = 0, this.accountHeld = false});

  /// The peer's identity key changed and the user has not reviewed it.
  final bool identityChanged;

  /// Messages of ours that did not go out.
  final int failedSends;

  /// The chat is listed under the peer's handle with another account than
  /// the one this device talked to, and waits for the user to say so.
  final bool accountHeld;
}

class LayoutWorld {
  LayoutWorld._(this.identities, this.account, this.locale);

  final LayoutIdentities identities;
  final LayoutAccount account;
  final String locale;

  final FakeRelay relay = FakeRelay();
  final SecureStorageService storage = _PinSetStorage(MemorySecureStore());
  final LayoutMemoryCache cache = LayoutMemoryCache();
  late final LayoutRelayClient api;
  late final IdentityTrust trust;
  late final VeilMessengerController messenger;
  late final ProviderContainer container;
  GoRouter? _router;

  bool get _hasAccount => account != LayoutAccount.signedOut;

  AppSessionState get _session => switch (account) {
        LayoutAccount.signedOut => const AppSessionState(locked: false, initializing: false),
        _ => AppSessionState(
            accessToken: 'token-$selfHandle',
            userId: 'user-$selfHandle',
            deviceId: 'dev-$selfHandle',
            handle: selfHandle,
            displayName: 'Atlas Moreau',
            onboardingAccepted: true,
            privacyConsentAccepted: true,
            locked: account == LayoutAccount.locked,
            initializing: false,
          ),
      };

  static Future<LayoutWorld> create({
    required LayoutIdentities identities,
    required LayoutAccount account,
    required String locale,
    ChatAttention attention = const ChatAttention(),
    bool bootstrapping = false,
    bool transferStarted = false,
  }) async {
    final world = LayoutWorld._(identities, account, locale);
    await world._build(attention: attention, bootstrapping: bootstrapping, transferStarted: transferStarted);
    return world;
  }

  Future<void> _build({
    required ChatAttention attention,
    required bool bootstrapping,
    required bool transferStarted,
  }) async {
    seedParties(relay, identities);
    if (account == LayoutAccount.signedIn || account == LayoutAccount.locked) {
      await seedConversations(relay, cache, locale: locale);
    }
    api = LayoutRelayClient(relay, relay.partiesByHandle[selfHandle]!, locale: locale);

    if (_hasAccount) {
      await storage.persistDeviceSecretRefs(
        identityPrivateRef: identities.self.identityPrivateKeyRef,
        authPrivateKey: 'auth',
        authPublicKey: 'auth-pub',
      );
    }
    trust = IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(InMemoryIdentityKeyValueBackend())));
    // The chat's peer was compared out of band, so the chat shows its mark.
    final peer = relay.partiesByHandle[peerHandle]!;
    await trust.resolver.evaluate(peer.userId, peer.deviceId, peer.identity.identityPublicKey);
    await trust.markVerified(peer.userId, peer.deviceId, peer.identity.identityPublicKey);

    // The idempotent mock engine: layout does not depend on the ratchet,
    // and this device's own messages are read from stored content anyway.
    final mock = createDefaultCryptoAdapter();
    messenger = _LayoutMessenger(
      apiClient: api,
      adapter: mock,
      realtime: relay.realtimeFor(selfHandle),
      cache: cache,
      trust: trust,
      attention: attention,
      peer: peer,
    );
    if (_hasAccount) await messenger.applySession(_session);

    final session = _LayoutSession(storage, api, identities.adapter, _session, bootstrapping: bootstrapping);
    container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(api),
      cryptoAdapterProvider.overrideWithValue(identities.adapter),
      appSessionProvider.overrideWith((ref) => session),
      messengerControllerProvider.overrideWith((ref) => messenger),
      identityTrustProvider.overrideWithValue(trust),
      conversationCacheProvider.overrideWith((ref) async => null),
      appLockServiceProvider.overrideWithValue(AppLockService(const _Biometrics(), storage)),
      localSecuritySnapshotProvider.overrideWith(
        (ref) async => const LocalSecuritySnapshot(
          hasDeviceSecretRefs: true,
          hasPin: true,
          biometricsAvailable: true,
          integrityCompromised: false,
          integrityReasons: [],
          screenCaptureProtectionSupported: true,
          screenCaptureProtectionEnabled: true,
          appPreviewProtectionEnabled: true,
        ),
      ),
    ]);
    if (transferStarted) await container.read(deviceTransferControllerProvider).initTransfer();
  }

  /// The app at [location]: the real route table (so tab screens get their
  /// bottom bar), the dark theme the product is designed in, [locale].
  /// [extraRoutes] reach screens no route leads to yet.
  Widget app({required String location, Object? extra, List<RouteBase> extraRoutes = const []}) {
    final router = _router = GoRouter(
      initialLocation: location,
      initialExtra: extra,
      routes: [...container.read(appRoutesProvider), ...extraRoutes],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        title: 'VEIL',
        theme: VeilTheme.light(),
        darkTheme: VeilTheme.dark(),
        themeMode: ThemeMode.dark,
        debugShowCheckedModeBanner: false,
        locale: Locale(locale),
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
  }

  /// Call once the widget tree is gone.
  void dispose() {
    _router?.dispose();
    // A provider disposes what it handed out; a screen that never asked
    // for the messenger leaves it, and its timers, to this world.
    final messengerHandedOut = container.exists(messengerControllerProvider);
    container.dispose();
    if (!messengerHandedOut) messenger.dispose();
  }
}

/// A keystore whose owner already chose a PIN, without paying for the key
/// derivation of a real one.
class _PinSetStorage extends SecureStorageService {
  _PinSetStorage(super.store);

  @override
  Future<bool> hasPin() async => true;
}

class _Biometrics implements LocalUnlockAuthenticator {
  const _Biometrics();

  @override
  Future<bool> authenticateBiometric() async => false;

  @override
  Future<bool> canUseBiometrics() async => true;
}

/// The session a case starts in. While [bootstrapping], startup never
/// finishes, which is what the splash screen is on screen for.
class _LayoutSession extends AppSessionController {
  _LayoutSession(
    super.storage,
    super.api,
    super.adapter,
    AppSessionState initial, {
    required this.bootstrapping,
  }) {
    state = bootstrapping ? const AppSessionState() : initial;
  }

  final bool bootstrapping;

  @override
  Future<void> bootstrap() => bootstrapping ? Completer<void>().future : super.bootstrap();
}

/// The messenger over the fake relay. A chat's warnings come from the same
/// questions the screen asks a real messenger; only their answers are set.
class _LayoutMessenger extends VeilMessengerController {
  _LayoutMessenger({
    required LayoutRelayClient apiClient,
    required CryptoAdapter adapter,
    required FakeRelayRealtime realtime,
    required LayoutMemoryCache cache,
    required IdentityTrust trust,
    required this.attention,
    required this.peer,
  }) : super(
          apiClient: apiClient,
          cryptoEngine: adapter.messaging,
          keyBundleCodec: adapter.keyBundles,
          envelopeCodec: adapter.envelopeCodec,
          sessionBootstrapper: adapter.sessions,
          realtimeService: realtime,
          cacheService: cache,
          identityTrust: trust,
        );

  final ChatAttention attention;
  final RelayParty peer;

  @override
  PendingIdentityChange? pendingIdentityChangeFor(String conversationId) =>
      attention.identityChanged && conversationId == chatConversationId
          ? PendingIdentityChange(
              conversationId: conversationId,
              userId: peer.userId,
              deviceId: peer.deviceId,
              presentedKey: peer.identity.identityPublicKey,
              previousKey: peer.identity.identityPublicKey,
              requiresReverification: true,
            )
          : super.pendingIdentityChangeFor(conversationId);

  @override
  PeerAccountHold? peerAccountHoldFor(String conversationId) =>
      attention.accountHeld && conversationId == chatConversationId
          ? PeerAccountHold(
              PeerAccountHoldReason.otherAccount,
              known: ConversationPeer(userId: 'user-earlier', handle: peer.handle),
            )
          : super.peerAccountHoldFor(conversationId);

  @override
  int pendingCountFor(String conversationId) =>
      conversationId == chatConversationId && attention.failedSends > 0
          ? attention.failedSends
          : super.pendingCountFor(conversationId);

  @override
  List<ChatMessage> messagesFor(String conversationId) {
    final messages = super.messagesFor(conversationId);
    if (conversationId != chatConversationId || attention.failedSends == 0) return messages;
    // The relay has no failed sends: the newest of ours stand in for them.
    var remaining = attention.failedSends;
    return [
      for (final message in messages.reversed)
        if (message.isMine && remaining-- > 0)
          message.copyWith(deliveryState: MessageDeliveryState.failed)
        else
          message,
    ].reversed.toList(growable: false);
  }
}
