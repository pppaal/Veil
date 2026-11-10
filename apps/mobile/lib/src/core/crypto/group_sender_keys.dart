import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

// ---------------------------------------------------------------------------
// Group Sender Keys (phase AB.3, mobile).
//
// Implements docs/group-sender-keys-design.md: every member owns a per-group
// symmetric *chain key* that advances one-way per send, plus a per-epoch
// Ed25519 *signing key* that binds authorship. A send is encrypted exactly
// once; the server fans the same ciphertext out to every member. Members hold
// each other's (chainKey, counter, signingPub) so they can derive the same
// per-message keys.
//
// Membership changes bump the group *epoch*. On every bump each member throws
// away all chain state for the group and starts a fresh chain + signing key
// (design "Option A": full reset on every churn), then redistributes it to the
// remaining members. A removed member therefore holds no key that decrypts
// any post-removal message, and a joiner holds no key that decrypts anything
// sent before they joined.
//
// Threat-model notes (for the external reviewer):
//   * Forward secrecy within a chain: chain keys advance via HKDF and the
//     previous value is discarded, so a leaked chain key reveals only
//     messages sent *after* the leak.
//   * Authorship: each frame carries an Ed25519 signature over
//     (AD || nonce || ciphertext) under the sender's per-epoch signing key.
//     A member who re-encrypts content under their own chain cannot forge
//     another member's signature, and a replayed frame under a different
//     senderDeviceId fails both the AEAD (senderDeviceId is in the AD) and
//     the signature check.
//   * Epoch binding: the epoch is part of the AD and of the signed bytes, so
//     a frame produced under a stale epoch (e.g. by a removed member) is
//     rejected before any key material is touched.
//
// Pre-audit engineering. Do not flip VEIL_AUDITED_CRYPTO_ATTESTED on the
// strength of this file.
// ---------------------------------------------------------------------------

/// Envelope `version` for group frames. The server allowlists it alongside
/// `veil-envelope-v1` but never interprets the ciphertext.
const String kGroupEnvelopeVersion = 'veil-group-v1';

/// `version` marker carried on key-distribution blobs
/// (POST /conversations/group/:id/key-distribute).
const String kGroupKeyDistributionVersion = 'veil-gkd-v1';

/// Persisted snapshot schema for [GroupSenderKeyEngine] state.
const int kGroupSnapshotSchemaVersion = 1;

/// Per-peer cap on stashed out-of-order message keys (design: 1000).
const int kMaxSkippedKeysPerPeer = 1000;

/// Hard cap on how far ahead of a peer's counter a single frame may jump.
/// Bounds the CPU/memory an attacker can force by sending `ctr = 2^32 - 1`.
const int kMaxForwardSkip = 2000;

/// Frame layout version byte.
const int _kFrameVersion = 0x01;
const int _kSignatureLength = 64;
const int _kTagLength = 16;
const int _kNonceLength = 12;

const String _kChainInfo = 'veil-gck-v1';
const String _kMessageKeyInfo = 'veil-gmk-v1';
const String _kDistributionWrapInfo = 'veil-gkd-wrap-v1';

final AesGcm _aesGcm = AesGcm.with256bits();
final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
final Ed25519 _ed25519 = Ed25519();
final X25519 _x25519 = X25519();
final Random _random = Random.secure();

