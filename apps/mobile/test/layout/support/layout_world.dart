import 'dart:async';
import 'dart:io';

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
import 'package:veil_mobile/src/core/storage/media_index.dart';
import 'package:veil_mobile/src/core/storage/secure_storage_service.dart';
import 'package:veil_mobile/src/core/theme/veil_theme.dart';
import 'package:veil_mobile/src/features/app_lock/data/lock_request_provider.dart';
import 'package:veil_mobile/src/features/attachments/data/attachment_storage_paths.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_names.dart';
import 'package:veil_mobile/src/features/contacts/data/contact_nicknames.dart';
import 'package:veil_mobile/src/features/conversations/data/conversation_models.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_peer_bindings.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';
import 'package:veil_mobile/src/features/device_transfer/data/device_transfer_providers.dart';
import 'package:veil_mobile/src/features/safety/application/contact_trust.dart';
import 'package:veil_mobile/src/features/safety/application/verified_accounts.dart';
import 'package:veil_mobile/src/features/safety/data/contact_trust_store.dart';
import 'package:veil_mobile/src/features/safety/data/conversation_mutes.dart';
import 'package:veil_mobile/src/features/safety/data/safety_providers.dart';
import 'package:veil_mobile/src/l10n/generated/app_localizations.dart';

import '../../support/fake_relay.dart';
import '../../support/memory_secure_store.dart';
import 'layout_seed.dart';
import 'phone_layout_probe.dart';
import 'trust_seed.dart';

// The app as one layout case sees it: the real route table, theme and
// localizations over the test fakes (FakeRelay, a mock-keyed messenger,
// memory stores), signed in as alex or signed out, with seeded content.

const selfHandle = 'alex';
const selfDisplayName = 'Alex Kim';
const peerHandle = 'sam';

/// The conversation the chat and safety-number cases open.
const chatConversationId = 'conv-$peerHandle';

/// A peer nobody has written to yet, and the conversation with them.
const emptyChatPeerHandle = 'lena_berlin';
const emptyChatConversationId = 'conv-$emptyChatPeerHandle';

