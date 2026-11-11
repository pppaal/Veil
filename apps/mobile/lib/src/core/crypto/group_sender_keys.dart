import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../util/base64url.dart';
import '../util/constant_time.dart';
import '../util/keyed_async_lock.dart';

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
//     rejected before any key material is touched. Epochs only move forward
//     locally, so the server cannot re-open an old epoch either.
//   * Distribution freshness: the relay sees (and may record) every sealed
//     distribution. A v2 distribution signs the sender's chain generation,
//     its issue time and start counter, and the engine keeps a per-sender
//     ledger, so a re-delivered blob can neither rewind a chain (replaying
//     consumed frames) nor reinstall a chain the sender has rotated away.
//
// Pre-audit engineering. Do not flip VEIL_AUDITED_CRYPTO_ATTESTED on the
// strength of this file.
// ---------------------------------------------------------------------------

/// Envelope `version` for group frames. The server allowlists it alongside
/// `veil-envelope-v1` but never interprets the ciphertext.
const String kGroupEnvelopeVersion = 'veil-group-v1';

/// `version` this client seals key distributions with
/// (POST /conversations/group/:id/key-distribute).
const String kGroupKeyDistributionVersion = 'veil-gkd-v2';

/// Distribution format of older clients. It carries no freshness metadata, so
/// it is opened only to fill an empty slot and never replaces a chain.
const String kLegacyGroupKeyDistributionVersion = 'veil-gkd-v1';

/// Persisted snapshot schema for [GroupSenderKeyEngine] state.
const int kGroupSnapshotSchemaVersion = 2;

/// Cap on stashed out-of-order message keys per sender chain.
const int kMaxSkippedKeysPerSender = 200;

/// Cap on stashed out-of-order message keys across every sender of a group.
const int kMaxSkippedKeysPerGroup = 1000;

/// A stashed key older than this belongs to a straggler that is never coming;
/// dropping it stops an adversary from pinning key material indefinitely.
const Duration kSkippedGroupKeyTtl = Duration(days: 7);

/// A distribution may replace an installed chain only if it was issued no
/// longer ago than the relay buffers blobs...
const Duration kDistributionMaxAge = Duration(minutes: 30);

/// ...and no further in the future than ordinary clock skew explains.
const Duration kDistributionMaxClockSkew = Duration(minutes: 5);

/// Hard cap on how far ahead of a peer's counter a single frame may jump.
/// Bounds the CPU/memory an attacker can force by sending `ctr = 2^32 - 1`.
const int kMaxForwardSkip = 2000;

/// Frame layout version byte.
const int _kFrameVersion = 0x01;
const int _kSignatureLength = 64;
const int _kTagLength = 16;
const int _kNonceLength = 12;
const int _kMaxUint32 = 0xFFFFFFFF;

const String _kChainInfo = 'veil-gck-v1';
const String _kMessageKeyInfo = 'veil-gmk-v1';
const String _kDistributionWrapInfo = 'veil-gkd-wrap-v1';

final AesGcm _aesGcm = AesGcm.with256bits();
final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
final Ed25519 _ed25519 = Ed25519();
final X25519 _x25519 = X25519();
final Random _random = Random.secure();

Uint8List _u32(int value) {
  if (value < 0 || value > _kMaxUint32) {
    throw ArgumentError.value(value, 'value', 'does not fit in u32');
  }
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

bool _isUint32(Object? value) => value is int && value >= 0 && value <= _kMaxUint32;

List<int> _randomBytes(int n) => List<int>.generate(n, (_) => _random.nextInt(256));

/// Typed failure surfaced by the engine. `code` is stable and safe to branch
/// on in app logic; `message` is for logs/tests and never contains plaintext.
class GroupCryptoException implements Exception {
  const GroupCryptoException(this.code, [this.message]);

  /// One of: `malformed`, `noOwnSenderKey`, `senderKeyMissing`,
  /// `epochMismatch`, `signatureInvalid`, `replayed`, `tooFarAhead`,
  /// `decryptFailed`, `distributionInvalid`, `distribution_stale` (the
  /// distribution does not supersede the chain we hold),
  /// `recipientBundleInvalid` (a recipient's directory bundle did not verify,
  /// so nothing was sealed to it), or `untrusted_identity` (the coordinator's
  /// trust check refused the distribution's signer).
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
    required this.generation,
  });

  final String groupId;
  final int epoch;
  final String senderDeviceId;
  final List<int> chainKey;
  final int counter;
  final List<int> signingPublicKey;

  /// Which of the sender's chains in this epoch this is: 1 for the first,
  /// +1 on every rotation. 0 marks a legacy record, which has no generation.
  final int generation;
}

/// A [GroupSenderKey] opened from a distribution blob, with the sender-signed
/// freshness metadata [GroupSenderKeyEngine.ingestDistribution] decides on.
class GroupKeyDistribution {
  const GroupKeyDistribution({required this.key, required int this.issuedAtMs});

  const GroupKeyDistribution.legacy(this.key) : issuedAtMs = null;

  final GroupSenderKey key;

  /// Sender's clock when the blob was sealed, in ms since the Unix epoch.
  /// Null for a [kLegacyGroupKeyDistributionVersion] blob.
  final int? issuedAtMs;
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

class _SkippedKey {
  _SkippedKey(this.key, this.storedAtMs);

  final List<int> key;
  final int storedAtMs;

