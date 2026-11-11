/// One Double Ratchet session state (Signal's "session state"). Mutable on
/// purpose, but only ever mutated on a private [copy]: the session cipher
/// commits the copy after AEAD success and destroys whichever object lost,
/// so a failed or concurrent operation can never roll state back.
library;

import 'dart:collection';
import 'dart:typed_data';

import '../bytes.dart';

const int protocolLegacy = 1;
const int protocolV2 = 2;

// Skipped keys older than this are abandoned stragglers; dropping them stops
// an adversary from pinning a receiver's key slots forever.
const Duration skippedKeyTtl = Duration(days: 7);

class SkippedMessageKey {
  SkippedMessageKey(this.key, this.stashedAt);

  final Uint8List key;
  final DateTime stashedAt;
}

class RatchetState {
  RatchetState({
    required this.protocol,
    required this.sessionLocator,
    required this.localDeviceId,
    required this.remoteDeviceId,
    required this.remoteIdentityFingerprint,
    required this.initiatedLocally,
    required this.createdAt,
    required this.rootKey,
    required this.sendRatchetPrivate,
    required this.sendRatchetPublic,
    required this.associatedData,
    this.localIdentityKey,
    this.remoteIdentityKey,
    this.baseKey,
    this.pendingPreKeyHeader,
    this.sendChainKey,
    this.receiveChainKey,
    this.remoteRatchetPublic,
    this.sendCounter = 0,
    this.receiveCounter = 0,
    this.previousSendCounter = 0,
    this.needsSendStep = false,
    this.ratchetRotationCount = 0,
    this.lastRatchetRotationAt,
  });

  final int protocol;
  final String sessionLocator;
  final String localDeviceId;
  final String remoteDeviceId;
  final String remoteIdentityFingerprint;
  final bool initiatedLocally;
  final DateTime createdAt;
  // Ed25519 identity keys bound by the handshake (v2 only).
  final Uint8List? localIdentityKey;
  final Uint8List? remoteIdentityKey;
  // X3DH AD; empty for legacy states, whose AAD binds no identities.
  final Uint8List associatedData;
  // EK_A of the handshake that created this state; PreKey frames carrying
  // it belong to this state rather than opening a new one.
  final Uint8List? baseKey;
  // Encoded PreKey header the initiator repeats until the first reply.
  Uint8List? pendingPreKeyHeader;

  Uint8List rootKey;
  Uint8List? sendChainKey;
  Uint8List? receiveChainKey;
  int sendCounter;
  int receiveCounter;
  int previousSendCounter;
  Uint8List sendRatchetPrivate;
  Uint8List sendRatchetPublic;
  Uint8List? remoteRatchetPublic;
  // Set by a receive DH step: the next send must rotate our ratchet key.
  bool needsSendStep;
  int ratchetRotationCount;
  DateTime? lastRatchetRotationAt;

  // Insertion-ordered so the oldest entry is evicted first when full.
  final LinkedHashMap<String, SkippedMessageKey> skipped = LinkedHashMap();
  // Ratchet keys the peer has moved past; a frame naming one with no stashed
  // key is a replay, not a reason to attempt a DH step.
  final List<String> previousRemoteRatchetKeys = [];

  bool get awaitingFirstReply => pendingPreKeyHeader != null;

  /// A v2 handshake not yet acknowledged from our side: we initiated it and
  /// have not heard back, or the peer did and we have not replied.
  bool get handshakePending =>
      protocol == protocolV2 && (initiatedLocally ? awaitingFirstReply : sendChainKey == null);

  /// Identity key of the party whose handshake created this state (v2 only).
  Uint8List? get initiatorIdentityKey => initiatedLocally ? localIdentityKey : remoteIdentityKey;

  static String skippedKeyId(List<int> ratchetPublic, int counter) => '${b64uEncode(ratchetPublic)}|$counter';

