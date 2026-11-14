/// 1:1 session operations over [SessionRecordStore]. Every operation runs
/// under the conversation's serial lock, works on a copy of the state it
/// touches, and commits (durably) only once the result is authenticated.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart' show SecretBoxAuthenticationError;

import '../bytes.dart';
import '../crypto_engine.dart';
import '../message_padding.dart';
import '../payload/inner_payload.dart';
import '../random_source.dart';
import '../x3dh/curve25519.dart';
import '../x3dh/identity_keys.dart';
import '../x3dh/local_keyring.dart';
import '../x3dh/x3dh_handshake.dart';
import 'aead.dart';
import 'double_ratchet.dart';
import 'frame_codec.dart';
import 'legacy_session.dart';
import 'ratchet_state.dart';
import 'session_record.dart';
import 'session_store.dart';

const String _auditHintV2 = 'x3dh-v2+double-ratchet+hkdf-sha256+aes256gcm';
const String _auditHintLegacy = 'x25519-double-ratchet+hkdf-sha256+aes256gcm';

String identityFingerprint(List<int> identityEd25519) => hash.sha256.convert(identityEd25519).toString();

class SessionCipher {
  SessionCipher({
    required this.store,
    required this.keyring,
    required RandomSource random,
    required DateTime Function() clock,
  })  : _random = random,
        _clock = clock;

  final SessionRecordStore store;
  final LocalKeyring keyring;
  final RandomSource _random;
  final DateTime Function() _clock;

  RemoteIdentityVerifier? identityVerifier;

  Future<SessionBootstrapMaterial> bootstrap(SessionBootstrapRequest request) async {
    final bundle = await verifyRemoteBundle(
      request.remoteSignedPrekeyBundle,
      request.remoteIdentityPublicKey,
      now: _clock(),
    );
    return store.serialized(request.conversationId, () async {
      final now = _clock();
      final state = switch (bundle) {
        PrekeyBundleV2() => await _initiateV2(request, bundle, now),
        LegacyPrekeyBundle() => await initiateLegacySession(request, bundle, _random, now),
      };
      await _commitAsCurrent(request.conversationId, state, now);
      return _material(state);
    });
  }

  Future<SessionBootstrapMaterial> acceptLegacyInbound(InboundSessionBootstrapRequest request) =>
      store.serialized(request.conversationId, () async {
        final now = _clock();
        final state = await acceptLegacySession(request, now);
        keyring.inboundIdentityRef = request.localIdentityPrivateRef;
        await _commitAsCurrent(request.conversationId, state, now);
        return _material(state);
      });

  /// Seals [payload] on the conversation's sending state. [recipientIdentityKey]
  /// (base64url, empty when the caller knows none) is the identity the caller
  /// chose to reach: an inbound handshake can install a state bound to
  /// another one in the meantime, and a message is never sealed to an
  /// identity the caller did not choose, nor to one the pins no longer admit
  /// ([SessionRecipientChanged]).
  Future<CryptoEnvelope> encrypt({
    required String conversationId,
    required String senderDeviceId,
    required String recipientUserId,
    required InnerPayload payload,
    String recipientIdentityKey = '',
  }) =>
      store.serialized(conversationId, () async {
        final record = store[conversationId];
        if (record == null) {
          throw StateError('No session for conversation $conversationId. Bootstrap a session before sending.');
        }
        final live = record.current;
        if (!_reaches(live, recipientIdentityKey) || !await _stillAdmitted(conversationId, live)) {
          throw SessionRecipientChanged(conversationId);
        }
        final scratch = live.copy();
        final String version;
        final Uint8List frame;
        final Uint8List nonce;
        try {
          final key = await advanceSendingChain(scratch, _random, _clock());
          nonce = _random.nextBytes(gcmNonceLength);
          if (scratch.protocol == protocolV2) {
            version = envelopeVersionV2;
            final header = FrameV2.encodeHeader(
              preKeyHeader: scratch.pendingPreKeyHeader,
              ratchetPublic: key.ratchetPublic,
              previousCounter: key.previousCounter,
              counter: key.counter,
            );
            final aad = buildFrameAadV4(
              version: version,
              conversationId: conversationId,
              senderDeviceId: senderDeviceId,
              messageKind: payload.kind.name,
              header: header,
              associatedData: scratch.associatedData,
            );
            final plaintext = MessagePadding.pad(payload.encode());
            frame = concatBytes(
                [header, await aesGcmSeal(key: key.messageKey, nonce: nonce, plaintext: plaintext, aad: aad)]);
          } else {
            version = envelopeVersionLegacy;
            final aad =
                buildFrameAadV3(ratchetPublic: key.ratchetPublic, counter: key.counter, senderDeviceId: senderDeviceId);
            final plaintext = MessagePadding.pad(payload.encodeLegacy());
            final sealed = await aesGcmSeal(key: key.messageKey, nonce: nonce, plaintext: plaintext, aad: aad);
            frame = LegacyFrame.encode(key.ratchetPublic, key.counter, sealed);
          }
          zeroize(key.messageKey);
        } catch (_) {
          scratch.destroy();
          rethrow;
        }
        await _commitReplacing(conversationId, record, live, scratch);
        return CryptoEnvelope(
          version: version,
          conversationId: conversationId,
          senderDeviceId: senderDeviceId,
          recipientUserId: recipientUserId,
          ciphertext: b64uEncode(frame),
          nonce: b64uEncode(nonce),
          messageKind: payload.kind,
          expiresAt: payload.expiresAt,
          attachment: payload.attachment,
        );
      });

