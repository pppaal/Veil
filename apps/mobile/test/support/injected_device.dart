import 'package:veil_mobile/src/core/crypto/crypto_engine.dart';
import 'package:veil_mobile/src/core/crypto/lib_crypto_adapter.dart';

import 'fake_relay.dart';
import 'messenger_party.dart';

/// A device the server invents under [owner]'s account, with an identity
/// the server holds: every handshake it opens is genuine X3DH, only from a
/// device [owner] never had.
class InjectedDevice {
  InjectedDevice._(this.deviceId, this.owner, this.adapter, this.identity);

  static Future<InjectedDevice> mint(String deviceId, {required MessengerParty owner}) async {
    final adapter = LibCryptoAdapter();
    final identity = await adapter.identity.generateDeviceIdentity(deviceId);
    adapter.setLocalIdentityLoader(() async => identity.identityPrivateKeyRef);
    return InjectedDevice._(deviceId, owner, adapter, identity);
  }

  final String deviceId;
  final MessengerParty owner;
  final LibCryptoAdapter adapter;
  final DeviceIdentityMaterial identity;

  String get identityKey => identity.identityPublicKey;

  /// The directory entry the server serves when it calls this device
  /// [owner]'s active one.
  Map<String, dynamic> get bundleJson => {
        'userId': owner.device.userId,
        'deviceId': deviceId,
        'handle': owner.device.handle,
        'identityPublicKey': identity.identityPublicKey,
        'signedPrekeyBundle': identity.signedPrekeyBundle,
      };

  /// Opens a fresh session to [peer] in [conversationId] and relays [body]
  /// on it in [owner]'s name; returns the envelope.
  Future<Map<String, dynamic>> handshake(
    FakeRelay relay,
    MessengerParty peer,
    String body, {
    required String conversationId,
  }) async {
    final peerBundle = _bundleOf(peer);
    await adapter.sessions.bootstrapSession(SessionBootstrapRequest(
      conversationId: conversationId,
      localDeviceId: deviceId,
      localUserId: owner.device.userId,
      remoteUserId: peerBundle.userId,
      remoteDeviceId: peerBundle.deviceId,
      remoteIdentityPublicKey: peerBundle.identityPublicKey,
      remoteSignedPrekeyBundle: peerBundle.signedPrekeyBundle,
    ));
    return send(relay, peer, body, conversationId: conversationId);
  }

  /// Relays [body] on the session this device already holds with [peer].
  Future<Map<String, dynamic>> send(
    FakeRelay relay,
    MessengerParty peer,
    String body, {
    required String conversationId,
  }) async {
    final envelope = adapter.envelopeCodec.encodeApiEnvelope(await adapter.messaging.encryptMessage(
      conversationId: conversationId,
      senderDeviceId: deviceId,
      recipientUserId: peer.device.userId,
      body: body,
      messageKind: MessageKind.text,
      recipientBundle: _bundleOf(peer),
    ));
    relay.inject(senderHandle: owner.device.handle, conversationId: conversationId, envelope: envelope);
    return envelope;
  }

  static KeyBundle _bundleOf(MessengerParty peer) => KeyBundle(
        userId: peer.device.userId,
        deviceId: peer.device.deviceId,
        handle: peer.device.handle,
        identityPublicKey: peer.device.identity.identityPublicKey,
        signedPrekeyBundle: peer.device.identity.signedPrekeyBundle,
      );

  /// What this device reads of a relayed envelope.
  Future<DecryptedMessage> open(Map<String, dynamic> relayed) =>
      adapter.messaging.decryptMessage(adapter.envelopeCodec.decodeApiEnvelope(relayed));
}
