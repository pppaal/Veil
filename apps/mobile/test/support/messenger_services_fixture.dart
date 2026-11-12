import 'package:veil_mobile/src/app/app_session_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/identity/identity_key_value_backend.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_resolver.dart';
import 'package:veil_mobile/src/core/identity/trusted_identity_store.dart';
import 'package:veil_mobile/src/core/network/keys_api.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';
import 'package:veil_mobile/src/core/realtime/realtime_service.dart';
import 'package:veil_mobile/src/core/storage/conversation_cache_service.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/conversation_peer_bindings.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/envelope_version_policy.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/identity_trust.dart';
import 'package:veil_mobile/src/features/conversations/data/messenger/messenger_services.dart';

const fixtureSession = AppSessionState(
  accessToken: 'token-atlas',
  userId: 'user-atlas',
  deviceId: 'dev-atlas',
  handle: 'atlas',
  onboardingAccepted: true,
  locked: false,
  initializing: false,
);

/// The messenger's services over the idempotent mock adapter, signed in as
/// atlas without running the sign-in flow, so a test drives one service.
MessengerServices messengerServicesFixture({
  required VeilApiClient api,
  ConversationCacheService? cache,
  RealtimeService? realtime,
  CryptoAdapter? crypto,
}) {
  final adapter = crypto ?? createDefaultCryptoAdapter();
  final services = MessengerServices(
    apiClient: api,
    cryptoEngine: adapter.messaging,
    keys: KeysApi(api, adapter.keyBundles),
    envelopeCodec: adapter.envelopeCodec,
    sessionBootstrapper: adapter.sessions,
    realtimeService: realtime ?? RealtimeService(),
    cache: cache,
    attachmentTempFileStore: null,
    notificationService: null,
    onSecurityException: null,
    sessionSnapshotRestorer: null,
    groupCrypto: null,
    readReceiptsEnabled: () => true,
    typingIndicatorsEnabled: () => true,
    trust: IdentityTrust(TrustedIdentityResolver(store: TrustedIdentityStore(InMemoryIdentityKeyValueBackend()))),
    envelopeVersions: EnvelopeVersionPolicy(),
    peerBindings: ConversationPeerBindings(),
    prekeyMaintenance: null,
    onChanged: () {},
    onSignedOut: () {},
  );
  services.session.diff(fixtureSession);
  return services;
}

/// The relay's copy of a message this device sent, as POST /messages and
/// history return it.
Map<String, dynamic> relayedMessageJson(
  Map<String, dynamic> envelope, {
  required String id,
  String? clientMessageId,
  required int order,
  String senderDeviceId = 'dev-atlas',
}) =>
    {
      ...envelope,
      'id': id,
      'clientMessageId': clientMessageId,
      'senderDeviceId': senderDeviceId,
      'conversationOrder': order,
      'serverReceivedAt': DateTime.utc(2026, 4, 1, 12).add(Duration(seconds: order)).toIso8601String(),
      'deliveredAt': null,
      'readAt': null,
    };
