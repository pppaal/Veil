import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_adapter_registry.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';

void main() {
  test('configured crypto adapter exposes the full beta boundary', () async {
    final adapter = createConfiguredCryptoAdapter();

    expect(adapter.adapterId, isNotEmpty);
    expect(adapter.identity, isA<DeviceIdentityProvider>());
    expect(adapter.deviceAuth, isA<DeviceAuthChallengeSigner>());
    expect(adapter.keyBundles, isA<KeyBundleCodec>());
    expect(adapter.envelopeCodec, isA<CryptoEnvelopeCodec>());
    expect(adapter.messaging, isA<MessageCryptoEngine>());
    expect(adapter.sessions, isA<ConversationSessionBootstrapper>());

    // Bootstrap now requires a real signed prekey bundle because the adapter
    // verifies the Ed25519 signature before using the embedded X25519 pub.
    // Generating a peer identity through the same adapter is the simplest
    // way to get a correctly-signed bundle.
    final peer = createConfiguredCryptoAdapter();
    final peerIdentity =
        await peer.identity.generateDeviceIdentity('device-remote');

    final bootstrap = await adapter.sessions.bootstrapSession(
      SessionBootstrapRequest(
        conversationId: 'conversation-1',
        localDeviceId: 'device-local',
        localUserId: 'user-local',
        remoteUserId: 'user-remote',
        remoteDeviceId: 'device-remote',
        remoteIdentityPublicKey: peerIdentity.identityPublicKey,
        remoteSignedPrekeyBundle: peerIdentity.signedPrekeyBundle,
      ),
    );

    expect(bootstrap.sessionLocator, isNotEmpty);
    expect(bootstrap.sessionEnvelopeVersion, isNotEmpty);
    expect(bootstrap.requiresLocalPersistence, isTrue);
    expect(bootstrap.sessionSchemaVersion, greaterThan(0));
    expect(bootstrap.localDeviceId, 'device-local');
    expect(bootstrap.remoteDeviceId, 'device-remote');
    expect(bootstrap.remoteIdentityFingerprint, isNotEmpty);
  });
}
