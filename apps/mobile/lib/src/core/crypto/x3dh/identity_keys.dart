/// Identity private refs and published prekey bundles (contract C1).
///
/// Every peer holds an Ed25519 identity key (IK) and an X25519 identity key
/// (IKx) certified by IK, plus a rotating signed prekey (SPK). Bundles are
/// base64url(compact UTF-8 JSON) with a fixed key order so independent
/// implementations produce identical strings.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../bytes.dart';
import 'curve25519.dart';

const String ikxSignatureLabel = 'veil-ikx-v2';
const String spkSignatureLabel = 'veil-spk-v2';
const int maxU32 = 0xFFFFFFFF;

// A signed prekey older than this is refused at session start: a server
// replaying an abandoned prekey would otherwise extend its exposure window.
const Duration maxSignedPrekeyAge = Duration(days: 60);
// Tolerates clock skew between devices without accepting far-future stamps.
const Duration maxSignedPrekeyClockSkew = Duration(days: 1);

class SignedPrekeySecret {
  SignedPrekeySecret({required this.id, required this.privateKey, required this.createdAt});

  final int id;
  final Uint8List privateKey;
  final DateTime createdAt;
}

/// Parsed opaque identity private ref. v1 refs carry only the identity keys;
/// v2 refs also carry the SPK published alongside them.
class LocalIdentity {
  LocalIdentity({
    required this.version,
    required this.ed25519Seed,
    required this.x25519Private,
    this.signedPrekey,
  });

  final int version;
  final Uint8List ed25519Seed;
  final Uint8List x25519Private;
  final SignedPrekeySecret? signedPrekey;

  /// Wipes the private keys parsed out of the ref once an operation is done
  /// with them; the ref itself stays in secure storage.
  void destroy() {
    zeroize(ed25519Seed);
    zeroize(x25519Private);
    zeroize(signedPrekey?.privateKey);
  }

  static LocalIdentity? tryParse(String ref) {
    try {
      final map = json.decode(utf8.decode(b64uDecode(ref))) as Map<String, dynamic>;
      final ed = b64uDecode(map['ed25519'] as String);
      final x = b64uDecode(map['x25519'] as String);
      if (ed.length != 32 || x.length != 32) return null;
      final version = (map['v'] as num?)?.toInt() ?? 1;
      SignedPrekeySecret? spk;
      if (version >= 2) {
        final spkMap = map['spk'] as Map<String, dynamic>;
        final priv = b64uDecode(spkMap['priv'] as String);
        if (priv.length != 32) return null;
        spk = SignedPrekeySecret(
          id: (spkMap['id'] as num).toInt(),
          privateKey: priv,
          createdAt: DateTime.fromMillisecondsSinceEpoch((spkMap['ts'] as num).toInt(), isUtc: true),
        );
      }
      return LocalIdentity(version: version, ed25519Seed: ed, x25519Private: x, signedPrekey: spk);
    } catch (_) {
      return null;
    }
  }

  static String encodeV2({
    required List<int> ed25519Seed,
    required List<int> x25519Private,
    required SignedPrekeySecret signedPrekey,
  }) {
    final map = {
      'v': 2,
      'ed25519': b64uEncode(ed25519Seed),
      'x25519': b64uEncode(x25519Private),
      'spk': {
        'id': signedPrekey.id,
        'priv': b64uEncode(signedPrekey.privateKey),
        'ts': signedPrekey.createdAt.millisecondsSinceEpoch,
      },
    };
    return b64uEncode(utf8.encode(json.encode(map)));
  }
}

Uint8List ikxSignedMessage(List<int> ikx) => concatBytes([utf8.encode(ikxSignatureLabel), ikx]);

Uint8List spkSignedMessage(int spkId, int spkTimestampMs, List<int> spk) =>
    concatBytes([utf8.encode(spkSignatureLabel), u32be(spkId), u64be(spkTimestampMs), spk]);

Future<bool> verifyIkxSignature(List<int> identityEd25519, List<int> ikx, List<int> signature) =>
    ed25519Verify(identityEd25519, ikxSignedMessage(ikx), signature);

/// A verified remote bundle: either the legacy single-key form or v2.
sealed class RemotePrekeyBundle {}

class LegacyPrekeyBundle implements RemotePrekeyBundle {
  LegacyPrekeyBundle(this.x25519);

  final Uint8List x25519;
}

class PrekeyBundleV2 implements RemotePrekeyBundle {
  PrekeyBundleV2({
    required this.ikx,
    required this.ikxSignature,
    required this.spkId,
    required this.spk,
    required this.spkTimestampMs,
    required this.spkSignature,
  });

  final Uint8List ikx;
  final Uint8List ikxSignature;
  final int spkId;
  final Uint8List spk;
  final int spkTimestampMs;
  final Uint8List spkSignature;

