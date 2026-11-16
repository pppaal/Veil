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
import 'phone_layout_probe.dart';

// The app as one layout case sees it: the real route table, theme and
// localizations over the test fakes (FakeRelay, a mock-keyed messenger,
// memory stores), signed in as alex or signed out, with seeded content.

const selfHandle = 'alex';
const selfDisplayName = 'Alex Kim';
const peerHandle = 'sam';

/// The conversation the chat and safety-number cases open.
const chatConversationId = 'conv-$peerHandle';

/// A peer nobody has written to yet, and the conversation with them.
const emptyChatPeerHandle = 'lena';
const emptyChatConversationId = 'conv-$emptyChatPeerHandle';

/// The conversation whose messages disappear after a day.
const timerChatPeerHandle = 'jonas';
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
  const ChatAttention({
    this.identityChanged = false,
    this.failedSends = 0,
    this.accountHeld = false,
    this.peerTyping = false,
    this.legacyMessage = false,
    this.identityChangedInGroup = false,
    this.loading = false,
    this.relayError = false,
  });

  /// The peer's identity key changed and the user has not reviewed it.
  final bool identityChanged;

  /// Messages of ours that did not go out.
  final int failedSends;

  /// The chat is listed under the peer's handle with another account than
  /// the one this device talked to, and waits for the user to say so.
  final bool accountHeld;

  /// The peer is typing while the chat is open.
  final bool peerTyping;

  /// The peer's first message came on a legacy frame whose handshake never
  /// authenticated its sender, so its bubble carries the badge saying so.
  final bool legacyMessage;

  /// The peer's identity key changed in the group they share with the
  /// user, which holds the change for review; their 1:1 holds none. Needs a
  /// world with the group.
  final bool identityChangedInGroup;

  /// The messenger is still fetching: a chat with nothing loaded and a list
  /// with no conversation yet show their loading state.
  final bool loading;

  /// The relay failed the last request, which the messenger reports as its
  /// error line: a chat and the list each say so.
  final bool relayError;

  /// How many of the chat's warnings come with an action: reviewing the
  /// identity change (in this chat, or the one that waits in the group),
  /// releasing the held account, retrying failed sends.
  int get warningActionCount =>
      (identityChanged ? 1 : 0) +
      (identityChangedInGroup ? 1 : 0) +
      (accountHeld ? 1 : 0) +
      (failedSends > 0 ? 1 : 0);
}

class LayoutWorld {
  LayoutWorld._(this.identities, this.account, this.locale, this.sessionError);

  final LayoutIdentities identities;
  final LayoutAccount account;
  final String locale;