  /// Opens [envelope]. [beforeCommit] runs once it authenticated and before
  /// the advanced state is committed; if it throws, nothing is committed.
  Future<DecryptedMessage> decrypt(CryptoEnvelope envelope, {BeforeCommit? beforeCommit}) async {
    // The server relays these in clear and the v2 AAD length-prefixes them,
    // so one too long to prefix is malformed. Rejected before the lock so it
    // never reaches a session state.
    if (![
      envelope.version,
      envelope.conversationId,
      envelope.senderDeviceId,
      envelope.transmittedMessageType ?? '',
    ].every(fitsLengthPrefix)) {
      return _invalidEnvelope(envelope);
    }
    final Uint8List nonce;
    final Uint8List bytes;
    try {
      nonce = b64uDecode(envelope.nonce);
      bytes = b64uDecode(envelope.ciphertext);
    } on FormatException {
      return _invalidEnvelope(envelope);
    }
    if (nonce.length != gcmNonceLength) {
      return _invalidEnvelope(envelope);
    }
    // Any version other than v1 takes the v2 path, where the version string
    // is bound into the AAD: a relabelled envelope fails authentication.
    return envelope.version == envelopeVersionLegacy
        ? _decryptLegacy(envelope, bytes, nonce, beforeCommit)
        : _decryptV2(envelope, bytes, nonce, beforeCommit);
  }

  Future<DecryptedMessage> _decryptV2(
    CryptoEnvelope envelope,
    Uint8List bytes,
    Uint8List nonce,
    BeforeCommit? beforeCommit,
  ) async {
    final FrameV2 frame;
    try {
      frame = FrameV2.decode(bytes);
    } on FormatException {
      return _invalidEnvelope(envelope);
    }
    return store.serialized(envelope.conversationId, () async {
      final record = store[envelope.conversationId];
      final preKey = frame.preKey;
      Future<_Opened> open(RatchetState scratch) => _openV2(scratch, envelope, frame, nonce);
      if (preKey != null) {
        final owner = record?.states.where((s) => _hasBaseKey(s, preKey.baseKey)).firstOrNull;
        if (owner == null) return _acceptInbound(envelope, frame, preKey, nonce, record, beforeCommit);
        return _decryptOnStates(envelope, record!, [owner], open, DecryptStatus.ok, beforeCommit);
      }
      final candidates = record?.states.where((s) => s.protocol == protocolV2).toList() ?? const [];
      if (candidates.isEmpty) return _failure(envelope, DecryptStatus.sessionMissing, 'session_missing');
      return _decryptOnStates(envelope, record!, candidates, open, DecryptStatus.ok, beforeCommit);
    });
  }

