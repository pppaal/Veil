import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:veil_mobile/src/core/crypto/group_sender_keys.dart';

const groupId = 'group-1';

String b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// A device's long-term identity as the directory publishes it: an Ed25519
/// identity key and an X25519 prekey. The "signed prekey bundle" is an opaque
/// label that [IdentityDirectory.resolvePrekey] maps back to the prekey.
class TestIdentity {
  TestIdentity._({
    required this.userId,
    required this.deviceId,
    required this.handle,
    required this.ed25519Seed,
    required this.identityPublicKey,
    required this.x25519Private,
    required this.x25519Public,
  });

  static Future<TestIdentity> generate({
    required String userId,
    required String deviceId,
    required String handle,
  }) async {
    final ed = await Ed25519().newKeyPair();
    final x = await X25519().newKeyPair();
    return TestIdentity._(
      userId: userId,
      deviceId: deviceId,
      handle: handle,
      ed25519Seed: (await ed.extract()).bytes,
      identityPublicKey: b64u((await ed.extractPublicKey()).bytes),
      x25519Private: (await x.extract()).bytes,
      x25519Public: await x.extractPublicKey(),
    );
  }

  final String userId;
  final String deviceId;
  final String handle;
  final List<int> ed25519Seed;
  final String identityPublicKey;
  final List<int> x25519Private;
  final SimplePublicKey x25519Public;

  String get signedPrekeyBundle => 'spk:$deviceId';

  Map<String, dynamic> get directoryBundle => {
        'userId': userId,
        'deviceId': deviceId,
        'handle': handle,
        'identityPublicKey': identityPublicKey,
        'signedPrekeyBundle': signedPrekeyBundle,
      };
}

/// Stands in for the adapter's prekey verification: resolves a bundle label
/// to the X25519 prekey only if it is presented with its own identity key.
class IdentityDirectory {
  final Map<String, TestIdentity> _byBundle = <String, TestIdentity>{};
  final List<String> resolvedBundles = <String>[];

  void add(TestIdentity identity) => _byBundle[identity.signedPrekeyBundle] = identity;

  Future<SimplePublicKey> resolvePrekey(String bundle, String identityPublicKey) async {
    final identity = _byBundle[bundle];
    if (identity == null || identity.identityPublicKey != identityPublicKey) {
      throw StateError('prekey bundle does not verify against identity');
    }
    resolvedBundles.add(bundle);
    return identity.x25519Public;
  }

  GroupSenderKeySealer sealer({DateTime Function()? clock}) =>
      GroupSenderKeySealer(resolveRecipientPrekey: resolvePrekey, clock: clock);
}

/// Seals [key] in the pre-freshness `veil-gkd-v1` format older clients still
/// send, so tests can check how the current client treats it.
Future<SealedGroupSenderKey> sealLegacyV1({
  required GroupSenderKey key,
  required TestIdentity sender,
  required TestIdentity recipient,
}) async {
  final eph = await X25519().newKeyPair();
  final ephPub = (await eph.extractPublicKey()).bytes;
  final shared = await X25519().sharedSecretKey(keyPair: eph, remotePublicKey: recipient.x25519Public);
  final wrapKey = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: shared,
    nonce: ephPub,
    info: utf8.encode('veil-gkd-wrap-v1'),
  );
  final nonce = List<int>.generate(12, (i) => i + 1);
  final aad = BytesBuilder(copy: false)
    ..add(utf8.encode(kLegacyGroupKeyDistributionVersion))
    ..add(_lengthPrefixed(utf8.encode(key.groupId)))
    ..add((ByteData(8)..setUint64(0, key.epoch)).buffer.asUint8List())
    ..add(_lengthPrefixed(utf8.encode(key.senderDeviceId)))
    ..add(_lengthPrefixed(utf8.encode(recipient.userId)));
  final ad = aad.toBytes();
  final box = await AesGcm.with256bits().encrypt(
    utf8.encode(json.encode({
      'v': 1,
      'groupId': key.groupId,
      'epoch': key.epoch,
      'senderDeviceId': key.senderDeviceId,
      'chainKey': b64u(key.chainKey),
      'counter': key.counter,
      'signingPub': b64u(key.signingPublicKey),
    })),
    secretKey: wrapKey,
    nonce: nonce,
    aad: ad,
  );
  final ciphertext = [...box.cipherText, ...box.mac.bytes];
  final signer = await Ed25519().newKeyPairFromSeed(sender.ed25519Seed);
  final signature = await Ed25519().sign([...ad, ...ephPub, ...nonce, ...ciphertext], keyPair: signer);
  return SealedGroupSenderKey(
    recipientUserId: recipient.userId,
    encryptedChainKey: b64u([...ephPub, ...signature.bytes, ...ciphertext]),
    nonce: b64u(nonce),
    version: kLegacyGroupKeyDistributionVersion,
  );
}

List<int> _lengthPrefixed(List<int> bytes) => [bytes.length >> 8, bytes.length & 0xFF, ...bytes];

/// Runs [fn] and returns the [GroupCryptoException] code it threw, or 'ok'.
Future<String> errorCode(Future<void> Function() fn) async {
  try {
    await fn();
    return 'ok';
  } on GroupCryptoException catch (e) {
    return e.code;
  }
}