  /// What the session reports as its last failure (a text
  /// formatUserFacingError returned), for a screen that shows it.
  final String? sessionError;

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
        LayoutAccount.signedOut => AppSessionState(locked: false, initializing: false, errorMessage: sessionError),
        _ => AppSessionState(
            accessToken: 'token-$selfHandle',
            userId: 'user-$selfHandle',
            deviceId: 'dev-$selfHandle',
            handle: selfHandle,
            displayName: selfDisplayName,
            onboardingAccepted: true,
            privacyConsentAccepted: true,
            locked: account == LayoutAccount.locked,
            initializing: false,
            errorMessage: sessionError,
          ),
      };

  static Future<LayoutWorld> create({
    required LayoutIdentities identities,
    required LayoutAccount account,
    required String locale,
    ChatAttention attention = const ChatAttention(),
    bool bootstrapping = false,
    bool transferStarted = false,
    bool withGroup = false,
    String? sessionError,
    void Function(FakeRelay relay)? beforeSession,
  }) async {
    final world = LayoutWorld._(identities, account, locale, sessionError);
    await world._build(
      attention: attention,
      bootstrapping: bootstrapping,
      transferStarted: transferStarted,
      withGroup: withGroup,
      beforeSession: beforeSession,
    );
    return world;
  }

  late final ChatAttention _attention;

  Future<void> _build({
    required ChatAttention attention,
    required bool bootstrapping,
    required bool transferStarted,
    required bool withGroup,
    void Function(FakeRelay relay)? beforeSession,
  }) async {
    _attention = attention;
    seedParties(relay, identities);
    if (account == LayoutAccount.signedIn || account == LayoutAccount.locked) {
      await seedConversations(relay, cache, withGroup: withGroup);
    }
    // A caller that shows less than the seed changes the relay here, before
    // this device's session loads anything from it.
    beforeSession?.call(relay);
    api = LayoutRelayClient(relay, relay.partiesByHandle[selfHandle]!);

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
    // A group's frames open only for members whose devices this device has
    // pinned, which is also how it knows who of the group wrote each one.
    if (withGroup) {
      for (final handle in groupMemberHandles) {
        final member = relay.partiesByHandle[handle]!;
        await trust.resolver.evaluate(member.userId, member.deviceId, member.identity.identityPublicKey);
      }
    }

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
      changedKey: identities.self.identityPublicKey,
    );
    if (_hasAccount) await messenger.applySession(_session);
    // After the session is applied, which forgets what was pending before it.
    if (attention.identityChangedInGroup) {
      assert(withGroup, 'a change in the group needs the group');
      // Their device presents another key there: refused, and held.
      await trust.admit(groupConversationId, peer.userId, peer.deviceId, identities.self.identityPublicKey);
    }

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

  /// What only happens while a chat is open: the peer starts typing. Call
  /// once the screen is up; the indicator clears by itself after 5 s.
  void startLiveAttention() {
    if (_attention.peerTyping) messenger.presenceTyping.typingStarted(chatConversationId, peerHandle);
  }

  /// The app at [location]: the real route table (so tab screens get their
  /// bottom bar), [locale], and the dark theme unless [themeMode] asks for
  /// the light one. The theme names the test font the probe loaded, so the
  /// renders measure real glyphs whatever the platform.
  Widget app({
    required String location,
    Object? extra,
    ThemeMode themeMode = ThemeMode.dark,
  }) {
    final router = _router = GoRouter(
      initialLocation: location,
      initialExtra: extra,
      routes: container.read(appRoutesProvider),
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        title: 'Veil',
        theme: VeilTheme.light(fontFamily: layoutFontFamily),
        darkTheme: VeilTheme.dark(fontFamily: layoutFontFamily),
        themeMode: themeMode,
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
    // A session still starting has no account yet, but may already have
    // failed (a build that cannot reach its relay).
    state = bootstrapping ? AppSessionState(errorMessage: initial.errorMessage) : initial;
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
    required this.changedKey,
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

  /// The key the peer's device presents in a case whose identity changed:
  /// another key than the pinned one, so the safety number page shows two
  /// numbers that differ, as it does after a real change.
  final String changedKey;

  @override
  bool get isBusy => attention.loading || super.isBusy;

  // What a relay answering 503 leaves as the messenger's error line.
  @override
  String? get errorMessage =>
      attention.relayError ? formatUserFacingError('Request failed: HTTP 503') : super.errorMessage;

  @override
  PendingIdentityChange? pendingIdentityChangeFor(String conversationId) =>
      attention.identityChanged && conversationId == chatConversationId
          ? PendingIdentityChange(
              conversationId: conversationId,
              userId: peer.userId,
              deviceId: peer.deviceId,
              presentedKey: changedKey,
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
  Future<DecryptedMessage> decryptMessage(ChatMessage message) async {
    final opened = await super.decryptMessage(message);
    if (!attention.legacyMessage || !opened.isOk || message.isMine) return opened;
    final first = super.messagesFor(chatConversationId).where((each) => !each.isMine).firstOrNull;
    if (first?.id != message.id) return opened;
    return DecryptedMessage(
      body: opened.body,
      messageKind: opened.messageKind,
      expiresAt: opened.expiresAt,
      attachment: opened.attachment,
      status: DecryptStatus.legacyUnauthenticated,
    );
  }

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