  Future<DecryptedMessage> _decryptLegacy(
    CryptoEnvelope envelope,
    Uint8List bytes,
    Uint8List nonce,
    BeforeCommit? beforeCommit,
  ) async {
    final LegacyFrame frame;
    try {
      frame = LegacyFrame.decode(bytes);
    } on FormatException {
      return _invalidEnvelope(envelope);
    }
    return store.serialized(envelope.conversationId, () async {
      final record = store[envelope.conversationId];
      final candidates = record?.states.where((s) => s.protocol == protocolLegacy).toList() ?? const [];
      if (candidates.isEmpty) return _failure(envelope, DecryptStatus.sessionMissing, 'session_missing');
      Future<_Opened> open(RatchetState scratch) async {
        final keyResult = await resolveReceivingKey(
          scratch,
          ratchetPublic: frame.ratchetPublic,
          previousCounter: null,
          counter: frame.counter,
          now: _clock(),
        );
        final aad = buildFrameAadV3(
          ratchetPublic: frame.ratchetPublic,
          counter: frame.counter,
          senderDeviceId: envelope.senderDeviceId,
        );
        return _openWithKey(keyResult, nonce, frame.sealed, aad, envelope.messageKind);
      }

      return _decryptOnStates(envelope, record!, candidates, open, DecryptStatus.legacyUnauthenticated, beforeCommit);
    });
  }

  /// Tries each candidate on its own copy and commits the first that
  /// authenticates, promoting it to the sending state when the record says
  /// so. The archived states make re-bootstrap and glare lossless; the
  /// copies make a failed attempt side-effect free, and so is a frame whose
  /// state the pins no longer admit: it stays unread until they do.
  Future<DecryptedMessage> _decryptOnStates(
    CryptoEnvelope envelope,
    SessionRecord record,
    List<RatchetState> candidates,
    Future<_Opened> Function(RatchetState scratch) open,
    DecryptStatus successStatus,
    BeforeCommit? beforeCommit,
  ) async {
    var replayed = false;
    // A frame further ahead on its chain than one step may skip (the spec's
    // per-frame bound) is not lost: it opens once the frames before it have,
    // so it waits for them instead of ending as failed.
    var farAhead = false;
    for (final live in candidates) {
      final scratch = live.copy();
      final opened = await open(scratch);
      final payload = opened.payload;
      if (payload != null) {
        if (!await _stillAdmitted(envelope.conversationId, live)) {
          scratch.destroy();
          return _failure(envelope, DecryptStatus.identityRejected, 'identity_rejected');
        }
        final opened = _success(payload, successStatus);
        // The caller stores the plaintext first: once the commit spends the
        // message key, a second decrypt only reports a replay.
        try {
          await beforeCommit?.call(opened);
        } catch (_) {
          scratch.destroy();
          return _failure(envelope, DecryptStatus.failed, 'persist_failed');
        }
        try {
          await _commit(envelope.conversationId, record.receiving(live, scratch, now: _clock()), scratch);
        } catch (_) {
          return _failure(envelope, DecryptStatus.failed, 'persist_failed');
        }
        return opened;
      }
      scratch.destroy();
      replayed = replayed || opened.replayed;
      farAhead = farAhead || opened.reason == 'skip_limit';
    }
    if (replayed) return _failure(envelope, DecryptStatus.replayed, 'replayed');
    return farAhead
        ? _failure(envelope, DecryptStatus.awaitingKey, 'skip_limit')
        : _failure(envelope, DecryptStatus.failed, 'decrypt_failed');
  }

  Future<_Opened> _openV2(RatchetState scratch, CryptoEnvelope envelope, FrameV2 frame, Uint8List nonce) async {
    final keyResult = await resolveReceivingKey(
      scratch,
      ratchetPublic: frame.ratchetPublic,
      previousCounter: frame.previousCounter,
      counter: frame.counter,
      now: _clock(),
    );
    final aad = buildFrameAadV4(
      version: envelope.version,
      conversationId: envelope.conversationId,
      senderDeviceId: envelope.senderDeviceId,
      // The kind as transmitted: a relay that relabels it, even to a value
      // this build cannot parse, breaks the tag.
      messageKind: envelope.transmittedMessageType ?? envelope.messageKind.name,
      header: frame.header,
      associatedData: scratch.associatedData,
    );
    final opened = await _openWithKey(keyResult, nonce, frame.sealed, aad, envelope.messageKind);
    // The peer evidently holds this session, so stop repeating the
    // handshake header.
    if (opened.payload != null) scratch.pendingPreKeyHeader = null;
    return opened;
  }

