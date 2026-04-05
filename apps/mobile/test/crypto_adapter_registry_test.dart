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

    final bootstrap = await adapter.sessions.bootstrapSession(
      const SessionBootstrapRequest(
        conversationId: 'conversation-1',
        localDeviceId: 'device-local',
        localUserId: 'user-local',
        remoteUserId: 'user-remote',
        remoteDeviceId: 'device-remote',
        remoteIdentityPublicKey: 'remote-identity-key',
        remoteSignedPrekeyBundle: 'remote-spk',
      ),
    );

    expect(bootstrap.sessionLocator, isNotEmpty);
    expect(bootstrap.sessionEnvelopeVersion, isNotEmpty);
    expect(bootstrap.requiresLocalPersistence, isTrue);
  });
}