  void wipe() => key.fillRange(0, key.length, 0);
}

/// Live receive chain for one sender.
class _PeerChain {
  _PeerChain({required this.chainKey, required this.counter});

  /// Chain key at [counter] (i.e. the key that derives message `counter`).
  List<int> chainKey;
  int counter;
  final Map<int, _SkippedKey> skipped = <int, _SkippedKey>{};

  Map<String, dynamic> toJson() => {
        'chainKey': base64UrlNoPadEncode(chainKey),
        'counter': counter,
        'skipped': {
          for (final e in skipped.entries)
            e.key.toString(): {'k': base64UrlNoPadEncode(e.value.key), 't': e.value.storedAtMs},
        },
      };

  static _PeerChain fromJson(Map<String, dynamic> json) {
    final chain = _PeerChain(
      chainKey: base64UrlNoPadDecode(json['chainKey'] as String),
      counter: json['counter'] as int,
    );
    (json['skipped'] as Map).forEach((counter, entry) {
      final fields = (entry as Map).cast<String, dynamic>();
      chain.skipped[int.parse(counter as String)] = _SkippedKey(
        base64UrlNoPadDecode(fields['k'] as String),
        fields['t'] as int,
      );
    });
    return chain;
  }

  /// Drops stashed keys stored before [cutoffMs]; true if any were dropped.
  bool purgeSkippedBefore(int cutoffMs) {
    var purged = false;
    skipped.removeWhere((_, entry) {
      if (entry.storedAtMs >= cutoffMs) return false;
      entry.wipe();
      purged = true;
      return true;
    });
    return purged;
  }

  void wipe() {
    chainKey.fillRange(0, chainKey.length, 0);
    for (final k in skipped.values) {
      k.wipe();
    }
    skipped.clear();
  }
}

/// Everything accepted from one sender in the current epoch. It outlives the
/// chain itself ([GroupSenderKeyEngine.dropPeer]) so a re-delivered
/// distribution can never reinstall key material below what was consumed.
class _SenderRecord {
  _SenderRecord({
    required this.signingPublicKey,
    required this.generation,
    required this.highWaterConsumed,
    required this.chain,
  });

  _SenderRecord.install(GroupSenderKey key)
      : signingPublicKey = List<int>.from(key.signingPublicKey),
        generation = key.generation,
        highWaterConsumed = key.counter - 1,
        chain = _PeerChain(chainKey: List<int>.from(key.chainKey), counter: key.counter);

  final List<int> signingPublicKey;
  final int generation;

  /// Highest counter whose message key has left the chain (decrypted or
  /// stashed); counters at or below it must never become derivable again.
  int highWaterConsumed;
  _PeerChain? chain;

  Map<String, dynamic> toJson() => {
        'signingPub': base64UrlNoPadEncode(signingPublicKey),
        'generation': generation,
        'highWater': highWaterConsumed,
        if (chain != null) 'chain': chain!.toJson(),
      };

  static _SenderRecord fromJson(Map<String, dynamic> json) => _SenderRecord(
        signingPublicKey: base64UrlNoPadDecode(json['signingPub'] as String),
        generation: json['generation'] as int,
        highWaterConsumed: json['highWater'] as int,
        chain: json['chain'] is Map
            ? _PeerChain.fromJson((json['chain'] as Map).cast<String, dynamic>())
            : null,
      );

  void wipe() {
    chain?.wipe();
    chain = null;
  }
}

class _OwnChain {
  _OwnChain({
    required this.deviceId,
    required this.chainKey,
    required this.counter,
    required this.signingSeed,
    required this.signingPublicKey,
    required this.generation,
    Set<String>? deliveredTo,
  }) : deliveredTo = deliveredTo ?? <String>{};

  final String deviceId;
  List<int> chainKey;
  int counter;
  final List<int> signingSeed;
  final List<int> signingPublicKey;
  final int generation;

  /// User ids this chain has been handed to. Kept with the chain so it is
  /// persisted with it and starts empty for every new chain.
  final Set<String> deliveredTo;

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'chainKey': base64UrlNoPadEncode(chainKey),
        'counter': counter,
        'signingSeed': base64UrlNoPadEncode(signingSeed),
        'signingPub': base64UrlNoPadEncode(signingPublicKey),
        'generation': generation,
        'deliveredTo': deliveredTo.toList(growable: false),
      };

  static _OwnChain fromJson(Map<String, dynamic> json) => _OwnChain(
        deviceId: json['deviceId'] as String,
        chainKey: base64UrlNoPadDecode(json['chainKey'] as String),
        counter: json['counter'] as int,
        signingSeed: base64UrlNoPadDecode(json['signingSeed'] as String),
        signingPublicKey: base64UrlNoPadDecode(json['signingPub'] as String),
        generation: json['generation'] as int,
        // Absent from snapshots written before delivery was recorded; the
        // chain is then handed to every member once more.
        deliveredTo: {for (final userId in json['deliveredTo'] as List? ?? const []) userId as String},
      );

  void wipe() {
    chainKey.fillRange(0, chainKey.length, 0);
    signingSeed.fillRange(0, signingSeed.length, 0);
  }
}

class _GroupState {
  _GroupState({required this.groupId, required this.epoch});

  final String groupId;
  final int epoch;
  _OwnChain? own;