String _b64Encode(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _b64Decode(String value) {
  final padded = value.padRight(
    value.length + ((4 - value.length % 4) % 4),
    '=',
  );
  return Uint8List.fromList(base64Url.decode(padded));
}

Uint8List _u32(int value) {
  final out = Uint8List(4);
  ByteData.view(out.buffer).setUint32(0, value, Endian.big);
  return out;
}

Uint8List _u64(int value) {
  final out = Uint8List(8);
  ByteData.view(out.buffer).setUint64(0, value, Endian.big);
  return out;
}

Uint8List _lengthPrefixed(List<int> bytes) {
  if (bytes.length > 0xFFFF) {
    throw ArgumentError('field too long for u16 length prefix');
  }
  final out = Uint8List(2 + bytes.length);
  ByteData.view(out.buffer).setUint16(0, bytes.length, Endian.big);
  out.setRange(2, out.length, bytes);
  return out;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

List<int> _randomBytes(int n) => List<int>.generate(n, (_) => _random.nextInt(256));

/// Typed failure surfaced by the engine. `code` is stable and safe to branch
/// on in app logic; `message` is for logs/tests and never contains plaintext.
class GroupCryptoException implements Exception {
  const GroupCryptoException(this.code, [this.message]);

  /// One of: `malformed`, `noOwnSenderKey`, `senderKeyMissing`,
  /// `epochMismatch`, `signatureInvalid`, `replayed`, `tooFarAhead`,
  /// `decryptFailed`, `distributionInvalid`.
  final String code;
  final String? message;

  @override
  String toString() => 'GroupCryptoException($code${message == null ? '' : ': $message'})';
}

/// What one member hands another so the recipient can decrypt the member's
/// future frames. Chain key + counter describe the chain *as of now*; the
/// recipient can decrypt counter ≥ [counter] and nothing earlier.
class GroupSenderKey {
  const GroupSenderKey({
    required this.groupId,
    required this.epoch,
    required this.senderDeviceId,
    required this.chainKey,
    required this.counter,
    required this.signingPublicKey,
  });

  final String groupId;
  final int epoch;
  final String senderDeviceId;
  final List<int> chainKey;
  final int counter;
  final List<int> signingPublicKey;

  Map<String, dynamic> toJson() => {
        'v': 1,
        'groupId': groupId,
        'epoch': epoch,
        'senderDeviceId': senderDeviceId,
        'chainKey': _b64Encode(chainKey),
        'counter': counter,
        'signingPub': _b64Encode(signingPublicKey),
      };

  static GroupSenderKey fromJson(Map<String, dynamic> json) {
    final chainKey = _b64Decode(json['chainKey'] as String);
    final signingPub = _b64Decode(json['signingPub'] as String);
    final counter = json['counter'] as int;
    final epoch = json['epoch'] as int;
    if (chainKey.length != 32 || signingPub.length != 32 || counter < 0 || epoch < 0) {
      throw const GroupCryptoException('distributionInvalid', 'bad sender key shape');
    }
    return GroupSenderKey(
      groupId: json['groupId'] as String,
      epoch: epoch,
      senderDeviceId: json['senderDeviceId'] as String,
      chainKey: chainKey,
      counter: counter,
      signingPublicKey: signingPub,
    );
  }
}

/// Parsed, unauthenticated frame header. Only used for routing decisions
/// (which epoch / which sender) *before* verification; never trust it for
/// anything else.
class GroupFrameHeader {
  const GroupFrameHeader({
    required this.senderDeviceId,
    required this.epoch,
    required this.counter,
  });

  final String senderDeviceId;
  final int epoch;
  final int counter;
}

/// Output of [GroupSenderKeyEngine.encrypt].
class GroupCiphertext {
  const GroupCiphertext({required this.payload, required this.nonce});

  /// base64url frame: see `_encodeFrame`.
  final String payload;
  final String nonce;
}

/// Output of [GroupSenderKeyEngine.decrypt].
class GroupPlaintext {
  const GroupPlaintext({
    required this.plaintext,
    required this.senderDeviceId,
    required this.epoch,
    required this.counter,
  });

  final List<int> plaintext;
  final String senderDeviceId;
  final int epoch;
  final int counter;
}

/// Hook for persisting a group's state to secure storage. `snapshot == null`
/// means the group's state was dropped and the stored copy must be deleted.
typedef GroupStatePersister = Future<void> Function(
  String groupId,
  Map<String, dynamic>? snapshot,
);

// ---------------------------------------------------------------------------
// Internal state
// ---------------------------------------------------------------------------

class _PeerChain {
  _PeerChain({
    required this.chainKey,
    required this.counter,
    required this.signingPublicKey,
  });

  /// Chain key at [counter] (i.e. the key that derives message `counter`).
  List<int> chainKey;
  int counter;
  final List<int> signingPublicKey;
  final Map<int, List<int>> skippedKeys = <int, List<int>>{};

  Map<String, dynamic> toJson() => {
        'chainKey': _b64Encode(chainKey),
        'counter': counter,
        'signingPub': _b64Encode(signingPublicKey),
        'skipped': {
          for (final e in skippedKeys.entries) e.key.toString(): _b64Encode(e.value),
        },
      };

  static _PeerChain fromJson(Map<String, dynamic> json) {
    final chain = _PeerChain(
      chainKey: _b64Decode(json['chainKey'] as String),
      counter: json['counter'] as int,
      signingPublicKey: _b64Decode(json['signingPub'] as String),
    );
    final skipped = json['skipped'];
    if (skipped is Map) {
      skipped.forEach((k, v) {
        final ctr = int.tryParse(k.toString());
        if (ctr != null && v is String) {
          chain.skippedKeys[ctr] = _b64Decode(v);
        }
      });
    }
    return chain;
  }

  void wipe() {
    chainKey.fillRange(0, chainKey.length, 0);
    for (final k in skippedKeys.values) {
      k.fillRange(0, k.length, 0);
    }
    skippedKeys.clear();
  }
}

class _OwnChain {
  _OwnChain({
    required this.deviceId,
    required this.chainKey,
    required this.counter,
    required this.signingSeed,
    required this.signingPublicKey,
  });

  final String deviceId;
  List<int> chainKey;
  int counter;
  final List<int> signingSeed;
  final List<int> signingPublicKey;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'chainKey': _b64Encode(chainKey),
        'counter': counter,
        'signingSeed': _b64Encode(signingSeed),
        'signingPub': _b64Encode(signingPublicKey),
      };

  static _OwnChain fromJson(Map<String, dynamic> json) => _OwnChain(
        deviceId: json['deviceId'] as String,
        chainKey: _b64Decode(json['chainKey'] as String),
        counter: json['counter'] as int,
        signingSeed: _b64Decode(json['signingSeed'] as String),
        signingPublicKey: _b64Decode(json['signingPub'] as String),
      );

  void wipe() {
    chainKey.fillRange(0, chainKey.length, 0);
    signingSeed.fillRange(0, signingSeed.length, 0);
  }
}

class _GroupState {
  _GroupState({required this.groupId, required this.epoch});

  final String groupId;
  int epoch;
  _OwnChain? own;
  final Map<String, _PeerChain> peers = <String, _PeerChain>{};

  Map<String, dynamic> toJson() => {
        'schema': kGroupSnapshotSchemaVersion,
        'groupId': groupId,
        'epoch': epoch,
        if (own != null) 'own': own!.toJson(),
        'peers': {for (final e in peers.entries) e.key: e.value.toJson()},
      };

  static _GroupState? tryRestore(Map<String, dynamic> json) {
    try {
      if (json['schema'] != kGroupSnapshotSchemaVersion) return null;
      final state = _GroupState(
        groupId: json['groupId'] as String,
        epoch: json['epoch'] as int,
      );
      if (json['own'] is Map) {
        state.own = _OwnChain.fromJson((json['own'] as Map).cast<String, dynamic>());
      }
      final peers = json['peers'];
      if (peers is Map) {
        peers.forEach((k, v) {
          if (v is Map) {
            state.peers[k.toString()] = _PeerChain.fromJson(v.cast<String, dynamic>());
          }
        });
      }
      return state;
    } catch (_) {
      return null;
    }
  }

  void wipe() {
    own?.wipe();
    own = null;
    for (final p in peers.values) {
      p.wipe();
    }
    peers.clear();
  }
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

class GroupSenderKeyEngine {
  GroupSenderKeyEngine({GroupStatePersister? persister}) : _persister = persister;

  final Map<String, _GroupState> _groups = <String, _GroupState>{};
  GroupStatePersister? _persister;

  void setPersistence({GroupStatePersister? persister}) {
    _persister = persister;
  }

  /// Rehydrates state written by [GroupStatePersister]. Snapshots with an
  /// unknown schema are dropped (the next send re-keys the group), never
  /// "migrated" into something that could resurrect old key material.
  Future<void> restoreFromSnapshots(Map<String, Map<String, dynamic>> snapshots) async {
    for (final entry in snapshots.entries) {
      final restored = _GroupState.tryRestore(entry.value);
      if (restored != null) {
        _groups[entry.key] = restored;
      }
    }
  }

  Future<void> _persist(String groupId) async {
    final persister = _persister;
    if (persister == null) return;
    final state = _groups[groupId];
    await persister(groupId, state?.toJson());
  }

  /// Epoch we currently hold state for, or null if we have none.
  int? currentEpoch(String groupId) => _groups[groupId]?.epoch;

  /// True if we have a chain of our own for this group at this epoch.
  bool hasOwnSenderKey({required String groupId, required int epoch, required String localDeviceId}) {
    final state = _groups[groupId];
    final own = state?.own;
    return state != null && own != null && state.epoch == epoch && own.deviceId == localDeviceId;
  }

  /// True if we hold a chain for [senderDeviceId] at the group's current epoch.
  bool hasSenderKeyFor({required String groupId, required String senderDeviceId}) {
    return _groups[groupId]?.peers.containsKey(senderDeviceId) ?? false;
  }

  /// Device ids we currently hold peer chains for (includes our own device).
  Set<String> knownSenders(String groupId) =>
      Set<String>.unmodifiable(_groups[groupId]?.peers.keys ?? const <String>[]);

  /// Guarantees we own a fresh chain + signing key for ([groupId], [epoch]).
  ///
  /// If our state is for a different epoch (membership changed) or we have
  /// none, *all* state for the group is wiped and a new chain is created —
  /// peers' keys from the old epoch are useless and must not linger. Returns
  /// the distribution record to hand to every other member. `forceRotate`
  /// re-keys even within the same epoch (e.g. after a suspected compromise).
  Future<GroupSenderKey> ensureOwnSenderKey({
    required String groupId,
    required int epoch,
    required String localDeviceId,
    bool forceRotate = false,
  }) async {
    var state = _groups[groupId];
    if (state == null || state.epoch != epoch) {
      state?.wipe();
      state = _GroupState(groupId: groupId, epoch: epoch);
      _groups[groupId] = state;
    }
    final existing = state.own;
    if (!forceRotate && existing != null && existing.deviceId == localDeviceId) {
      return _exportOwn(state);
    }

    existing?.wipe();
    // Our previous self-chain (if any) is obsolete too.
    state.peers.remove(localDeviceId)?.wipe();

    final signingPair = await _ed25519.newKeyPair();
    final signingSeed = (await signingPair.extract()).bytes;
    final signingPub = (await signingPair.extractPublicKey()).bytes;
    final chainKey = _randomBytes(32);

    state.own = _OwnChain(
      deviceId: localDeviceId,
      chainKey: List<int>.from(chainKey),
      counter: 0,
      signingSeed: List<int>.from(signingSeed),
      signingPublicKey: List<int>.from(signingPub),
    );
    // Register ourselves as a peer too so our own frames (fetched back from
    // server history on another screen / after restart) decrypt locally.
    state.peers[localDeviceId] = _PeerChain(
      chainKey: List<int>.from(chainKey),
      counter: 0,
      signingPublicKey: List<int>.from(signingPub),
    );
    await _persist(groupId);
    return _exportOwn(state);
  }

  GroupSenderKey _exportOwn(_GroupState state) {
    final own = state.own!;
    return GroupSenderKey(
      groupId: state.groupId,
      epoch: state.epoch,
      senderDeviceId: own.deviceId,
      chainKey: List<int>.unmodifiable(own.chainKey),
      counter: own.counter,
      signingPublicKey: List<int>.unmodifiable(own.signingPublicKey),
    );
  }

  /// Our current distribution record, or null if we have no chain yet.
  GroupSenderKey? exportOwnSenderKey(String groupId) {
    final state = _groups[groupId];
    if (state?.own == null) return null;
    return _exportOwn(state!);
  }

  /// Installs a peer's chain. Called after a `group.key.distribution` blob
  /// has been unsealed and its sender authenticated by the caller.
  ///
  /// A record for a *newer* epoch than ours resets the group (we missed the
  /// bump); a record for an *older* epoch is rejected. Within an epoch a
  /// redistribution overwrites the previous chain (idempotent, matches the
  /// server's relay semantics).
  Future<void> ingestSenderKey(GroupSenderKey key) async {
    var state = _groups[key.groupId];
    if (state == null || key.epoch > state.epoch) {
      state?.wipe();
      state = _GroupState(groupId: key.groupId, epoch: key.epoch);
      _groups[key.groupId] = state;
    } else if (key.epoch < state.epoch) {
      throw const GroupCryptoException('epochMismatch', 'sender key is for a stale epoch');
    }
    if (state.own != null && key.senderDeviceId == state.own!.deviceId) {
      // Never let a remote blob overwrite our own chain.
      throw const GroupCryptoException('distributionInvalid', 'refusing to overwrite own chain');
    }
    state.peers.remove(key.senderDeviceId)?.wipe();
    state.peers[key.senderDeviceId] = _PeerChain(
      chainKey: List<int>.from(key.chainKey),
      counter: key.counter,
      signingPublicKey: List<int>.from(key.signingPublicKey),
    );
    await _persist(key.groupId);
  }

  /// Forgets a departed member's chain. Their frames will fail with
  /// `senderKeyMissing` from now on even if the epoch gate were bypassed.
  Future<void> dropPeer({required String groupId, required String senderDeviceId}) async {
    final state = _groups[groupId];
    if (state == null) return;
    state.peers.remove(senderDeviceId)?.wipe();
    await _persist(groupId);
  }

  /// Drops every chain for the group (ours included). The next
  /// [ensureOwnSenderKey] starts the new epoch. Called on `group.epoch.bumped`.
  Future<void> resetForEpoch({required String groupId, required int epoch}) async {
    final state = _groups[groupId];
    if (state != null) {
      state.wipe();
      state.epoch = epoch;
    } else {
      _groups[groupId] = _GroupState(groupId: groupId, epoch: epoch);
    }
    await _persist(groupId);
  }

  /// Removes all state for the group (left/removed/deleted).
  Future<void> forget(String groupId) async {
    _groups.remove(groupId)?.wipe();
    await _persist(groupId);
  }

  /// Drops in-memory state without touching persistence. Used on logout,
  /// after the secure store has already been wiped by the session layer.
  void clearInMemory() {
    for (final g in _groups.values) {
      g.wipe();
    }
    _groups.clear();
  }

  /// Wipes everything (logout / revoke / device wipe).
  Future<void> wipeAll() async {
    final ids = _groups.keys.toList(growable: false);
    for (final g in _groups.values) {
      g.wipe();
    }
    _groups.clear();
    for (final id in ids) {
      await _persist(id);
    }
  }

  // ---- send ---------------------------------------------------------------

  /// Encrypts one frame under our chain. Caller must have called
  /// [ensureOwnSenderKey] for the current epoch first.
  Future<GroupCiphertext> encrypt({
    required String groupId,
    required String localDeviceId,
    required List<int> plaintext,
  }) async {
    final state = _groups[groupId];
    final own = state?.own;
    if (state == null || own == null || own.deviceId != localDeviceId) {
      throw const GroupCryptoException('noOwnSenderKey', 'ensureOwnSenderKey first');
    }

    final counter = own.counter;
    final messageKey = await _deriveMessageKey(own.chainKey, counter);
    final nextChain = await _advanceChain(own.chainKey);
    own.chainKey.fillRange(0, own.chainKey.length, 0);
    own.chainKey = nextChain;
    own.counter = counter + 1;

    final nonce = _randomBytes(_kNonceLength);
    final aad = _buildAad(
      groupId: groupId,
      senderDeviceId: localDeviceId,
      counter: counter,
      epoch: state.epoch,
    );
    final box = await _aesGcm.encrypt(
      plaintext,
      secretKey: SecretKey(messageKey),
      nonce: nonce,
      aad: aad,
    );
    messageKey.fillRange(0, messageKey.length, 0);

    final ctWithTag = Uint8List(box.cipherText.length + _kTagLength)
      ..setRange(0, box.cipherText.length, box.cipherText)
      ..setRange(box.cipherText.length, box.cipherText.length + _kTagLength, box.mac.bytes);

    final signingPair = await _ed25519.newKeyPairFromSeed(own.signingSeed);
    final toSign = _signedBytes(aad: aad, nonce: nonce, ciphertext: ctWithTag);
    final signature = await _ed25519.sign(toSign, keyPair: signingPair);

    await _persist(groupId);

    return GroupCiphertext(
      payload: _b64Encode(_encodeFrame(
        senderDeviceId: localDeviceId,
        epoch: state.epoch,
        counter: counter,
        signature: signature.bytes,
        ciphertext: ctWithTag,
      )),
      nonce: _b64Encode(nonce),
    );
  }

  // ---- receive ------------------------------------------------------------

  /// Parses the unauthenticated header (sender / epoch / counter) so the
  /// caller can decide whether it even holds a key before attempting a
  /// decrypt. Returns null on a malformed frame.
  static GroupFrameHeader? parseHeader(String payload) {
    try {
      return _decodeFrame(_b64Decode(payload)).header;
    } catch (_) {
      return null;
    }
  }

  Future<GroupPlaintext> decrypt({
    required String groupId,
    required String payload,
    required String nonce,
  }) async {
    final _Frame frame;
    final Uint8List nonceBytes;
    try {
      frame = _decodeFrame(_b64Decode(payload));
      nonceBytes = _b64Decode(nonce);
    } catch (_) {
      throw const GroupCryptoException('malformed');
    }
    if (nonceBytes.length != _kNonceLength) {
      throw const GroupCryptoException('malformed', 'bad nonce length');
    }
    final header = frame.header;

    final state = _groups[groupId];
    if (state == null) {
      throw const GroupCryptoException('senderKeyMissing', 'no state for group');
    }
    if (header.epoch != state.epoch) {
      throw GroupCryptoException(
        'epochMismatch',
        'frame epoch ${header.epoch} != local ${state.epoch}',
      );
    }
    final peer = state.peers[header.senderDeviceId];
    if (peer == null) {
      throw const GroupCryptoException('senderKeyMissing');
    }

    // Authorship first: a frame whose signature does not verify under the
    // sender's per-epoch key is dropped before it can touch chain state.
    final aad = _buildAad(
      groupId: groupId,
      senderDeviceId: header.senderDeviceId,
      counter: header.counter,
      epoch: header.epoch,
    );
    final sigOk = await _ed25519.verify(
      _signedBytes(aad: aad, nonce: nonceBytes, ciphertext: frame.ciphertext),
      signature: Signature(
        frame.signature,
        publicKey: SimplePublicKey(peer.signingPublicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!sigOk) {
      throw const GroupCryptoException('signatureInvalid');
    }

    // Commit-after-verify: compute everything on a scratch copy of the
    // peer chain and only write it back once the AEAD authenticates.
    final scratchChain = List<int>.from(peer.chainKey);
    var scratchCounter = peer.counter;
    final newlySkipped = <int, List<int>>{};
    List<int>? messageKey;

    final stashed = peer.skippedKeys[header.counter];
    if (stashed != null) {
      messageKey = List<int>.from(stashed);
    } else if (header.counter < peer.counter) {
      throw const GroupCryptoException('replayed', 'counter already consumed');
    } else {
      if (header.counter - peer.counter > kMaxForwardSkip) {
        throw const GroupCryptoException('tooFarAhead');
      }
      var chain = scratchChain;
      while (scratchCounter < header.counter) {
        newlySkipped[scratchCounter] = await _deriveMessageKey(chain, scratchCounter);
        chain = await _advanceChain(chain);
        scratchCounter++;
      }
      messageKey = await _deriveMessageKey(chain, scratchCounter);
      final advanced = await _advanceChain(chain);
      scratchChain
        ..clear()
        ..addAll(advanced);
      scratchCounter++;
    }

    final ct = frame.ciphertext.sublist(0, frame.ciphertext.length - _kTagLength);
    final tag = frame.ciphertext.sublist(frame.ciphertext.length - _kTagLength);
    final List<int> plaintext;
    try {
      plaintext = await _aesGcm.decrypt(
        SecretBox(ct, nonce: nonceBytes, mac: Mac(tag)),
        secretKey: SecretKey(messageKey),
        aad: aad,
      );
    } catch (_) {
      messageKey.fillRange(0, messageKey.length, 0);
      for (final k in newlySkipped.values) {
        k.fillRange(0, k.length, 0);
      }
      throw const GroupCryptoException('decryptFailed');
    }
    messageKey.fillRange(0, messageKey.length, 0);

    // Authenticated — commit.
    if (stashed != null) {
      peer.skippedKeys.remove(header.counter)?.fillRange(0, 32, 0);
    } else {
      peer.chainKey.fillRange(0, peer.chainKey.length, 0);
      peer.chainKey = scratchChain;
      peer.counter = scratchCounter;
      peer.skippedKeys.addAll(newlySkipped);
      _trimSkipped(peer);
    }
    await _persist(groupId);

    return GroupPlaintext(
      plaintext: plaintext,
      senderDeviceId: header.senderDeviceId,
      epoch: header.epoch,
      counter: header.counter,
    );
  }

  static void _trimSkipped(_PeerChain peer) {
    if (peer.skippedKeys.length <= kMaxSkippedKeysPerPeer) return;
    final counters = peer.skippedKeys.keys.toList()..sort();
    final excess = peer.skippedKeys.length - kMaxSkippedKeysPerPeer;
    for (var i = 0; i < excess; i++) {
      peer.skippedKeys.remove(counters[i])?.fillRange(0, 32, 0);
    }
  }

  // ---- KDF ------------------------------------------------------------------

  /// chainKey_{n+1} = HKDF(chainKey_n, salt=[0x02], info="veil-gck-v1")
  static Future<List<int>> _advanceChain(List<int> chainKey) async {
    final next = await _hkdf.deriveKey(
      secretKey: SecretKey(chainKey),
      nonce: const [0x02],
      info: utf8.encode(_kChainInfo),
    );
    return (await next.extractBytes()).toList();
  }

  /// mk_n = HKDF(chainKey_n, salt=ctr(4 BE), info="veil-gmk-v1", L=32)
  static Future<List<int>> _deriveMessageKey(List<int> chainKey, int counter) async {
    final mk = await _hkdf.deriveKey(
      secretKey: SecretKey(chainKey),
      nonce: _u32(counter),
      info: utf8.encode(_kMessageKeyInfo),
    );
    return (await mk.extractBytes()).toList();
  }

  /// AD = "veil-group-v1" || len16(groupId) || len16(senderDeviceId)
  ///      || ctr (4 BE) || epoch (8 BE)
  static Uint8List _buildAad({
    required String groupId,
    required String senderDeviceId,
    required int counter,
    required int epoch,
  }) {
    final out = BytesBuilder(copy: false)
      ..add(utf8.encode(kGroupEnvelopeVersion))
      ..add(_lengthPrefixed(utf8.encode(groupId)))
      ..add(_lengthPrefixed(utf8.encode(senderDeviceId)))
      ..add(_u32(counter))
      ..add(_u64(epoch));
    return out.toBytes();
  }

  static Uint8List _signedBytes({
    required List<int> aad,
    required List<int> nonce,
    required List<int> ciphertext,
  }) {
    final out = BytesBuilder(copy: false)
      ..add(aad)
      ..add(nonce)
      ..add(ciphertext);
    return out.toBytes();
  }

  // ---- frame codec ------------------------------------------------------------
  //
  //   [0x01][len u8][senderDeviceId utf8][epoch u64 BE][ctr u32 BE]
  //   [signature 64][ciphertext || tag16]

  static Uint8List _encodeFrame({
    required String senderDeviceId,
    required int epoch,
    required int counter,
    required List<int> signature,
    required List<int> ciphertext,
  }) {
    final sender = utf8.encode(senderDeviceId);
    if (sender.isEmpty || sender.length > 0xFF) {
      throw ArgumentError('senderDeviceId must be 1..255 utf8 bytes');
    }
    final out = BytesBuilder(copy: false)
      ..addByte(_kFrameVersion)
      ..addByte(sender.length)
      ..add(sender)
      ..add(_u64(epoch))
      ..add(_u32(counter))
      ..add(signature)
      ..add(ciphertext);
    return out.toBytes();
  }

  static _Frame _decodeFrame(Uint8List bytes) {
    if (bytes.length < 2) throw const GroupCryptoException('malformed');
    if (bytes[0] != _kFrameVersion) {
      throw const GroupCryptoException('malformed', 'unknown frame version');
    }
    final senderLen = bytes[1];
    var offset = 2;
    if (senderLen == 0 || bytes.length < offset + senderLen + 8 + 4 + _kSignatureLength + _kTagLength) {
      throw const GroupCryptoException('malformed');
    }
    final sender = utf8.decode(bytes.sublist(offset, offset + senderLen));
    offset += senderLen;
    final epoch = ByteData.sublistView(bytes, offset, offset + 8).getUint64(0, Endian.big);
    offset += 8;
    final counter = ByteData.sublistView(bytes, offset, offset + 4).getUint32(0, Endian.big);
    offset += 4;
    final signature = bytes.sublist(offset, offset + _kSignatureLength);
    offset += _kSignatureLength;
    final ciphertext = bytes.sublist(offset);
    return _Frame(
      header: GroupFrameHeader(senderDeviceId: sender, epoch: epoch, counter: counter),
      signature: signature,
      ciphertext: ciphertext,
    );
  }
}

class _Frame {
  const _Frame({required this.header, required this.signature, required this.ciphertext});

  final GroupFrameHeader header;
  final Uint8List signature;
  final Uint8List ciphertext;
}

// ---------------------------------------------------------------------------
// Key-distribution sealing.
//
// The design calls for the distribution blob to ride a 1:1 ratchet session.
// VEIL's ratchet sessions are keyed per *conversation*, so two members of a
// group need not share one. Instead each blob is sealed directly to the
// recipient's identity: ephemeral X25519 → HKDF → AES-256-GCM to the
// recipient's signed X25519 prekey (whose signature is verified against the
// recipient's Ed25519 identity, exactly as 1:1 bootstrap does), and the
// whole blob is signed by the *sender's* Ed25519 identity so the recipient
// can authenticate who the chain key came from. The server relays it opaque
// and TTL-buffers it for 30 minutes.
//
// Not forward secret on its own — but a blob only ever carries a chain key
// that dies at the next epoch bump, and the 30-minute relay window bounds
// exposure. Flagged for the external reviewer in the design doc.
// ---------------------------------------------------------------------------

/// Resolves the recipient's X25519 public key from a directory bundle, after
/// verifying the bundle signature against their identity key. Supplied by
/// the active 1:1 adapter so both paths share one verification routine.
typedef RecipientPrekeyResolver = Future<SimplePublicKey> Function(
  String signedPrekeyBundle,
  String identityPublicKey,
);

/// Sealed distribution as it goes over the wire.
class SealedGroupSenderKey {
  const SealedGroupSenderKey({
    required this.recipientUserId,
    required this.encryptedChainKey,
    required this.nonce,
    this.version = kGroupKeyDistributionVersion,
  });

  final String recipientUserId;

  /// b64url( ephPub(32) || senderSig(64) || ct || tag(16) )
  final String encryptedChainKey;
  final String nonce;
  final String version;

  Map<String, dynamic> toUploadJson() => {
        'recipientUserId': recipientUserId,
        'encryptedChainKey': encryptedChainKey,
        'nonce': nonce,
        'version': version,
      };
}

class GroupSenderKeySealer {
  GroupSenderKeySealer({required RecipientPrekeyResolver resolveRecipientPrekey})
      : _resolveRecipientPrekey = resolveRecipientPrekey;

  final RecipientPrekeyResolver _resolveRecipientPrekey;

  /// AD binds the routing fields the server sees so a blob cannot be
  /// re-addressed to another group / epoch / recipient.
  static Uint8List _distributionAad({
    required String groupId,
    required int epoch,
    required String senderDeviceId,
    required String recipientUserId,
  }) {
    final out = BytesBuilder(copy: false)
      ..add(utf8.encode(kGroupKeyDistributionVersion))
      ..add(_lengthPrefixed(utf8.encode(groupId)))
      ..add(_u64(epoch))
      ..add(_lengthPrefixed(utf8.encode(senderDeviceId)))
      ..add(_lengthPrefixed(utf8.encode(recipientUserId)));
    return out.toBytes();
  }

  Future<SealedGroupSenderKey> seal({
    required GroupSenderKey key,
    required String recipientUserId,
    required String recipientIdentityPublicKey,
    required String recipientSignedPrekeyBundle,
    required List<int> senderIdentityEd25519Seed,
  }) async {
    final recipientX = await _resolveRecipientPrekey(
      recipientSignedPrekeyBundle,
      recipientIdentityPublicKey,
    );
    final eph = await _x25519.newKeyPair();
    final ephPub = (await eph.extractPublicKey()).bytes;
    final shared = await _x25519.sharedSecretKey(keyPair: eph, remotePublicKey: recipientX);
    final sharedBytes = await shared.extractBytes();
    if (sharedBytes.every((b) => b == 0)) {
      throw const GroupCryptoException('distributionInvalid', 'low-order recipient key');
    }
    final wrapKey = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: ephPub,
      info: utf8.encode(_kDistributionWrapInfo),
    );
    final nonce = _randomBytes(_kNonceLength);
    final aad = _distributionAad(
      groupId: key.groupId,
      epoch: key.epoch,
      senderDeviceId: key.senderDeviceId,
      recipientUserId: recipientUserId,
    );
    final box = await _aesGcm.encrypt(
      utf8.encode(json.encode(key.toJson())),
      secretKey: wrapKey,
      nonce: nonce,
      aad: aad,
    );
    final ctWithTag = Uint8List(box.cipherText.length + _kTagLength)
      ..setRange(0, box.cipherText.length, box.cipherText)
      ..setRange(box.cipherText.length, box.cipherText.length + _kTagLength, box.mac.bytes);

    final signer = await _ed25519.newKeyPairFromSeed(senderIdentityEd25519Seed);
    final sig = await _ed25519.sign(
      _sealedSignedBytes(aad: aad, ephPub: ephPub, nonce: nonce, ciphertext: ctWithTag),
      keyPair: signer,
    );

    final blob = BytesBuilder(copy: false)
      ..add(ephPub)
      ..add(sig.bytes)
      ..add(ctWithTag);
    return SealedGroupSenderKey(
      recipientUserId: recipientUserId,
      encryptedChainKey: _b64Encode(blob.toBytes()),
      nonce: _b64Encode(nonce),
    );
  }

  /// Opens a blob addressed to us. [senderIdentityPublicKey] must come from
  /// the directory (trusted key bundle), never from the blob itself.
  Future<GroupSenderKey> unseal({
    required String groupId,
    required int epoch,
    required String senderDeviceId,
    required String localUserId,
    required String encryptedChainKey,
    required String nonce,
    required String version,
    required List<int> localIdentityX25519Private,
    required String senderIdentityPublicKey,
  }) async {
    if (version != kGroupKeyDistributionVersion) {
      throw const GroupCryptoException('distributionInvalid', 'unknown version');
    }
    final Uint8List blob;
    final Uint8List nonceBytes;
    final Uint8List senderIdBytes;
    try {
      blob = _b64Decode(encryptedChainKey);
      nonceBytes = _b64Decode(nonce);
      senderIdBytes = _b64Decode(senderIdentityPublicKey);
    } catch (_) {
      throw const GroupCryptoException('distributionInvalid', 'bad encoding');
    }
    if (blob.length < 32 + _kSignatureLength + _kTagLength ||
        nonceBytes.length != _kNonceLength ||
        senderIdBytes.length != 32) {
      throw const GroupCryptoException('distributionInvalid', 'bad lengths');
    }
    final ephPub = blob.sublist(0, 32);
    final sig = blob.sublist(32, 32 + _kSignatureLength);
    final ctWithTag = blob.sublist(32 + _kSignatureLength);

    final aad = _distributionAad(
      groupId: groupId,
      epoch: epoch,
      senderDeviceId: senderDeviceId,
      recipientUserId: localUserId,
    );
    final sigOk = await _ed25519.verify(
      _sealedSignedBytes(aad: aad, ephPub: ephPub, nonce: nonceBytes, ciphertext: ctWithTag),
      signature: Signature(sig, publicKey: SimplePublicKey(senderIdBytes, type: KeyPairType.ed25519)),
    );
    if (!sigOk) {
      throw const GroupCryptoException('signatureInvalid', 'distribution not signed by sender');
    }

    final local = await _x25519.newKeyPairFromSeed(localIdentityX25519Private);
    final shared = await _x25519.sharedSecretKey(
      keyPair: local,
      remotePublicKey: SimplePublicKey(ephPub, type: KeyPairType.x25519),
    );
    final wrapKey = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: ephPub,
      info: utf8.encode(_kDistributionWrapInfo),
    );
    final List<int> plain;
    try {
      plain = await _aesGcm.decrypt(
        SecretBox(
          ctWithTag.sublist(0, ctWithTag.length - _kTagLength),
          nonce: nonceBytes,
          mac: Mac(ctWithTag.sublist(ctWithTag.length - _kTagLength)),
        ),
        secretKey: wrapKey,
        aad: aad,
      );
    } catch (_) {
      throw const GroupCryptoException('decryptFailed', 'distribution AEAD failed');
    }
    final GroupSenderKey key;
    try {
      key = GroupSenderKey.fromJson(json.decode(utf8.decode(plain)) as Map<String, dynamic>);
    } catch (_) {
      throw const GroupCryptoException('distributionInvalid', 'bad payload');
    }
    // The inner record must agree with the (authenticated) routing fields.
    if (key.groupId != groupId || key.epoch != epoch || key.senderDeviceId != senderDeviceId) {
      throw const GroupCryptoException('distributionInvalid', 'routing mismatch');
    }
    return key;
  }

  static Uint8List _sealedSignedBytes({
    required List<int> aad,
    required List<int> ephPub,
    required List<int> nonce,
    required List<int> ciphertext,
  }) {
    final out = BytesBuilder(copy: false)
      ..add(aad)
      ..add(ephPub)
      ..add(nonce)
      ..add(ciphertext);
    return out.toBytes();
  }
}

/// Convenience for tests and callers that need to compare keys.
bool groupKeyBytesEqual(List<int> a, List<int> b) => _bytesEqual(a, b);
