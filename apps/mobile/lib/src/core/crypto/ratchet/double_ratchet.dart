/// Double Ratchet send and receive steps (Signal spec §3.4–3.5) over a
/// scratch [RatchetState]. Nothing here commits: callers apply these to a
/// copy and keep it only after the AEAD verifies.
library;

import 'dart:typed_data';

import '../bytes.dart';
import '../random_source.dart';
import '../x3dh/curve25519.dart';
import 'kdf.dart';
import 'ratchet_state.dart';

// Most keys one received frame may force us to derive and stash. Bounds the
// HKDF work and memory a hostile header can demand.
const int maxSkipPerStep = 200;
// Session-wide stash; beyond it the oldest skipped keys are evicted.
const int maxSkippedKeysPerSession = 1000;
const int _maxPreviousRemoteRatchetKeys = 32;

class InitialSendingChain {
  InitialSendingChain(this.ratchetKeyPair, this.rootKey, this.chainKey);

  final X25519KeyPair ratchetKeyPair;
  final Uint8List rootKey;
  final Uint8List chainKey;
}

/// The initiator's first DH ratchet step against the responder's signed
/// prekey: (RK, CKs) = KDF_RK(SK, DH(DHs, SPK_B)).
Future<InitialSendingChain> deriveInitialSendingChain(
  List<int> sharedKey,
  List<int> remoteSignedPrekey,
  RandomSource random,
) async {
  final pair = await generateX25519KeyPair(random);
  final Uint8List dh;
  try {
    dh = await x25519SharedSecret(pair.privateKey, remoteSignedPrekey);
  } catch (_) {
    zeroize(pair.privateKey);
    rethrow;
  }
  final (rootKey, chainKey) = await kdfRootKey(sharedKey, dh);
  zeroize(dh);
  return InitialSendingChain(pair, rootKey, chainKey);
}

class OutgoingMessageKey {
  OutgoingMessageKey({
    required this.ratchetPublic,
    required this.previousCounter,
    required this.counter,
    required this.messageKey,
  });

  final Uint8List ratchetPublic;
  final int previousCounter;
  final int counter;
  final Uint8List messageKey;
}

Future<OutgoingMessageKey> advanceSendingChain(RatchetState state, RandomSource random, DateTime now) async {
  if (state.needsSendStep) {
    await _sendDhStep(state, random, now);
  }
  final chain = state.sendChainKey;
  if (chain == null) {
    throw StateError('Session has no sending chain yet.');
  }
  final counter = state.sendCounter;
  final messageKey = await deriveMessageKey(chain, counter);
  state.sendChainKey = await nextChainKey(chain);
  zeroize(chain);
  state.sendCounter = counter + 1;
  return OutgoingMessageKey(
    ratchetPublic: Uint8List.fromList(state.sendRatchetPublic),
    previousCounter: state.previousSendCounter,
    counter: counter,
    messageKey: messageKey,
  );
}

sealed class ReceiveKeyResult {}

class ReceiveKeyFound implements ReceiveKeyResult {
  ReceiveKeyFound(this.messageKey);

  final Uint8List messageKey;
}

class ReceiveKeyReplayed implements ReceiveKeyResult {}

class ReceiveKeyRejected implements ReceiveKeyResult {
  ReceiveKeyRejected(this.reason);

  final String reason;
}