  /// Keyed by sender device id; includes our own device so frames we sent
  /// decrypt when fetched back from server history.
  final Map<String, _SenderRecord> senders = <String, _SenderRecord>{};

  Iterable<_PeerChain> get _chains => senders.values.map((s) => s.chain).whereType<_PeerChain>();

  Map<String, dynamic> toJson() => {
        'schema': kGroupSnapshotSchemaVersion,
        'groupId': groupId,
        'epoch': epoch,
        if (own != null) 'own': own!.toJson(),
        'senders': {for (final e in senders.entries) e.key: e.value.toJson()},
      };

  static _GroupState? tryRestore(String groupId, Map<String, dynamic> json) {
    try {
      if (json['schema'] != kGroupSnapshotSchemaVersion || json['groupId'] != groupId) {
        return null;
      }
      final state = _GroupState(groupId: groupId, epoch: json['epoch'] as int);
      if (json['own'] is Map) {
        state.own = _OwnChain.fromJson((json['own'] as Map).cast<String, dynamic>());
      }
      (json['senders'] as Map).forEach((deviceId, record) {
        state.senders[deviceId as String] =
            _SenderRecord.fromJson((record as Map).cast<String, dynamic>());
      });
      return state;
    } catch (_) {
      return null;
    }
  }

  /// Drops stashed keys stored before [cutoffMs]; true if any were dropped.
  bool purgeSkippedBefore(int cutoffMs) {
    var purged = false;
    for (final chain in _chains) {
      purged = chain.purgeSkippedBefore(cutoffMs) || purged;
    }
    return purged;
  }

  /// Evicts the oldest stashed keys beyond [kMaxSkippedKeysPerSender] per
  /// chain and [kMaxSkippedKeysPerGroup] across the group.
  void enforceSkippedKeyCaps() {
    for (final chain in _chains) {
      _evictOldest([chain], chain.skipped.length - kMaxSkippedKeysPerSender);
    }
    final total = _chains.fold<int>(0, (n, chain) => n + chain.skipped.length);
    _evictOldest(_chains.toList(growable: false), total - kMaxSkippedKeysPerGroup);
  }

  static void _evictOldest(List<_PeerChain> chains, int excess) {
    if (excess <= 0) return;
    final entries = [
      for (final chain in chains)
        for (final e in chain.skipped.entries) (chain: chain, counter: e.key, storedAtMs: e.value.storedAtMs),
    ]..sort((a, b) {
        final byAge = a.storedAtMs.compareTo(b.storedAtMs);
        return byAge != 0 ? byAge : a.counter.compareTo(b.counter);
      });
    for (final victim in entries.take(excess)) {
      victim.chain.skipped.remove(victim.counter)?.wipe();
    }
  }

  void wipe() {
    own?.wipe();
    own = null;
    for (final s in senders.values) {
      s.wipe();
    }
    senders.clear();
  }
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

/// All mutating calls on one group are serialized and return only after the
/// persister has stored the resulting state.
class GroupSenderKeyEngine {
  GroupSenderKeyEngine({GroupStatePersister? persister, DateTime Function()? clock})
      : _persister = persister,
        _clock = clock ?? DateTime.now;

  final Map<String, _GroupState> _groups = <String, _GroupState>{};
  final KeyedAsyncLock<String> _lock = KeyedAsyncLock<String>();
  final DateTime Function() _clock;
  GroupStatePersister? _persister;

  int get _nowMs => _clock().millisecondsSinceEpoch;

  void setPersistence({GroupStatePersister? persister}) {
    _persister = persister;
  }

  /// Rehydrates state written by [GroupStatePersister]. Snapshots with an
  /// unknown schema are dropped (the next send re-keys the group), never
  /// "migrated" into something that could resurrect old key material. A
  /// group already held in memory is never overwritten: memory is at least as
  /// new as anything persisted, so restoring over it could only roll it back.
  Future<void> restoreFromSnapshots(Map<String, Map<String, dynamic>> snapshots) async {
    for (final entry in snapshots.entries) {
      await _lock.synchronized(entry.key, () async {
        if (_groups.containsKey(entry.key)) return;
        final restored = _GroupState.tryRestore(entry.key, entry.value);
        if (restored == null) return;
        _groups[entry.key] = restored;
        if (restored.purgeSkippedBefore(_skippedKeyCutoffMs())) {
          await _persist(entry.key);
        }
      });
    }
  }

  int _skippedKeyCutoffMs() => _nowMs - kSkippedGroupKeyTtl.inMilliseconds;

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
    return _groups[groupId]?.senders[senderDeviceId]?.chain != null;
  }

  /// Device ids we currently hold peer chains for (includes our own device).
  Set<String> knownSenders(String groupId) => Set<String>.unmodifiable(
        (_groups[groupId]?.senders.entries ?? const <MapEntry<String, _SenderRecord>>[])
            .where((e) => e.value.chain != null)
            .map((e) => e.key),
      );

  /// State for [epoch], starting the epoch afresh when we hold an older one.
  /// Epochs never move backwards: re-entering an old epoch would wipe the
  /// current chains and re-open that epoch's recorded distributions.
  _GroupState _stateForEpoch(String groupId, int epoch) {
    final state = _groups[groupId];
    if (state != null && epoch < state.epoch) {
      throw GroupCryptoException('epochMismatch', 'epoch $epoch is older than local ${state.epoch}');
    }
    if (state != null && state.epoch == epoch) return state;
    state?.wipe();
    return _groups[groupId] = _GroupState(groupId: groupId, epoch: epoch);
  }

