/// Local identity and prekey private material: generation, rotation, and
/// the lookups a responder needs to answer a PreKey frame.
library;

import 'dart:math';
import 'dart:typed_data';

import '../bytes.dart';
import '../crypto_engine.dart';
import '../random_source.dart';
import 'curve25519.dart';
import 'identity_keys.dart';
import 'x3dh_handshake.dart';

// How long a superseded signed prekey still answers PreKey frames, so
// initiators holding a just-rotated bundle are not stranded.
const Duration signedPrekeyGrace = Duration(days: 14);
const int firstSignedPrekeyId = 1;

/// Public keys derived once from a parsed identity ref.
class LocalIdentityKeys {
  LocalIdentityKeys(this.identity, this.ed25519Public, this.x25519Public);

  final LocalIdentity identity;
  final Uint8List ed25519Public;
  final Uint8List x25519Public;

  Future<Uint8List> signIkx() => ed25519Sign(identity.ed25519Seed, ikxSignedMessage(x25519Public));

  void destroy() => identity.destroy();
}

class HandshakePrekeys {
  HandshakePrekeys(this.identity, this.signedPrekey, this.oneTimePrekeyPrivate);

  final LocalIdentityKeys identity;
  final X25519KeyPair signedPrekey;
  final Uint8List? oneTimePrekeyPrivate;

  void destroy() {
    identity.destroy();
    zeroize(signedPrekey.privateKey);
    zeroize(oneTimePrekeyPrivate);
  }
}

/// A PreKey frame names prekeys this device can no longer use.
class PrekeyUnavailable implements Exception {
  PrekeyUnavailable(this.reason);

  final String reason;
}

class LocalKeyring {
  LocalKeyring({required RandomSource random, required DateTime Function() clock})
      : _random = random,
        _clock = clock;

  final RandomSource _random;
  final DateTime Function() _clock;
  final Set<int> _oneTimePrekeysInUse = {};
  // Used by a committed session. Remembered for the process lifetime so a
  // failed delete cannot make a one-time prekey claimable again.
  final Set<int> _spentOneTimePrekeys = {};

  LocalPrekeyStore store = InMemoryLocalPrekeyStore();
  Future<String?> Function()? identityLoader;
  // Fallbacks so an adapter works before the host wires a loader: the
  // identity this instance generated, then the ref a legacy inbound
  // bootstrap was handed.
  String? generatedIdentityRef;
  String? inboundIdentityRef;

  Future<LocalIdentityKeys> resolveIdentity() async {
    final loaded = await identityLoader?.call();
    final ref = [loaded, generatedIdentityRef, inboundIdentityRef].firstWhere(
      (candidate) => candidate != null && candidate.isNotEmpty,
      orElse: () => throw StateError('No local identity is available for protocol v2.'),
    )!;
    final identity = LocalIdentity.tryParse(ref);
    if (identity == null) {
      throw StateError('Local identity private ref is malformed.');
    }
    final ikx = await x25519KeyPairFromPrivate(identity.x25519Private);
    zeroize(ikx.privateKey);
    return LocalIdentityKeys(identity, await ed25519PublicKeyFromSeed(identity.ed25519Seed), ikx.publicKey);
  }

  Future<DeviceIdentityMaterial> generateIdentity() async {
    final seed = _random.nextBytes(32);
    final ikx = await generateX25519KeyPair(_random);
    final spk = await generateX25519KeyPair(_random);
    final createdAt = _clock();
    final bundle = await PrekeyBundleV2.sign(
      ed25519Seed: seed,
      ikx: ikx.publicKey,
      spkId: firstSignedPrekeyId,
      spk: spk.publicKey,
      createdAt: createdAt,
    );
    final ref = LocalIdentity.encodeV2(
      ed25519Seed: seed,
      x25519Private: ikx.privateKey,
      signedPrekey: SignedPrekeySecret(id: firstSignedPrekeyId, privateKey: spk.privateKey, createdAt: createdAt),
    );
    generatedIdentityRef = ref;
    final identityPublicKey = b64uEncode(await ed25519PublicKeyFromSeed(seed));
    [seed, ikx.privateKey, spk.privateKey].forEach(zeroize);
    return DeviceIdentityMaterial(
      identityPublicKey: identityPublicKey,
      identityPrivateKeyRef: ref,
      signedPrekeyBundle: bundle.encode(),
    );
  }

  Future<List<OneTimePrekey>> generateOneTimePrekeys(int count) async {
    final first = await store.reserveOneTimePrekeyIds(count);
    if (first + count > noOneTimePrekeyId) {
      throw StateError('One-time prekey ids are exhausted.');
    }
    final out = <OneTimePrekey>[];
    for (var keyId = first; keyId < first + count; keyId++) {
      final pair = await generateX25519KeyPair(_random);
      await store.saveOneTimePrekey(keyId, pair.privateKey);
      zeroize(pair.privateKey);
      out.add(OneTimePrekey(keyId: keyId, publicKey: b64uEncode(pair.publicKey)));
    }
    return out;
  }

  Future<SignedPrekeyRotation> rotateSignedPrekey() async {
    final keys = await resolveIdentity();
    try {
      return await _rotateSignedPrekey(keys);
    } finally {
      keys.destroy();
    }
  }