/// Resolves the message key for header (ratchetPublic, PN, N), stepping the
/// ratchet as needed. [previousCounter] is null for legacy frames, which do
/// not carry PN; their previous-chain stragglers cannot be recovered.
Future<ReceiveKeyResult> resolveReceivingKey(
  RatchetState state, {
  required Uint8List ratchetPublic,
  required int? previousCounter,
  required int counter,
  required DateTime now,
}) async {
  state.pruneSkipped(now);
  // A stashed key decrypts a straggler without touching the ratchet; doing
  // a DH step first would corrupt the session.
  final stashed = state.skipped.remove(RatchetState.skippedKeyId(ratchetPublic, counter));
  if (stashed != null) return ReceiveKeyFound(stashed.key);
  if (state.previousRemoteRatchetKeys.contains(b64uEncode(ratchetPublic))) {
    return ReceiveKeyReplayed();
  }

  var budget = maxSkipPerStep;
  final current = state.remoteRatchetPublic;
  if (current == null || !constantTimeEquals(current, ratchetPublic)) {
    if (current != null && state.receiveChainKey != null && previousCounter != null) {
      // Keys the peer sent on the chain it is leaving: stash them under the
      // OLD ratchet key so late messages from that turn still decrypt.
      final stashCount = previousCounter - state.receiveCounter;
      if (stashCount > budget) return ReceiveKeyRejected('skip_limit');
      if (stashCount > 0) {
        await _stashUntil(state, current, previousCounter, now);
        budget -= stashCount;
      }
    }
    if (current != null) _rememberPreviousRemoteKey(state, current);
    try {
      await _receiveDhStep(state, ratchetPublic, now);
    } on FormatException {
      return ReceiveKeyRejected('low_order_ratchet_key');
    }
  } else if (counter < state.receiveCounter) {
    return ReceiveKeyReplayed();
  }

  if (state.receiveChainKey == null) return ReceiveKeyRejected('no_receiving_chain');
  if (counter - state.receiveCounter > budget) return ReceiveKeyRejected('skip_limit');
  await _stashUntil(state, ratchetPublic, counter, now);
  final chain = state.receiveChainKey!;
  final messageKey = await deriveMessageKey(chain, counter);
  state.receiveChainKey = await nextChainKey(chain);
  zeroize(chain);
  state.receiveCounter = counter + 1;
  state.evictSkippedBeyond(maxSkippedKeysPerSession);
  return ReceiveKeyFound(messageKey);
}

Future<void> _stashUntil(RatchetState state, List<int> ratchetPublic, int until, DateTime now) async {
  while (state.receiveCounter < until) {
    final chain = state.receiveChainKey!;
    final key = await deriveMessageKey(chain, state.receiveCounter);
    state.skipped[RatchetState.skippedKeyId(ratchetPublic, state.receiveCounter)] = SkippedMessageKey(key, now);
    state.receiveChainKey = await nextChainKey(chain);
    zeroize(chain);
    state.receiveCounter += 1;
  }
}

void _rememberPreviousRemoteKey(RatchetState state, List<int> ratchetPublic) {
  state.previousRemoteRatchetKeys.add(b64uEncode(ratchetPublic));
  if (state.previousRemoteRatchetKeys.length > _maxPreviousRemoteRatchetKeys) {
    state.previousRemoteRatchetKeys.removeAt(0);
  }
}

Future<void> _receiveDhStep(RatchetState state, Uint8List ratchetPublic, DateTime now) async {
  final dh = await x25519SharedSecret(state.sendRatchetPrivate, ratchetPublic);
  final (rootKey, chainKey) = await kdfRootKey(state.rootKey, dh);
  zeroize(dh);
  zeroize(state.rootKey);
  zeroize(state.receiveChainKey);
  state
    ..rootKey = rootKey
    ..receiveChainKey = chainKey
    ..receiveCounter = 0
    ..remoteRatchetPublic = Uint8List.fromList(ratchetPublic)
    ..needsSendStep = true
    ..ratchetRotationCount += 1
    ..lastRatchetRotationAt = now;
}

Future<void> _sendDhStep(RatchetState state, RandomSource random, DateTime now) async {
  final remote = state.remoteRatchetPublic;
  if (remote == null) {
    throw StateError('Cannot rotate the sending ratchet before receiving a peer ratchet key.');
  }
  final pair = await generateX25519KeyPair(random);
  final dh = await x25519SharedSecret(pair.privateKey, remote);
  final (rootKey, chainKey) = await kdfRootKey(state.rootKey, dh);
  zeroize(dh);
  zeroize(state.rootKey);
  zeroize(state.sendChainKey);
  zeroize(state.sendRatchetPrivate);
  state
    ..previousSendCounter = state.sendCounter
    ..sendCounter = 0
    ..rootKey = rootKey
    ..sendChainKey = chainKey
    ..sendRatchetPrivate = pair.privateKey
    ..sendRatchetPublic = pair.publicKey
    ..needsSendStep = false
    ..ratchetRotationCount += 1
    ..lastRatchetRotationAt = now;
}