  /// Guarantees we own a fresh chain + signing key for ([groupId], [epoch]).
  ///
  /// If our state is for an older epoch (membership changed) or we have
  /// none, *all* state for the group is wiped and a new chain is created —
  /// peers' keys from the old epoch are useless and must not linger. Returns
  /// the distribution record to hand to every other member. `forceRotate`
  /// re-keys even within the same epoch (e.g. after a suspected compromise);
  /// every new chain in an epoch carries the next generation.
  Future<GroupSenderKey> ensureOwnSenderKey({
    required String groupId,
    required int epoch,
    required String localDeviceId,
    bool forceRotate = false,
  }) =>
      _lock.synchronized(groupId, () async {
        final state = _stateForEpoch(groupId, epoch);
        final existing = state.own;
        if (!forceRotate && existing != null && existing.deviceId == localDeviceId) {
          return _exportOwn(state);
        }

        final generation = (existing?.generation ?? 0) + 1;
        existing?.wipe();
        // Our previous self-chain (if any) is obsolete too.
        state.senders.remove(localDeviceId)?.wipe();

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
          generation: generation,
        );
        // Register ourselves as a sender too so our own frames (fetched back
        // from server history on another screen / after restart) decrypt.
        state.senders[localDeviceId] = _SenderRecord.install(_exportOwn(state));
        await _persist(groupId);
        return _exportOwn(state);
      });

  GroupSenderKey _exportOwn(_GroupState state) {
    final own = state.own!;
    return GroupSenderKey(
      groupId: state.groupId,
      epoch: state.epoch,
      senderDeviceId: own.deviceId,
      chainKey: List<int>.unmodifiable(own.chainKey),
      counter: own.counter,
      signingPublicKey: List<int>.unmodifiable(own.signingPublicKey),
      generation: own.generation,
    );
  }

  /// Our current distribution record, or null if we have no chain yet.
  GroupSenderKey? exportOwnSenderKey(String groupId) {
    final state = _groups[groupId];
    if (state?.own == null) return null;
    return _exportOwn(state!);
  }

  /// User ids [recordDelivered] has recorded as holding [key]; empty when
  /// [key] is no longer our chain (rotated, re-keyed or forgotten since).
  Set<String> deliveredTo(GroupSenderKey key) {
    final own = _ownChainMatching(key);
    return own == null ? const <String>{} : Set<String>.unmodifiable(own.deliveredTo);
  }

  /// Records that [key], our current chain, has been handed to [userIds].
  /// Persisted with the chain, so a restart neither forgets who still needs
  /// it nor sends it again to someone who has it. Ignored when [key] is no
  /// longer our chain.
  Future<void> recordDelivered(GroupSenderKey key, Iterable<String> userIds) =>
      _lock.synchronized(key.groupId, () async {
        final own = _ownChainMatching(key);
        if (own == null) return;
        own.deliveredTo.addAll(userIds);
        await _persist(key.groupId);
      });

  /// Our chain, if [key] describes it. Every chain gets a fresh signing key,
  /// so the signing key names the chain even across a lost-state restart at
  /// the same generation.
  _OwnChain? _ownChainMatching(GroupSenderKey key) {
    final state = _groups[key.groupId];
    final own = state?.own;
    if (state == null || own == null || state.epoch != key.epoch) return null;
    return constantTimeBytesEqual(own.signingPublicKey, key.signingPublicKey) ? own : null;
  }

  /// Installs a peer's chain from a distribution whose blob has been unsealed
  /// and whose sender has been authenticated by the caller. Returns true if a
  /// chain was installed and false if the distribution changed nothing (a
  /// re-delivery).
  ///
  /// A distribution for a *newer* epoch than ours resets the group (we missed
  /// the bump); an *older* epoch throws `epochMismatch`, and one claiming to
  /// come from our own device throws `distributionInvalid`. Against the
  /// sender's ledger entry:
  ///   * no entry yet: legacy and v2 distributions are both accepted;
  ///   * a legacy distribution never replaces an entry;
  ///   * same signing key and generation: the chain never rewinds, so this is
  ///     a no-op — unless [dropPeer] removed the chain and the distribution
  ///     starts above everything already consumed;
  ///   * a higher generation replaces the chain only if it was issued within
  ///     [kDistributionMaxAge] before / [kDistributionMaxClockSkew] after now;
  ///   * a lower generation, or a different signing key at the same
  ///     generation, is rejected.
  /// Every rejection by the ledger throws `distribution_stale`.
  Future<bool> ingestDistribution(GroupKeyDistribution distribution) {
    final key = distribution.key;
    return _lock.synchronized(key.groupId, () async {
      final state = _stateForEpoch(key.groupId, key.epoch);
      if (state.own?.deviceId == key.senderDeviceId) {
        throw const GroupCryptoException('distributionInvalid', 'refusing to overwrite own chain');
      }
      final current = state.senders[key.senderDeviceId];
      if (current != null && !_supersedes(distribution, current)) return false;
      current?.wipe();
      state.senders[key.senderDeviceId] = _SenderRecord.install(key);
      await _persist(key.groupId);
      return true;
    });
  }

  /// Whether [distribution] should replace [current]; throws
  /// `distribution_stale` when it must be rejected outright.
  bool _supersedes(GroupKeyDistribution distribution, _SenderRecord current) {
    final key = distribution.key;
    final issuedAtMs = distribution.issuedAtMs;
    if (issuedAtMs == null) {
      throw const GroupCryptoException(
        'distribution_stale',
        'a legacy distribution cannot replace an installed chain',
      );
    }
    final sameSigner = constantTimeBytesEqual(key.signingPublicKey, current.signingPublicKey);
    if (sameSigner && key.generation == current.generation) {
      return current.chain == null && key.counter > current.highWaterConsumed;
    }
    if (key.generation > current.generation) {
      final now = _nowMs;
      final fresh = issuedAtMs >= now - kDistributionMaxAge.inMilliseconds &&
          issuedAtMs <= now + kDistributionMaxClockSkew.inMilliseconds;
      if (!fresh) {
        throw const GroupCryptoException(
          'distribution_stale',
          'distribution issued outside the freshness window',
        );
      }
      return true;
    }
    throw const GroupCryptoException(
      'distribution_stale',
      'distribution does not supersede the installed chain',
    );
  }

  /// Forgets a departed member's chain. Their frames will fail with
  /// `senderKeyMissing` from now on even if the epoch gate were bypassed. The
  /// ledger entry stays, so re-delivering their old distribution cannot bring
  /// the chain back.
  Future<void> dropPeer({required String groupId, required String senderDeviceId}) =>
      _lock.synchronized(groupId, () async {
        final record = _groups[groupId]?.senders[senderDeviceId];
        if (record == null) return;
        record.wipe();
        await _persist(groupId);
      });

  /// Starts [epoch] afresh, dropping every chain for the group (ours
  /// included). The next [ensureOwnSenderKey] creates our chain for it.
  /// Called on `group.epoch.bumped`; a bump to an epoch we already hold, or
  /// an older one, changes nothing.
  Future<void> resetForEpoch({required String groupId, required int epoch}) =>
      _lock.synchronized(groupId, () async {
        final state = _groups[groupId];
        if (state != null && epoch <= state.epoch) return;
        state?.wipe();
        _groups[groupId] = _GroupState(groupId: groupId, epoch: epoch);
        await _persist(groupId);
      });

  /// Removes all state for the group (left/removed/deleted).
  Future<void> forget(String groupId) => _lock.synchronized(groupId, () async {
        _groups.remove(groupId)?.wipe();
        await _persist(groupId);
      });

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
    for (final groupId in _groups.keys.toList(growable: false)) {
      await forget(groupId);
    }
  }

  // ---- send ---------------------------------------------------------------

  /// Encrypts one frame under our chain. Caller must have called
  /// [ensureOwnSenderKey] for the current epoch first.
  Future<GroupCiphertext> encrypt({
    required String groupId,
    required String localDeviceId,
    required List<int> plaintext,
  }) =>
      _lock.synchronized(groupId, () async {
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

        final ctWithTag = _joinTag(box);
        final signingPair = await _ed25519.newKeyPairFromSeed(own.signingSeed);
        final toSign = _signedBytes(aad: aad, nonce: nonce, ciphertext: ctWithTag);
        final signature = await _ed25519.sign(toSign, keyPair: signingPair);

        await _persist(groupId);

        return GroupCiphertext(
          payload: base64UrlNoPadEncode(_encodeFrame(
            senderDeviceId: localDeviceId,
            epoch: state.epoch,
            counter: counter,
            signature: signature.bytes,
            ciphertext: ctWithTag,
          )),
          nonce: base64UrlNoPadEncode(nonce),
        );
      });

  // ---- receive ------------------------------------------------------------

  /// Parses the unauthenticated header (sender / epoch / counter) so the
  /// caller can decide whether it even holds a key before attempting a
  /// decrypt. Returns null on a malformed frame.
  static GroupFrameHeader? parseHeader(String payload) {
    try {
      return _decodeFrame(base64UrlNoPadDecode(payload)).header;
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
      frame = _decodeFrame(base64UrlNoPadDecode(payload));
      nonceBytes = base64UrlNoPadDecode(nonce);
    } catch (_) {
      throw const GroupCryptoException('malformed');
    }
    if (nonceBytes.length != _kNonceLength) {
      throw const GroupCryptoException('malformed', 'bad nonce length');
    }
    return _lock.synchronized(groupId, () => _decryptFrame(groupId, frame, nonceBytes));
  }

  Future<GroupPlaintext> _decryptFrame(String groupId, _Frame frame, Uint8List nonceBytes) async {
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
    final nowMs = _nowMs;
    state.purgeSkippedBefore(nowMs - kSkippedGroupKeyTtl.inMilliseconds);
    final sender = state.senders[header.senderDeviceId];
    final peer = sender?.chain;
    if (sender == null || peer == null) {
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
        publicKey: SimplePublicKey(sender.signingPublicKey, type: KeyPairType.ed25519),
      ),
    );
    if (!sigOk) {
      throw const GroupCryptoException('signatureInvalid');
    }

    // Commit-after-verify: compute everything on a scratch copy of the
    // peer chain and only write it back once the AEAD authenticates.
    var scratchChain = List<int>.from(peer.chainKey);
    var scratchCounter = peer.counter;
    final newlySkipped = <int, List<int>>{};
    final List<int> messageKey;

    final stashed = peer.skipped[header.counter];
    if (stashed != null) {
      messageKey = List<int>.from(stashed.key);
    } else if (header.counter < peer.counter) {
      throw const GroupCryptoException('replayed', 'counter already consumed');
    } else {
      if (header.counter - peer.counter > kMaxForwardSkip) {
        throw const GroupCryptoException('tooFarAhead');
      }
      while (scratchCounter < header.counter) {
        newlySkipped[scratchCounter] = await _deriveMessageKey(scratchChain, scratchCounter);
        scratchChain = await _advanceChain(scratchChain);
        scratchCounter++;
      }
      messageKey = await _deriveMessageKey(scratchChain, scratchCounter);
      scratchChain = await _advanceChain(scratchChain);
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
      peer.skipped.remove(header.counter)?.wipe();
    } else {
      peer.chainKey.fillRange(0, peer.chainKey.length, 0);
      peer.chainKey = scratchChain;
      peer.counter = scratchCounter;
      newlySkipped.forEach((counter, key) => peer.skipped[counter] = _SkippedKey(key, nowMs));
      sender.highWaterConsumed = scratchCounter - 1;
      state.enforceSkippedKeyCaps();
    }
    await _persist(groupId);

    return GroupPlaintext(
      plaintext: plaintext,
      senderDeviceId: header.senderDeviceId,
      epoch: header.epoch,
      counter: header.counter,
    );
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