/// The conversation whose messages disappear after a day.
const timerChatPeerHandle = 'jonask';
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

  /// Signed in with no PIN yet, behind the lock the user turned on in
  /// Settings: the PIN setup, which can be cancelled.
  choosingPin,
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
    this.relayErrorWhileOpen = false,
    this.peerBlocked = false,
    this.muted = false,
    this.reportRefused = false,
    this.trust,
  });

  /// The peer's identity key changed and the user has not reviewed it.
  /// With [failedSends] the change came during the morning: the chat says
  /// so where it happened, and our messages after it are the failed ones.
  final bool identityChanged;

  /// Messages of ours that did not go out.
  final int failedSends;

  /// The chat is listed under the peer's handle with another account than
  /// the one this device talked to, and waits for the user to say so. Such
  /// a chat is a conversation of its own: it holds only the two messages
  /// that account sent, both locked until the user confirms it.
  final bool accountHeld;

  /// The peer is typing while the chat is open.
  final bool peerTyping;

  /// The peer's first message of the morning came on a legacy frame whose
  /// handshake never authenticated its sender, so its bubble carries the
  /// line saying so.
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

  /// The relay fails a request once the chat is open (startLiveAttention):
  /// the chat says so in a toast, which it shows only for a failure that
  /// comes while it is open.
  final bool relayErrorWhileOpen;

  /// The user blocked the chat's peer, and before them one more account
  /// (tom_walsh, who set no name): the chat shows the line that takes the
  /// composer's place, and the blocked accounts list has two rows.
  final bool peerBlocked;

  /// The user muted the chat on this phone, with no end, and the chat with
  /// the disappearing timer for a week: their rows in the list show it.
  final bool muted;

  /// The relay refuses the next report, as its throttle does: the chat says
  /// so in a toast with Retry.
  final bool reportRefused;

  /// A chat of the trust cases (trust_seed.dart): a stranger's request, a
  /// look-alike account, a family claim, or Sam unverified for the nudge.
  final TrustCase? trust;

  /// How many of the chat's warnings come with an action: reviewing the
  /// identity change (in this chat, or the one that waits in the group),
  /// releasing the held account, verifying a new account that says it is
  /// family, or the nudge to verify Sam. Failed sends are retried from
  /// their own bubbles, with no banner; the look-alike warning has none.
  int get warningActionCount =>
      (identityChanged ? 1 : 0) +
      (identityChangedInGroup ? 1 : 0) +
      (accountHeld ? 1 : 0) +
      (trust == TrustCase.claim || trust == TrustCase.nudge ? 1 : 0);
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
  late final SecureStorageService storage = account == LayoutAccount.choosingPin
      ? SecureStorageService(MemorySecureStore())
      : _PinSetStorage(MemorySecureStore());
  final LayoutMemoryCache cache = LayoutMemoryCache();

  /// What the phone's clock reads (wallClockProvider): [layoutNow] unless a
  /// test moves it.
  DateTime now = layoutNow;
  late final LayoutRelayClient api;
  late final IdentityTrust trust;

  /// The trust layer, attached to [messenger] as the app attaches it, from
  /// the document trust_seed.dart writes.
  late final VerifiedAccounts verifiedAccounts;
  late final ContactTrust contactTrust;
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
            locked: account == LayoutAccount.locked || account == LayoutAccount.choosingPin,
            initializing: false,
            errorMessage: sessionError,
          ),
      };

  /// The phone's attachment folders, every root (the iOS system temporary
  /// folder too) under a temporary folder of this world's, so a purge or a
  /// sweep runs for real and touches nothing else. Gone with [dispose].
  final Directory attachmentRoot = Directory.systemTemp.createTempSync('veil-layout-');
  late final AttachmentStoragePaths attachmentPaths = AttachmentStoragePaths(
    temporaryRoot: () async => Directory('${attachmentRoot.path}/tmp')..createSync(recursive: true),
    supportRoot: () async => Directory('${attachmentRoot.path}/support')..createSync(recursive: true),
    systemTempRoot: () => Directory('${attachmentRoot.path}/system-tmp')..createSync(recursive: true),
    sweepSystemTemp: true,
  );

  /// The media index, in memory, as the phone keeps it in its database.
  final MediaIndex mediaIndex = MemoryMediaIndex();

  /// [beforeSession] changes the relay before this device's session loads
  /// anything from it; [overrides] go into the world's provider container
  /// beside its own (a picker, an opener), so they name providers the world
  /// leaves alone: a container takes one override per provider.
  static Future<LayoutWorld> create({
    required LayoutIdentities identities,
    required LayoutAccount account,
    required String locale,
    ChatAttention attention = const ChatAttention(),
    bool bootstrapping = false,
    bool transferClaimed = false,
    bool transferStarted = false,
    bool withGroup = false,
    bool searchesArchive = false,
    String? sessionError,
    void Function(FakeRelay relay)? beforeSession,
    List<Override> overrides = const [],
  }) async {
    final world = LayoutWorld._(identities, account, locale, sessionError);
    // A search of Chats looks through every seeded line with words.
    world.cache.searchesArchive = searchesArchive;
    await world._build(
      attention: attention,
      bootstrapping: bootstrapping,
      transferClaimed: transferClaimed,
      transferStarted: transferStarted,
      withGroup: withGroup,
      beforeSession: beforeSession,
      overrides: overrides,
    );
    return world;
  }

  late final ChatAttention _attention;

  Future<void> _build({
    required ChatAttention attention,
    required bool bootstrapping,
    required bool transferClaimed,
    required bool transferStarted,
    required bool withGroup,
    void Function(FakeRelay relay)? beforeSession,
    List<Override> overrides = const [],
  }) async {
    _attention = attention;
    seedParties(relay, identities);
    if (account == LayoutAccount.signedIn || account == LayoutAccount.locked) {
      await seedConversations(
        relay,
        cache,
        withGroup: withGroup,
        keyChange: attention.identityChanged && attention.failedSends > 0,
        heldAccount: attention.accountHeld,
      );
    }
    // A caller that shows less than the seed changes the relay here, before
    // this device's session loads anything from it.
    beforeSession?.call(relay);
    final trustCase = attention.trust;
    if (_hasAccount) {
      if (trustCase != null) await seedTrustChat(relay, identities, trustCase);
      final (:requests, :acceptedAt) = trustDocumentOf(trustCase);
      await writeTrustDocument(storage, relay, requests: requests, acceptedAt: acceptedAt);
    }
    api = LayoutRelayClient(relay, relay.partiesByHandle[selfHandle]!);
    if (attention.peerBlocked) {
      relay.blocks['user-$selfHandle'] = {
        'user-tom_walsh': DateTime.utc(2026, 3, 30, 18),
        'user-$peerHandle': DateTime.utc(2026, 4, 7, 9),
      };
    }
    if (attention.reportRefused) relay.refuseReports = 1;
    if (attention.muted) {
      await MuteStore(storage.scoped(SecureScope.notifications)).write({
        chatConversationId: null,
        timerChatConversationId: DateTime.now().add(const Duration(days: 7)),
      });
    }

    if (_hasAccount) {
      await storage.persistDeviceSecretRefs(
        identityPrivateRef: identities.self.identityPrivateKeyRef,
        authPrivateKey: 'auth',
        authPublicKey: 'auth-pub',
      );
      // The names the screens show are the nicknames alex gave on this
      // phone, as on a real one: the relay sends none.
      final nicknames = ContactNicknames(storage.scoped(SecureScope.contacts));
      for (final MapEntry(key: handle, value: name) in peerNames.entries) {
        if (name != null) await nicknames.write(handle, name);
      }
    }
    // Pins and verifications are stamped by the phone's clock, so Safety
    // number's "Verified" date is this morning's, as the chats are.
    trust = IdentityTrust(
      TrustedIdentityResolver(store: TrustedIdentityStore(InMemoryIdentityKeyValueBackend()), clock: () => now),
    );
    // The chat's peer was compared out of band, so the chat shows its mark;
    // in the nudge's case never.
    final peer = relay.partiesByHandle[peerHandle]!;
    await trust.resolver.evaluate(peer.userId, peer.deviceId, peer.identity.identityPublicKey);
    if (trustCase != TrustCase.nudge) {
      await trust.markVerified(peer.userId, peer.deviceId, peer.identity.identityPublicKey);
    }
    if (trustCase != null) await pinTrustParties(trust, relay, trustCase);
    verifiedAccounts = VerifiedAccounts(trust);
    contactTrust = ContactTrust(
      store: ContactTrustStore(storage.scoped(SecureScope.conversationPolicy)),
      verified: verifiedAccounts,
      clock: () => now,
    );
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
      attachmentPaths: attachmentPaths,
      mediaIndex: mediaIndex,
      withheldByUser: contactTrust.withholds,
      onOwnSend: contactTrust.noteOwnSend,
    );
    if (_hasAccount) await messenger.applySession(_session);
    // After the session is applied, which forgets what was pending before it.
    if (attention.identityChangedInGroup) {
      assert(withGroup, 'a change in the group needs the group');
      // Their device presents another key there: refused, and held.
      await trust.admit(groupConversationId, peer.userId, peer.deviceId, identities.self.identityPublicKey);
    }

    final session = _LayoutSession(
      storage,
      api,
      identities.adapter,
      _session,
      bootstrapping: bootstrapping,
      // A new phone that claimed a move and waits for the old one, with
      // the relay's ids as production has them: a UUID for the claim.
      claimed: !transferClaimed
          ? null
          : PendingTransferRecord(
              sessionId: layoutTransferSessionId,
              transferToken: 'token',
              claimId: layoutClaimId,
              claimantFingerprint: layoutClaimFingerprint,
              expiresAt: DateTime.now().add(const Duration(minutes: 4, seconds: 30)),
              identity: identities.self,
              authKey: const DeviceAuthKeyMaterial(publicKey: 'auth-pub', privateKey: 'auth'),
              completionOutcomeUnknown: false,
            ),
    );
    container = ProviderContainer(overrides: [
      secureStorageProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(api),
      cryptoAdapterProvider.overrideWithValue(identities.adapter),
      appSessionProvider.overrideWith((ref) => session),
      messengerControllerProvider.overrideWith((ref) => messenger),
      identityTrustProvider.overrideWithValue(trust),
      unattachedContactTrustProvider.overrideWithValue(contactTrust),
      conversationCacheProvider.overrideWith((ref) async => null),
      appLockServiceProvider.overrideWithValue(AppLockService(const _Biometrics(), storage)),
      // The seed's Tuesday morning, whatever day the case runs.
      wallClockProvider.overrideWithValue(() => now),
      attachmentStoragePathsProvider.overrideWithValue(attachmentPaths),
      if (account == LayoutAccount.choosingPin) lockRequestedInSettingsProvider.overrideWith((ref) => true),
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
      ...overrides,
    ]);
    if (transferStarted) await container.read(deviceTransferControllerProvider).initTransfer();
    attachLayoutTrust(
      contactTrust,
      messenger,
      identityTrust: trust,
      book: container.read(contactNameBookProvider),
      blocked: () => container.exists(blockedAccountsProvider) ? container.read(blockedAccountsProvider) : null,
    );
    // The document is read and the baseline stands before any screen opens,
    // and what the first list started (reading the peers' keys, which the
    // trust layer's listeners slow down) has run its course, as it had
    // before the trust layer was attached here.
    for (var turn = 0; _hasAccount && turn < 200; turn++) {
      await Future<void>.value();
    }
    if (account == LayoutAccount.signedIn && !contactTrust.ready) throw StateError('the trust document was not read');
  }

  /// What only happens while a chat is open: the peer starts typing. Call
  /// once the screen is up; the indicator clears by itself after 5 s.
  void startLiveAttention() {
    if (_attention.peerTyping) messenger.presenceTyping.typingStarted(chatConversationId, peerHandle);
    if (_attention.relayErrorWhileOpen) (messenger as _LayoutMessenger).failWhileOpen();
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
    contactTrust.dispose();
    verifiedAccounts.dispose();
    if (!messengerHandedOut) messenger.dispose();
    if (attachmentRoot.existsSync()) attachmentRoot.deleteSync(recursive: true);
  }
}