  /// X3DH responder: opens a session a peer started with a PreKey frame.
  Future<DecryptedMessage> _acceptInbound(
    CryptoEnvelope envelope,
    FrameV2 frame,
    PreKeyHeader header,
    Uint8List nonce,
    SessionRecord? record,
    BeforeCommit? beforeCommit,
  ) async {
    final HandshakePrekeys prekeys;
    try {
      prekeys = await keyring.claimHandshakePrekeys(header);
    } on PrekeyUnavailable catch (e) {
      return _failure(envelope, DecryptStatus.failed, e.reason);
    }
    // Owned by the store once committed; destroyed on every other way out,
    // including a verifier that throws.
    RatchetState? state;
    var committed = false;
    try {
      final ikxValid = await verifyIkxSignature(
        header.identityEd25519,
        header.identityX25519,
        header.identityX25519Signature,
      );
      if (!ikxValid) return _failure(envelope, DecryptStatus.failed, 'bad_ikx_signature');
      final HandshakeKeys keys;
      try {
        keys = await deriveResponderKeys(
          header: header,
          identityEd25519: prekeys.identity.ed25519Public,
          identityX25519Private: prekeys.identity.identity.x25519Private,
          identityX25519: prekeys.identity.x25519Public,
          signedPrekeyPrivate: prekeys.signedPrekey.privateKey,
          oneTimePrekeyPrivate: prekeys.oneTimePrekeyPrivate,
        );
      } on FormatException {
        return _failure(envelope, DecryptStatus.failed, 'low_order_key');
      }
      final now = _clock();
      state = RatchetState(
        protocol: protocolV2,
        sessionLocator: 'session://${envelope.conversationId}',
        // A PreKey frame does not name the recipient device.
        localDeviceId: '',
        remoteDeviceId: envelope.senderDeviceId,
        remoteIdentityFingerprint: identityFingerprint(header.identityEd25519),
        initiatedLocally: false,
        createdAt: now,
        rootKey: keys.sharedKey,
        sendRatchetPrivate: Uint8List.fromList(prekeys.signedPrekey.privateKey),
        sendRatchetPublic: prekeys.signedPrekey.publicKey,
        associatedData: keys.associatedData,
        localIdentityKey: prekeys.identity.ed25519Public,
        remoteIdentityKey: header.identityEd25519,
        baseKey: header.baseKey,
      );
      final opened = await _openV2(state, envelope, frame, nonce);
      final payload = opened.payload;
      if (payload == null) {
        // A handshake frame further along its chain than one step may skip
        // waits, as on an installed session: it opens on the session an
        // earlier frame of the same handshake installs. Nothing was spent on
        // it, and its one-time prekey is released below.
        final status = opened.reason == 'skip_limit' ? DecryptStatus.awaitingKey : DecryptStatus.failed;
        return _failure(envelope, status, opened.reason);
      }
      // Decided only once the handshake authenticated, so neither a pinning
      // verifier nor identityRejected ever concerns a claim nobody proved.
      if (!await _identityAccepted(envelope, header, record)) {
        return _failure(envelope, DecryptStatus.identityRejected, 'identity_rejected');
      }
      final result = _success(payload, DecryptStatus.ok);
      try {
        // The caller stores the plaintext before the session is installed.
        await beforeCommit?.call(result);
        await store.commit(envelope.conversationId, SessionRecord.installingInbound(record, state, now: now));
      } catch (_) {
        return _failure(envelope, DecryptStatus.failed, 'persist_failed');
      }
      committed = true;
      if (header.usesOneTimePrekey) await _consumeOneTimePrekey(header.oneTimePrekeyId);
      return result;
    } finally {
      if (!committed) state?.destroy();
      keyring.releaseOneTimePrekey(header);
      prekeys.destroy();
    }
  }

  /// A configured verifier (the trust store) owns this decision. Without
  /// one, the conversation stays bound to the identity of its most recent
  /// authenticated (v2) state, which only a local bootstrap can change:
  /// otherwise any genuine identity the server steers here could take over
  /// the sending state of an established conversation. Legacy states never
  /// authenticated their peer, so they pin nothing.
  Future<bool> _identityAccepted(CryptoEnvelope envelope, PreKeyHeader header, SessionRecord? record) async {
    final verifier = identityVerifier;
    if (verifier != null) {
      return verifier(RemoteIdentityClaim(
        conversationId: envelope.conversationId,
        senderDeviceId: envelope.senderDeviceId,
        identityKeyEd25519: b64uEncode(header.identityEd25519),
        identityKeyX25519: b64uEncode(header.identityX25519),
      ));
    }
    final bound = record?.states.where((s) => s.protocol == protocolV2).firstOrNull;
    if (bound == null) return true;
    final pinned = bound.remoteIdentityKey;
    return pinned != null && constantTimeEquals(pinned, header.identityEd25519);
  }