Uint8List _joinTag(SecretBox box) => Uint8List(box.cipherText.length + _kTagLength)
  ..setRange(0, box.cipherText.length, box.cipherText)
  ..setRange(box.cipherText.length, box.cipherText.length + _kTagLength, box.mac.bytes);

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
// v2 (`veil-gkd-v2`) keeps that construction and adds freshness: the sealed
// payload carries the chain generation and the sender's issue time, and the
// identity signature covers them together with the start counter:
//
//   AD  = "veil-gkd-v2" || lp(groupId) || u32(epoch) || lp(senderDeviceId)
//         || lp(recipientUserId)
//   sig = Ed25519(senderIdentity, AD || u32(generation) || u64(issuedAtMs)
//         || u32(startCounter) || ephPub || nonce || ciphertext)
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
    this.recipientDeviceId,
    this.version = kGroupKeyDistributionVersion,
  });

  final String recipientUserId;

  /// The device whose identity the blob is sealed to. It routes the blob on
  /// the relay; only that device can open it either way.
  final String? recipientDeviceId;

  /// b64url( ephPub(32) || senderSig(64) || ct || tag(16) )
  final String encryptedChainKey;
  final String nonce;
  final String version;

  Map<String, dynamic> toUploadJson() => {
        'recipientUserId': recipientUserId,
        if (recipientDeviceId != null) 'recipientDeviceId': recipientDeviceId,
        'encryptedChainKey': encryptedChainKey,
        'nonce': nonce,
        'version': version,
      };
}