  RatchetState copy() {
    final clone = RatchetState(
      protocol: protocol,
      sessionLocator: sessionLocator,
      localDeviceId: localDeviceId,
      remoteDeviceId: remoteDeviceId,
      remoteIdentityFingerprint: remoteIdentityFingerprint,
      initiatedLocally: initiatedLocally,
      createdAt: createdAt,
      rootKey: Uint8List.fromList(rootKey),
      sendRatchetPrivate: Uint8List.fromList(sendRatchetPrivate),
      sendRatchetPublic: Uint8List.fromList(sendRatchetPublic),
      associatedData: Uint8List.fromList(associatedData),
      localIdentityKey: _copyOrNull(localIdentityKey),
      remoteIdentityKey: _copyOrNull(remoteIdentityKey),
      baseKey: _copyOrNull(baseKey),
      pendingPreKeyHeader: _copyOrNull(pendingPreKeyHeader),
      sendChainKey: _copyOrNull(sendChainKey),
      receiveChainKey: _copyOrNull(receiveChainKey),
      remoteRatchetPublic: _copyOrNull(remoteRatchetPublic),
      sendCounter: sendCounter,
      receiveCounter: receiveCounter,
      previousSendCounter: previousSendCounter,
      needsSendStep: needsSendStep,
      ratchetRotationCount: ratchetRotationCount,
      lastRatchetRotationAt: lastRatchetRotationAt,
    );
    for (final entry in skipped.entries) {
      clone.skipped[entry.key] = SkippedMessageKey(Uint8List.fromList(entry.value.key), entry.value.stashedAt);
    }
    clone.previousRemoteRatchetKeys.addAll(previousRemoteRatchetKeys);
    return clone;
  }

  /// Zeroes every secret this object owns. Called on the losing side of a
  /// commit (the superseded state, or a scratch copy that failed).
  void destroy() {
    zeroize(rootKey);
    zeroize(sendChainKey);
    zeroize(receiveChainKey);
    zeroize(sendRatchetPrivate);
    clearSkipped();
  }

  void clearSkipped() {
    for (final entry in skipped.values) {
      zeroize(entry.key);
    }
    skipped.clear();
  }

  void pruneSkipped(DateTime now) {
    final cutoff = now.subtract(skippedKeyTtl);
    skipped.removeWhere((_, entry) {
      if (!entry.stashedAt.isBefore(cutoff)) return false;
      zeroize(entry.key);
      return true;
    });
  }

  void evictSkippedBeyond(int limit) {
    while (skipped.length > limit) {
      final oldest = skipped.keys.first;
      zeroize(skipped.remove(oldest)!.key);
    }
  }

  Map<String, dynamic> toJson() => {
        'protocol': protocol,
        'sessionLocator': sessionLocator,
        'localDeviceId': localDeviceId,
        'remoteDeviceId': remoteDeviceId,
        'remoteIdentityFingerprint': remoteIdentityFingerprint,
        'initiatedLocally': initiatedLocally,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'localIdentityKey': _b64OrNull(localIdentityKey),
        'remoteIdentityKey': _b64OrNull(remoteIdentityKey),
        'associatedData': b64uEncode(associatedData),
        'baseKey': _b64OrNull(baseKey),
        'pendingPreKey': _b64OrNull(pendingPreKeyHeader),
        'rootKey': b64uEncode(rootKey),
        'sendChainKey': _b64OrNull(sendChainKey),
        'receiveChainKey': _b64OrNull(receiveChainKey),
        'sendCounter': sendCounter,
        'receiveCounter': receiveCounter,
        'previousSendCounter': previousSendCounter,
        'sendRatchetPriv': b64uEncode(sendRatchetPrivate),
        'sendRatchetPub': b64uEncode(sendRatchetPublic),
        'lastSeenPeerPub': _b64OrNull(remoteRatchetPublic),
        'hasReceivedSinceLastSend': needsSendStep,
        'skippedKeys': {
          for (final entry in skipped.entries)
            entry.key: {'k': b64uEncode(entry.value.key), 't': entry.value.stashedAt.toUtc().toIso8601String()},
        },
        'previousPeerPubs': List<String>.of(previousRemoteRatchetKeys),
        'ratchetRotationCount': ratchetRotationCount,
        'lastRatchetRotationAt': lastRatchetRotationAt?.toUtc().toIso8601String(),
      };