/// A keystore whose owner already chose a PIN, without paying for the key
/// derivation of a real one.
class _PinSetStorage extends SecureStorageService {
  _PinSetStorage(super.store);

  @override
  Future<bool> hasPin() async => true;
}

/// A Pixel's: a fingerprint sensor, so the lock screen's button says "Use
/// fingerprint". It always refuses.
class _Biometrics implements LocalUnlockAuthenticator, BiometricKindSource {
  const _Biometrics();

  @override
  Future<bool> authenticateBiometric() async => false;

  @override
  Future<bool> canUseBiometrics() async => true;

  @override
  Future<BiometricKind> biometricKind() async => BiometricKind.fingerprint;
}

/// The session a case starts in. While [bootstrapping], startup never
/// finishes, which is what the splash screen is on screen for.
class _LayoutSession extends AppSessionController {
  _LayoutSession(
    super.storage,
    super.api,
    super.adapter,
    AppSessionState initial, {
    this.claimed,
    required this.bootstrapping,
  }) {
    // A session still starting has no account yet, but may already have
    // failed (a build that cannot reach its relay).
    state = bootstrapping ? AppSessionState(errorMessage: initial.errorMessage) : initial;
  }

  final bool bootstrapping;

  /// The claim this phone made, as start-up would have read it.
  final PendingTransferRecord? claimed;

