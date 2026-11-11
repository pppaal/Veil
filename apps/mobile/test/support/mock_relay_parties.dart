import 'package:veil_mobile/src/app/app_session_state.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/features/conversations/data/veil_messenger_controller.dart';

import 'fake_relay.dart';
import 'strict_mock_crypto_adapter.dart';

/// Registers mock-keyed parties on [relay] and joins them in one direct
/// conversation, for controller tests that do not need real crypto.
void seedMockParties(FakeRelay relay, String conversationId, List<String> handles) {
  for (final handle in handles) {
    relay.addParty(RelayParty(
      handle: handle,
      userId: 'user-$handle',
      deviceId: 'dev-$handle',
      identity: DeviceIdentityMaterial(
        identityPublicKey: 'ik-$handle',
        identityPrivateKeyRef: 'ref-$handle',
        signedPrekeyBundle: 'spk-$handle',
      ),
    ));
  }
  relay.addDirect(conversationId, handles[0], handles[1]);
}

/// A controller for [handle] on [relay], backed by a strict mock adapter.
VeilMessengerController mockPartyController(
  FakeRelay relay,
  String handle, {
  CryptoAdapter? adapter,
  bool Function()? readReceiptsEnabled,
  bool Function()? typingIndicatorsEnabled,
}) {
  final crypto = adapter ?? StrictMockCryptoAdapter();
  return VeilMessengerController(
    apiClient: relay.clientFor(handle),
    cryptoEngine: crypto.messaging,
    keyBundleCodec: crypto.keyBundles,
    envelopeCodec: crypto.envelopeCodec,
    sessionBootstrapper: crypto.sessions,
    realtimeService: relay.realtimeFor(handle),
    cacheService: null,
    readReceiptsEnabled: readReceiptsEnabled,
    typingIndicatorsEnabled: typingIndicatorsEnabled,
  );
}

AppSessionState mockPartySession(String handle) => AppSessionState(
      accessToken: 'token-$handle',
      userId: 'user-$handle',
      deviceId: 'dev-$handle',
      handle: handle,
      displayName: handle,
      onboardingAccepted: true,
      locked: false,
      initializing: false,
    );
