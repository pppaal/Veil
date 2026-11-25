// The web demo's protocol-v2 stack as a peer another implementation can talk
// to: apps/mobile/test/interop/web_mobile_interop_test.dart starts it under
// Node and drives it turn by turn, so mobile and web exchange real frames in
// both directions. The known-answer tests only show that each client
// reproduces the shared vectors; this shows that the two clients understand
// each other.
//
// Protocol: one JSON request per line on stdin, {"id", "op", ...arguments};
// one JSON line back on stdout per request, {"id", "result"} or
// {"id", "error"}. Requests run one at a time, in order. Every operation
// goes through the same modules the web app runs (src/crypto, src/domain);
// only the server is left out, so the caller relays envelopes and plays the
// key directory.

import { webcrypto } from 'node:crypto';
import { createInterface } from 'node:readline';

import { decodeBase64Url, encodeBase64Url } from '../src/core/base64url.js';
import { decryptAttachment, encryptAttachment } from '../src/crypto/attachment-v2.js';
import { verifyBundle } from '../src/crypto/bundle.js';
import { generateIdentity, publishedKeys } from '../src/crypto/identity.js';
import { createKeySource } from '../src/crypto/keys.js';
import { createLocks } from '../src/crypto/locks.js';
import { claimedOneTimePrekey, createLocalKeyring, maintainPrekeys } from '../src/crypto/prekeys.js';
import { matchesPeerCode, safetyNumber, verificationCode } from '../src/crypto/safety-number.js';
import { createSessionCipher } from '../src/crypto/session-cipher.js';
import { createSessionRepo } from '../src/crypto/session-repo.js';
import { contentFromPayload, payloadFromContent } from '../src/domain/content.js';
import { createMemoryKv } from '../src/platform/kv.js';

const { subtle } = webcrypto;
const keys = createKeySource(webcrypto);
const devices = new Map(); // name -> device

function device(name) {
  const found = devices.get(name);
  if (!found) throw new Error(`no web device named ${name}`);
  return found;
}

// { identityKey: b64u, userId } as the safety-number module takes it.
const party = ({ identityKey, userId }) => ({ identityKey: decodeBase64Url(identityKey), userId });

const ops = {
  // A registered device. Resolves to what /auth/register publishes for it.
  async create({ name, userId, deviceId }) {
    const clock = () => Date.now();
    let record = await generateIdentity(subtle, { nowMs: clock() });
    const opkKv = createMemoryKv('keyId');
    const keyring = createLocalKeyring({ loadIdentity: async () => record, opkKv, clock });
    const repo = createSessionRepo({
      subtle,
      random: keys.randomBytes,
      getKek: async () => record.sessionKek,
      kv: createMemoryKv('conversationId'),
      clock,
    });
    // No identity verifier: pinning is each app's local policy, not part of
    // the wire protocol, and without one the cipher still binds every
    // conversation to the identity it was started with.
    const cipher = createSessionCipher({ subtle, keys, repo, locks: createLocks(null), keyring, clock });
    const identity = {
      current: () => record,
      update: async (fields) => {
        record = { ...record, ...fields };
      },
    };
    devices.set(name, { userId, deviceId, cipher, opkKv, identity, clock });
    const published = await publishedKeys(subtle, record);
    return { identityPublicKey: published.publicIdentityKey, signedPrekeyBundle: published.signedPrekeyBundle };
  },

  // Runs the app's prekey maintenance against a directory holding none of
  // this device's one-time prekeys. Resolves to the batch it uploaded, in
  // the POST /prekeys wire form the directory hands out again on a claim.
  async uploadOneTimePrekeys({ name }) {
    const { identity, opkKv, clock } = device(name);
    let uploaded = null;
    const authedApi = async (path, { method = 'GET', body } = {}) => {
      if (path === '/prekeys/count') return { available: 0 };
      if (path === '/prekeys' && method === 'POST') {
        uploaded = body.prekeys;
        return { available: body.prekeys.length };
      }
      throw new Error(`unexpected directory call ${method} ${path}`);
    };
    await maintainPrekeys({ subtle, keys, authedApi, identity, opkKv, clock });
    return { prekeys: uploaded };
  },

  async holdsOneTimePrekey({ name, keyId }) {
    return { held: (await device(name).opkKv.get(keyId)) !== null };
  },

  // Starts a session from a key-directory device entry, mapped exactly as
  // the app's lookupPeer maps GET /keys/:handle.
  async bootstrap({ name, conversationId, entry }) {
    const started = await device(name).cipher.bootstrap({
      conversationId,
      remoteDeviceId: entry.deviceId,
      remoteIdentityKey: decodeBase64Url(entry.identityPublicKey),
      signedPrekeyBundle: entry.signedPrekeyBundle,
      oneTimePrekey: claimedOneTimePrekey(entry.oneTimePrekey),
    });
    return { started };
  },

  // `content` is a message as the app sends it (src/domain/content.js);
  // `payload` reaches inner-payload fields the app's content model never
  // sets (an authenticated expiry, the system kind). The envelope is what
  // the app posts: a media message names its blob outside the ciphertext
  // too, as src/features/sender.js does.
  async encrypt({ name, conversationId, recipientUserId, content, payload }) {
    const self = device(name);
    const inner = content ? payloadFromContent(content) : { expiresAt: null, attachment: null, ...payload };
    const envelope = await self.cipher.encrypt({
      conversationId,
      senderDeviceId: self.deviceId,
      recipientUserId,
      payload: inner,
    });
    if (inner.attachment) envelope.attachment = { attachmentId: inner.attachment.id };
    return { envelope };
  },

  // The cipher's result, plus the content the app would build from it.
  async decrypt({ name, envelope }) {
    const { status, reason, payload } = await device(name).cipher.decrypt(envelope);
    return { status, reason, payload, content: payload ? contentFromPayload(payload) : null };
  },

  async verifyBundle({ bundle, identityKey }) {
    try {
      const verified = await verifyBundle(subtle, bundle, decodeBase64Url(identityKey), { nowMs: Date.now() });
      return { ok: true, spkId: verified.spkId };
    } catch (error) {
      return { ok: false, reason: error.reason ?? error.message };
    }
  },

  async safetyNumber({ local, remote }) {
    return {
      number: await safetyNumber(subtle, party(local), party(remote)),
      code: verificationCode(party(local), party(remote)),
    };
  },

  async matchesPeerCode({ local, remote, code }) {
    return { match: matchesPeerCode(party(local), party(remote), code) };
  },

  async encryptAttachment({ attachmentId, contentType, data }) {
    const { pointer, blob } = await encryptAttachment(subtle, keys.randomBytes, {
      attachmentId,
      contentType,
      plaintext: decodeBase64Url(data),
    });
    return { pointer, blob: encodeBase64Url(blob) };
  },

  async decryptAttachment({ pointer, blob }) {
    try {
      return { data: encodeBase64Url(await decryptAttachment(subtle, pointer, decodeBase64Url(blob))) };
    } catch (error) {
      return { error: error.message };
    }
  },
};

let queue = Promise.resolve();
createInterface({ input: process.stdin }).on('line', (line) => {
  queue = queue.then(async () => {
    let id = null;
    let response;
    try {
      const { id: requestId, op, ...args } = JSON.parse(line);
      id = requestId;
      if (!Object.hasOwn(ops, op)) throw new Error(`unknown op ${op}`);
      response = { id, result: await ops[op](args) };
    } catch (error) {
      response = { id, error: `${error.name}: ${error.message}` };
    }
    process.stdout.write(`${JSON.stringify(response)}\n`);
  });
});
