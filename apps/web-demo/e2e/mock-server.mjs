// A stand-in for the VEIL API that the browser tests (e2e/browser/) run the
// web demo against, with no Postgres, Redis or object storage: it serves the
// demo at /demo/ and an in-memory /v1 relay (auth, key directory, prekeys,
// conversations, messages, attachments). It relays ciphertext and never
// decrypts. /socket.io and /v1/realtime answer 404, so the demo falls back
// to polling.
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
//
// Usage: node apps/web-demo/e2e/mock-server.mjs   (VEIL_MOCK_PORT, default 4317)

import { createPublicKey, randomBytes, randomUUID, verify, webcrypto } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import http from 'node:http';
import { extname, join, normalize, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { decodeBase64Url } from '../src/core/base64url.js';
import { generateIdentity, publishedKeys } from '../src/crypto/identity.js';
import { createKeySource } from '../src/crypto/keys.js';
import { createLocks } from '../src/crypto/locks.js';
import { createLocalKeyring } from '../src/crypto/prekeys.js';
import { createSessionCipher } from '../src/crypto/session-cipher.js';
import { createSessionRepo } from '../src/crypto/session-repo.js';
import { createMemoryKv } from '../src/platform/kv.js';

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

class HttpError extends Error {
  constructor(status, code, message = code) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

let db;
function reset() {
  db = {
    users: new Map(), // id -> { id, handle, activeDeviceId }
    devices: new Map(), // id -> { id, userId, identityPublicKey, signedPrekeyBundle, authPublicKey, oneTimePrekeys: [] }
    tokens: new Map(), // access token -> deviceId
    refreshTokens: new Map(),
    challenges: new Map(),
    conversations: new Map(), // id -> { id, memberIds, createdAt, lastOrder }
    messages: [],
    blobs: new Map(),
    shuffle: false,
    tamper: false,
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

function authenticate(req) {
  const match = /^Bearer (.+)$/.exec(req.headers.authorization ?? '');
  const device = match ? db.devices.get(db.tokens.get(match[1])) : null;
  if (!device) throw new HttpError(401, 'unauthorized');
  return { device, user: db.users.get(device.userId) };
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
    expiresAt: null,
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
  storeMessage(victimDevice, conversation, { clientMessageId: `relay-${randomUUID()}`, envelope });
}

const routes = [
  ['POST', /^\/__test\/reset$/, () => {
    reset();
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
  ['POST', /^\/v1\/auth\/challenge$/, (req) => {
    const device = db.devices.get(req.body.deviceId);
    if (!device || db.users.get(device.userId)?.handle !== req.body.handle) throw new HttpError(404, 'handle_not_found');
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
    const key = createPublicKey({
      key: Buffer.concat([ED25519_SPKI_PREFIX, Buffer.from(device.authPublicKey, 'base64url')]),
      format: 'der',
      type: 'spki',
    });
    if (!verify(null, Buffer.from(pending.challenge), key, Buffer.from(req.body.signature, 'base64url'))) {
      throw new HttpError(401, 'invalid_device_signature');
    }
    return issueTokens(device);
  }],
  ['POST', /^\/v1\/auth\/refresh$/, (req) => {
    const device = db.devices.get(db.refreshTokens.get(req.body.refreshToken));
    db.refreshTokens.delete(req.body.refreshToken);
    if (!device) throw new HttpError(401, 'invalid_refresh_token');
    return issueTokens(device);
  }],

  ['GET', /^\/v1\/keys\/([^/?]+)$/, (req, [handle]) => {
    authenticate(req);
    return directory(decodeURIComponent(handle));
  }],
  ['PUT', /^\/v1\/keys\/signed-prekey$/, (req) => {
    const { device } = authenticate(req);
    device.signedPrekeyBundle = req.body.signedPrekeyBundle;
    return { deviceId: device.id, spkId: 0 };
  }],
  ['POST', /^\/v1\/prekeys$/, (req) => {
    const { device } = authenticate(req);
    device.oneTimePrekeys.push(...req.body.prekeys);
    return { uploaded: req.body.prekeys.length, remaining: device.oneTimePrekeys.length };
  }],
  ['GET', /^\/v1\/prekeys\/count$/, (req) => ({ available: authenticate(req).device.oneTimePrekeys.length })],

  ['GET', /^\/v1\/conversations$/, (req) => {
    const { user } = authenticate(req);
    return [...db.conversations.values()]
      .filter((c) => c.memberIds.includes(user.id))
      .map((c) => conversationSummary(user, c));
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
    }
    return { conversation: conversationSummary(user, conversation) };
  }],
  ['GET', /^\/v1\/conversations\/([^/]+)\/messages$/, (req, [conversationId]) => {
    const { user } = authenticate(req);
    conversationFor(user, conversationId);
    if (db.shuffle) releaseOneHeld(user, conversationId);
    const items = db.messages
      .filter((m) => m.conversationId === conversationId && visibleTo(user, m))
      .slice(-50)
      .map(summaryFor);
    return { items };
  }],

  ['POST', /^\/v1\/messages$/, (req) => {
    const { device, user } = authenticate(req);
    const conversation = conversationFor(user, req.body.conversationId);
    const { envelope } = req.body;
    if (envelope.senderDeviceId !== device.id || envelope.conversationId !== conversation.id) {
      throw new HttpError(400, 'envelope_mismatch');
    }
    return { message: summaryFor(storeMessage(device, conversation, req.body)) };
  }],
  ['POST', /^\/v1\/messages\/([^/]+)\/read$/, (req) => {
    authenticate(req);
    return {};
  }],
  ['PATCH', /^\/v1\/messages\/([^/]+)$/, (req, [messageId]) => {
    const { device } = authenticate(req);
    const message = db.messages.find((m) => m.id === messageId && m.senderDeviceId === device.id);
    if (!message) throw new HttpError(404, 'message_not_found');
    Object.assign(message, {
      ciphertext: req.body.ciphertext,
      nonce: req.body.nonce,
      editedAt: now(),
      editCount: message.editCount + 1,
    });
    return { message: summaryFor(message) };
  }],
  ['DELETE', /^\/v1\/messages\/([^/]+)$/, (req, [messageId]) => {
    const { device } = authenticate(req);
    const message = db.messages.find((m) => m.id === messageId && m.senderDeviceId === device.id);
    if (!message) throw new HttpError(404, 'message_not_found');
    message.deletedAt = now();
    return {};
  }],

  ['POST', /^\/v1\/attachments\/upload-ticket$/, (req) => {
    authenticate(req);
    const { attachmentId } = req.body;
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

server.listen(PORT, '127.0.0.1', () => {
  console.log(`veil mock relay on http://127.0.0.1:${PORT}/demo/`);
});
