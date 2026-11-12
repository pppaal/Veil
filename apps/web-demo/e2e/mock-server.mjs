// A stand-in for the VEIL API that the browser tests (e2e/browser/,
// e2e/characterization/) run the web demo against, with no Postgres, Redis
// or object storage: it serves the demo at /demo/ and an in-memory /v1 relay
// (auth, key directory, prekeys, conversations, messages, receipts,
// attachments, reports, device transfer, one-time secret links). It relays
// ciphertext and never decrypts. Its realtime gateway (mock-realtime.mjs) is
// off until a test turns it on, so by default /v1/realtime refuses the
// upgrade and the demo falls back to polling.
//
// Whatever the real API refuses on the routes the demo uses, this relay
// refuses too, with the same status and error code: request bodies are
// checked as the API's global ValidationPipe ({ whitelist,
// forbidNonWhitelisted }) checks its DTOs, a signed prekey as
// KeysService.rotateSignedPrekey checks it (signature, the spkTs window of an
// hour back and 10 minutes ahead of server time, the IKx pin, an increasing
// spkId), and a device transfer as DeviceTransferService runs it (token,
// signed claim, approval and completion proofs, first claim wins, approval
// first, the old device revoked with the transfer, an identical completion
// retry answered as the first). A break between the demo and the
// API then fails here first.
//
// Test hooks, under /__test/:
//   POST /__test/reset                  forget everything
//   POST /__test/delivery {shuffle}     hold new messages back from their
//                                       recipient and hand them over one at a
//                                       time, picked at random, per history
//                                       fetch: frames arrive out of order
//   POST /__test/tamper {enabled}       serve every ciphertext with a flipped
//                                       byte (what a client renders now cannot
//                                       come from decrypting the relay's copy)
//   POST /__test/impersonate {victim, target, text}
//                                       swap the victim's directory keys for a
//                                       relay-held identity and open a session
//                                       to the target as the victim's device
//   POST /__test/timer {seconds, relayExpiry}
//                                       set the conversation timer (null:
//                                       off): conversations list it, and the
//                                       outer expiresAt of messages stored
//                                       from now on follows it, as the API
//                                       does, unless relayExpiry is false (a
//                                       hostile relay that drops it). Expired
//                                       messages are still served, as a
//                                       lagging or hostile relay would
//   POST /__test/realtime {enabled}     turn the realtime gateway on or off
//   POST /__test/revoke {handle}        revoke the handle's active device, as
//                                       a revocation on the server would: its
//                                       tokens and sockets stop working and it
//                                       can no longer sign in
//   POST /__test/lose-completion        the next device transfer that
//                                       completes answers 503, as if its
//                                       answer were lost: the transfer stands
//   GET  /__test/reports                the abuse reports filed so far
//
// Usage: node apps/web-demo/e2e/mock-server.mjs   (VEIL_MOCK_PORT, default 4317)

import { createHash, createPublicKey, randomBytes, randomUUID, verify, webcrypto } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import http from 'node:http';
import { extname, join, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { decodeBase64Url } from '../src/core/base64url.js';
import { BundleError, verifyBundle } from '../src/crypto/bundle.js';
import { constantTimeEqual } from '../src/crypto/bytes.js';
import { generateIdentity, publishedKeys } from '../src/crypto/identity.js';
import { createKeySource } from '../src/crypto/keys.js';
import { createLocks } from '../src/crypto/locks.js';
import { createLocalKeyring } from '../src/crypto/prekeys.js';
import { createSessionCipher } from '../src/crypto/session-cipher.js';
import { createSessionRepo } from '../src/crypto/session-repo.js';
import { createMemoryKv } from '../src/platform/kv.js';
import { createRealtimeGateway } from './mock-realtime.mjs';

const PORT = Number(process.env.VEIL_MOCK_PORT ?? 4317);
const DEMO_ROOT = fileURLToPath(new URL('..', import.meta.url));
const SERVED = ['index.html', 's.html', 'app.js', 's.js', 'app.css', 'socket.io.min.js', 'manifest.json', 'icon.svg'];
const SERVED_DIRS = ['i18n', 'src', 'lib'];
const CONTENT_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
};
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');
// The window PUT /keys/signed-prekey accepts spkTs in (contract C-SPK).
const SIGNED_PREKEY_MAX_AGE_MS = 60 * 60 * 1000;
const SIGNED_PREKEY_MAX_LEAD_MS = 10 * 60 * 1000;
const REPORT_REASONS = ['spam', 'harassment', 'impersonation', 'csam', 'violence', 'scam', 'other'];
const UPLOAD_STATUSES = ['pending', 'uploaded', 'failed'];
const DEVICE_PLATFORMS = ['ios', 'android', 'windows', 'macos', 'linux'];
// VEIL_TRANSFER_TOKEN_TTL_SECONDS default.
const TRANSFER_TTL_MS = 5 * 60 * 1000;
// CreateSecretDto: MAX_CIPHERTEXT_LENGTH and the ttlSeconds bounds.
const SECRET_MAX_CIPHERTEXT = 128 * 1024;
const SECRET_TTL_SECONDS = { min: 60, max: 7 * 24 * 60 * 60, fallback: 24 * 60 * 60 };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

