// 1:1 protocol-v2 sessions: bootstrap (X3DH initiator), encrypt, and
// decrypt with the responder's PreKey handling, over the session repository.
// A port of the mobile reference session_cipher.dart (v2 only: the web client
// never spoke mobile's legacy v1 protocol).
//
// Every operation holds the conversation's lock (src/crypto/locks.js) from
// reading the record to writing it, works on a copy of the state it touches,
// and commits only once the result is authenticated and the new record is
// durable. Encrypt hands out no ciphertext whose state could still be lost.

import { decodeBase64Url, encodeBase64Url } from '../core/base64url.js';
import { verifyBundle, verifyIkxSignature } from './bundle.js';
import { concatBytes, constantTimeEqual, fitsLengthPrefix, zeroize } from './bytes.js';
import { buildFrameAad, decodeFrame, encodeFrameHeader, ENVELOPE_VERSION_V2 } from './frame.js';
import { aesGcmOpen, aesGcmSeal, GCM_NONCE_BYTES, KeyAgreementError } from './keys.js';
import { conversationLockName } from './locks.js';
import { padMessage, unpad } from './padding.js';
import { decodeInnerPayload, encodeInnerPayload, PayloadFormatError } from './payload-v2.js';
import { PrekeyUnavailableError } from './prekeys.js';
import { advanceSendingChain, deriveInitialSendingChain, RatchetState, resolveReceivingKey } from './ratchet.js';
import { SessionRecord } from './session-record.js';
import {
  deriveInitiatorKeys,
  deriveResponderKeys,
  encodePreKeyHeader,
  NO_ONE_TIME_PREKEY_ID,
} from './x3dh.js';

export const DecryptStatus = Object.freeze({
  OK: 'ok',
  // malformed, unauthenticated, or prekeys unavailable; `reason` says which
  FAILED: 'failed',
  // (ratchetPub, N) already consumed or its chain left behind
  REPLAYED: 'replayed',
  // a Normal frame with no matching session
  SESSION_MISSING: 'sessionMissing',
  // an authenticated handshake from an identity the verifier refused
  IDENTITY_REJECTED: 'identityRejected',
});

class SessionMissingError extends Error {
  constructor(conversationId) {
    super(`no session for conversation ${conversationId}; bootstrap one before sending`);
    this.name = 'SessionMissingError';
  }
}

// The identity the conversation sends to is not admitted any more; nothing
// was encrypted, and the verifier has recorded the change for review.
export class RecipientNotAdmittedError extends Error {
  constructor(conversationId) {
    super(`conversation ${conversationId} sends to an identity that needs review`);
    this.name = 'RecipientNotAdmittedError';
    this.conversationId = conversationId;
  }
}

const failure = (status, reason) => ({ status, payload: null, reason });

// An authenticated frame from an identity the verifier refused, named so the
// caller can tell a key refused for good from one awaiting review.
const identityRejected = (state) => ({
  ...failure(DecryptStatus.IDENTITY_REJECTED, 'identity_rejected'),
  identity: { remoteDeviceId: state.remoteDeviceId, remoteIdentityKey: state.remoteIdentityKey.slice() },
});

