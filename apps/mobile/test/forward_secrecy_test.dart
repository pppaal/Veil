import 'package:flutter_test/flutter_test.dart';
import 'package:veil_mobile/src/core/crypto/crypto_adapter_registry.dart';
import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';

// Verifies the hash-ratchet produces distinct ciphertexts for identical
// plaintexts and that sequential encryptions advance the ratchet. The body is
// the same, the conversation/session is the same, but the ciphertexts must
// diverge because each message uses a freshly-derived one-shot key + nonce.
void main() {
  // Generates a recipient bundle carrying a genuine Ed25519-signed prekey so
  // the bootstrap path exercises full signature verification rather than the
  // old insecure fallback (which has been removed).
  Future<({KeyBundle bundle, DeviceIdentityMaterial identity})>
      generatePeer() async {
    final peer = createConfiguredCryptoAdapter();
    final id = await peer.identity.generateDeviceIdentity('device-remote');
    return (
      bundle: KeyBundle(
        userId: 'user-remote',
        deviceId: 'device-remote',
        handle: 'remote',
        identityPublicKey: id.identityPublicKey,
        signedPrekeyBundle: id.signedPrekeyBundle,
      ),
      identity: id,
    );
  }

  Future<CryptoEnvelope> encryptOnce(
    MessageCryptoEngine engine,
    String conversationId,
    String senderDeviceId,
    String body,
    KeyBundle recipientBundle,
  ) {
    return engine.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: senderDeviceId,
      recipientUserId: recipientBundle.userId,
      body: body,
      messageKind: MessageKind.text,
      recipientBundle: recipientBundle,
    );
  }

  test('sequential encrypts advance the ratchet and produce distinct ciphertexts',
      () async {
    final adapter = createConfiguredCryptoAdapter();
    final peer = await generatePeer();
    await adapter.sessions.bootstrapSession(
      SessionBootstrapRequest(
        conversationId: 'conv-ratchet-1',
        localDeviceId: 'device-local',
        localUserId: 'user-local',
        remoteUserId: 'user-remote',
        remoteDeviceId: 'device-remote',
        remoteIdentityPublicKey: peer.identity.identityPublicKey,
        remoteSignedPrekeyBundle: peer.identity.signedPrekeyBundle,
      ),
    );

    final first = await encryptOnce(
      adapter.messaging,
      'conv-ratchet-1',
      'device-local',
      'hello',
      peer.bundle,
    );
    final second = await encryptOnce(
      adapter.messaging,
      'conv-ratchet-1',
      'device-local',
      'hello',
      peer.bundle,
    );
    final third = await encryptOnce(
      adapter.messaging,
      'conv-ratchet-1',
      'device-local',
      'hello',
      peer.bundle,
    );

    expect(first.ciphertext, isNot(equals(second.ciphertext)));
    expect(second.ciphertext, isNot(equals(third.ciphertext)));
    expect(first.nonce, isNot(equals(second.nonce)));
  });

  test('ratchet encrypt survives many messages without error', () async {
    final adapter = createConfiguredCryptoAdapter();
    final peer = await generatePeer();
    await adapter.sessions.bootstrapSession(
      SessionBootstrapRequest(
        conversationId: 'conv-ratchet-2',
        localDeviceId: 'device-local',
        localUserId: 'user-local',
        remoteUserId: 'user-remote',
        remoteDeviceId: 'device-remote',
        remoteIdentityPublicKey: peer.identity.identityPublicKey,
        remoteSignedPrekeyBundle: peer.identity.signedPrekeyBundle,
      ),
    );

    final ciphertexts = <String>{};
    for (var i = 0; i < 25; i++) {
      final env = await encryptOnce(
        adapter.messaging,
        'conv-ratchet-2',
        'device-local',
        'ping $i',
        peer.bundle,
      );
      ciphertexts.add(env.ciphertext);
    }
    expect(ciphertexts.length, 25);
  });

  test('encrypt without bootstrapped session fails fast', () async {
    final adapter = createConfiguredCryptoAdapter();
    final peer = await generatePeer();
    expect(
      () => encryptOnce(
        adapter.messaging,
        'conv-never-bootstrapped',
        'device-local',
        'hello',
        peer.bundle,
      ),
      throwsStateError,
    );
  });
}