class HttpError extends Error {
  constructor(status, code, message = code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

// Field rules for validateBody: each returns what is wrong, or null.
const rule = (holds, problem) => (value) => (holds(value) ? null : problem);
const optional = (check) => (value) => (value === undefined || value === null ? null : check(value));
const uuid = (pattern = UUID) => rule((value) => typeof value === 'string' && pattern.test(value), 'must be a UUID');
const oneOf = (allowed) => rule((value) => allowed.includes(value), `must be one of the following values: ${allowed.join(', ')}`);
const matches = (pattern) => rule((value) => typeof value === 'string' && pattern.test(value), `must match ${pattern}`);
const intWithin = (min, max) =>
  rule((value) => Number.isInteger(value) && value >= min && value <= max, `must be an integer from ${min} to ${max}`);
const stringUpTo = (max) =>
  rule((value) => typeof value === 'string' && value.length <= max, `must be a string of at most ${max} characters`);
// UploadPrekeysDto: 1 to 100 { keyId, publicKey }.
const prekeyBatch = (value) => {
  const valid = Array.isArray(value) && value.length >= 1 && value.length <= 100 && value.every((prekey) => (
    Object.keys(prekey ?? {}).every((field) => field === 'keyId' || field === 'publicKey')
    && intWithin(0, 0x7fffffff)(prekey.keyId) === null
    && matches(/^[A-Za-z0-9._:+/=-]{1,512}$/)(prekey.publicKey) === null));
  return valid ? null : 'must be 1 to 100 one-time prekeys { keyId, publicKey }';
};

const NONCE = /^[A-Za-z0-9._:-]{1,512}$/;
const isIsoDate = (value) => typeof value === 'string' && Number.isFinite(Date.parse(value));
// The fields of an object a DTO nests, each with its rule.
const nested = (rules) => (value) => {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return 'must be an object';
  const unknown = Object.keys(value).filter((field) => !Object.hasOwn(rules, field));
  if (unknown.length > 0) return `has properties that should not exist: ${unknown.join(', ')}`;
  const broken = Object.entries(rules).filter(([field, rule]) => rule(value[field]) !== null).map(([field]) => field);
  return broken.length > 0 ? `has invalid ${broken.join(', ')}` : null;
};
const ciphertext = stringUpTo(131072);
// EnvelopeDto and AttachmentReferenceDto (send-message.dto.ts).
const envelopeRule = nested({
  version: stringUpTo(64),
  conversationId: uuid(),
  senderDeviceId: uuid(),
  recipientUserId: optional(uuid()),
  ciphertext,
  nonce: matches(NONCE),
  messageType: stringUpTo(32),
  expiresAt: optional((value) => (isIsoDate(value) ? null : 'must be an ISO-8601 date')),
  viewOnce: optional((value) => (typeof value === 'boolean' ? null : 'must be a boolean')),
  attachment: optional(nested({
    attachmentId: uuid(),
    storageKey: optional(stringUpTo(256)),
    contentType: optional(stringUpTo(128)),
    sizeBytes: optional(intWithin(0, Number.MAX_SAFE_INTEGER)),
    sha256: optional(stringUpTo(128)),
    encryption: optional((value) => (typeof value === 'object' ? null : 'must be an object')),
  })),
});

// Refuses a body the way the API's ValidationPipe does: properties the DTO
// does not declare, and declared ones that break their rule.
function validateBody(body, rules) {
  const problems = Object.keys(body ?? {})
    .filter((field) => !Object.hasOwn(rules, field))
    .map((field) => `property ${field} should not exist`);
  for (const [field, rule] of Object.entries(rules)) {
    const problem = rule(body?.[field]);
    if (problem) problems.push(`${field} ${problem}`);
  }
  if (problems.length > 0) throw new HttpError(400, 'validation_failed', problems.join('; '));
}

let db;
function reset() {
  db = {
    users: new Map(), // id -> { id, handle, activeDeviceId }
    devices: new Map(), // id -> { id, userId, identityPublicKey, signedPrekeyBundle, authPublicKey, oneTimePrekeys: [], revokedAt }
    tokens: new Map(), // access token -> deviceId
    refreshTokens: new Map(),
    challenges: new Map(),
    conversations: new Map(), // id -> { id, memberIds, createdAt, lastOrder }
    messages: [],
    blobs: new Map(),
    receipts: new Set(), // `${messageId}:${userId}` once that member read it
    transfers: new Map(), // id -> { id, userId, oldDeviceId, token, expiresAt, completedAt, ended, claim, newDeviceId }
    secrets: new Map(), // id -> { ciphertext, expiresAt }
    reports: [],
    shuffle: false,
    tamper: false,
    timerSeconds: null,
    relayExpiry: true,
    loseCompletion: false,
  };
}
reset();

const now = () => new Date().toISOString();
const token = () => randomBytes(24).toString('hex');
const userByHandle = (handle) => [...db.users.values()].find((user) => user.handle === handle) ?? null;
const activeDevice = (user) => db.devices.get(user.activeDeviceId);

function issueTokens(device) {
  const accessToken = token();
  const refreshToken = token();
  db.tokens.set(accessToken, device.id);
  db.refreshTokens.set(refreshToken, device.id);
  return { accessToken, refreshToken, userId: device.userId, deviceId: device.id };
}

// The device and user an access token belongs to, or null.
function sessionOf(accessToken) {
  const device = db.devices.get(db.tokens.get(accessToken));
  return device && !device.revokedAt ? { device, user: db.users.get(device.userId) } : null;
}

function authenticate(req) {
  const match = /^Bearer (.+)$/.exec(req.headers.authorization ?? '');
  const session = match ? sessionOf(match[1]) : null;
  if (!session) throw new HttpError(401, 'unauthorized');
  return session;
}

// As revokeDevice in apps/api: the device's tokens stop working at once and
// it holds no realtime channel.
function revokeDevice(device) {
  device.revokedAt = now();
  for (const tokens of [db.tokens, db.refreshTokens]) {
    for (const [value, deviceId] of tokens) if (deviceId === device.id) tokens.delete(value);
  }
  realtime.disconnectDevice(device.id);
}

// The device-auth proofs: an Ed25519 signature by the raw 32-byte auth key
// over the challenge text.
function signedBy(authPublicKey, challenge, signature) {
  try {
    const key = createPublicKey({
      key: Buffer.concat([ED25519_SPKI_PREFIX, Buffer.from(authPublicKey, 'base64url')]),
      format: 'der',
      type: 'spki',
    });
    return verify(null, Buffer.from(challenge), key, Buffer.from(signature, 'base64url'));
  } catch {
    return false;
  }
}

const isMember = (userId, conversationId) => db.conversations.get(conversationId)?.memberIds.includes(userId) ?? false;

const realtime = createRealtimeGateway({
  authenticate: sessionOf,
  isMember,
  membersOf: (conversationId) => db.conversations.get(conversationId)?.memberIds ?? [],
});

function emitToMembers(conversation, event, payload, { except = null } = {}) {
  for (const userId of conversation.memberIds) if (userId !== except) realtime.emitToUser(userId, event, payload);
}

function conversationFor(user, conversationId) {
  const conversation = db.conversations.get(conversationId);
  if (!conversation?.memberIds.includes(user.id)) throw new HttpError(404, 'conversation_not_found');
  return conversation;
}

// What a viewer may see of a message: held-back messages only once released,
// ciphertext flipped while tampering.
function visibleTo(viewer, message) {
  return message.senderUserId === viewer.id || message.released;
}

// While shuffling, each history fetch hands its recipient one held message,
// picked at random.
function releaseOneHeld(viewer, conversationId) {
  const held = db.messages.filter(
    (m) => m.conversationId === conversationId && m.senderUserId !== viewer.id && !m.released,
  );
  if (held.length > 0) held[Math.floor(Math.random() * held.length)].released = true;
}

function summaryFor(message) {
  const { senderUserId, released, ...summary } = message;
  if (!db.tamper || summary.deletedAt) return summary;
  const bytes = Buffer.from(summary.ciphertext, 'base64url');
  bytes[bytes.length - 1] ^= 0xff;
  return { ...summary, ciphertext: bytes.toString('base64url') };
}

function conversationSummary(viewer, conversation) {
  const visible = db.messages.filter((m) => m.conversationId === conversation.id && visibleTo(viewer, m));
  return {
    id: conversation.id,
    type: 'direct',
    createdAt: conversation.createdAt,
    members: conversation.memberIds.map((id) => ({ userId: id, handle: db.users.get(id).handle })),
    disappearingTimerSeconds: db.timerSeconds,
    lastMessage: visible.length > 0 ? summaryFor(visible.at(-1)) : null,
  };
}

function storeMessage(device, conversation, { clientMessageId, envelope }) {
  const duplicate = db.messages.find((m) => m.senderDeviceId === device.id && m.clientMessageId === clientMessageId);
  if (duplicate) return duplicate;
  conversation.lastOrder += 1;
  const message = {
    id: randomUUID(),
    clientMessageId,
    conversationId: conversation.id,
    senderDeviceId: device.id,
    conversationOrder: conversation.lastOrder,
    version: envelope.version,
    ciphertext: envelope.ciphertext,
    nonce: envelope.nonce,
    messageType: envelope.messageType,
    attachment: envelope.attachment?.attachmentId ? { attachmentId: envelope.attachment.attachmentId } : null,
    expiresAt: db.timerSeconds && db.relayExpiry ? new Date(Date.now() + db.timerSeconds * 1000).toISOString() : null,
    viewOnce: false,
    serverReceivedAt: now(),
    deletedAt: null,
    editedAt: null,
    editCount: 0,
    replyToMessageId: null,
    deliveredAt: null,
    readAt: null,
    senderUserId: device.userId,
    released: !db.shuffle,
  };
  db.messages.push(message);
  return message;
}

function claimOneTimePrekey(device) {
  return device.oneTimePrekeys.shift() ?? null;
}

// As KeysService.rotateSignedPrekey: a canonical v2 bundle signed by the
// device identity key, stamped within the window of server time, on the
// pinned IKx, with a larger spkId than the stored bundle's.
async function rotateSignedPrekey(device, signedPrekeyBundle) {
  validateBody({ signedPrekeyBundle }, { signedPrekeyBundle: matches(/^[A-Za-z0-9_-]{1,8192}$/) });
  const identityKey = decodeBase64Url(device.identityPublicKey);
  const now = Date.now();
  let next = null;
  try {
    next = await verifyBundle(webcrypto.subtle, signedPrekeyBundle, identityKey, { nowMs: now });
  } catch (error) {
    if (!(error instanceof BundleError)) throw error;
    if (error.reason === 'unsupported' || error.reason === 'malformed') {
      throw new HttpError(400, 'validation_failed', 'Signed prekey bundle must be a canonical v2 bundle');
    }
    if (error.reason === 'bad_signature') {
      throw new HttpError(400, 'invalid_device_signature', 'Signed prekey bundle is not signed by the device identity key');
    }
    // 'stale' or 'future': far outside the window, checked next.
    next = { spkTs: NaN };
  }
  if (!(next.spkTs >= now - SIGNED_PREKEY_MAX_AGE_MS && next.spkTs <= now + SIGNED_PREKEY_MAX_LEAD_MS)) {
    throw new HttpError(
      400,
      'signed_prekey_timestamp_out_of_window',
      'Signed prekey timestamp must be within the last hour and at most 10 minutes ahead of server time',
    );
  }
  const current = await verifyBundle(webcrypto.subtle, device.signedPrekeyBundle, identityKey, { nowMs: now }).catch(() => null);
  if (current && !constantTimeEqual(next.ikx, current.ikx)) {
    throw new HttpError(400, 'validation_failed', 'The X25519 identity key cannot change');
  }
  if (current && next.spkId <= current.spkId) {
    throw new HttpError(400, 'validation_failed', 'spkId must increase with every rotation');
  }
  device.signedPrekeyBundle = signedPrekeyBundle;
  return { deviceId: device.id, spkId: next.spkId };
}

function directory(handle) {
  const user = userByHandle(handle);
  if (!user) throw new HttpError(404, 'handle_not_found');
  const device = activeDevice(user);
  return {
    user: { id: user.id, handle: user.handle, activeDeviceId: device.id },
    devices: [{
      deviceId: device.id,
      identityPublicKey: device.identityPublicKey,
      signedPrekeyBundle: device.signedPrekeyBundle,
      isActive: true,
      oneTimePrekey: claimOneTimePrekey(device),
    }],
  };
}

// A relay that holds an identity of its own takes over the victim's
// directory entry and opens a session to the target as the victim's device.
// The handshake authenticates (the relay holds that identity's keys); only
// the target's pin on the victim's real key can tell.
async function impersonate({ victim, target, text }) {
  const victimUser = userByHandle(victim);
  const targetUser = userByHandle(target);
  const victimDevice = activeDevice(victimUser);
  const targetDevice = activeDevice(targetUser);
  const conversation = [...db.conversations.values()].find(
    (c) => c.memberIds.includes(victimUser.id) && c.memberIds.includes(targetUser.id),
  );
  const { subtle } = webcrypto;
  const identity = await generateIdentity(subtle);
  const cipher = createSessionCipher({
    subtle,
    keys: createKeySource(webcrypto),
    repo: createSessionRepo({
      subtle,
      random: (length) => webcrypto.getRandomValues(new Uint8Array(length)),
      getKek: async () => identity.sessionKek,
      kv: createMemoryKv('conversationId'),
      clock: Date.now,
    }),
    locks: createLocks(null),
    keyring: createLocalKeyring({ loadIdentity: async () => identity, opkKv: createMemoryKv('keyId'), clock: Date.now }),
    clock: Date.now,
  });
  const opk = claimOneTimePrekey(targetDevice);
  await cipher.bootstrap({
    conversationId: conversation.id,
    remoteDeviceId: targetDevice.id,
    remoteIdentityKey: decodeBase64Url(targetDevice.identityPublicKey),
    signedPrekeyBundle: targetDevice.signedPrekeyBundle,
    oneTimePrekey: opk ? { keyId: opk.keyId, publicKey: decodeBase64Url(opk.publicKey) } : null,
  });
  const envelope = await cipher.encrypt({
    conversationId: conversation.id,
    senderDeviceId: victimDevice.id,
    recipientUserId: targetUser.id,
    payload: { body: text, kind: 'text', expiresAt: null, attachment: null },
  });
  const published = await publishedKeys(subtle, identity);
  victimDevice.identityPublicKey = published.publicIdentityKey;
  victimDevice.signedPrekeyBundle = published.signedPrekeyBundle;
  victimDevice.oneTimePrekeys = [];
  victimDevice.uploadedPrekeyIds = new Set();
  storeMessage(victimDevice, conversation, { clientMessageId: `relay-${randomUUID()}`, envelope });
}

// What the old device compares: SHA-256 over the auth key and the identity
// key the new device will be trusted with, in groups of four hex digits.
const claimFingerprint = (authPublicKey, publicIdentityKey) =>
  createHash('sha256')
    .update(Buffer.from(authPublicKey, 'base64url'))
    .update(Buffer.from(publicIdentityKey, 'base64url'))
    .digest('hex')
    .replace(/(.{4})(?!$)/g, '$1 ');

// As DeviceTransferService.getSessionStatus. A session that ended without a
// transfer was 'invalidated' (claimed twice) or 'closed' (superseded or
// expired), and never shows a claim again.
function transferStatus(transfer) {
  if (transfer.ended === 'invalidated') return 'invalidated';
  if (transfer.ended === 'closed') return 'expired';
  if (transfer.completedAt) return 'completed';
  if (transfer.expiresAt <= Date.now()) return 'expired';
  if (transfer.claim?.approvedAt) return 'approved';
  return transfer.claim ? 'claimed' : 'pending';
}

// A session that can still take a step: not completed, ended or expired.
function activeTransfer(sessionId) {
  const transfer = db.transfers.get(sessionId);
  if (!transfer) throw new HttpError(404, 'transfer_session_not_found', 'Transfer session not found');
  if (transfer.completedAt || transfer.ended || transfer.expiresAt <= Date.now()) {
    throw new HttpError(403, 'transfer_session_inactive', 'Transfer session is no longer active');
  }
  return transfer;
}

// The steps the new device takes hold the session's token, and need the old
// device still trusted.
function checkTransferToken(transfer, transferToken) {
  if (transferToken !== transfer.token) throw new HttpError(401, 'transfer_token_invalid', 'Transfer token invalid');
  if (db.devices.get(transfer.oldDeviceId).revokedAt) {
    throw new HttpError(403, 'transfer_session_inactive', 'Old trusted device is unavailable; transfer cannot proceed');
  }
}

// The transfer session the old device runs; anyone else is told it does
// not exist.
function ownTransfer({ user, device }, sessionId) {
  const transfer = db.transfers.get(sessionId);
  if (transfer?.userId !== user.id || transfer.oldDeviceId !== device.id) {
    throw new HttpError(404, 'transfer_session_not_found', 'Transfer session not found');
  }
  return transfer;
}

const TRANSFER_TOKEN = matches(/^[A-Za-z0-9._-]{1,256}$/);

const completionOf = (transfer, claimId) => ({
  sessionId: transfer.id,
  claimId,
  newDeviceId: transfer.newDeviceId,
  revokedDeviceId: transfer.oldDeviceId,
  preferredDeviceId: transfer.newDeviceId,
  handle: db.users.get(transfer.userId).handle,
  completedAt: transfer.completedAt,
});

// As DeviceTransferService.replayCompletion: only for the device the
// transfer created, while it is active, and with its proof.
function replayCompletion(transfer, { sessionId, transferToken, claimId, authProof }) {
  const device = db.devices.get(transfer.newDeviceId);
  if (!device || device.revokedAt) throw new HttpError(403, 'transfer_session_inactive', 'Transfer session already completed');
  if (!signedBy(device.authPublicKey, `transfer-complete:${sessionId}:${claimId}:${transferToken}`, authProof)) {
    throw new HttpError(401, 'transfer_completion_invalid', 'New device completion proof is invalid');
  }
  return completionOf(transfer, claimId);
}

const routes = [
  ['POST', /^\/__test\/reset$/, () => {
    reset();
    realtime.setEnabled(false);
    return {};
  }],
  ['POST', /^\/__test\/delivery$/, (req) => {
    db.shuffle = req.body.shuffle === true;
    // Turning shuffling off delivers whatever is still held.
    if (!db.shuffle) for (const message of db.messages) message.released = true;
    return {};
  }],
  ['POST', /^\/__test\/tamper$/, (req) => {
    db.tamper = req.body.enabled === true;
    return {};
  }],
  ['POST', /^\/__test\/impersonate$/, async (req) => {
    await impersonate(req.body);
    return {};
  }],
  ['POST', /^\/__test\/timer$/, (req) => {
    db.timerSeconds = req.body.seconds ?? null;
    db.relayExpiry = req.body.relayExpiry !== false;
    return {};
  }],
  ['POST', /^\/__test\/realtime$/, (req) => {
    realtime.setEnabled(req.body.enabled === true);
    return {};
  }],
  ['POST', /^\/__test\/revoke$/, (req) => {
    revokeDevice(activeDevice(userByHandle(req.body.handle)));
    return {};
  }],
  ['POST', /^\/__test\/lose-completion$/, () => {
    db.loseCompletion = true;
    return {};
  }],
  ['GET', /^\/__test\/reports$/, () => db.reports],
  ['GET', /^\/__test\/health$/, () => ({ ok: true })],

  ['POST', /^\/v1\/auth\/register$/, (req) => {
    const { handle, publicIdentityKey, signedPrekeyBundle, authPublicKey } = req.body;
    if (userByHandle(handle)) throw new HttpError(409, 'handle_taken', 'Handle is already taken');
    const user = { id: randomUUID(), handle };
    const device = {
      id: randomUUID(),
      userId: user.id,
      identityPublicKey: publicIdentityKey,
      signedPrekeyBundle,
      authPublicKey,
      oneTimePrekeys: [],
    };
    user.activeDeviceId = device.id;
    db.users.set(user.id, user);
    db.devices.set(device.id, device);
    return { userId: user.id, deviceId: device.id, handle, status: 'active' };
  }],
  // As AuthService.createChallenge: the handle, then an active device of it.
  ['POST', /^\/v1\/auth\/challenge$/, (req) => {
    const user = userByHandle(req.body.handle);
    if (!user) throw new HttpError(404, 'handle_not_found');
    const device = db.devices.get(req.body.deviceId);
    if (device?.userId !== user.id || device.revokedAt) throw new HttpError(404, 'active_device_not_found');
    const challengeId = randomUUID();
    const challenge = `veil-auth:${token()}`;
    db.challenges.set(challengeId, { challenge, deviceId: device.id });
    return { challengeId, challenge };
  }],
  ['POST', /^\/v1\/auth\/verify$/, (req) => {
    const pending = db.challenges.get(req.body.challengeId);
    db.challenges.delete(req.body.challengeId);
    const device = pending && pending.deviceId === req.body.deviceId ? db.devices.get(pending.deviceId) : null;
    if (!device) throw new HttpError(401, 'invalid_challenge');
    if (device.revokedAt) throw new HttpError(401, 'device_not_active');
    if (!signedBy(device.authPublicKey, pending.challenge, req.body.signature)) {
      throw new HttpError(401, 'invalid_device_signature');
    }
    return issueTokens(device);
  }],
  ['POST', /^\/v1\/auth\/refresh$/, (req) => {
    const device = db.devices.get(db.refreshTokens.get(req.body.refreshToken));
    db.refreshTokens.delete(req.body.refreshToken);
    if (!device || device.revokedAt) throw new HttpError(401, 'invalid_refresh_token');
    return issueTokens(device);
  }],

  ['GET', /^\/v1\/keys\/([^/?]+)$/, (req, [handle]) => {
    authenticate(req);
    return directory(decodeURIComponent(handle));
  }],
  ['PUT', /^\/v1\/keys\/signed-prekey$/, (req) => rotateSignedPrekey(authenticate(req).device, req.body.signedPrekeyBundle)],
  // As PrekeysService.upload: ids the device already uploaded are skipped.
  ['POST', /^\/v1\/prekeys$/, (req) => {
    const { device } = authenticate(req);
    validateBody(req.body, { prekeys: prekeyBatch });
    const uploaded = device.uploadedPrekeyIds ?? new Set();
    device.uploadedPrekeyIds = uploaded;
    const fresh = req.body.prekeys.filter((prekey) => !uploaded.has(prekey.keyId));
    for (const prekey of fresh) uploaded.add(prekey.keyId);
    device.oneTimePrekeys.push(...fresh);
    return { uploaded: fresh.length, available: device.oneTimePrekeys.length };
  }],
  ['GET', /^\/v1\/prekeys\/count$/, (req) => ({ available: authenticate(req).device.oneTimePrekeys.length })],

  ['GET', /^\/v1\/conversations$/, (req) => {
    const { user } = authenticate(req);
    const items = [...db.conversations.values()]
      .filter((c) => c.memberIds.includes(user.id))
      .map((c) => conversationSummary(user, c));
    return { items, nextCursor: null };
  }],
  ['POST', /^\/v1\/conversations\/direct$/, (req) => {
    const { user } = authenticate(req);
    const peer = userByHandle(req.body.peerHandle);
    if (!peer || peer.id === user.id) throw new HttpError(404, 'handle_not_found', 'User not found');
    let conversation = [...db.conversations.values()].find(
      (c) => c.memberIds.includes(user.id) && c.memberIds.includes(peer.id),
    );
    if (!conversation) {
      conversation = { id: randomUUID(), memberIds: [user.id, peer.id], createdAt: now(), lastOrder: 0 };
      db.conversations.set(conversation.id, conversation);
      emitToMembers(conversation, 'conversation.sync', { conversationId: conversation.id, reason: 'membership' });
    }
    return { conversation: conversationSummary(user, conversation) };
  }],
  // As ConversationsService.listMessages pages: the newest `limit` (1 to
  // 100, default 50) messages before the cursor message, in conversation
  // order, and while the page is full a cursor to the page before it.
  ['GET', /^\/v1\/conversations\/([^/]+)\/messages$/, (req, [conversationId]) => {
    const { user } = authenticate(req);
    conversationFor(user, conversationId);
    if (db.shuffle) releaseOneHeld(user, conversationId);
    const requested = Number(req.query.get('limit') ?? 50);
    const limit = Number.isFinite(requested) ? Math.min(100, Math.max(1, requested)) : 50;
    const cursor = req.query.get('cursor');
    const before = cursor ? db.messages.find((m) => m.id === cursor && m.conversationId === conversationId) : null;
    if (cursor && !before) throw new HttpError(404, 'message_not_found');
    const page = db.messages
      .filter((m) => m.conversationId === conversationId && visibleTo(user, m))
      .filter((m) => !before || m.conversationOrder < before.conversationOrder)
      .slice(-limit);
    return { items: page.map(summaryFor), nextCursor: page.length === limit ? page[0].id : null };
  }],

  ['POST', /^\/v1\/messages$/, (req) => {
    const { device, user } = authenticate(req);
    validateBody(req.body, {
      conversationId: uuid(),
      clientMessageId: matches(/^[a-zA-Z0-9._:-]{8,80}$/),
      envelope: envelopeRule,
      replyToMessageId: optional(uuid()),
      groupEpoch: optional(intWithin(0, Number.MAX_SAFE_INTEGER)),
    });
    const conversation = conversationFor(user, req.body.conversationId);
    const { envelope } = req.body;
    if (envelope.senderDeviceId !== device.id || envelope.conversationId !== conversation.id) {
      throw new HttpError(400, 'envelope_mismatch');
    }
    const message = storeMessage(device, conversation, req.body);
    if (message.released) emitToMembers(conversation, 'message.new', summaryFor(message), { except: user.id });
    emitToMembers(conversation, 'conversation.sync', { conversationId: conversation.id, reason: 'message' });
    return { message: summaryFor(message) };
  }],
  // As MessagesService.markRead in a direct conversation: the first read of
  // a peer's message records a receipt, and only the sender and the reader
  // hear about it.
  ['POST', /^\/v1\/messages\/([^/]+)\/read$/, (req, [messageId]) => {
    const { user } = authenticate(req);
    const message = db.messages.find((m) => m.id === messageId && isMember(user.id, m.conversationId) && visibleTo(user, m));
    if (!message) throw new HttpError(404, 'message_not_found');
    const readAt = now();
    const receipt = `${messageId}:${user.id}`;
    if (message.senderUserId !== user.id && !db.receipts.has(receipt)) {
      db.receipts.add(receipt);
      for (const userId of [message.senderUserId, user.id]) {
        realtime.emitToUser(userId, 'message.delivered', { messageId, userId: user.id, deliveredAt: readAt });
        realtime.emitToUser(userId, 'message.read', { messageId, userId: user.id, readAt });
      }
    }
    return { messageId, readAt };
  }],
  ['PATCH', /^\/v1\/messages\/([^/]+)$/, (req, [messageId]) => {
    const { device } = authenticate(req);
    validateBody(req.body, { ciphertext, nonce: matches(NONCE), version: stringUpTo(64) });
    const message = db.messages.find((m) => m.id === messageId && m.senderDeviceId === device.id);
    if (!message) throw new HttpError(404, 'message_not_found');
    Object.assign(message, {
      ciphertext: req.body.ciphertext,
      nonce: req.body.nonce,
      editedAt: now(),
      editCount: message.editCount + 1,
    });
    emitToMembers(db.conversations.get(message.conversationId), 'message.edited', summaryFor(message));
    return { message: summaryFor(message) };
  }],
  ['DELETE', /^\/v1\/messages\/([^/]+)$/, (req, [messageId]) => {
    const { device } = authenticate(req);
    const message = db.messages.find((m) => m.id === messageId && m.senderDeviceId === device.id);
    if (!message) throw new HttpError(404, 'message_not_found');
    message.deletedAt ??= now();
    emitToMembers(db.conversations.get(message.conversationId), 'message.deleted', { messageId, deletedAt: message.deletedAt });
    return { messageId, deletedAt: message.deletedAt };
  }],

  // CreateUploadTicketDto: a proposed id must be a random (version 4) UUID.
  ['POST', /^\/v1\/attachments\/upload-ticket$/, (req) => {
    authenticate(req);
    validateBody(req.body, {
      attachmentId: optional(uuid(UUID_V4)),
      contentType: matches(/^[\w.+-]+\/[\w.+-]+$/),
      sizeBytes: intWithin(1, 50 * 1024 * 1024),
      sha256: matches(/^[a-f0-9]{64}$/i),
    });
    const attachmentId = req.body.attachmentId ?? randomUUID();
    return {
      attachmentId,
      upload: {
        uploadUrl: `/blob/${attachmentId}`,
        headers: { 'Content-Type': 'application/octet-stream' },
        storageKey: attachmentId,
      },
      constraints: { maxSizeBytes: 25 * 1024 * 1024, allowedMimeTypes: ['application/octet-stream'] },
    };
  }],
  ['POST', /^\/v1\/attachments\/complete$/, (req) => {
    authenticate(req);
    validateBody(req.body, { attachmentId: uuid(), uploadStatus: oneOf(UPLOAD_STATUSES) });
    return {};
  }],
  ['GET', /^\/v1\/attachments\/([^/]+)\/download-ticket$/, (req, [attachmentId]) => {
    authenticate(req);
    return { ticket: { downloadUrl: `/blob/${attachmentId}` } };
  }],
  ['GET', /^\/v1\/safety\/blocks$/, (req) => {
    authenticate(req);
    return { items: [] };
  }],
  // FileAbuseReportDto. The API accepts a deprecated note and never stores
  // it; this relay keeps what it was sent, so a test can see that no note
  // leaves the demo.
  ['POST', /^\/v1\/safety\/reports$/, (req) => {
    const { user } = authenticate(req);
    validateBody(req.body, {
      reportedUserId: uuid(),
      conversationId: optional(uuid()),
      messageId: optional(uuid()),
      reason: oneOf(REPORT_REASONS),
      note: optional(stringUpTo(1000)),
    });
    const report = { reportId: randomUUID(), filedAt: now() };
    const reportedHandle = db.users.get(req.body.reportedUserId)?.handle ?? null;
    db.reports.push({ ...report, reporterHandle: user.handle, reportedHandle, body: req.body });
    return report;
  }],

  // DeviceTransferController. The old device opens a session, which closes
  // any earlier one, and watches it; the new device claims it with a signed
  // proof and completes once the old device approved, which revokes the old
  // device.
  ['POST', /^\/v1\/device-transfer\/init$/, (req) => {
    const { device, user } = authenticate(req);
    validateBody(req.body, { oldDeviceId: uuid() });
    if (req.body.oldDeviceId !== device.id) {
      throw new HttpError(403, 'device_forbidden', 'Transfer must be initiated from the trusted old device');
    }
    for (const earlier of db.transfers.values()) {
      if (earlier.oldDeviceId === device.id && !earlier.completedAt) {
        Object.assign(earlier, { ended: 'closed', completedAt: now(), claim: null });
      }
    }
    const transfer = {
      id: randomUUID(),
      userId: user.id,
      oldDeviceId: device.id,
      token: randomUUID(),
      expiresAt: Date.now() + TRANSFER_TTL_MS,
      completedAt: null,
      ended: null,
      claim: null,
      newDeviceId: null,
    };
    db.transfers.set(transfer.id, transfer);
    return { sessionId: transfer.id, transferToken: transfer.token, expiresAt: new Date(transfer.expiresAt).toISOString() };
  }],
  ['GET', /^\/v1\/device-transfer\/sessions\/([^/]+)$/, (req, [sessionId]) => {
    const transfer = ownTransfer(authenticate(req), sessionId);
    const status = transferStatus(transfer);
    const claim = transfer.ended ? null : transfer.claim;
    return {
      sessionId,
      status,
      expiresAt: new Date(transfer.expiresAt).toISOString(),
      completedAt: status === 'completed' ? transfer.completedAt : null,
      pendingClaim: claim && {
        claimId: claim.claimId,
        claimantFingerprint: claim.claimantFingerprint,
        newDeviceName: claim.newDeviceName,
        platform: claim.platform,
        approvedAt: claim.approvedAt ?? null,
      },
    };
  }],
  ['POST', /^\/v1\/device-transfer\/claim$/, (req) => {
    validateBody(req.body, {
      sessionId: uuid(),
      transferToken: TRANSFER_TOKEN,
      newDeviceName: stringUpTo(80),
      platform: oneOf(DEVICE_PLATFORMS),
      publicIdentityKey: stringUpTo(1024),
      signedPrekeyBundle: stringUpTo(8192),
      authPublicKey: stringUpTo(512),
      authProof: stringUpTo(1024),
    });
    const { sessionId, transferToken, newDeviceName, platform, publicIdentityKey, signedPrekeyBundle, authPublicKey } = req.body;
    const transfer = activeTransfer(sessionId);
    checkTransferToken(transfer, transferToken);
    if (!signedBy(authPublicKey, `transfer-claim:${sessionId}:${transferToken}`, req.body.authProof)) {
      throw new HttpError(401, 'transfer_claim_invalid', 'New device claim proof is invalid');
    }
    // First claim wins; a second valid one means the code leaked.
    if (transfer.claim) {
      Object.assign(transfer, { ended: 'invalidated', completedAt: now(), claim: null });
      throw new HttpError(409, 'transfer_claim_invalid', 'Transfer session was claimed twice and has been invalidated; start a new transfer');
    }
    transfer.claim = {
      claimId: randomUUID(),
      newDeviceName,
      platform,
      publicIdentityKey,
      signedPrekeyBundle,
      authPublicKey,
      claimantFingerprint: claimFingerprint(authPublicKey, publicIdentityKey),
    };
    return {
      sessionId,
      claimId: transfer.claim.claimId,
      claimantFingerprint: transfer.claim.claimantFingerprint,
      expiresAt: new Date(transfer.expiresAt).toISOString(),
    };
  }],
  // The approval is signed by the old device's auth key over the claim and
  // its fingerprint (buildApprovalChallenge); every relay requires it.
  ['POST', /^\/v1\/device-transfer\/approve$/, (req) => {
    const session = authenticate(req);
    validateBody(req.body, { sessionId: uuid(), claimId: uuid(), approvalProof: optional(stringUpTo(1024)) });
    const transfer = activeTransfer(ownTransfer(session, req.body.sessionId).id);
    if (transfer.claim?.claimId !== req.body.claimId) {
      throw new HttpError(403, 'transfer_claim_required', 'A matching new-device claim is required before approval');
    }
    if (!req.body.approvalProof) throw new HttpError(401, 'invalid_device_signature', 'The old device must sign the approval');
    const challenge = `transfer-approve:${transfer.id}:${transfer.claim.claimId}:${transfer.claim.claimantFingerprint}`;
    if (!signedBy(session.device.authPublicKey, challenge, req.body.approvalProof)) {
      throw new HttpError(401, 'invalid_device_signature', 'Approval signature is invalid');
    }
    transfer.claim.approvedAt = now();
    return { sessionId: transfer.id, claimId: transfer.claim.claimId, approved: true };
  }],
  ['POST', /^\/v1\/device-transfer\/complete$/, (req) => {
    validateBody(req.body, { sessionId: uuid(), transferToken: TRANSFER_TOKEN, claimId: uuid(), authProof: stringUpTo(1024) });
    const { sessionId, transferToken, claimId, authProof } = req.body;
    const done = db.transfers.get(sessionId);
    // A retry of a completion that already went through is answered as the
    // first one was, and changes nothing.
    if (done?.newDeviceId && transferToken === done.token) return replayCompletion(done, req.body);
    const transfer = activeTransfer(sessionId);
    checkTransferToken(transfer, transferToken);
    const { claim } = transfer;
    if (claim?.claimId !== claimId) {
      throw new HttpError(403, 'transfer_claim_required', 'A matching approved claim is required before completion');
    }
    if (!claim.approvedAt) throw new HttpError(403, 'transfer_approval_required', 'Old device approval is required before completion');
    if (!signedBy(claim.authPublicKey, `transfer-complete:${sessionId}:${claimId}:${transferToken}`, authProof)) {
      throw new HttpError(401, 'transfer_completion_invalid', 'New device completion proof is invalid');
    }
    const user = db.users.get(transfer.userId);
    const device = {
      id: randomUUID(),
      userId: user.id,
      identityPublicKey: claim.publicIdentityKey,
      signedPrekeyBundle: claim.signedPrekeyBundle,
      authPublicKey: claim.authPublicKey,
      oneTimePrekeys: [],
    };
    db.devices.set(device.id, device);
    revokeDevice(db.devices.get(transfer.oldDeviceId));
    user.activeDeviceId = device.id;
    Object.assign(transfer, { completedAt: now(), claim: null, newDeviceId: device.id });
    if (db.loseCompletion) {
      db.loseCompletion = false;
      throw new HttpError(503, 'service_unavailable', 'Service unavailable');
    }
    return completionOf(transfer, claimId);
  }],

  // SecretController: public, opaque ciphertext, read once.
  ['POST', /^\/v1\/s$/, (req) => {
    validateBody(req.body, {
      ciphertext: rule(
        (value) => typeof value === 'string' && value.length > 0 && value.length <= SECRET_MAX_CIPHERTEXT,
        `must be a non-empty string of at most ${SECRET_MAX_CIPHERTEXT} characters`,
      ),
      ttlSeconds: optional(intWithin(SECRET_TTL_SECONDS.min, SECRET_TTL_SECONDS.max)),
    });
    const id = randomUUID();
    const expiresAt = new Date(Date.now() + (req.body.ttlSeconds ?? SECRET_TTL_SECONDS.fallback) * 1000).toISOString();
    db.secrets.set(id, { ciphertext: req.body.ciphertext, expiresAt });
    return { id, expiresAt };
  }],
  ['GET', /^\/v1\/s\/([^/]+)$/, (req, [id]) => {
    if (!UUID.test(id)) throw new HttpError(400, 'validation_failed', 'Validation failed (uuid is expected)');
    const secret = db.secrets.get(id);
    db.secrets.delete(id);
    if (!secret || Date.parse(secret.expiresAt) <= Date.now()) {
      throw new HttpError(404, 'resource_not_found', 'This link has already been opened or has expired.');
    }
    return { ciphertext: secret.ciphertext };
  }],
];

async function serveStatic(pathname, res) {
  const relative = normalize(decodeURIComponent(pathname.replace(/^\/demo\/?/, '')) || 'index.html');
  const allowed = SERVED.includes(relative) || SERVED_DIRS.some((dir) => relative.startsWith(dir + sep));
  if (!allowed || relative.includes('..')) return false;
  try {
    const body = await readFile(join(DEMO_ROOT, relative));
    res.writeHead(200, { 'Content-Type': CONTENT_TYPES[extname(relative)] ?? 'application/octet-stream' });
    res.end(body);
    return true;
  } catch {
    return false;
  }
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks);
}

function sendJson(res, status, body) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`);
  const { pathname } = url;
  try {
    if (pathname === '/') {
      res.writeHead(302, { Location: '/demo/' });
      res.end();
      return;
    }
    if (pathname.startsWith('/demo/') && req.method === 'GET') {
      if (await serveStatic(pathname, res)) return;
      throw new HttpError(404, 'not_found');
    }
    const blob = /^\/blob\/([^/]+)$/.exec(pathname);
    if (blob && req.method === 'PUT') {
      db.blobs.set(blob[1], await readBody(req));
      res.writeHead(200);
      res.end();
      return;
    }
    if (blob && req.method === 'GET') {
      if (!db.blobs.has(blob[1])) throw new HttpError(404, 'not_found');
      res.writeHead(200, { 'Content-Type': 'application/octet-stream' });
      res.end(db.blobs.get(blob[1]));
      return;
    }
    for (const [method, pattern, handler] of routes) {
      const match = req.method === method ? pattern.exec(pathname) : null;
      if (!match) continue;
      const raw = await readBody(req);
      req.body = raw.length > 0 ? JSON.parse(raw.toString('utf8')) : {};
      req.query = url.searchParams;
      sendJson(res, 200, await handler(req, match.slice(1)));
      return;
    }
    // /socket.io, /v1/realtime and everything else: no realtime gateway here.
    throw new HttpError(404, 'not_found');
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    sendJson(res, status, { code: error.code ?? 'internal_error', message: error.message });
  }
});

server.on('upgrade', (req, socket) => realtime.handleUpgrade(req, socket));

server.listen(PORT, '127.0.0.1', () => {
  console.log(`veil mock relay on http://127.0.0.1:${PORT}/demo/`);
});