  Future<SignedPrekeyRotation> _rotateSignedPrekey(LocalIdentityKeys keys) async {
    final identity = keys.identity;
    final stored = await _signedPrekeysInStore(identity);
    final spkId = stored.fold<int>(0, (highest, p) => max(highest, p.keyId)) + 1;
    if (spkId >= maxU32) {
      throw StateError('Signed prekey ids are exhausted.');
    }
    final pair = await generateX25519KeyPair(_random);
    final createdAt = _clock();
    await store.saveSignedPrekey(StoredSignedPrekey(keyId: spkId, privateKey: pair.privateKey, createdAt: createdAt));
    final bundle = await PrekeyBundleV2.sign(
      ed25519Seed: identity.ed25519Seed,
      ikx: keys.x25519Public,
      spkId: spkId,
      spk: pair.publicKey,
      createdAt: createdAt,
    );
    // A v1 ref has no SPK slot; its X25519 identity key becomes IKx.
    final upgradedRef = identity.version < 2
        ? LocalIdentity.encodeV2(
            ed25519Seed: identity.ed25519Seed,
            x25519Private: identity.x25519Private,
            signedPrekey: SignedPrekeySecret(id: spkId, privateKey: pair.privateKey, createdAt: createdAt),
          )
        : null;
    zeroize(pair.privateKey);
    return SignedPrekeyRotation(
      signedPrekeyBundle: bundle.encode(),
      spkId: spkId,
      createdAt: createdAt,
      upgradedIdentityPrivateRef: upgradedRef,
    );
  }

  Future<DateTime?> currentSignedPrekeyCreatedAt() async {
    final stored = _sorted(await store.loadSignedPrekeys());
    if (stored.isNotEmpty) return stored.last.createdAt;
    final keys = await resolveIdentity();
    keys.destroy();
    return keys.identity.signedPrekey?.createdAt;
  }

  Future<int> pruneSignedPrekeys(Duration grace) async {
    final stored = _sorted(await store.loadSignedPrekeys());
    final now = _clock();
    var pruned = 0;
    for (var i = 0; i < stored.length - 1; i++) {
      if (now.difference(stored[i + 1].createdAt) > grace) {
        await store.deleteSignedPrekey(stored[i].keyId);
        pruned += 1;
      }
    }
    return pruned;
  }

  /// Loads everything needed to answer [header], claiming its one-time
  /// prekey so a concurrent handshake cannot use it too. Callers must
  /// [releaseOneTimePrekey] when done.
  Future<HandshakePrekeys> claimHandshakePrekeys(PreKeyHeader header) async {
    final LocalIdentityKeys identity;
    try {
      identity = await resolveIdentity();
    } on StateError {
      throw PrekeyUnavailable('local_identity_unavailable');
    }
    X25519KeyPair? signedPrekey;
    try {
      signedPrekey = await _signedPrekey(identity.identity, header.signedPrekeyId);
      if (signedPrekey == null) throw PrekeyUnavailable('spk_unavailable');
      return HandshakePrekeys(identity, signedPrekey, await _claimOneTimePrekey(header));
    } catch (_) {
      // Any sender can name unknown prekeys; do not leave the private keys
      // already loaded for it lingering in memory.
      identity.destroy();
      zeroize(signedPrekey?.privateKey);
      rethrow;
    }
  }

  Future<Uint8List?> _claimOneTimePrekey(PreKeyHeader header) async {
    if (!header.usesOneTimePrekey) return null;
    final keyId = header.oneTimePrekeyId;
    if (_spentOneTimePrekeys.contains(keyId) || !_oneTimePrekeysInUse.add(keyId)) {
      throw PrekeyUnavailable('opk_unavailable');
    }
    final oneTime = await store.loadOneTimePrekey(keyId);
    if (oneTime == null) {
      _oneTimePrekeysInUse.remove(keyId);
      throw PrekeyUnavailable('opk_unavailable');
    }
    return Uint8List.fromList(oneTime);
  }

  void releaseOneTimePrekey(PreKeyHeader header) => _oneTimePrekeysInUse.remove(header.oneTimePrekeyId);

  Future<void> consumeOneTimePrekey(int keyId) {
    _spentOneTimePrekeys.add(keyId);
    return store.deleteOneTimePrekey(keyId);
  }

  // The store is authoritative once a rotation has populated it; until then
  // the only SPK is the one embedded in the identity ref.
  Future<X25519KeyPair?> _signedPrekey(LocalIdentity identity, int spkId) async {
    final stored = _sorted(await store.loadSignedPrekeys());
    if (stored.isEmpty) {
      final embedded = identity.signedPrekey;
      return embedded != null && embedded.id == spkId ? x25519KeyPairFromPrivate(embedded.privateKey) : null;
    }
    final index = stored.indexWhere((p) => p.keyId == spkId);
    if (index < 0) return null;
    final successor = index + 1 < stored.length ? stored[index + 1] : null;
    if (successor != null && _clock().difference(successor.createdAt) > signedPrekeyGrace) return null;
    return x25519KeyPairFromPrivate(stored[index].privateKey);
  }

  Future<List<StoredSignedPrekey>> _signedPrekeysInStore(LocalIdentity identity) async {
    final stored = await store.loadSignedPrekeys();
    final embedded = identity.signedPrekey;
    if (stored.isNotEmpty || embedded == null) return stored;
    // First rotation: retain the embedded SPK so in-flight handshakes that
    // name it are answered through the grace period.
    final retained = StoredSignedPrekey(
      keyId: embedded.id,
      privateKey: embedded.privateKey,
      createdAt: embedded.createdAt,
    );
    await store.saveSignedPrekey(retained);
    return [retained];
  }

  static List<StoredSignedPrekey> _sorted(List<StoredSignedPrekey> prekeys) =>
      List.of(prekeys)..sort((a, b) => a.keyId.compareTo(b.keyId));
}