// keyring: src/crypto/prekeys.js createLocalKeyring.
// verifyIdentity({ conversationId, remoteDeviceId, identityKey }) -> boolean
// decides whether the peer identity a frame is sealed to or opened from may
// be used, and whether an authenticated PreKey frame may install its state;
// it owns pinning. Without one, a conversation stays bound to the identity
// of its most recent state.
export function createSessionCipher({ subtle, keys, repo, locks, keyring, clock, verifyIdentity = null }) {
  // Runs task({ record, commit }) on the conversation's stored record, under
  // its lock. commit(next) writes the next record, compare-and-swap on the
  // rev that was read; a failed write leaves the stored record as it was.
  // Every operation reloads the record, so the states it read and the ones
  // it committed are wiped when it ends: only the sealed stored copy remains.
  function withRecord(conversationId, task) {
    return locks.run(conversationLockName(conversationId), async () => {
      const { rev, record } = await repo.load(conversationId);
      const touched = new Set(record?.states ?? []);
      const commit = async (next) => {
        await repo.save(conversationId, next, rev);
        for (const state of next.states) touched.add(state);
      };
      try {
        return await task({ record, commit });
      } finally {
        for (const state of touched) state.destroy();
      }
    });
  }

  async function initiate({ remoteDeviceId, remoteIdentityKey, bundle, oneTimePrekey, nowMs }) {
    const local = await keyring.localIdentity();
    const ephemeral = await keys.x25519();
    const handshake = await deriveInitiatorKeys(subtle, {
      identityEd25519: local.ed25519Public,
      identityX25519Private: local.x25519Private,
      identityX25519: local.x25519Public,
      ephemeralPrivate: ephemeral.privateKey,
      remoteIdentityEd25519: remoteIdentityKey,
      remoteIdentityX25519: bundle.ikx,
      remoteSignedPrekey: bundle.spk,
      remoteOneTimePrekey: oneTimePrekey?.publicKey ?? null,
    });
    const chain = await deriveInitialSendingChain(subtle, keys, handshake.sharedKey, bundle.spk);
    zeroize(handshake.sharedKey);
    return new RatchetState({
      remoteDeviceId,
      initiatedLocally: true,
      createdAt: nowMs,
      localIdentityKey: local.ed25519Public.slice(),
      remoteIdentityKey: remoteIdentityKey.slice(),
      associatedData: handshake.associatedData,
      baseKey: ephemeral.publicKey,
      pendingPreKeyHeader: encodePreKeyHeader({
        identityEd25519: local.ed25519Public,
        identityX25519: local.x25519Public,
        identityX25519Signature: local.ikxSignature,
        baseKey: ephemeral.publicKey,
        signedPrekeyId: bundle.spkId,
        oneTimePrekeyId: oneTimePrekey?.keyId ?? NO_ONE_TIME_PREKEY_ID,
      }),
      rootKey: chain.rootKey,
      sendChainKey: chain.chainKey,
      sendRatchet: chain.ratchet,
      remoteRatchetPublic: bundle.spk.slice(),
    });
  }

  // Resolves the key for this frame on `scratch`, then opens it. The AAD is
  // built from the envelope's transmitted fields.
  async function openOn(scratch, envelope, frame, nonce) {
    const resolved = await resolveReceivingKey(subtle, scratch, {
      ratchetPublic: frame.ratchetPublic,
      previousCounter: frame.previousCounter,
      counter: frame.counter,
      nowMs: clock(),
    });
    if (resolved.replayed) return { replayed: true, reason: 'replayed' };
    if (resolved.rejected) return { reason: resolved.rejected };
    const aad = buildFrameAad({
      version: envelope.version,
      conversationId: envelope.conversationId,
      senderDeviceId: envelope.senderDeviceId,
      messageType: envelope.messageType,
      header: frame.header,
      associatedData: scratch.associatedData,
    });
    let padded;
    try {
      padded = await aesGcmOpen(subtle, resolved.messageKey, nonce, frame.sealed, aad);
    } catch {
      return { reason: 'aead_failed' };
    } finally {
      zeroize(resolved.messageKey);
    }
    try {
      const payload = decodeInnerPayload(unpad(padded), { fallbackKind: envelope.messageType });
      // The peer evidently holds this session: stop repeating the handshake.
      scratch.pendingPreKeyHeader = null;
      return { payload };
    } catch (error) {
      if (error instanceof PayloadFormatError) return { reason: 'malformed_payload' };
      throw error;
    } finally {
      zeroize(padded);
    }
  }

  // Asked for every frame sealed or opened, not only when its state was
  // installed: the user may since have verified the contact on another
  // device, and an identity they had accepted before then no longer passes.
  // libsignal consults its identity store before every encrypt and decrypt
  // for the same reason.
  function admitted(conversationId, state) {
    return !verifyIdentity
      || verifyIdentity({ conversationId, remoteDeviceId: state.remoteDeviceId, identityKey: state.remoteIdentityKey });
  }

  // Tries each candidate on its own copy and commits the first that
  // authenticates. `beforeCommit` runs before the state is written, so
  // whatever it persists (the decrypted content) is on disk before the
  // message key is gone.
  async function decryptOnStates({ envelope, frame, nonce, record, commit, candidates, beforeCommit }) {
    let replayed = false;
    for (const live of candidates) {
      const scratch = live.copy();
      const opened = await openOn(scratch, envelope, frame, nonce);
      if (!opened.payload) {
        scratch.destroy();
        replayed ||= opened.replayed === true;
        continue;
      }
      if (!(await admitted(envelope.conversationId, live))) {
        scratch.destroy();
        return identityRejected(live);
      }
      try {
        await beforeCommit?.(opened.payload);
        await commit(record.receiving(live, scratch, clock()));
      } catch {
        scratch.destroy();
        return failure(DecryptStatus.FAILED, 'persist_failed');
      }
      return { status: DecryptStatus.OK, payload: opened.payload, reason: null };
    }
    return replayed ? failure(DecryptStatus.REPLAYED, 'replayed') : failure(DecryptStatus.FAILED, 'decrypt_failed');
  }

  async function inboundAccepted(conversationId, record, state) {
    if (verifyIdentity) return admitted(conversationId, state);
    const bound = record?.current;
    return !bound || constantTimeEqual(bound.remoteIdentityKey, state.remoteIdentityKey);
  }

  // X3DH responder: opens a session a peer started with a PreKey frame. The
  // identity decision comes only after the AEAD verified, so it is never
  // made about a claim nobody proved; a refusal stores nothing and consumes
  // no one-time prekey.
  async function acceptInbound({ envelope, frame, nonce, record, commit, beforeCommit }) {
    const header = frame.preKey;
    let prekeys;
    try {
      prekeys = await keyring.claimHandshakePrekeys(header);
    } catch (error) {
      if (error instanceof PrekeyUnavailableError) return failure(DecryptStatus.FAILED, error.reason);
      throw error;
    }
    let state = null;
    let committed = false;
    try {
      const ikxValid = await verifyIkxSignature(
        subtle,
        header.identityEd25519,
        header.identityX25519,
        header.identityX25519Signature,
      );
      if (!ikxValid) return failure(DecryptStatus.FAILED, 'bad_ikx_signature');
      let handshake;
      try {
        handshake = await deriveResponderKeys(subtle, {
          header,
          identityEd25519: prekeys.identity.ed25519Public,
          identityX25519Private: prekeys.identity.x25519Private,
          identityX25519: prekeys.identity.x25519Public,
          signedPrekeyPrivate: prekeys.signedPrekey.privateKey,
          oneTimePrekeyPrivate: prekeys.oneTimePrekeyPrivate,
        });
      } catch (error) {
        if (error instanceof KeyAgreementError) return failure(DecryptStatus.FAILED, 'low_order_key');
        throw error;
      }
      const nowMs = clock();
      state = new RatchetState({
        remoteDeviceId: envelope.senderDeviceId,
        initiatedLocally: false,
        createdAt: nowMs,
        localIdentityKey: prekeys.identity.ed25519Public.slice(),
        remoteIdentityKey: header.identityEd25519,
        associatedData: handshake.associatedData,
        baseKey: header.baseKey,
        rootKey: handshake.sharedKey,
        sendRatchet: { privateKey: prekeys.signedPrekey.privateKey, publicKey: prekeys.signedPrekey.publicKey.slice() },
      });
      const opened = await openOn(state, envelope, frame, nonce);
      if (!opened.payload) return failure(DecryptStatus.FAILED, opened.reason);
      if (!(await inboundAccepted(envelope.conversationId, record, state))) {
        return identityRejected(state);
      }
      try {
        await beforeCommit?.(opened.payload);
        await commit(SessionRecord.installingInbound(record, state, nowMs));
      } catch {
        return failure(DecryptStatus.FAILED, 'persist_failed');
      }
      committed = true;
      if (header.oneTimePrekeyId !== NO_ONE_TIME_PREKEY_ID) {
        // The session is durable, so its plaintext is returned even if the
        // delete fails; the keyring already marked the prekey spent.
        await keyring.consumeOneTimePrekey(header.oneTimePrekeyId).catch(() => {});
      }
      return { status: DecryptStatus.OK, payload: opened.payload, reason: null };
    } finally {
      if (!committed) state?.destroy();
      keyring.release(header);
    }
  }

  return {
    async hasSession(conversationId) {
      const { record } = await repo.load(conversationId);
      for (const state of record?.states ?? []) state.destroy();
      return record !== null;
    },

    // The identity this conversation sends to: { remoteDeviceId,
    // remoteIdentityKey } of its current state, or null without a session.
    // A safety number is about this key, whichever keys are pinned.
    sessionIdentity(conversationId) {
      return withRecord(conversationId, async ({ record }) => (record
        ? { remoteDeviceId: record.current.remoteDeviceId, remoteIdentityKey: record.current.remoteIdentityKey.slice() }
        : null));
    },

    // Starts a session from a directory entry. The bundle is authenticated
    // against remoteIdentityKey here (BundleError when it does not verify),
    // so no caller can start a session on an unverified one; admit() then
    // decides about the identity key itself (the trust store pins it), so
    // only a key that certifies a valid bundle is ever pinned. Resolves to
    // false, starting nothing, when admit() refuses. The new state becomes
    // current; an older one is archived, not destroyed.
    async bootstrap({
      conversationId,
      remoteDeviceId,
      remoteIdentityKey,
      signedPrekeyBundle,
      oneTimePrekey = null,
      admit = async () => true,
    }) {
      const bundle = await verifyBundle(subtle, signedPrekeyBundle, remoteIdentityKey, { nowMs: clock() });
      if (!(await admit())) return false;
      return withRecord(conversationId, async ({ record, commit }) => {
        const nowMs = clock();
        const state = await initiate({ remoteDeviceId, remoteIdentityKey, bundle, oneTimePrekey, nowMs });
        try {
          await commit(record ? record.promoting(state, nowMs) : new SessionRecord({ current: state }));
        } catch (error) {
          state.destroy();
          throw error;
        }
        return true;
      });
    },

    // payload: { body, kind, expiresAt, attachment, replyTo } (payload-v2.js).
    // The envelope's messageType is the payload's kind, as both are bound.
    async encrypt({ conversationId, senderDeviceId, recipientUserId, payload }) {
      return withRecord(conversationId, async ({ record, commit }) => {
        if (!record) throw new SessionMissingError(conversationId);
        const live = record.current;
        if (!(await admitted(conversationId, live))) throw new RecipientNotAdmittedError(conversationId);
        const scratch = live.copy();
        let frame;
        let nonce;
        try {
          const key = await advanceSendingChain(subtle, keys, scratch);
          nonce = keys.randomBytes(GCM_NONCE_BYTES);
          const header = encodeFrameHeader({
            preKeyHeader: scratch.pendingPreKeyHeader,
            ratchetPublic: key.ratchetPublic,
            previousCounter: key.previousCounter,
            counter: key.counter,
          });
          const aad = buildFrameAad({
            version: ENVELOPE_VERSION_V2,
            conversationId,
            senderDeviceId,
            messageType: payload.kind,
            header,
            associatedData: scratch.associatedData,
          });
          const plaintext = padMessage(encodeInnerPayload(payload));
          const sealed = await aesGcmSeal(subtle, key.messageKey, nonce, plaintext, aad);
          zeroize(key.messageKey, plaintext);
          frame = concatBytes([header, sealed]);
          await commit(record.replacing(live, scratch, clock()));
        } catch (error) {
          scratch.destroy();
          throw error;
        }
        return {
          version: ENVELOPE_VERSION_V2,
          conversationId,
          senderDeviceId,
          recipientUserId,
          ciphertext: encodeBase64Url(frame),
          nonce: encodeBase64Url(nonce),
          messageType: payload.kind,
        };
      });
    },

    // Resolves to { status, payload, reason }, plus the refused { identity }
    // for IDENTITY_REJECTED; hostile input is a result, never an exception,
    // and leaves session state untouched.
    async decrypt(envelope, { beforeCommit = null } = {}) {
      const routing = [envelope.version, envelope.conversationId, envelope.senderDeviceId, envelope.messageType];
      if (!routing.every(fitsLengthPrefix)) return failure(DecryptStatus.FAILED, 'invalid_envelope');
      let frame;
      let nonce;
      try {
        nonce = decodeBase64Url(envelope.nonce);
        frame = decodeFrame(decodeBase64Url(envelope.ciphertext));
      } catch {
        return failure(DecryptStatus.FAILED, 'invalid_envelope');
      }
      if (nonce.length !== GCM_NONCE_BYTES) return failure(DecryptStatus.FAILED, 'invalid_envelope');
      return withRecord(envelope.conversationId, async ({ record, commit }) => {
        const context = { envelope, frame, nonce, record, commit, beforeCommit };
        if (frame.preKey) {
          const owner = record?.states.find((state) => constantTimeEqual(state.baseKey, frame.preKey.baseKey));
          return owner ? decryptOnStates({ ...context, candidates: [owner] }) : acceptInbound(context);
        }
        if (!record) return failure(DecryptStatus.SESSION_MISSING, 'session_missing');
        return decryptOnStates({ ...context, candidates: record.states });
      });
    },
  };
}