  @override
  PendingTransferRecord? get pendingTransfer => super.pendingTransfer ?? claimed;

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
    required AttachmentStoragePaths attachmentPaths,
    required MediaIndex mediaIndex,
    required bool Function(String conversationId) withheldByUser,
    required void Function(String conversationId) onOwnSend,
  }) : super(
          apiClient: apiClient,
          cryptoEngine: adapter.messaging,
          keyBundleCodec: adapter.keyBundles,
          envelopeCodec: adapter.envelopeCodec,
          sessionBootstrapper: adapter.sessions,
          realtimeService: realtime,
          cacheService: cache,
          identityTrust: trust,
          attachmentPaths: attachmentPaths,
          mediaIndex: mediaIndex,
          withheldByUser: withheldByUser,
          onOwnSend: onOwnSend,
        );

  final ChatAttention attention;
  final RelayParty peer;

  /// The key the peer's device presents in a case whose identity changed:
  /// another key than the pinned one, so the safety number page shows two
  /// numbers that differ, as it does after a real change.
  final String changedKey;

  @override
  bool get isBusy => attention.loading || super.isBusy;

  bool _failedWhileOpen = false;

  /// A request fails now, while a screen is open.
  void failWhileOpen() {
    _failedWhileOpen = true;
    notifyListeners();
  }

  // What a relay answering 503 leaves as the messenger's error line.
  @override
  String? get errorMessage => attention.relayError || _failedWhileOpen
      ? formatUserFacingError('Request failed: HTTP 503')
      : super.errorMessage;

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
    // A held chat admits no identity until the user confirms the account
    // (ConversationCryptoRouter.verifyRemoteIdentity), so nothing that
    // account sent opens: the engine refuses each frame as it would one
    // from a changed identity.
    if (attention.accountHeld && !message.isMine && message.envelope.conversationId == chatConversationId) {
      return DecryptedMessage(
        body: '',
        messageKind: message.envelope.messageKind,
        status: DecryptStatus.identityRejected,
      );
    }
    final opened = await super.decryptMessage(message);
    if (!attention.legacyMessage || !opened.isOk || message.isMine || opened.body != legacyMessageBody) {
      return opened;
    }
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
