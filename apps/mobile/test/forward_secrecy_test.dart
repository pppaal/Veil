import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_adapter_registry.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';

// Verifies the hash-ratchet produces distinct ciphertexts for identical
// plaintexts and that sequential encryptions advance the ratchet. The body is
// the same, the conversation/session is the same, but the ciphertexts must
// diverge because each message uses a freshly-derived one-shot key + nonce.
void main() {
  Future<CryptoEnvelope> encryptOnce(
    MessageCryptoEngine engine,
    String conversationId,
    String senderDeviceId,
    String body,
  ) {
    return engine.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientUserId: 'user-remote',
      body: body,
      messageKind: MessageKind.text,
      recipientBundle: const KeyBundle(
        userId: 'user-remote',
        deviceId: 'device-remote',
        handle: 'remote',
        identityPublicKey: 'id-pub',
        signedPrekeyBundle: 'spk-bundle',
      ),
    );
  }

  test('sequential encrypts advance the ratchet and produce distinct ciphertexts',
      () async {
    final adapter = createConfiguredCryptoAdapter();
    await adapter.sessions.bootstrapSession(
      const SessionBootstrapRequest(
        conversationId: 'conv-ratchet-1',
        localDeviceId: 'device-local',
        localUserId: 'user-local',
        remoteUserId: 'user-remote',
        remoteDeviceId: 'device-remote',
        remoteIdentityPublicKey: 'remote-identity-key',
        remoteSignedPrekeyBundle: 'remote-spk',
      ),
    );

    final first = await encryptOnce(
      adapter.messaging,
      'conv-ratchet-1',
      'device-local',
      'hello',
    );
    final second = await encryptOnce(
      adapter.messaging,
      'conv-ratchet-1',
      'device-local',
      'hello',
    );
    final third = await encryptOnce(
      adapter.messaging,
      'conv-ratchet-1',
      'device-local',
      'hello',
    );

    expect(first.ciphertext, isNot(equals(second.ciphertext)));
    expect(second.ciphertext, isNot(equals(third.ciphertext)));
    expect(first.nonce, isNot(equals(second.nonce)));
  });

  test('ratchet encrypt survives many messages without error', () async {
    final adapter = createConfiguredCryptoAdapter();
    await adapter.sessions.bootstrapSession(
      const SessionBootstrapRequest(
        conversationId: 'conv-ratchet-2',
        localDeviceId: 'device-local',
        localUserId: 'user-local',
        remoteUserId: 'user-remote',
        remoteDeviceId: 'device-remote',
        remoteIdentityPublicKey: 'remote-identity-key',
        remoteSignedPrekeyBundle: 'remote-spk',
      ),
    );

    final ciphertexts = <String>{};
    for (var i = 0; i < 25; i++) {
      final env = await encryptOnce(
        adapter.messaging,
        'conv-ratchet-2',
        'device-local',
        'ping $i',
      );
      ciphertexts.add(env.ciphertext);
    }
    expect(ciphertexts.length, 25);
  });

  test('encrypt without bootstrapped session fails fast', () async {
    final adapter = createConfiguredCryptoAdapter();
    expect(
      () => encryptOnce(
        adapter.messaging,
        'conv-never-bootstrapped',
        'device-local',
        'hello',
      ),
      throwsStateError,
    );
  });
}