class GroupSenderKeySealer {
  GroupSenderKeySealer({
    required RecipientPrekeyResolver resolveRecipientPrekey,
    DateTime Function()? clock,
  })  : _resolveRecipientPrekey = resolveRecipientPrekey,
        _clock = clock ?? DateTime.now;

  final RecipientPrekeyResolver _resolveRecipientPrekey;
  final DateTime Function() _clock;

  /// Routing fields the server sees, bound as AD (and signed) so a blob cannot
  /// be re-addressed to another group / epoch / sender / recipient.
  static Uint8List _routingAd({
    required String version,
    required String groupId,
    required int epoch,
    required String senderDeviceId,
    required String recipientUserId,
  }) {
    final out = BytesBuilder(copy: false)
      ..add(utf8.encode(version))
      ..add(_lengthPrefixed(utf8.encode(groupId)))
      ..add(version == kLegacyGroupKeyDistributionVersion ? _u64(epoch) : _u32(epoch))
      ..add(_lengthPrefixed(utf8.encode(senderDeviceId)))
      ..add(_lengthPrefixed(utf8.encode(recipientUserId)));
    return out.toBytes();
  }

  /// Seals [key] for one recipient as a [kGroupKeyDistributionVersion] blob,
  /// stamped with the current time as its issue time. Throws
  /// `recipientBundleInvalid` when the recipient's bundle does not verify, and
  /// `distributionInvalid` when its prekey is a low-order point.
  Future<SealedGroupSenderKey> seal({
    required GroupSenderKey key,
    required String recipientUserId,
    String? recipientDeviceId,
    required String recipientIdentityPublicKey,
    required String recipientSignedPrekeyBundle,
    required List<int> senderIdentityEd25519Seed,
  }) async {
    if (key.generation < 1 || !_isUint32(key.generation)) {
      throw ArgumentError.value(key.generation, 'key.generation', 'must be a u32 >= 1');
    }
    final issuedAtMs = _clock().millisecondsSinceEpoch;
    final SimplePublicKey recipientX;
    try {
      recipientX = await _resolveRecipientPrekey(
        recipientSignedPrekeyBundle,
        recipientIdentityPublicKey,
      );
    } catch (e) {
      // Resolvers report a bundle that fails verification in their own way
      // (the 1:1 adapter throws StateError); callers need one typed outcome
      // to skip that recipient rather than abort everyone else's delivery.
      throw GroupCryptoException('recipientBundleInvalid', '$e');
    }
    final eph = await _x25519.newKeyPair();
    final ephPub = (await eph.extractPublicKey()).bytes;
    final shared = await _x25519.sharedSecretKey(keyPair: eph, remotePublicKey: recipientX);
    final wrapKey = await _deriveWrapKey(shared, ephPub);
    final nonce = _randomBytes(_kNonceLength);
    final ad = _routingAd(
      version: kGroupKeyDistributionVersion,
      groupId: key.groupId,
      epoch: key.epoch,
      senderDeviceId: key.senderDeviceId,
      recipientUserId: recipientUserId,
    );
    final box = await _aesGcm.encrypt(
      utf8.encode(json.encode(_encodePayload(key, issuedAtMs))),
      secretKey: wrapKey,
      nonce: nonce,
      aad: ad,
    );
    final ctWithTag = _joinTag(box);

    final signer = await _ed25519.newKeyPairFromSeed(senderIdentityEd25519Seed);
    final sig = await _ed25519.sign(
      _signedBytesV2(
        ad: ad,
        generation: key.generation,
        issuedAtMs: issuedAtMs,
        startCounter: key.counter,
        ephPub: ephPub,
        nonce: nonce,
        ciphertext: ctWithTag,
      ),
      keyPair: signer,
    );

    final blob = BytesBuilder(copy: false)
      ..add(ephPub)
      ..add(sig.bytes)
      ..add(ctWithTag);
    return SealedGroupSenderKey(
      recipientUserId: recipientUserId,
      recipientDeviceId: recipientDeviceId,
      encryptedChainKey: base64UrlNoPadEncode(blob.toBytes()),
      nonce: base64UrlNoPadEncode(nonce),
    );
  }