  /// Reads a v4 state map, or a whole v2/v3 snapshot (which shared the same
  /// field names and always described a legacy-protocol state).
  static RatchetState fromJson(Map<String, dynamic> json, {required DateTime now}) {
    final state = RatchetState(
      protocol: (json['protocol'] as num?)?.toInt() ?? protocolLegacy,
      sessionLocator: json['sessionLocator'] as String,
      localDeviceId: json['localDeviceId'] as String? ?? '',
      remoteDeviceId: json['remoteDeviceId'] as String? ?? '',
      remoteIdentityFingerprint: json['remoteIdentityFingerprint'] as String? ?? '',
      initiatedLocally: json['initiatedLocally'] as bool? ?? false,
      createdAt: _parseTime(json['createdAt']) ?? now,
      localIdentityKey: _bytesOrNull(json['localIdentityKey']),
      remoteIdentityKey: _bytesOrNull(json['remoteIdentityKey']),
      associatedData: _bytesOrNull(json['associatedData']) ?? Uint8List(0),
      baseKey: _bytesOrNull(json['baseKey']),
      pendingPreKeyHeader: _bytesOrNull(json['pendingPreKey']),
      rootKey: b64uDecode(json['rootKey'] as String),
      sendChainKey: _bytesOrNull(json['sendChainKey']),
      receiveChainKey: _bytesOrNull(json['receiveChainKey']),
      sendCounter: (json['sendCounter'] as num?)?.toInt() ?? 0,
      receiveCounter: (json['receiveCounter'] as num?)?.toInt() ?? 0,
      previousSendCounter: (json['previousSendCounter'] as num?)?.toInt() ?? 0,
      sendRatchetPrivate: b64uDecode(json['sendRatchetPriv'] as String),
      sendRatchetPublic: b64uDecode(json['sendRatchetPub'] as String),
      remoteRatchetPublic: _bytesOrNull(json['lastSeenPeerPub']),
      needsSendStep: json['hasReceivedSinceLastSend'] as bool? ?? false,
      ratchetRotationCount: (json['ratchetRotationCount'] as num?)?.toInt() ?? 0,
      lastRatchetRotationAt: _parseTime(json['lastRatchetRotationAt']),
    );
    final skipped = json['skippedKeys'] as Map<String, dynamic>? ?? const {};
    for (final entry in skipped.entries) {
      final value = entry.value;
      // v2 snapshots stored the bare key with no timestamp.
      final (key, stashedAt) = value is String
          ? (value, now)
          : ((value as Map<String, dynamic>)['k'] as String, _parseTime(value['t']) ?? now);
      state.skipped[entry.key] = SkippedMessageKey(b64uDecode(key), stashedAt);
    }
    state.previousRemoteRatchetKeys.addAll(
      (json['previousPeerPubs'] as List<dynamic>? ?? const []).cast<String>(),
    );
    // A long-backgrounded device must not resurrect week-old stragglers.
    state.pruneSkipped(now);
    return state;
  }
}

Uint8List? _copyOrNull(Uint8List? bytes) => bytes == null ? null : Uint8List.fromList(bytes);

String? _b64OrNull(Uint8List? bytes) => bytes == null ? null : b64uEncode(bytes);

Uint8List? _bytesOrNull(Object? value) => value is String ? b64uDecode(value) : null;

DateTime? _parseTime(Object? value) => value is String ? DateTime.tryParse(value)?.toUtc() : null;
