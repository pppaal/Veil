import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// The ratchet's key-derivation functions. Labels and salts are wire format
/// (pinned by packages/shared/test-vectors/crypto-kat.json): protocol v2
/// reuses the v1 root/chain/message KDFs unchanged and only changes what
/// feeds them.

const String rootKdfLabel = 'veil-dh-rk-v2';
const String messageKeyLabel = 'veil-msg-v1';
const String chainKeyLabel = 'veil-chain-next-v1';

Future<Uint8List> hkdfSha256({
  required List<int> ikm,
  required List<int> salt,
  required List<int> info,
  required int length,
}) async {
  final key = await Hkdf(hmac: Hmac.sha256(), outputLength: length).deriveKey(
    secretKey: SecretKey(Uint8List.fromList(ikm)),
    nonce: salt,
    info: info,
  );
  final out = Uint8List.fromList(await key.extractBytes());
  key.destroy();
  return out;
}

/// DH ratchet step: (newRootKey, newChainKey) from the old root and a fresh
/// DH output.
Future<(Uint8List, Uint8List)> kdfRootKey(List<int> rootKey, List<int> dhOutput) async {
  final out = await hkdfSha256(
    ikm: dhOutput,
    salt: rootKey,
    info: utf8.encode(rootKdfLabel),
    length: 64,
  );
  final keys = (Uint8List.fromList(out.sublist(0, 32)), Uint8List.fromList(out.sublist(32)));
  out.fillRange(0, out.length, 0);
  return keys;
}

Future<Uint8List> deriveMessageKey(List<int> chainKey, int counter) => hkdfSha256(
      ikm: chainKey,
      salt: utf8.encode('veil-msg-n$counter'),
      info: utf8.encode(messageKeyLabel),
      length: 32,
    );

Future<Uint8List> nextChainKey(List<int> chainKey) => hkdfSha256(
      ikm: chainKey,
      salt: const [0],
      info: utf8.encode(chainKeyLabel),
      length: 32,
    );