  /// Opens a blob addressed to us. [senderIdentityPublicKey] must come from
  /// the directory (trusted key bundle), never from the blob itself. Accepts
  /// [kGroupKeyDistributionVersion] and [kLegacyGroupKeyDistributionVersion];
  /// whether the result may be installed is the engine's decision.
  Future<GroupKeyDistribution> unseal({
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
    final legacy = version == kLegacyGroupKeyDistributionVersion;
    if (!legacy && version != kGroupKeyDistributionVersion) {
      throw const GroupCryptoException('distributionInvalid', 'unknown version');
    }
    if (!legacy && !_isUint32(epoch)) {
      throw const GroupCryptoException('distributionInvalid', 'epoch out of range');
    }
    // The server supplies these, and the AD length-prefixes them in u16:
    // one too long must be a typed refusal, not an ArgumentError.
    if ([groupId, senderDeviceId].any((field) => utf8.encode(field).length > 0xFFFF)) {
      throw const GroupCryptoException('distributionInvalid', 'routing field too long');
    }
    final Uint8List blob;
    final Uint8List nonceBytes;
    final Uint8List senderIdBytes;
    try {
      blob = base64UrlNoPadDecode(encryptedChainKey);
      nonceBytes = base64UrlNoPadDecode(nonce);
      senderIdBytes = base64UrlNoPadDecode(senderIdentityPublicKey);
    } catch (_) {
      throw const GroupCryptoException('distributionInvalid', 'bad encoding');
    }
    if (blob.length < 32 + _kSignatureLength + _kTagLength ||
        nonceBytes.length != _kNonceLength ||
        senderIdBytes.length != 32) {
      throw const GroupCryptoException('distributionInvalid', 'bad lengths');
    }
    final opened = _OpenedBlob(
      ephPub: blob.sublist(0, 32),
      signature: Signature(
        blob.sublist(32, 32 + _kSignatureLength),
        publicKey: SimplePublicKey(senderIdBytes, type: KeyPairType.ed25519),
      ),
      ciphertext: blob.sublist(32 + _kSignatureLength),
      nonce: nonceBytes,
      ad: _routingAd(
        version: version,
        groupId: groupId,
        epoch: epoch,
        senderDeviceId: senderDeviceId,
        recipientUserId: localUserId,
      ),
    );

    final GroupKeyDistribution distribution;
    if (legacy) {
      // v1 signs only what is visible outside the ciphertext, so it can be
      // verified before any key agreement.
      await _verify(opened, _sealedSignedBytesV1(opened));
      distribution = GroupKeyDistribution.legacy(
        _decodeSenderKey(await _decrypt(opened, localIdentityX25519Private), generation: 0),
      );
    } else {
      // v2 also signs the generation, issue time and start counter, which
      // travel inside the ciphertext: decrypt, then verify before anything
      // from the payload is trusted.
      final payload = await _decrypt(opened, localIdentityX25519Private);
      distribution = _decodePayload(payload);
      final key = distribution.key;
      await _verify(
        opened,
        _signedBytesV2(
          ad: opened.ad,
          generation: key.generation,
          issuedAtMs: distribution.issuedAtMs!,
          startCounter: key.counter,
          ephPub: opened.ephPub,
          nonce: opened.nonce,
          ciphertext: opened.ciphertext,
        ),
      );
    }
    final key = distribution.key;
    // The inner record must agree with the (authenticated) routing fields.
    if (key.groupId != groupId || key.epoch != epoch || key.senderDeviceId != senderDeviceId) {
      throw const GroupCryptoException('distributionInvalid', 'routing mismatch');
    }
    return distribution;
  }

  static Future<void> _verify(_OpenedBlob opened, List<int> signedBytes) async {
    if (!await _ed25519.verify(signedBytes, signature: opened.signature)) {
      throw const GroupCryptoException('signatureInvalid', 'distribution not signed by sender');
    }
  }

  static Future<Map<String, dynamic>> _decrypt(
    _OpenedBlob opened,
    List<int> localIdentityX25519Private,
  ) async {
    final local = await _x25519.newKeyPairFromSeed(localIdentityX25519Private);
    final shared = await _x25519.sharedSecretKey(
      keyPair: local,
      remotePublicKey: SimplePublicKey(opened.ephPub, type: KeyPairType.x25519),
    );
    final wrapKey = await _deriveWrapKey(shared, opened.ephPub);
    final List<int> plain;
    try {
      plain = await _aesGcm.decrypt(
        SecretBox(
          opened.ciphertext.sublist(0, opened.ciphertext.length - _kTagLength),
          nonce: opened.nonce,
          mac: Mac(opened.ciphertext.sublist(opened.ciphertext.length - _kTagLength)),
        ),
        secretKey: wrapKey,
        aad: opened.ad,
      );
    } catch (_) {
      throw const GroupCryptoException('decryptFailed', 'distribution AEAD failed');
    }
    try {
      return json.decode(utf8.decode(plain)) as Map<String, dynamic>;
    } catch (_) {
      throw const GroupCryptoException('distributionInvalid', 'bad payload');
    }
  }

  /// wrapKey = HKDF(X25519(eph, recipient), salt=ephPub, info="veil-gkd-wrap-v1")
  static Future<SecretKey> _deriveWrapKey(SecretKey shared, List<int> ephPub) async {
    final sharedBytes = await shared.extractBytes();
    if (sharedBytes.every((b) => b == 0)) {
      throw const GroupCryptoException('distributionInvalid', 'low-order key');
    }
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: ephPub,
      info: utf8.encode(_kDistributionWrapInfo),
    );
  }

