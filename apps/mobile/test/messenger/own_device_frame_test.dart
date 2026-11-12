import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/mock_crypto_engine.dart';
import 'package:veil_mobile/src/core/network/veil_api_client.dart';

import '../support/counting_crypto_adapter.dart';
import '../support/messenger_services_fixture.dart';

// The decrypt guard on its own. The idempotent mock adapter opens any frame
// and never asks the identity verifier, so nothing but the router's own check
// keeps a pairwise frame under this device's id from showing as the user's.
void main() {
  test('a pairwise frame under this device\'s own id is never handed to the engine', () async {
    final adapter = CountingCryptoAdapter(createDefaultCryptoAdapter());
    final services = messengerServicesFixture(
      api: VeilApiClient(baseUrl: 'http://relay.invalid/v1'),
      crypto: adapter,
    );
    final forged = await adapter.messaging.encryptMessage(
      conversationId: 'conv-1',
      senderDeviceId: fixtureSession.deviceId!,
      recipientUserId: fixtureSession.userId!,
      body: 'I agree to transfer everything',
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-atlas',
        deviceId: 'dev-atlas',
        handle: 'atlas',
        identityPublicKey: 'pub-atlas',
        signedPrekeyBundle: 'bundle-atlas',
      ),
    );
    adapter.counts.reset();

    final opened = await services.crypto.decrypt(forged);

    expect(opened.status, DecryptStatus.failed);
    expect(opened.failureReason, 'own_device_frame');
    expect(opened.body, isEmpty);
    expect(adapter.counts.decrypt, 0);
  });
}