  /// Asked for every frame sealed to or opened on [state], not only when it
  /// was installed: the user may since have verified another device of the
  /// contact, or accepted a successor for this one, and what the pins
  /// admitted then no longer passes. Legacy states never learned their
  /// peer's identity, and without a verifier only installs are decided.
  Future<bool> _stillAdmitted(String conversationId, RatchetState state) async {
    final verifier = identityVerifier;
    final identity = state.remoteIdentityKey;
    if (verifier == null || identity == null) return true;
    return verifier(RemoteIdentityClaim(
      conversationId: conversationId,
      senderDeviceId: state.remoteDeviceId,
      identityKeyEd25519: b64uEncode(identity),
      installsSession: false,
    ));
  }

  /// The session is already durable, so its plaintext must be returned even
  /// if the delete fails: a retry would only report a replay. The keyring
  /// marks the prekey spent before deleting it, so it cannot open a second
  /// session either way.
  Future<void> _consumeOneTimePrekey(int keyId) async {
    try {
      await keyring.consumeOneTimePrekey(keyId);
    } catch (_) {
      // Only the stored private half outlives the failure; see above.
    }
  }

  Future<RatchetState> _initiateV2(SessionBootstrapRequest request, PrekeyBundleV2 bundle, DateTime now) async {
    final local = await keyring.resolveIdentity();
    try {
      return await _initiateWithIdentity(request, bundle, local, now);
    } finally {
      local.destroy();
    }
  }

  Future<RatchetState> _initiateWithIdentity(
    SessionBootstrapRequest request,
    PrekeyBundleV2 bundle,
    LocalIdentityKeys local,
    DateTime now,
  ) async {
    final remoteIdentity = b64uDecode(request.remoteIdentityPublicKey);
    final oneTime = request.remoteOneTimePrekey;
    final oneTimePublic = oneTime == null ? null : _validOneTimePrekey(oneTime);
    final ephemeral = await generateX25519KeyPair(_random);
    final HandshakeKeys keys;
    try {
      keys = await deriveInitiatorKeys(
        identityEd25519: local.ed25519Public,
        identityX25519Private: local.identity.x25519Private,
        identityX25519: local.x25519Public,
        ephemeralPrivate: ephemeral.privateKey,
        remoteIdentityEd25519: remoteIdentity,
        remoteIdentityX25519: bundle.ikx,
        remoteSignedPrekey: bundle.spk,
        remoteOneTimePrekey: oneTimePublic,
      );
    } finally {
      zeroize(ephemeral.privateKey);
    }
    final InitialSendingChain chain;
    try {
      chain = await deriveInitialSendingChain(keys.sharedKey, bundle.spk, _random);
    } finally {
      zeroize(keys.sharedKey);
    }
    final header = PreKeyHeader(
      identityEd25519: local.ed25519Public,
      identityX25519: local.x25519Public,
      identityX25519Signature: await local.signIkx(),
      baseKey: ephemeral.publicKey,
      signedPrekeyId: bundle.spkId,
      oneTimePrekeyId: oneTime?.keyId ?? noOneTimePrekeyId,
    );
    return RatchetState(
      protocol: protocolV2,
      sessionLocator: 'session://${request.conversationId}',
      localDeviceId: request.localDeviceId,
      remoteDeviceId: request.remoteDeviceId,
      remoteIdentityFingerprint: identityFingerprint(remoteIdentity),
      initiatedLocally: true,
      createdAt: now,
      rootKey: chain.rootKey,
      sendChainKey: chain.chainKey,
      sendRatchetPrivate: chain.ratchetKeyPair.privateKey,
      sendRatchetPublic: chain.ratchetKeyPair.publicKey,
      remoteRatchetPublic: bundle.spk,
      associatedData: keys.associatedData,
      localIdentityKey: local.ed25519Public,
      remoteIdentityKey: remoteIdentity,
      baseKey: ephemeral.publicKey,
      pendingPreKeyHeader: header.encode(),
    );
  }

  Future<void> _commitAsCurrent(String conversationId, RatchetState state, DateTime now) async {
    final record = store[conversationId];
    final update =
        record == null ? RecordUpdate(SessionRecord(rev: 0, current: state)) : record.promoting(state, now: now);
    try {
      await store.commit(conversationId, update);
    } catch (_) {
      state.destroy();
      rethrow;
    }
  }

  Future<void> _commitReplacing(String conversationId, SessionRecord record, RatchetState live, RatchetState scratch) =>
      _commit(conversationId, record.replacing(live, scratch, now: _clock()), scratch);