  static Map<String, dynamic> _encodePayload(GroupSenderKey key, int issuedAtMs) => {
        'v': 2,
        'groupId': key.groupId,
        'epoch': key.epoch,
        'senderDeviceId': key.senderDeviceId,
        'chainKey': base64UrlNoPadEncode(key.chainKey),
        'counter': key.counter,
        'signingPub': base64UrlNoPadEncode(key.signingPublicKey),
        'generation': key.generation,
        'issuedAtMs': issuedAtMs,
      };

  static GroupKeyDistribution _decodePayload(Map<String, dynamic> payload) {
    final generation = payload['generation'];
    final issuedAtMs = payload['issuedAtMs'];
    if (payload['v'] != 2 ||
        !_isUint32(generation) ||
        (generation as int) < 1 ||
        issuedAtMs is! int ||
        issuedAtMs < 0) {
      throw const GroupCryptoException('distributionInvalid', 'bad payload');
    }
    return GroupKeyDistribution(
      key: _decodeSenderKey(payload, generation: generation),
      issuedAtMs: issuedAtMs,
    );
  }

  static GroupSenderKey _decodeSenderKey(Map<String, dynamic> payload, {required int generation}) {
    const badShape = GroupCryptoException('distributionInvalid', 'bad sender key shape');
    final GroupSenderKey key;
    try {
      key = GroupSenderKey(
        groupId: payload['groupId'] as String,
        epoch: payload['epoch'] as int,
        senderDeviceId: payload['senderDeviceId'] as String,
        chainKey: base64UrlNoPadDecode(payload['chainKey'] as String),
        counter: payload['counter'] as int,
        signingPublicKey: base64UrlNoPadDecode(payload['signingPub'] as String),
        generation: generation,
      );
    } catch (_) {
      throw badShape;
    }
    if (key.chainKey.length != 32 ||
        key.signingPublicKey.length != 32 ||
        !_isUint32(key.counter) ||
        key.epoch < 0) {
      throw badShape;
    }
    return key;
  }

  static Uint8List _sealedSignedBytesV1(_OpenedBlob opened) {
    final out = BytesBuilder(copy: false)
      ..add(opened.ad)
      ..add(opened.ephPub)
      ..add(opened.nonce)
      ..add(opened.ciphertext);
    return out.toBytes();
  }

  static Uint8List _signedBytesV2({
    required List<int> ad,
    required int generation,
    required int issuedAtMs,
    required int startCounter,
    required List<int> ephPub,
    required List<int> nonce,
    required List<int> ciphertext,
  }) {
    final out = BytesBuilder(copy: false)
      ..add(ad)
      ..add(_u32(generation))
      ..add(_u64(issuedAtMs))
      ..add(_u32(startCounter))
      ..add(ephPub)
      ..add(nonce)
      ..add(ciphertext);
    return out.toBytes();
  }
}

/// A distribution blob split into its parts, with the AD it must match.
class _OpenedBlob {
  const _OpenedBlob({
    required this.ephPub,
    required this.signature,
    required this.ciphertext,
    required this.nonce,
    required this.ad,
  });

  final List<int> ephPub;
  final Signature signature;
  final List<int> ciphertext;
  final List<int> nonce;
  final Uint8List ad;
}

/// Convenience for tests and callers that need to compare keys.
bool groupKeyBytesEqual(List<int> a, List<int> b) => constantTimeBytesEqual(a, b);