  static Future<PrekeyBundleV2> sign({
    required List<int> ed25519Seed,
    required List<int> ikx,
    required int spkId,
    required List<int> spk,
    required DateTime createdAt,
  }) async {
    final ts = createdAt.millisecondsSinceEpoch;
    return PrekeyBundleV2(
      ikx: Uint8List.fromList(ikx),
      ikxSignature: await ed25519Sign(ed25519Seed, ikxSignedMessage(ikx)),
      spkId: spkId,
      spk: Uint8List.fromList(spk),
      spkTimestampMs: ts,
      spkSignature: await ed25519Sign(ed25519Seed, spkSignedMessage(spkId, ts, spk)),
    );
  }

  String encode() {
    final compact = json.encode({
      'v': 2,
      'ikx': b64uEncode(ikx),
      'ikxSig': b64uEncode(ikxSignature),
      'spkId': spkId,
      'spk': b64uEncode(spk),
      'spkTs': spkTimestampMs,
      'spkSig': b64uEncode(spkSignature),
    });
    return b64uEncode(utf8.encode(compact));
  }
}

/// Parses and AUTHENTICATES a directory bundle against the peer's Ed25519
/// identity key. A hostile server that swaps any key cannot re-sign it, so
/// every failure throws instead of degrading. When [now] is given, the SPK
/// timestamp must also be fresh.
Future<RemotePrekeyBundle> verifyRemoteBundle(
  String signedPrekeyBundle,
  String identityPublicKey, {
  DateTime? now,
}) async {
  final Map<String, dynamic> map;
  try {
    map = json.decode(utf8.decode(b64uDecode(signedPrekeyBundle))) as Map<String, dynamic>;
  } catch (e) {
    throw StateError('Signed prekey bundle is malformed: $e');
  }
  final identity = _decodeKey(identityPublicKey, 32, 'Remote identity public key');
  if (map['v'] == 2) {
    final bundle = _parseV2(map);
    await _verifyV2(bundle, identity);
    if (now != null) _checkFreshness(bundle.spkTimestampMs, now);
    return bundle;
  }
  return _verifyLegacy(map, identity);
}

PrekeyBundleV2 _parseV2(Map<String, dynamic> map) {
  final spkId = map['spkId'];
  final spkTs = map['spkTs'];
  if (spkId is! int || spkId < 0 || spkId > maxU32 || spkTs is! int || spkTs < 0) {
    throw StateError('Signed prekey bundle has an invalid spkId or spkTs.');
  }
  return PrekeyBundleV2(
    ikx: _decodeField(map, 'ikx', 32),
    ikxSignature: _decodeField(map, 'ikxSig', 64),
    spkId: spkId,
    spk: _decodeField(map, 'spk', 32),
    spkTimestampMs: spkTs,
    spkSignature: _decodeField(map, 'spkSig', 64),
  );
}

Future<void> _verifyV2(PrekeyBundleV2 bundle, Uint8List identity) async {
  if (!await verifyIkxSignature(identity, bundle.ikx, bundle.ikxSignature)) {
    throw StateError('Bundle ikxSig did not verify against the remote identity key (possible MITM).');
  }
  final spkMessage = spkSignedMessage(bundle.spkId, bundle.spkTimestampMs, bundle.spk);
  if (!await ed25519Verify(identity, spkMessage, bundle.spkSignature)) {
    throw StateError('Bundle spkSig did not verify against the remote identity key (possible MITM).');
  }
}

void _checkFreshness(int spkTimestampMs, DateTime now) {
  final created = DateTime.fromMillisecondsSinceEpoch(spkTimestampMs, isUtc: true);
  if (now.difference(created) > maxSignedPrekeyAge) {
    throw StateError('Signed prekey is stale (created $created); refusing to start a session.');
  }
  if (created.difference(now) > maxSignedPrekeyClockSkew) {
    throw StateError('Signed prekey timestamp $created is in the future; refusing it.');
  }
}

// Legacy v1 bundle: { "v": 1, "x25519": pub, "sig": Ed25519(IK, pub) }.
Future<LegacyPrekeyBundle> _verifyLegacy(Map<String, dynamic> map, Uint8List identity) async {
  if (map['x25519'] is! String || map['sig'] is! String) {
    throw StateError(
      'Signed prekey bundle missing x25519 or sig field — refusing to accept unsigned peer key.',
    );
  }
  final x25519 = _decodeField(map, 'x25519', 32);
  final signature = b64uDecode(map['sig'] as String);
  if (!await ed25519Verify(identity, x25519, signature)) {
    throw StateError(
      'Signed prekey signature did not verify against remote identity key — '
      'aborting session bootstrap (possible MITM).',
    );
  }
  return LegacyPrekeyBundle(x25519);
}

Uint8List _decodeField(Map<String, dynamic> map, String field, int length) {
  final value = map[field];
  if (value is! String) {
    throw StateError('Signed prekey bundle is missing "$field".');
  }
  return _decodeKey(value, length, 'Bundle field "$field"');
}

Uint8List _decodeKey(String value, int length, String label) {
  final Uint8List bytes;
  try {
    bytes = b64uDecode(value);
  } catch (_) {
    throw StateError('$label is not valid base64url.');
  }
  if (bytes.length != length) {
    throw StateError('$label has wrong length (expected $length, got ${bytes.length}).');
  }
  return bytes;
}