  Future<void> _commit(String conversationId, RecordUpdate update, RatchetState scratch) async {
    try {
      await store.commit(conversationId, update);
    } catch (_) {
      scratch.destroy();
      rethrow;
    }
  }

  static Uint8List _validOneTimePrekey(OneTimePrekey prekey) {
    final public = b64uDecode(prekey.publicKey);
    if (public.length != 32 || prekey.keyId < 0 || prekey.keyId >= noOneTimePrekeyId) {
      throw StateError('Claimed one-time prekey is malformed.');
    }
    return public;
  }

  // Legacy states never learned their peer's identity, so only the caller's
  // choice of session binds them. A bound state is reached only by naming
  // its identity: a caller that names none (a conversation that lost what
  // it knew) must choose again instead of sealing to whoever the state holds.
  static bool _reaches(RatchetState state, String identityKey) {
    final bound = state.remoteIdentityKey;
    if (bound == null) return true;
    if (identityKey.isEmpty) return false;
    try {
      return constantTimeEquals(bound, b64uDecode(identityKey));
    } on FormatException {
      return false;
    }
  }

  static bool _hasBaseKey(RatchetState state, Uint8List baseKey) {
    final own = state.baseKey;
    return own != null && constantTimeEquals(own, baseKey);
  }

  static SessionBootstrapMaterial _material(RatchetState state) {
    final v2 = state.protocol == protocolV2;
    return SessionBootstrapMaterial(
      sessionLocator: state.sessionLocator,
      sessionEnvelopeVersion: v2 ? envelopeVersionV2 : envelopeVersionLegacy,
      requiresLocalPersistence: true,
      sessionSchemaVersion: sessionSnapshotSchemaVersion,
      localDeviceId: state.localDeviceId,
      remoteDeviceId: state.remoteDeviceId,
      remoteIdentityFingerprint: state.remoteIdentityFingerprint,
      auditHint: v2 ? _auditHintV2 : _auditHintLegacy,
    );
  }

  static Future<_Opened> _openWithKey(
    ReceiveKeyResult keyResult,
    Uint8List nonce,
    Uint8List sealed,
    Uint8List aad,
    MessageKind fallbackKind,
  ) async {
    switch (keyResult) {
      case ReceiveKeyReplayed():
        return _Opened.replayed();
      case ReceiveKeyRejected(:final reason):
        return _Opened.failed(reason);
      case ReceiveKeyFound(:final messageKey):
        try {
          final padded = await aesGcmOpen(key: messageKey, nonce: nonce, sealed: sealed, aad: aad);
          return _Opened.ok(InnerPayload.decode(MessagePadding.unpad(padded), fallbackKind: fallbackKind));
        } on SecretBoxAuthenticationError {
          return _Opened.failed('aead_failed');
        } catch (e) {
          // Backstop for the decoder: bytes the peer authenticated can still
          // be hostile, and an error they provoke (RangeError is an
          // ArgumentError) must fail this frame, not escape decrypt.
          if (e is FormatException || e is ArgumentError || e is UnsupportedError) {
            return _Opened.failed('malformed_payload');
          }
          rethrow;
        } finally {
          zeroize(messageKey);
        }
    }
  }

  static DecryptedMessage _success(InnerPayload payload, DecryptStatus status) => DecryptedMessage(
        body: payload.body,
        messageKind: payload.kind,
        expiresAt: payload.expiresAt,
        attachment: payload.attachment,
        status: status,
      );

  /// Non-ok results carry no body at all, so nothing a peer can type ever
  /// looks like one; callers branch on [DecryptStatus].
  static DecryptedMessage _failure(CryptoEnvelope envelope, DecryptStatus status, String? reason) => DecryptedMessage(
        body: '',
        messageKind: envelope.messageKind,
        status: status,
        failureReason: reason,
      );

  static DecryptedMessage _invalidEnvelope(CryptoEnvelope envelope) =>
      _failure(envelope, DecryptStatus.failed, 'invalid_envelope');
}

class _Opened {
  _Opened.ok(InnerPayload this.payload)
      : replayed = false,
        reason = null;

  _Opened.replayed()
      : payload = null,
        replayed = true,
        reason = 'replayed';

  _Opened.failed(String this.reason)
      : payload = null,
        replayed = false;

  final InnerPayload? payload;
  final bool replayed;
  final String? reason;
}
