// VEIL web demo client.
// Vanilla-JS chat shell that talks to the NestJS API at /v1 and the realtime
// gateway at /v1/realtime. Messages are end-to-end encrypted with X25519 ECDH
// + HKDF-SHA256 + AES-256-GCM (see deriveSharedAesKey / encryptWithKey). The
// server only ever sees ciphertext.
//
// State is held in the `state` object below and persisted in IndexedDB
// (`veil-demo`): session, conversations, messages (ciphertext only), drafts,
// outbound queue. Re-derive plaintext on hydrate via the same shared key.

const API = '/v1';
const STORE = 'veil-demo-session';
const POLL_MS = 4000;
// Cap a single message body. UTF-8 worst case is ~3 bytes/char so 8000 chars
// keeps us comfortably under the API's 64 KB envelope ceiling and prevents a
// 10 MB paste from locking the encrypt/render path.
const MESSAGE_MAX_CHARS = 8000;
const DRAFT_DEBOUNCE_MS = 300;

// ---------- utils ----------
const $ = (id) => document.getElementById(id);
const el = (tag, attrs = {}, children = []) => {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') node.className = v;
    else if (k === 'dataset') Object.assign(node.dataset, v);
    else if (k.startsWith('on') && typeof v === 'function') node.addEventListener(k.slice(2), v);
    else if (v != null) node.setAttribute(k, v);
  }
  for (const c of [].concat(children)) {
    if (c == null) continue;
    node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
  }
  return node;
};

const b64uEncode = (buf) => {
  const bytes = new Uint8Array(buf);
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};
const b64uDecode = (str) => {
  const pad = str.length % 4 === 0 ? '' : '='.repeat(4 - (str.length % 4));
  const b64 = (str + pad).replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out.buffer;
};

// Deterministic gradient/initial for an avatar from a handle.
const PALETTE = [
  ['#6c8eff', '#b06cff'],
  ['#ff6c8e', '#ffb46c'],
  ['#4ade80', '#22d3ee'],
  ['#fbbf24', '#fb7185'],
  ['#a855f7', '#ec4899'],
  ['#06b6d4', '#3b82f6'],
  ['#f97316', '#eab308'],
  ['#10b981', '#14b8a6'],
];
const handleHash = (h) => {
  let n = 0;
  for (let i = 0; i < h.length; i++) n = (n * 31 + h.charCodeAt(i)) >>> 0;
  return n;
};
const avatarFor = (handle, size = 'md') => {
  const initial = (handle?.[0] ?? '?').toUpperCase();
  const [a, b] = PALETTE[handleHash(handle ?? '?') % PALETTE.length];
  return el(
    'div',
    {
      class: `avatar size-${size}`,
      style: `background: linear-gradient(135deg, ${a} 0%, ${b} 100%)`,
      title: handle ?? '',
    },
    [initial],
  );
};

// ---------- toast ----------
const toast = (msg, kind = '') => {
  const node = el('div', { class: `toast ${kind ? `toast-${kind}` : ''}` }, [msg]);
  $('toast-root').appendChild(node);
  setTimeout(() => {
    node.style.transition = 'opacity 0.2s ease';
    node.style.opacity = '0';
    setTimeout(() => node.remove(), 220);
  }, kind === 'error' ? 5000 : 2500);
};

// ---------- crypto ----------
// Each device gets two static keypairs:
//   * Ed25519 — signs auth challenges (so the server can prove device identity).
//   * X25519  — derives a shared AES-GCM key per peer via ECDH + HKDF, used to
//               encrypt every envelope sent through the relay.
// This is not a Double Ratchet — there is no forward secrecy or post-compromise
// security — but it is real end-to-end encryption: the API sees ciphertext
// only. The Flutter mobile app uses the audited LibCryptoAdapter for the real
// thing; the web demo trades ratchet complexity for browser-native primitives.
// Wire format (v2):
//   ciphertext = "v2." + base64url(AES-GCM ciphertext)
//   nonce      = base64url(12-byte random IV)  (also doubles as the HKDF salt)
//   AES key    = HKDF-SHA256(
//                  ikm  = ECDH(myXPriv, peerXPub),
//                  salt = nonce,
//                  info = "veil-demo-v2|aesgcm|" + sorted(myXPub,peerXPub) + "|" + conversationId,
//                )
//
// Per-message key derivation eliminates the nonce-reuse-under-fixed-key risk;
// even if two messages collide on the random IV, the derived key differs.
// `info` binds the derived key to the (peer-pair, conversation) tuple so the
// same ECDH secret can't silently cover a different context.
//
// Browser CryptoKey objects are structured-cloneable, so we can store them
// directly in IndexedDB without ever exporting JWK to disk. Web Crypto applies
// `extractable` to both halves of an asymmetric pair, so we keep them
// extractable=true (otherwise we cannot raw-export the public key once) and
// instead never call exportKey on the private half ourselves.

async function generateIdentityKeys() {
  const ed = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
  const x = await crypto.subtle.generateKey({ name: 'X25519' }, true, ['deriveBits']);
  return {
    edPrivKey: ed.privateKey,
    edPubB64u: b64uEncode(await crypto.subtle.exportKey('raw', ed.publicKey)),
    xPrivKey: x.privateKey,
    xPubB64u: b64uEncode(await crypto.subtle.exportKey('raw', x.publicKey)),
  };
}
async function importEdPrivFromJwk(jwk) {
  return await crypto.subtle.importKey('jwk', jwk, { name: 'Ed25519' }, true, ['sign']);
}
async function importXPrivFromJwk(jwk) {
  return await crypto.subtle.importKey('jwk', jwk, { name: 'X25519' }, true, ['deriveBits']);
}
async function importXPubFromB64u(b64u) {
  return await crypto.subtle.importKey('raw', b64uDecode(b64u), { name: 'X25519' }, false, []);
}
async function signChallenge(edPrivateKey, challenge) {
  const sig = await crypto.subtle.sign({ name: 'Ed25519' }, edPrivateKey, new TextEncoder().encode(challenge));
  return b64uEncode(sig);
}

async function encryptForConv(convId, plaintext) {
  const ctx = await getConvCryptoCtx(convId);
  if (!ctx) return null;
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const aesKey = await deriveAesKey(ctx.hkdfBase, nonce, ctx.info);
  const ct = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce },
    aesKey,
    new TextEncoder().encode(plaintext),
  );
  return { ciphertext: 'v2.' + b64uEncode(ct), nonce: b64uEncode(nonce) };
}

async function decryptFromConv(convId, ciphertext, nonceB64u) {
  if (!ciphertext?.startsWith('v2.')) return null;
  const ctx = await getConvCryptoCtx(convId);
  if (!ctx) return null;
  const nonceBuf = new Uint8Array(b64uDecode(nonceB64u));
  const ct = b64uDecode(ciphertext.slice(3));
  try {
    const aesKey = await deriveAesKey(ctx.hkdfBase, nonceBuf, ctx.info);
    const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonceBuf }, aesKey, ct);
    return new TextDecoder().decode(pt);
  } catch {
    return null;
  }
}

async function deriveAesKey(hkdfBase, salt, info) {
  return await crypto.subtle.deriveKey(
    { name: 'HKDF', hash: 'SHA-256', salt, info },
    hkdfBase,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
}

// Wrap reply metadata into the encrypted payload so the server never sees
// which message is being answered. The wire format inside the ciphertext is
// either a plain UTF-8 string (legacy) or a JSON object {v:1, text, replyTo}.
function packPayload(text, replyToId) {
  if (!replyToId) return text;
  return JSON.stringify({ v: 1, text, replyTo: replyToId });
}
function unpackPayload(decoded) {
  if (typeof decoded !== 'string') return { text: '', replyTo: null };
  if (decoded.startsWith('{"v":1,')) {
    try {
      const o = JSON.parse(decoded);
      if (o?.v === 1) return { text: o.text ?? '', replyTo: o.replyTo ?? null };
    } catch {}
  }
  return { text: decoded, replyTo: null };
}

// Per-conversation HKDF context (ECDH base key + domain-separation info).
const convCryptoCtx = new Map(); // convId -> { hkdfBase: CryptoKey, info: Uint8Array }
const peerXPubByUserId = new Map(); // userId -> CryptoKey (X25519 pub)
const peerXPubB64uByUserId = new Map(); // userId -> base64url raw pub (mixed into HKDF info)

async function getPeerXPub(userId, handle) {
  if (peerXPubByUserId.has(userId)) return peerXPubByUserId.get(userId);
  const r = await api(`/users/${handle}/key-bundle`);
  const pubB64u = r.bundle.identityPublicKey;
  const pub = await importXPubFromB64u(pubB64u);
  peerXPubByUserId.set(userId, pub);
  peerXPubB64uByUserId.set(userId, pubB64u);
  return pub;
}

async function getConvCryptoCtx(convId) {
  if (convCryptoCtx.has(convId)) return convCryptoCtx.get(convId);
  const conv = state.conversations.find((c) => c.id === convId);
  if (!conv || !state.me?.xPrivKey) return null;
  const peer = (conv.members || []).find((m) => m.userId !== state.me.userId);
  if (!peer) return null;
  try {
    const peerXPub = await getPeerXPub(peer.userId, peer.handle);
    const ecdhBits = await crypto.subtle.deriveBits(
      { name: 'X25519', public: peerXPub },
      state.me.xPrivKey,
      256,
    );
    const hkdfBase = await crypto.subtle.importKey('raw', ecdhBits, 'HKDF', false, ['deriveKey']);
    const peerPubB64u = peerXPubB64uByUserId.get(peer.userId) ?? '';
    const sortedPubs = [state.me.xPubB64u, peerPubB64u].sort().join('|');
    const info = new TextEncoder().encode(`veil-demo-v2|aesgcm|${sortedPubs}|${convId}`);
    const ctx = { hkdfBase, info };
    convCryptoCtx.set(convId, ctx);
    return ctx;
  } catch (e) {
    console.warn('shared secret derive failed', e);
    return null;
  }
}

// Drop the cached HKDF base for a conversation. Called when decrypts start
// failing in a row (e.g., the peer rotated their X25519 key on re-register).
function invalidateConvCrypto(convId) {
  convCryptoCtx.delete(convId);
}
function invalidatePeerXPub(userId) {
  peerXPubByUserId.delete(userId);
  peerXPubB64uByUserId.delete(userId);
}

// Track consecutive decrypt failures per conversation so we know when to
// invalidate the cached HKDF base — e.g., the peer rotated their X25519 key.
const decryptFailureCount = new Map(); // convId -> int
const PEER_ROTATION_FAILURE_THRESHOLD = 3;

async function decryptMessage(msg) {
  if (msg._plaintext != null) return; // already done
  const ct = msg.ciphertext || '';
  if (!ct.startsWith('v2.')) {
    msg._plaintext = '🔒 이전 형식';
    msg._replyTo = null;
    return;
  }
  if (!await getConvCryptoCtx(msg.conversationId)) {
    msg._plaintext = '🔒 키 미해결';
    msg._replyTo = null;
    return;
  }
  const pt = await decryptFromConv(msg.conversationId, ct, msg.nonce);
  if (pt == null) {
    msg._plaintext = '🔒 복호화 실패';
    msg._replyTo = null;
    const failures = (decryptFailureCount.get(msg.conversationId) ?? 0) + 1;
    decryptFailureCount.set(msg.conversationId, failures);
    if (failures >= PEER_ROTATION_FAILURE_THRESHOLD) {
      // Peer probably rotated keys; flush caches so the next render re-fetches.
      invalidateConvCrypto(msg.conversationId);
      const conv = state.conversations.find((c) => c.id === msg.conversationId);
      const peer = conv?.members?.find((m) => m.userId !== state.me?.userId);
      if (peer) invalidatePeerXPub(peer.userId);
      decryptFailureCount.delete(msg.conversationId);
    }
    return;
  }
  decryptFailureCount.delete(msg.conversationId);
  const { text, replyTo } = unpackPayload(pt);
  msg._plaintext = text;
  msg._replyTo = replyTo;
}

async function decryptAllForConv(convId) {
  const list = state.messagesByConv.get(convId) || [];
  await Promise.all(list.map(decryptMessage));
  // Also decrypt the conversation summary's lastMessage (sidebar preview).
  const conv = state.conversations.find((c) => c.id === convId);
  if (conv?.lastMessage) await decryptMessage(conv.lastMessage);
}

async function decryptAllConversations() {
  await Promise.all(
    state.conversations.map(async (c) => {
      if (c.lastMessage) await decryptMessage(c.lastMessage);
    }),
  );
}

// ---------- API client ----------
async function api(path, { method = 'GET', body, token } = {}) {
  const r = await fetch(API + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: 'Bearer ' + token } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  if (!r.ok) {
    let msg = text;
    try { msg = JSON.parse(text).message ?? text; } catch {}
    throw Object.assign(new Error(msg), { status: r.status });
  }
  return text ? JSON.parse(text) : {};
}

// Authed wrapper that auto-refreshes the access token on 401. The refresh
// endpoint runs first (cheap, server-side validation only). If that also
// fails, fall back to re-running challenge/verify with the stored Ed25519
// key — the device-bound auth that registered the session in the first
// place. Single-flight so a burst of 401s doesn't kick off N refreshes.
let refreshInFlight = null;
async function refreshAccessToken() {
  if (refreshInFlight) return refreshInFlight;
  refreshInFlight = (async () => {
    try {
      if (state.me?.refreshToken) {
        try {
          const r = await api('/auth/refresh', {
            method: 'POST',
            body: { refreshToken: state.me.refreshToken },
          });
          state.me.accessToken = r.accessToken;
          state.me.refreshToken = r.refreshToken;
          await session.save(state.me);
          return state.me.accessToken;
        } catch {
          // refresh token expired/revoked — fall through to re-auth
        }
      }
      const stored = await session.load();
      if (stored?.edPrivKey || stored?.edJwkPriv) {
        await doRestore(stored);
        return state.me?.accessToken ?? null;
      }
      return null;
    } finally {
      refreshInFlight = null;
    }
  })();
  return refreshInFlight;
}

async function authedApi(path, opts = {}) {
  const token = state.me?.accessToken;
  try {
    return await api(path, { ...opts, token });
  } catch (e) {
    if (e.status !== 401 || !state.me) throw e;
    const fresh = await refreshAccessToken();
    if (!fresh) {
      await logout();
      throw e;
    }
    // Reconnect WS with the new token and retry once.
    if (state.socket) {
      try { state.socket.auth = { token: fresh }; state.socket.disconnect().connect(); } catch {}
    }
    return await api(path, { ...opts, token: fresh });
  }
}

// ---------- websocket ----------
function setConnPill(kind, text) {
  const pill = $('conn-pill');
  pill.className = 'topbar-pill ' + kind;
  pill.textContent = text;
}

function connectSocket() {
  if (!state.me) return;
  if (typeof window.io !== 'function') {
    setConnPill('offline', '폴링 모드');
    return;
  }
  if (state.socket) {
    try { state.socket.removeAllListeners(); state.socket.disconnect(); } catch {}
  }
  setConnPill('connecting', '연결 중…');
  const s = window.io({
    path: '/v1/realtime',
    auth: { token: state.me.accessToken },
    transports: ['websocket', 'polling'],
    reconnection: true,
    reconnectionDelay: 1000,
    reconnectionDelayMax: 30000,
    randomizationFactor: 0.4,
  });
  state.socket = s;

  s.on('connect', () => {
    setConnPill('connected', '실시간');
    // Slow polling to a heartbeat once we have the WS push channel.
    if (state.pollTimer) clearInterval(state.pollTimer);
    state.pollTimer = setInterval(loadConversations, 30000);
    // Reconnect is the moment to retry anything we couldn't send while offline.
    drainOutbound();
  });
  s.on('disconnect', (reason) => {
    setConnPill('connecting', reason === 'io server disconnect' ? '연결 끊김' : '재연결 중…');
  });
  s.on('connect_error', () => {
    setConnPill('offline', '연결 실패');
  });

  s.on('message.new', (msg) => onMessageNew(msg));
  s.on('message.delivered', ({ messageId, deliveredAt }) =>
    patchMessage(messageId, { deliveredAt }),
  );
  s.on('message.read', ({ messageId, readAt }) =>
    patchMessage(messageId, { readAt }),
  );
  s.on('presence.update', ({ userId, status }) => {
    if (status === 'online') state.online.add(userId);
    else state.online.delete(userId);
    renderSidebar();
    renderActivePanel();
  });
  s.on('typing.start', ({ conversationId, userId, handle }) => {
    let perConv = state.typing.get(conversationId);
    if (!perConv) {
      perConv = new Map();
      state.typing.set(conversationId, perConv);
    }
    perConv.set(userId, { handle, expiresAt: Date.now() + 6000 });
    renderActivePanel();
    setTimeout(() => clearStaleTyping(conversationId), 6500);
  });
  s.on('typing.stop', ({ conversationId, userId }) => {
    const perConv = state.typing.get(conversationId);
    if (perConv) {
      perConv.delete(userId);
      if (perConv.size === 0) state.typing.delete(conversationId);
      renderActivePanel();
    }
  });
  s.on('conversation.sync', () => loadConversations());
}

function clearStaleTyping(convId) {
  const perConv = state.typing.get(convId);
  if (!perConv) return;
  const now = Date.now();
  let changed = false;
  for (const [uid, entry] of perConv) {
    if (entry.expiresAt < now) {
      perConv.delete(uid);
      changed = true;
    }
  }
  if (perConv.size === 0) state.typing.delete(convId);
  if (changed) renderActivePanel();
}

function disconnectSocket() {
  if (state.socket) {
    try { state.socket.removeAllListeners(); state.socket.disconnect(); } catch {}
  }
  state.socket = null;
  state.online.clear();
  state.typing.clear();
}

async function onMessageNew(msg) {
  const convId = msg.conversationId;
  const list = state.messagesByConv.get(convId) || [];
  // If we already have this message id, ignore.
  if (list.some((m) => m.id === msg.id)) return;
  // Replace optimistic pending entry with the same clientMessageId (server echo of our own send).
  if (msg.clientMessageId) {
    const idx = list.findIndex((m) => m.clientMessageId === msg.clientMessageId);
    if (idx >= 0) {
      // Carry over the plaintext we already typed locally.
      if (list[idx]._plaintext != null) msg._plaintext = list[idx]._plaintext;
      list[idx] = msg;
      state.messagesByConv.set(convId, list);
      bumpConversation(convId, msg);
      return;
    }
  }
  list.push(msg);
  state.messagesByConv.set(convId, list);
  bumpConversation(convId, msg);
  await decryptMessage(msg);
  // Re-render with the now-plaintext bubble + sidebar preview.
  renderSidebar();
  if (convId === state.activeConv || convId === state.secondaryConv) renderActivePanel();
}

function bumpConversation(convId, msg) {
  const conv = state.conversations.find((c) => c.id === convId);
  if (conv) {
    conv.lastMessage = msg;
    state.conversations.sort((a, b) => {
      const ax = a.lastMessage?.serverReceivedAt ?? a.createdAt;
      const bx = b.lastMessage?.serverReceivedAt ?? b.createdAt;
      return bx.localeCompare(ax);
    });
  }
  renderSidebar();
  if (convId === state.activeConv || convId === state.secondaryConv) renderActivePanel();
}

function patchMessage(messageId, patch) {
  for (const [convId, list] of state.messagesByConv) {
    const idx = list.findIndex((m) => m.id === messageId);
    if (idx >= 0) {
      list[idx] = { ...list[idx], ...patch };
      if (convId === state.activeConv || convId === state.secondaryConv) renderActivePanel();
      return;
    }
  }
}

const typingEmits = new Map(); // convId -> { lastStartAt: number, stopTimer: number }
function emitTypingStart(convId) {
  if (!state.socket?.connected) return;
  const entry = typingEmits.get(convId) ?? { lastStartAt: 0, stopTimer: null };
  const now = Date.now();
  if (now - entry.lastStartAt > 3000) {
    state.socket.emit('typing.start', { conversationId: convId });
    entry.lastStartAt = now;
  }
  if (entry.stopTimer) clearTimeout(entry.stopTimer);
  entry.stopTimer = setTimeout(() => emitTypingStop(convId), 4000);
  typingEmits.set(convId, entry);
}
function emitTypingStop(convId) {
  const entry = typingEmits.get(convId);
  // No-op if we never emitted a typing.start for this conversation. This avoids
  // a spurious stop when the textarea blurs from a re-render, which would
  // otherwise prime the server's per-socket throttle and swallow the next
  // legitimate typing.start.
  if (!entry) return;
  if (entry.stopTimer) clearTimeout(entry.stopTimer);
  typingEmits.delete(convId);
  if (state.socket?.connected) {
    state.socket.emit('typing.stop', { conversationId: convId });
  }
}

// ---------- IndexedDB ----------
// One DB per browser. Stores:
//   session     - { id: 'me', value: { handle, userId, deviceId, accessToken, refreshToken,
//                                       edPrivKey, xPrivKey, edPubB64u, xPubB64u } }
//                 (CryptoKey objects are stored directly via structured clone;
//                  legacy JWK fields edJwkPriv/xJwkPriv are auto-migrated on
//                  first restore.)
//   conversations - ConversationSummary keyed by id
//   messages    - { ...ConversationMessageSummary, _key: convId + ':' + conversationOrder },
//                 indexed by convId
//   outbound    - pending sends keyed by clientMessageId
//   drafts      - { convId: textareaValue }
const IDB_NAME = 'veil-demo';
const IDB_VERSION = 1;

function openIdb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(IDB_NAME, IDB_VERSION);
    req.onerror = () => reject(req.error);
    req.onsuccess = () => resolve(req.result);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains('session')) db.createObjectStore('session', { keyPath: 'id' });
      if (!db.objectStoreNames.contains('conversations')) db.createObjectStore('conversations', { keyPath: 'id' });
      if (!db.objectStoreNames.contains('messages')) {
        const ms = db.createObjectStore('messages', { keyPath: '_key' });
        ms.createIndex('byConv', 'conversationId', { unique: false });
      }
      if (!db.objectStoreNames.contains('outbound')) db.createObjectStore('outbound', { keyPath: 'clientMessageId' });
      if (!db.objectStoreNames.contains('drafts')) db.createObjectStore('drafts', { keyPath: 'convId' });
    };
  });
}

let _db = null;
async function db() {
  if (!_db) _db = await openIdb();
  return _db;
}
async function idbGet(store, key) {
  const tx = (await db()).transaction(store, 'readonly');
  return new Promise((resolve, reject) => {
    const req = tx.objectStore(store).get(key);
    req.onsuccess = () => resolve(req.result ?? null);
    req.onerror = () => reject(req.error);
  });
}
async function idbPut(store, value) {
  const tx = (await db()).transaction(store, 'readwrite');
  return new Promise((resolve, reject) => {
    const req = tx.objectStore(store).put(value);
    req.onsuccess = () => resolve();
    req.onerror = () => reject(req.error);
  });
}
async function idbDelete(store, key) {
  const tx = (await db()).transaction(store, 'readwrite');
  return new Promise((resolve, reject) => {
    const req = tx.objectStore(store).delete(key);
    req.onsuccess = () => resolve();
    req.onerror = () => reject(req.error);
  });
}
async function idbAll(store) {
  const tx = (await db()).transaction(store, 'readonly');
  return new Promise((resolve, reject) => {
    const req = tx.objectStore(store).getAll();
    req.onsuccess = () => resolve(req.result || []);
    req.onerror = () => reject(req.error);
  });
}
async function idbAllByIndex(store, indexName, key) {
  const tx = (await db()).transaction(store, 'readonly');
  return new Promise((resolve, reject) => {
    const req = tx.objectStore(store).index(indexName).getAll(key);
    req.onsuccess = () => resolve(req.result || []);
    req.onerror = () => reject(req.error);
  });
}
async function idbClear(store) {
  const tx = (await db()).transaction(store, 'readwrite');
  return new Promise((resolve, reject) => {
    const req = tx.objectStore(store).clear();
    req.onsuccess = () => resolve();
    req.onerror = () => reject(req.error);
  });
}
async function idbWipeAll() {
  for (const s of ['session', 'conversations', 'messages', 'outbound', 'drafts']) {
    try { await idbClear(s); } catch {}
  }
}

// ---------- session ----------
const session = {
  // Migration: legacy localStorage entry from earlier phases.
  async load() {
    const fromIdb = await idbGet('session', 'me');
    if (fromIdb?.value) return fromIdb.value;
    try {
      const legacy = JSON.parse(localStorage.getItem(STORE) ?? 'null');
      if (legacy) {
        await idbPut('session', { id: 'me', value: legacy });
        localStorage.removeItem(STORE);
        return legacy;
      }
    } catch {}
    return null;
  },
  async save(me) { await idbPut('session', { id: 'me', value: me }); },
  async wipe() {
    try { localStorage.removeItem(STORE); } catch {}
    await idbWipeAll();
  },
};

// ---------- state ----------
const state = {
  me: null,                    // { handle, userId, deviceId, jwkPriv, accessToken, refreshToken }
  conversations: [],           // ConversationSummary[]
  messagesByConv: new Map(),   // convId -> ConversationMessageSummary[]
  openTabs: [],                // convId[] order = open order
  activeConv: null,            // primary panel convId | null
  secondaryConv: null,         // split-mode right panel convId | null
  splitView: false,            // is split layout enabled?
  pollTimer: null,
  socket: null,                // socket.io client
  online: new Set(),           // userId set, populated from presence.update
  typing: new Map(),           // convId -> Map<userId, { handle, expiresAt }>
  replyDraftByConv: new Map(), // convId -> { id, snippet, sender } awaiting send
};
// Diagnostic handle, gated to localhost so a deployed copy doesn't leak the
// access/refresh tokens and private JWKs to anything that can run JS in the
// page. Playwright runs against localhost so its probes still work.
const __isDevHost = typeof location !== 'undefined' && (
  location.hostname === 'localhost' ||
  location.hostname === '127.0.0.1' ||
  location.hostname.endsWith('.local')
);
if (typeof window !== 'undefined' && __isDevHost) {
  window.__veil = state;
}

// ---------- render ----------
async function showAuth() {
  $('auth-screen').classList.remove('hidden');
  $('app').classList.add('hidden');
  const stored = await session.load();
  if (stored) {
    $('restore-row').classList.remove('hidden');
    $('restore-handle').textContent = '@' + stored.handle;
  } else {
    $('restore-row').classList.add('hidden');
  }
  // wipe-btn stays visible regardless. A user with a corrupted/partially
  // restored session needs to be able to nuke local state without first
  // succeeding at restore.
}

function showApp() {
  $('auth-screen').classList.add('hidden');
  $('app').classList.remove('hidden');
  renderMe();
  renderSidebar();
  renderActivePanel();
}

function renderMe() {
  if (!state.me) return;
  $('sidebar-me').replaceChildren(
    avatarFor(state.me.handle, 'sm'),
    el('div', {}, [
      el('div', { style: 'font-weight:600' }, ['@' + state.me.handle]),
      el('div', { style: 'font-size:11px;color:var(--fg-faint)' }, ['기기 ' + state.me.deviceId.slice(0, 8)]),
    ]),
  );
}

function renderSidebar() {
  const list = $('conv-list');
  const q = ($('search-input').value || '').trim().toLowerCase();
  const filtered = state.conversations.filter((c) => {
    if (!q) return true;
    return (c.members || []).some((m) => (m.handle || '').toLowerCase().includes(q));
  });

  if (filtered.length === 0) {
    list.replaceChildren(el('div', { class: 'conv-empty' }, [
      q ? `"${q}" 검색 결과 없음` : '대화 없음. + 새 대화 버튼으로 시작하세요.',
    ]));
    return;
  }

  list.replaceChildren(
    ...filtered.map((c) => {
      const peer = (c.members || []).find((m) => m.handle !== state.me.handle) ?? c.members?.[0];
      const isActive = state.activeConv === c.id || state.secondaryConv === c.id;
      const last = c.lastMessage;
      const preview = last ? renderPreview(last) : '아직 메시지 없음';
      const time = last ? formatRelTime(last.serverReceivedAt) : '';
      const peerOnline = peer && state.online.has(peer.userId);
      const av = avatarFor(peer?.handle ?? '?', 'md');
      av.appendChild(el('span', { class: 'presence-dot' }));
      if (peerOnline) av.classList.add('online');
      return el(
        'button',
        {
          class: 'conv-item' + (isActive ? ' active' : ''),
          onclick: () => openConversation(c.id),
        },
        [
          av,
          el('div', { class: 'conv-meta' }, [
            el('div', { class: 'conv-row1' }, [
              el('span', { class: 'conv-name' }, ['@' + (peer?.handle ?? '?')]),
              time ? el('span', { class: 'conv-time' }, [time]) : null,
            ]),
            el('div', { class: 'conv-preview' }, [preview]),
          ]),
        ],
      );
    }),
  );
}

function renderPreview(msgOrCiphertext) {
  if (msgOrCiphertext == null) return '';
  // Phase E onward: messages are pre-decrypted into _plaintext on ingest.
  if (typeof msgOrCiphertext === 'object') {
    if (msgOrCiphertext._plaintext != null) return msgOrCiphertext._plaintext;
    return '🔒 암호화됨';
  }
  // Rare callers passing a raw ciphertext string instead of a message object.
  const ct = msgOrCiphertext;
  if (ct.startsWith('v1.')) return '🔒 암호화됨';
  return ct;
}

function formatRelTime(iso) {
  const d = new Date(iso);
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  if (sameDay) return formatTime(d);
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  if (d.toDateString() === yesterday.toDateString()) return '어제';
  return `${d.getMonth() + 1}월 ${d.getDate()}일`;
}

function formatTime(d) {
  const h = d.getHours();
  const m = d.getMinutes();
  const ampm = h < 12 ? '오전' : '오후';
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${ampm} ${h12}:${String(m).padStart(2, '0')}`;
}

function dayKey(d) {
  return `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
}

function dayLabel(d) {
  const now = new Date();
  if (dayKey(d) === dayKey(now)) return '오늘';
  const yesterday = new Date(now);
  yesterday.setDate(yesterday.getDate() - 1);
  if (dayKey(d) === dayKey(yesterday)) return '어제';
  if (d.getFullYear() === now.getFullYear()) {
    return `${d.getMonth() + 1}월 ${d.getDate()}일`;
  }
  return `${d.getFullYear()}년 ${d.getMonth() + 1}월 ${d.getDate()}일`;
}

// Bucket messages into [{ dayKey, dayLabel, groups: [{ senderDeviceId, senderHandle, isMe, msgs[] }] }].
// Within a day, consecutive messages from the same device within 2 minutes form one group.
function groupMessages(msgs, peerByDeviceId, me) {
  const days = [];
  let day = null;
  let group = null;
  const GAP_MS = 2 * 60 * 1000;
  for (const m of msgs) {
    const t = new Date(m.serverReceivedAt || m._localAt || Date.now());
    const dk = dayKey(t);
    if (!day || day.dayKey !== dk) {
      day = { dayKey: dk, dayLabel: dayLabel(t), groups: [] };
      days.push(day);
      group = null;
    }
    const isMe = m.senderDeviceId === me.deviceId;
    const senderHandle = isMe ? me.handle : (peerByDeviceId.get(m.senderDeviceId) || '?');
    const lastMsg = group ? group.msgs[group.msgs.length - 1] : null;
    const lastT = lastMsg ? new Date(lastMsg.serverReceivedAt || lastMsg._localAt || 0) : null;
    if (
      group &&
      group.senderDeviceId === m.senderDeviceId &&
      lastT &&
      t - lastT < GAP_MS
    ) {
      group.msgs.push(m);
    } else {
      group = { senderDeviceId: m.senderDeviceId, senderHandle, isMe, msgs: [m] };
      day.groups.push(group);
    }
  }
  return days;
}

function statusForMine(m) {
  if (m._status === 'pending') return 'pending';
  if (m._status === 'failed') return 'failed';
  if (m.readAt) return 'read';
  if (m.deliveredAt) return 'delivered';
  return 'sent';
}

function statusGlyph(status) {
  if (status === 'pending') return '⏳';
  if (status === 'failed') return '!';
  if (status === 'read') return '✓✓';
  if (status === 'delivered') return '✓✓';
  return '✓';
}

function statusLabel(status) {
  if (status === 'pending') return '전송 중';
  if (status === 'failed') return '전송 실패';
  if (status === 'read') return '읽음';
  if (status === 'delivered') return '전달됨';
  return '전송됨';
}

// Track scroll positions per conversation so re-renders don't yank the user.
const scrollPosByConv = new Map();
const NEAR_BOTTOM_PX = 120;

function renderReplyHead(replyToId, allMsgs) {
  const target = allMsgs.find((m) => m.id === replyToId);
  const sender = target
    ? (target.senderDeviceId === state.me.deviceId ? state.me.handle : null)
    : null;
  const snippet = target?._plaintext != null
    ? (target._plaintext.length > 80 ? target._plaintext.slice(0, 80) + '…' : target._plaintext)
    : '이전 메시지';
  return el('div', { class: 'msg-reply-head' }, [
    el('span', { class: 'msg-reply-icon' }, ['↩']),
    el('span', { class: 'msg-reply-snippet' }, [snippet]),
  ]);
}

function startReply(convId, msg) {
  const sender = msg.senderDeviceId === state.me.deviceId ? state.me.handle : null;
  const snippet = msg._plaintext != null
    ? (msg._plaintext.length > 60 ? msg._plaintext.slice(0, 60) + '…' : msg._plaintext)
    : '이전 메시지';
  state.replyDraftByConv.set(convId, { id: msg.id, snippet, sender });
  renderActivePanel();
  // Focus the textarea after re-render.
  requestAnimationFrame(() => {
    const ta = document.querySelector(`.panel[data-conv="${convId}"] .panel-input textarea`);
    if (ta) ta.focus();
  });
}

function cancelReply(convId) {
  state.replyDraftByConv.delete(convId);
  renderActivePanel();
}

function renderActivePanel() {
  const panels = $('panels');
  const slots = [state.activeConv, state.splitView ? state.secondaryConv : null].filter(Boolean);
  if (slots.length === 0) {
    panels.replaceChildren(
      el('div', { class: 'panel-empty', style: 'display:flex' }, [
        el('div', { class: 'empty-emoji' }, ['💬']),
        el('div', { class: 'empty-title' }, ['대화를 골라주세요']),
        el('div', { class: 'empty-sub' }, ['좌측에서 대화를 선택하거나 새로 시작하세요']),
      ]),
    );
    return;
  }
  panels.replaceChildren(...slots.map(renderOnePanel).filter(Boolean));
}

function renderOnePanel(convId) {
  const conv = state.conversations.find((c) => c.id === convId);
  if (!conv) return null;
  const peer = (conv.members || []).find((m) => m.handle !== state.me.handle) ?? conv.members?.[0];
  const msgs = state.messagesByConv.get(conv.id) || [];

  // Build a deviceId->handle lookup. We only know our own deviceId here; others
  // collapse to the conversation peer for DMs.
  const peerByDeviceId = new Map();
  if (peer) peerByDeviceId.set('__peer__', peer.handle);
  for (const m of msgs) {
    if (m.senderDeviceId !== state.me.deviceId && peer && !peerByDeviceId.has(m.senderDeviceId)) {
      peerByDeviceId.set(m.senderDeviceId, peer.handle);
    }
  }

  // Capture scroll position from the previous render of THIS conversation, if any.
  const prevMsgsNode = document.querySelector(`.panel-msgs[data-conv="${convId}"]`);
  let wasNearBottom = true;
  let prevScrollTop = scrollPosByConv.get(convId) ?? 0;
  if (prevMsgsNode) {
    prevScrollTop = prevMsgsNode.scrollTop;
    wasNearBottom =
      prevMsgsNode.scrollHeight - prevMsgsNode.scrollTop - prevMsgsNode.clientHeight <= NEAR_BOTTOM_PX;
  }

  const msgsNode = el('div', { class: 'panel-msgs', dataset: { conv: convId } });
  const days = groupMessages(msgs, peerByDeviceId, state.me);
  for (const day of days) {
    msgsNode.appendChild(el('div', { class: 'day-divider' }, [el('span', {}, [day.dayLabel])]));
    for (const group of day.groups) {
      const stack = el('div', { class: 'group-stack' });
      if (!group.isMe) {
        stack.appendChild(el('div', { class: 'group-meta' }, ['@' + group.senderHandle]));
      }
      for (let i = 0; i < group.msgs.length; i++) {
        const m = group.msgs[i];
        const cls = ['msg'];
        if (i === 0) cls.push('first-of-group');
        if (i === group.msgs.length - 1) cls.push('last-of-group');
        if (m._status === 'pending') cls.push('pending');
        if (m._status === 'failed') cls.push('failed');
        // Reply header on the bubble that's answering an earlier message.
        const replyHead = m._replyTo ? renderReplyHead(m._replyTo, msgs) : null;
        // Reply button (visible on hover, accessible by keyboard).
        const replyBtn = m.id?.startsWith('__pending__') ? null : el(
          'button',
          {
            class: 'msg-reply-btn',
            'aria-label': '답장',
            title: '답장',
            onclick: (e) => { e.stopPropagation(); startReply(convId, m); },
          },
          ['↩'],
        );
        const bubble = el('div', { class: cls.join(' ') }, [
          replyHead,
          el('span', { class: 'msg-text' }, [renderPreview(m)]),
        ]);
        const wrap = el('div', { class: 'msg-row ' + (group.isMe ? 'me' : 'them') }, [
          group.isMe ? replyBtn : null,
          bubble,
          group.isMe ? null : replyBtn,
        ]);
        wrap.dataset.msgId = m.id;
        stack.appendChild(wrap);
      }
      const last = group.msgs[group.msgs.length - 1];
      const lastT = new Date(last.serverReceivedAt || last._localAt || Date.now());
      const timeBits = [formatTime(lastT)];
      if (group.isMe) {
        const status = statusForMine(last);
        const statusEl = el(
          'span',
          { class: 'msg-status ' + status, title: statusLabel(status) },
          [statusGlyph(status)],
        );
        const children = [...timeBits, ' · ', statusEl];
        if (status === 'failed' || (status === 'pending' && last._status === 'failed')) {
          children.push(
            ' · ',
            el(
              'button',
              {
                class: 'msg-action',
                title: '다시 보내기',
                onclick: () => retryFailedMessage(convId, last.clientMessageId),
              },
              ['다시 보내기'],
            ),
            ' · ',
            el(
              'button',
              {
                class: 'msg-action danger',
                title: '취소',
                onclick: () => cancelFailedMessage(convId, last.clientMessageId),
              },
              ['취소'],
            ),
          );
        }
        stack.appendChild(el('div', { class: 'msg-time' }, children));
      } else {
        stack.appendChild(el('div', { class: 'msg-time' }, timeBits));
      }
      msgsNode.appendChild(
        el('div', { class: 'msg-group ' + (group.isMe ? 'me' : 'them') }, [
          !group.isMe ? avatarFor(group.senderHandle, 'sm') : null,
          stack,
        ]),
      );
    }
  }
  if (msgs.length === 0) {
    msgsNode.appendChild(
      el('div', { class: 'panel-empty', style: 'display:flex; flex:1' }, [
        el('div', { class: 'empty-emoji' }, ['👋']),
        el('div', { class: 'empty-title' }, ['아직 메시지가 없어요']),
        el('div', { class: 'empty-sub' }, ['아래 입력창으로 첫 메시지를 보내보세요']),
      ]),
    );
  }

  msgsNode.addEventListener('scroll', () => {
    scrollPosByConv.set(convId, msgsNode.scrollTop);
  });

  const textarea = el('textarea', {
    placeholder: '메시지 입력 (Enter 전송, Shift+Enter 줄바꿈)',
    rows: '1',
    'aria-label': '메시지 입력',
    maxlength: String(MESSAGE_MAX_CHARS),
  });
  // Restore the draft if we have one cached for this conversation.
  const cachedDraft = draftCache.get(convId);
  if (cachedDraft) textarea.value = cachedDraft.slice(0, MESSAGE_MAX_CHARS);
  const sendBtn = el(
    'button',
    { class: 'send-btn', 'aria-label': '전송', onclick: () => sendMessage(textarea, convId) },
    [el('span', { 'aria-hidden': 'true' }, ['↑'])],
  );
  // Auto-grow + emit typing + persist the draft on every input.
  const autoGrow = () => {
    // maxlength is enforced by the browser, but a paste larger than the cap
    // can still arrive as a one-shot input event; trim defensively.
    if (textarea.value.length > MESSAGE_MAX_CHARS) {
      textarea.value = textarea.value.slice(0, MESSAGE_MAX_CHARS);
      toast(`메시지가 잘렸어요 (최대 ${MESSAGE_MAX_CHARS.toLocaleString()}자)`, 'error');
    }
    textarea.style.height = 'auto';
    textarea.style.height = Math.min(textarea.scrollHeight, 140) + 'px';
    sendBtn.disabled = textarea.value.trim().length === 0;
    if (textarea.value.trim().length > 0) emitTypingStart(convId);
    else emitTypingStop(convId);
    saveDraft(convId, textarea.value);
  };
  textarea.addEventListener('input', autoGrow);
  // No `blur` handler — the textarea blurs every time renderActivePanel
  // re-creates it (via WS message.new / typing / presence events), and a
  // typing.stop spam there is a) wrong (the user didn't stop) and b)
  // primes the server-side rate limit so the next legitimate typing.start
  // gets throttled. The 4-second idle timer + send-clears-stop covers the
  // real cases.
  // IME-safe Enter to send.
  let composing = false;
  textarea.addEventListener('compositionstart', () => { composing = true; });
  textarea.addEventListener('compositionend', () => { composing = false; });
  textarea.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey && !composing && !e.isComposing) {
      e.preventDefault();
      sendMessage(textarea, convId);
    }
  });
  sendBtn.disabled = true;

  // Header subtitle: typing > online > conversation id.
  const peerTyping = peer && state.typing.get(convId)?.has(peer.userId);
  const peerOnline = peer && state.online.has(peer.userId);
  let subText = `대화 ${conv.id.slice(0, 8)}`;
  let subClass = 'sub';
  if (peerTyping) {
    subText = '입력 중…';
    subClass = 'sub typing';
  } else if (peerOnline) {
    subText = '온라인';
    subClass = 'sub online';
  }
  const headerAvatar = avatarFor(peer?.handle ?? '?', 'md');
  headerAvatar.appendChild(el('span', { class: 'presence-dot' }));
  if (peerOnline) headerAvatar.classList.add('online');

  const replyDraft = state.replyDraftByConv.get(convId);
  const replyBanner = replyDraft
    ? el('div', { class: 'reply-banner' }, [
        el('span', { class: 'reply-banner-icon' }, ['↩']),
        el('div', { class: 'reply-banner-body' }, [
          el('div', { class: 'reply-banner-meta' }, ['답장: @' + (replyDraft.sender ?? peer?.handle ?? '?')]),
          el('div', { class: 'reply-banner-snippet' }, [replyDraft.snippet]),
        ]),
        el('button', {
          class: 'reply-banner-close',
          'aria-label': '답장 취소',
          onclick: () => cancelReply(convId),
        }, ['×']),
      ])
    : null;

  const panelNode = el('div', { class: 'panel', dataset: { conv: convId } }, [
    el('div', { class: 'panel-header' }, [
      headerAvatar,
      el('div', { class: 'panel-title' }, [
        el('div', { class: 'name' }, ['@' + (peer?.handle ?? '?')]),
        el('div', { class: subClass }, [subText]),
      ]),
    ]),
    msgsNode,
    el('div', { class: 'panel-input-wrap' }, [
      replyBanner,
      el('div', { class: 'panel-input' }, [textarea, sendBtn]),
    ]),
  ]);

  // Restore scroll: if user was near the bottom, snap to bottom; otherwise keep
  // them where they were.
  requestAnimationFrame(() => {
    if (wasNearBottom) {
      msgsNode.scrollTop = msgsNode.scrollHeight;
    } else {
      msgsNode.scrollTop = prevScrollTop;
    }
    // Focus the textarea ONCE per explicit open/switch action. Subsequent
    // renders (caused by WS events) leave the focus alone so the mobile
    // soft keyboard doesn't pop back open and the IME composition isn't
    // interrupted.
    if (pendingFocusClaim.has(convId) && state.activeConv === convId) {
      pendingFocusClaim.delete(convId);
      textarea.focus();
    }
  });

  // Mark visible peer messages as read in the background (only for primary tab).
  if (state.activeConv === convId || state.secondaryConv === convId) {
    requestAnimationFrame(() => attachReadObserver(convId, msgsNode));
  }

  return panelNode;
}

// Track which messages we've already marked as read so we don't hammer the
// /read endpoint. Survives across re-renders for the lifetime of the session.
const readMarked = new Set();

async function markOneAsRead(messageId) {
  if (readMarked.has(messageId)) return;
  readMarked.add(messageId);
  try {
    await authedApi(`/messages/${messageId}/read`, { method: 'POST', body: {} });
  } catch (e) {
    readMarked.delete(messageId);
    if (e.status === 401) return;
  }
}

// Per-panel IntersectionObservers. Old ones are torn down on re-render.
const panelObservers = new Map(); // convId -> IntersectionObserver

function attachReadObserver(convId, msgsNode) {
  const prev = panelObservers.get(convId);
  if (prev) prev.disconnect();
  const obs = new IntersectionObserver((entries) => {
    if (document.visibilityState !== 'visible') return;
    if (state.activeConv !== convId && state.secondaryConv !== convId) return;
    for (const entry of entries) {
      if (entry.intersectionRatio < 0.5) continue;
      const msgId = entry.target.dataset.msgId;
      if (!msgId || msgId.startsWith('__pending__')) continue;
      const list = state.messagesByConv.get(convId) || [];
      const m = list.find((x) => x.id === msgId);
      if (!m || m.senderDeviceId === state.me.deviceId || m.readAt) continue;
      markOneAsRead(msgId);
      obs.unobserve(entry.target);
    }
  }, { root: msgsNode, threshold: [0.5] });
  panelObservers.set(convId, obs);
  // Observe every peer message that hasn't been read yet.
  for (const row of msgsNode.querySelectorAll('.msg-row.them')) {
    obs.observe(row);
  }
}

// ---------- cache hydration ----------
// Pull conversations + messages from IDB so the UI paints something before the
// network refresh comes back. We never store plaintext on disk — only the
// ciphertext envelope — and re-derive _plaintext via decryptAllForConv.
async function hydrateFromCache() {
  try {
    const cachedConvs = await idbAll('conversations');
    if (cachedConvs.length > 0) {
      state.conversations = cachedConvs.sort((a, b) => {
        const ax = a.lastMessage?.serverReceivedAt ?? a.createdAt;
        const bx = b.lastMessage?.serverReceivedAt ?? b.createdAt;
        return bx.localeCompare(ax);
      });
      const allMsgs = await idbAll('messages');
      const byConv = new Map();
      for (const m of allMsgs) {
        const list = byConv.get(m.conversationId) ?? [];
        list.push(m);
        byConv.set(m.conversationId, list);
      }
      for (const [convId, list] of byConv) {
        list.sort((a, b) => a.conversationOrder - b.conversationOrder);
        state.messagesByConv.set(convId, list);
      }
      // Decrypt cached payloads in parallel (uses our keys so this is local).
      await Promise.all(state.conversations.map((c) => decryptAllForConv(c.id)));
      await decryptAllConversations();
    }
  } catch (e) {
    console.warn('hydrate from cache failed', e);
  }
}

async function persistConversation(conv) {
  // Strip _plaintext before writing to disk.
  const clean = { ...conv };
  if (clean.lastMessage) {
    const { _plaintext, ...lm } = clean.lastMessage;
    clean.lastMessage = lm;
  }
  try { await idbPut('conversations', clean); } catch {}
}

async function persistAllConversations() {
  for (const c of state.conversations) await persistConversation(c);
}

async function persistMessage(msg) {
  if (!msg.id || !msg.conversationId || msg.id.startsWith('__pending__')) return;
  const { _plaintext, _status, _localAt, ...clean } = msg;
  clean._key = msg.conversationId + ':' + msg.conversationOrder;
  try { await idbPut('messages', clean); } catch {}
}

async function persistMessages(convId) {
  const list = state.messagesByConv.get(convId) || [];
  for (const m of list) await persistMessage(m);
}

// ---------- outbound queue ----------
async function enqueueOutbound(entry) {
  await idbPut('outbound', entry);
}

async function retryFailedMessage(convId, clientMessageId) {
  if (!clientMessageId) return;
  const list = state.messagesByConv.get(convId) || [];
  const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
  if (idx < 0) return;
  list[idx] = { ...list[idx], _status: 'pending' };
  // Re-add to outbound with nextRetryAt=0 so the next drain runs immediately.
  const queued = await idbGet('outbound', clientMessageId);
  if (queued) {
    await idbPut('outbound', { ...queued, attempts: 0, nextRetryAt: 0 });
  }
  renderActivePanel();
  drainOutbound();
}

async function cancelFailedMessage(convId, clientMessageId) {
  if (!clientMessageId) return;
  const list = state.messagesByConv.get(convId) || [];
  const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
  if (idx >= 0) {
    list.splice(idx, 1);
    state.messagesByConv.set(convId, list);
  }
  try { await idbDelete('outbound', clientMessageId); } catch {}
  renderActivePanel();
  toast('전송 취소됨');
}
async function dequeueOutbound(clientMessageId) {
  await idbDelete('outbound', clientMessageId);
}
// BroadcastChannel-backed leader election. Multiple tabs of the same handle
// in the same browser would otherwise both poll the outbound queue, leading
// to duplicate /messages POSTs (idempotency stops the duplicate write but
// not the wasted request). Each tab elects itself only if no leader has
// announced itself in the last ~2s.
const TAB_ID = Math.random().toString(36).slice(2, 12) + '-' + Date.now().toString(36);
let leaderUntil = 0;
let outboundChannel = null;
try { outboundChannel = new BroadcastChannel('veil-demo-outbound'); } catch {}
if (outboundChannel) {
  outboundChannel.addEventListener('message', (ev) => {
    if (ev.data?.kind === 'lead' && ev.data?.tab !== TAB_ID) {
      // Another tab is leading; back off.
      leaderUntil = Math.max(leaderUntil, Date.now() + 2000);
    }
  });
}
function isOutboundLeader() {
  if (!outboundChannel) return true; // no BroadcastChannel = old browser, behave as before
  const now = Date.now();
  if (leaderUntil > now) return false;
  // Announce ourselves and reserve the leader slot for the next 2 seconds.
  try { outboundChannel.postMessage({ kind: 'lead', tab: TAB_ID }); } catch {}
  leaderUntil = now + 2000;
  return true;
}

async function drainOutbound() {
  if (!state.me) return;
  if (!isOutboundLeader()) return;
  const items = await idbAll('outbound');
  if (items.length === 0) return;
  for (const item of items) {
    if (item.nextRetryAt && item.nextRetryAt > Date.now()) continue;
    try {
      const sent = await authedApi('/messages', {
        method: 'POST',
        body: {
          conversationId: item.conversationId,
          clientMessageId: item.clientMessageId,
          envelope: item.envelope,
        },
      });
      sent.message._plaintext = item.plaintext;
      const list = state.messagesByConv.get(item.conversationId) || [];
      const idx = list.findIndex((m) => m.clientMessageId === item.clientMessageId);
      if (idx >= 0) list[idx] = sent.message;
      else list.push(sent.message);
      state.messagesByConv.set(item.conversationId, list);
      const conv = state.conversations.find((c) => c.id === item.conversationId);
      if (conv) conv.lastMessage = sent.message;
      await dequeueOutbound(item.clientMessageId);
      await persistMessage(sent.message);
      if (item.conversationId === state.activeConv || item.conversationId === state.secondaryConv) {
        renderActivePanel();
      }
      renderSidebar();
    } catch (e) {
      // Bump retry with exponential backoff up to 30s.
      const attempts = (item.attempts ?? 0) + 1;
      const delay = Math.min(30_000, 1000 * 2 ** attempts);
      await idbPut('outbound', { ...item, attempts, nextRetryAt: Date.now() + delay });
      if (e.status && e.status >= 400 && e.status < 500 && e.status !== 429) {
        // Permanent failure — surface to the user, mark as failed locally.
        await dequeueOutbound(item.clientMessageId);
        const list = state.messagesByConv.get(item.conversationId) || [];
        const idx = list.findIndex((m) => m.clientMessageId === item.clientMessageId);
        if (idx >= 0) list[idx] = { ...list[idx], _status: 'failed' };
        toast('전송 실패: ' + e.message, 'error');
        renderActivePanel();
      }
    }
  }
}

// ---------- drafts ----------
const draftCache = new Map(); // convId -> text (mirrors IDB; written on input, read on render)
const draftFlushTimers = new Map(); // convId -> setTimeout handle
async function loadDraftsFromIdb() {
  try {
    const all = await idbAll('drafts');
    for (const d of all) draftCache.set(d.convId, d.text);
  } catch {}
}
async function flushDraftToIdb(convId, text) {
  if (text) {
    try { await idbPut('drafts', { convId, text }); } catch {}
  } else {
    try { await idbDelete('drafts', convId); } catch {}
  }
}
function saveDraft(convId, text) {
  if (!convId) return;
  draftCache.set(convId, text);
  // Debounce IDB writes — a fast typer otherwise hits disk every keystroke.
  const existing = draftFlushTimers.get(convId);
  if (existing) clearTimeout(existing);
  draftFlushTimers.set(convId, setTimeout(() => {
    draftFlushTimers.delete(convId);
    flushDraftToIdb(convId, draftCache.get(convId) ?? '');
  }, DRAFT_DEBOUNCE_MS));
}
async function flushAllDraftsImmediately() {
  for (const [convId, t] of draftFlushTimers) clearTimeout(t);
  draftFlushTimers.clear();
  for (const [convId, text] of draftCache) await flushDraftToIdb(convId, text);
}
// ---------- actions ----------
async function doRegister(displayName, handle) {
  const keys = await generateIdentityKeys();
  const reg = await api('/auth/register', {
    method: 'POST',
    body: {
      handle,
      displayName: displayName || handle,
      deviceName: 'web-' + (navigator.platform || 'browser'),
      platform: 'android',
      // X25519 raw public key — peers fetch this through /users/:handle/key-bundle
      // and use it to derive the per-conversation AES key via ECDH.
      publicIdentityKey: keys.xPubB64u,
      signedPrekeyBundle: 'web-demo-no-prekey',
      authPublicKey: keys.edPubB64u,
    },
  });
  const ch = await api('/auth/challenge', {
    method: 'POST',
    body: { handle: reg.handle, deviceId: reg.deviceId },
  });
  const signature = await signChallenge(keys.edPrivKey, ch.challenge);
  const ver = await api('/auth/verify', {
    method: 'POST',
    body: { challengeId: ch.challengeId, deviceId: reg.deviceId, signature },
  });
  state.me = {
    handle: reg.handle,
    userId: reg.userId,
    deviceId: reg.deviceId,
    edPrivKey: keys.edPrivKey,    // CryptoKey, never exported as JWK
    xPrivKey: keys.xPrivKey,      // CryptoKey, never exported as JWK
    xPubB64u: keys.xPubB64u,
    edPubB64u: keys.edPubB64u,
    accessToken: ver.accessToken,
    refreshToken: ver.refreshToken,
  };
  await session.save(state.me);
}

async function doRestore(stored) {
  // Auto-migrate sessions that still hold JWK material from earlier phases.
  if (stored.edJwkPriv && !stored.edPrivKey) {
    stored.edPrivKey = await importEdPrivFromJwk(stored.edJwkPriv);
    delete stored.edJwkPriv;
  }
  if (stored.xJwkPriv && !stored.xPrivKey) {
    stored.xPrivKey = await importXPrivFromJwk(stored.xJwkPriv);
    delete stored.xJwkPriv;
  }
  if (!stored.edPrivKey || !stored.xPrivKey) {
    throw Object.assign(
      new Error('이 브라우저의 세션은 새 암호화 형식과 호환되지 않아요. 다시 등록해주세요.'),
      { status: 0 },
    );
  }
  const ch = await api('/auth/challenge', {
    method: 'POST',
    body: { handle: stored.handle, deviceId: stored.deviceId },
  });
  const signature = await signChallenge(stored.edPrivKey, ch.challenge);
  const ver = await api('/auth/verify', {
    method: 'POST',
    body: { challengeId: ch.challengeId, deviceId: stored.deviceId, signature },
  });
  state.me = { ...stored, accessToken: ver.accessToken, refreshToken: ver.refreshToken };
  await session.save(state.me);
}

async function loadConversations() {
  try {
    const r = await authedApi('/conversations');
    state.conversations = Array.isArray(r) ? r : (r.items ?? []);
    // Decrypt each conversation's lastMessage for the sidebar preview before
    // rendering so we don't flash "🔒 암호화됨" on every refresh.
    await decryptAllConversations();
    renderSidebar();
    persistAllConversations();
    drainOutbound();
  } catch (e) {
    if (e.status === 401) return logout();
    toast(e.message, 'error');
  }
}

// Track which conversations want a one-shot focus claim. We only focus the
// textarea when the user *explicitly* opens or switches to a tab, never on
// re-renders triggered by WS events — otherwise every incoming typing.start
// or presence.update yanks the mobile keyboard back open.
const pendingFocusClaim = new Set();

async function openConversation(convId) {
  if (!state.openTabs.includes(convId)) state.openTabs.push(convId);
  if (state.splitView && state.activeConv && state.activeConv !== convId) {
    state.secondaryConv = state.activeConv;
  }
  state.activeConv = convId;
  if (state.secondaryConv === convId) state.secondaryConv = null;
  pendingFocusClaim.add(convId);
  $('app').classList.add('viewing-chat');
  renderSidebar();
  renderTabs();
  renderActivePanel();
  // Pre-fetch the peer key so the first send doesn't have to wait on a
  // network round trip. Failures are non-fatal — sendMessage will retry.
  getConvCryptoCtx(convId).catch(() => {});
  await refreshMessages(convId);
}

function setActiveTab(convId) {
  if (state.splitView && state.activeConv && state.activeConv !== convId) {
    state.secondaryConv = state.activeConv;
  }
  state.activeConv = convId;
  if (state.secondaryConv === convId) state.secondaryConv = null;
  pendingFocusClaim.add(convId);
  renderSidebar();
  renderTabs();
  renderActivePanel();
}

function closeTab(convId) {
  const idx = state.openTabs.indexOf(convId);
  if (idx === -1) return;
  state.openTabs.splice(idx, 1);
  if (state.secondaryConv === convId) state.secondaryConv = null;
  if (state.activeConv === convId) {
    const fallback = state.openTabs[Math.min(idx, state.openTabs.length - 1)] || null;
    state.activeConv = fallback;
    if (state.activeConv === state.secondaryConv) state.secondaryConv = null;
  }
  if (state.splitView && !state.secondaryConv && state.activeConv) {
    state.secondaryConv = state.openTabs.find((c) => c !== state.activeConv) || null;
  }
  if (!state.activeConv) {
    $('app').classList.remove('viewing-chat');
  }
  scrollPosByConv.delete(convId);
  renderSidebar();
  renderTabs();
  renderActivePanel();
}

function toggleSplit() {
  if (window.matchMedia && window.matchMedia('(max-width: 720px)').matches) {
    toast('분할 보기는 데스크탑에서만 사용할 수 있어요', 'error');
    return;
  }
  state.splitView = !state.splitView;
  $('split-btn').classList.toggle('active', state.splitView);
  if (state.splitView) {
    state.secondaryConv = state.openTabs.find((c) => c !== state.activeConv) || null;
    if (!state.secondaryConv) {
      toast('탭을 두 개 이상 열어주세요', 'good');
    }
  } else {
    state.secondaryConv = null;
  }
  renderTabs();
  renderActivePanel();
}

function renderTabs() {
  const strip = $('tab-strip');
  if (state.openTabs.length === 0) {
    strip.replaceChildren();
    return;
  }
  strip.replaceChildren(
    ...state.openTabs.map((convId) => {
      const conv = state.conversations.find((c) => c.id === convId);
      const peer = conv ? (conv.members || []).find((m) => m.handle !== state.me.handle) ?? conv.members?.[0] : null;
      const isActive = state.activeConv === convId;
      const isSecondary = state.secondaryConv === convId;
      const closeBtn = el(
        'span',
        {
          class: 'tab-close',
          'aria-label': '탭 닫기',
          role: 'button',
          onclick: (e) => { e.stopPropagation(); closeTab(convId); },
        },
        ['×'],
      );
      return el(
        'button',
        {
          class: 'tab' + (isActive ? ' active' : '') + (isSecondary ? ' secondary' : ''),
          onclick: () => setActiveTab(convId),
          title: peer?.handle ? '@' + peer.handle : '대화',
        },
        [el('span', {}, ['@' + (peer?.handle ?? '?')]), closeBtn],
      );
    }),
  );
}

async function refreshMessages(convId) {
  const target = convId ?? state.activeConv;
  if (!target) return;
  try {
    const r = await authedApi(`/conversations/${target}/messages?limit=50`);
    // Preserve any pending optimistic entries that haven't been ACKed yet.
    const prev = state.messagesByConv.get(target) || [];
    const pendings = prev.filter((m) => m._status === 'pending' || m._status === 'failed');
    const prevByClientId = new Map(prev.map((m) => [m.clientMessageId, m]));
    const seenClientIds = new Set((r.items ?? []).map((m) => m.clientMessageId));
    const fresh = (r.items ?? []).map((m) => {
      const cached = prevByClientId.get(m.clientMessageId);
      // Reuse a previously-decrypted plaintext if we still have it cached.
      if (cached?._plaintext != null) m._plaintext = cached._plaintext;
      return m;
    });
    const merged = [
      ...fresh,
      ...pendings.filter((m) => !seenClientIds.has(m.clientMessageId)),
    ];
    state.messagesByConv.set(target, merged);
    await decryptAllForConv(target);
    if (target === state.activeConv || target === state.secondaryConv) renderActivePanel();
    persistMessages(target);
  } catch (e) {
    if (e.status === 401) return logout();
  }
}

async function sendMessage(textarea, convId) {
  const target = convId ?? state.activeConv;
  const text = textarea.value.trim();
  if (!text || !target) return;
  if (text.length > MESSAGE_MAX_CHARS) {
    toast(`메시지가 너무 길어요 (최대 ${MESSAGE_MAX_CHARS.toLocaleString()}자)`, 'error');
    return;
  }
  const conv = state.conversations.find((c) => c.id === target);
  if (!conv) return;
  const peer = conv.members.find((m) => m.userId !== state.me.userId);
  const clientMessageId = 'web-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);

  // Encrypt the body with a fresh per-message AES-GCM key derived from the
  // per-peer ECDH secret. The server only ever sees `ciphertext` and `nonce`.
  const replyDraft = state.replyDraftByConv.get(target);
  const replyToId = replyDraft?.id ?? null;
  const payload = packPayload(text, replyToId);
  const envelope = await encryptForConv(target, payload);
  if (!envelope) {
    toast('상대 키를 찾지 못했어요. 잠시 후 다시 시도해주세요.', 'error');
    return;
  }
  const { ciphertext, nonce } = envelope;

  // Optimistic insert with pending status so the bubble appears immediately.
  const optimistic = {
    id: '__pending__' + clientMessageId,
    clientMessageId,
    conversationId: conv.id,
    senderDeviceId: state.me.deviceId,
    ciphertext,
    nonce,
    messageType: 'text',
    serverReceivedAt: null,
    _localAt: new Date().toISOString(),
    _status: 'pending',
    _plaintext: text,
    _replyTo: replyToId,
  };
  // Reply consumed — clear the banner.
  if (replyToId) state.replyDraftByConv.delete(target);
  const list = state.messagesByConv.get(conv.id) || [];
  list.push(optimistic);
  state.messagesByConv.set(conv.id, list);
  textarea.value = '';
  textarea.style.height = 'auto';
  textarea.dispatchEvent(new Event('input'));
  emitTypingStop(target);
  renderActivePanel();

  try {
    const sent = await authedApi('/messages', {
      method: 'POST',
      body: {
        conversationId: conv.id,
        clientMessageId,
        envelope: {
          version: 'veil-envelope-v1-dev',
          conversationId: conv.id,
          senderDeviceId: state.me.deviceId,
          recipientUserId: peer.userId,
          ciphertext,
          nonce,
          messageType: 'text',
        },
      },
    });
    // Carry over the plaintext we already have locally.
    sent.message._plaintext = text;
    const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
    if (idx >= 0) list[idx] = sent.message;
    else list.push(sent.message);
    conv.lastMessage = sent.message;
    state.conversations.sort((a, b) => {
      const ax = a.lastMessage?.serverReceivedAt ?? a.createdAt;
      const bx = b.lastMessage?.serverReceivedAt ?? b.createdAt;
      return bx.localeCompare(ax);
    });
    persistMessage(sent.message);
    persistConversation(conv);
    renderActivePanel();
    renderSidebar();
  } catch (e) {
    if (e.status === 401) return logout();
    // Network or 5xx error — enqueue the encrypted envelope so it can be
    // retried after reconnect. Permanent 4xx (other than 429) bubbles up.
    const isRetryable = !e.status || e.status >= 500 || e.status === 429;
    if (isRetryable) {
      await enqueueOutbound({
        clientMessageId,
        conversationId: conv.id,
        envelope: {
          version: 'veil-envelope-v1-dev',
          conversationId: conv.id,
          senderDeviceId: state.me.deviceId,
          recipientUserId: peer.userId,
          ciphertext,
          nonce,
          messageType: 'text',
        },
        plaintext: text,
        attempts: 0,
        nextRetryAt: 0, // try immediately on the next drain opportunity
      });
      const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
      if (idx >= 0) list[idx] = { ...list[idx], _status: 'pending' };
      renderActivePanel();
      toast('연결 안 됨 — 큐잉 후 자동 재시도합니다');
    } else {
      const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
      if (idx >= 0) list[idx] = { ...optimistic, _status: 'failed' };
      renderActivePanel();
      toast('전송 실패: ' + e.message, 'error');
    }
  }
}

async function logout() {
  await session.wipe();
  state.me = null;
  state.conversations = [];
  state.messagesByConv.clear();
  state.activeConv = null;
  state.secondaryConv = null;
  state.openTabs = [];
  state.splitView = false;
  scrollPosByConv.clear();
  readMarked.clear();
  disconnectSocket();
  if (state.pollTimer) clearInterval(state.pollTimer);
  state.pollTimer = null;
  setConnPill('offline', '오프라인');
  showAuth();
  toast('로그아웃되었습니다');
}

function startPolling() {
  if (state.pollTimer) clearInterval(state.pollTimer);
  // Polling acts as a safety-net that runs while the WS handshake is pending
  // and stays at a relaxed cadence after WS connects.
  state.pollTimer = setInterval(async () => {
    if (!state.me) return;
    if (document.hidden) return;
    await loadConversations();
    if (state.socket?.connected) return; // WS handles per-message updates
    for (const convId of state.openTabs) {
      await refreshMessages(convId);
    }
  }, POLL_MS);
}

// ---------- event wiring ----------
async function bootIfSession() {
  const stored = await session.load();
  if (!stored) {
    await showAuth();
    return;
  }
  try {
    await doRestore(stored);
    await loadDraftsFromIdb();
    // Hydrate from cache before going to network so the UI paints instantly.
    await hydrateFromCache();
    showApp();
    // Then refresh in the background.
    loadConversations().catch(() => {});
    startPolling();
    connectSocket();
  } catch (e) {
    toast('세션 복원 실패: ' + e.message, 'error');
    showAuth();
  }
}

$('register-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const name = $('reg-name').value.trim();
  const handle = $('reg-handle').value.trim().toLowerCase();
  if (!handle) return toast('핸들을 입력하세요', 'error');
  if (!/^[a-z0-9_]{1,32}$/.test(handle)) return toast('소문자, 숫자, _ 만 사용 (최대 32자)', 'error');
  $('reg-btn').disabled = true;
  try {
    await doRegister(name, handle);
    await loadConversations();
    showApp();
    startPolling();
    connectSocket();
    toast('환영합니다 @' + handle, 'good');
  } catch (e) {
    toast(e.message, 'error');
  } finally {
    $('reg-btn').disabled = false;
  }
});

$('restore-btn').addEventListener('click', async () => {
  const stored = await session.load();
  if (!stored) return;
  $('restore-btn').disabled = true;
  try {
    await doRestore(stored);
    await loadConversations();
    showApp();
    startPolling();
    connectSocket();
  } catch (e) {
    toast('복원 실패: ' + e.message, 'error');
  } finally {
    $('restore-btn').disabled = false;
  }
});

$('wipe-btn').addEventListener('click', async () => {
  const ok = await uiConfirm({
    title: '키 · 캐시 삭제',
    body: '이 브라우저의 키를 전부 삭제합니다. 이 핸들로는 다시 로그인할 수 없어요.',
    okLabel: '삭제',
    destructive: true,
  });
  if (!ok) return;
  await session.wipe();
  await showAuth();
  toast('키를 삭제했습니다');
});

$('search-input').addEventListener('input', renderSidebar);

// Track the element that had focus before a dialog opens so we can restore
// it on close — important for keyboard users.
let dialogReturnFocusEl = null;
function openDialog(dialogId, firstFocusId) {
  dialogReturnFocusEl = document.activeElement;
  $(dialogId).classList.remove('hidden');
  if (firstFocusId) requestAnimationFrame(() => $(firstFocusId)?.focus());
}
function closeDialog(dialogId) {
  $(dialogId).classList.add('hidden');
  if (dialogReturnFocusEl && document.contains(dialogReturnFocusEl)) {
    try { dialogReturnFocusEl.focus(); } catch {}
  }
  dialogReturnFocusEl = null;
}
// Themed replacement for native confirm(). Returns a Promise<boolean>.
// Uses the same .dialog-backdrop / .dialog markup as the new-chat dialog so
// it inherits focus trap + Esc + click-outside-to-cancel behavior.
function uiConfirm({
  title = '확인',
  body = '',
  okLabel = '확인',
  cancelLabel = '취소',
  destructive = false,
} = {}) {
  return new Promise((resolve) => {
    const dialog = $('confirm-dialog');
    if (!dialog) {
      resolve(false);
      return;
    }
    $('confirm-title').textContent = title;
    $('confirm-body').textContent = body;
    const okBtn = $('confirm-ok');
    const cancelBtn = $('confirm-cancel');
    okBtn.textContent = okLabel;
    cancelBtn.textContent = cancelLabel;
    okBtn.classList.toggle('btn-primary', !destructive);
    okBtn.classList.toggle('btn-secondary', destructive);
    okBtn.style.background = destructive ? 'var(--bad)' : '';
    okBtn.style.borderColor = destructive ? 'var(--bad)' : '';

    const cleanup = (result) => {
      okBtn.removeEventListener('click', onOk);
      cancelBtn.removeEventListener('click', onCancel);
      dialog.removeEventListener('click', onBackdrop);
      dialog.removeEventListener('keydown', onKey);
      okBtn.style.background = '';
      okBtn.style.borderColor = '';
      closeDialog('confirm-dialog');
      resolve(result);
    };
    const onOk = () => cleanup(true);
    const onCancel = () => cleanup(false);
    const onBackdrop = (e) => { if (e.target === dialog) cleanup(false); };
    const onKey = (e) => {
      if (e.key === 'Escape') { e.preventDefault(); cleanup(false); }
      else trapFocus('confirm-dialog', e);
    };
    okBtn.addEventListener('click', onOk);
    cancelBtn.addEventListener('click', onCancel);
    dialog.addEventListener('click', onBackdrop);
    dialog.addEventListener('keydown', onKey);
    openDialog('confirm-dialog', 'confirm-cancel');
  });
}

function trapFocus(dialogId, e) {
  if (e.key !== 'Tab') return;
  const dialog = $(dialogId).querySelector('.dialog');
  if (!dialog) return;
  const focusable = dialog.querySelectorAll('input, button:not([disabled])');
  if (focusable.length === 0) return;
  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (e.shiftKey && document.activeElement === first) {
    e.preventDefault();
    last.focus();
  } else if (!e.shiftKey && document.activeElement === last) {
    e.preventDefault();
    first.focus();
  }
}

$('new-chat-btn').addEventListener('click', () => {
  $('new-peer-input').value = '';
  $('new-peer-error').textContent = '';
  openDialog('new-chat-dialog', 'new-peer-input');
});
$('new-cancel').addEventListener('click', () => closeDialog('new-chat-dialog'));
$('new-confirm').addEventListener('click', async () => {
  const peer = $('new-peer-input').value.trim().toLowerCase();
  if (!peer) {
    $('new-peer-error').textContent = '핸들을 입력하세요';
    return;
  }
  if (peer === state.me.handle) {
    $('new-peer-error').textContent = '자기 자신과는 대화할 수 없어요';
    return;
  }
  $('new-confirm').disabled = true;
  try {
    const r = await authedApi('/conversations/direct', {
      method: 'POST',
      body: { peerHandle: peer },
    });
    closeDialog('new-chat-dialog');
    await loadConversations();
    await openConversation(r.conversation.id);
  } catch (e) {
    $('new-peer-error').textContent = e.message;
  } finally {
    $('new-confirm').disabled = false;
  }
});
$('new-peer-input').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.isComposing) $('new-confirm').click();
});
$('new-chat-dialog').addEventListener('click', (e) => {
  if (e.target.id === 'new-chat-dialog') closeDialog('new-chat-dialog');
});
$('new-chat-dialog').addEventListener('keydown', (e) => {
  if (e.key === 'Escape') {
    e.preventDefault();
    closeDialog('new-chat-dialog');
  } else {
    trapFocus('new-chat-dialog', e);
  }
});

$('back-to-list').addEventListener('click', () => {
  state.activeConv = null;
  $('app').classList.remove('viewing-chat');
  renderSidebar();
  renderActivePanel();
});

$('menu-btn').addEventListener('click', (e) => {
  e.stopPropagation();
  $('menu').classList.toggle('hidden');
});
document.addEventListener('click', () => $('menu').classList.add('hidden'));
$('menu').addEventListener('click', (e) => e.stopPropagation());
$('menu').addEventListener('click', async (e) => {
  const action = e.target?.dataset?.action;
  if (!action) return;
  $('menu').classList.add('hidden');
  if (action === 'copy-handle') {
    try {
      await navigator.clipboard.writeText('@' + state.me.handle);
      toast('핸들을 복사했습니다', 'good');
    } catch {
      toast('클립보드 접근 실패', 'error');
    }
  } else if (action === 'ws-info') {
    const status = state.socket?.connected ? '실시간 (WebSocket)' : '폴링 (' + (POLL_MS / 1000) + '초)';
    toast('연결: ' + status, 'good');
  } else if (action === 'wipe') {
    const ok = await uiConfirm({
      title: '로그아웃 + 키 삭제',
      body: '로그아웃하고 이 브라우저의 키를 전부 삭제합니다. 이 핸들로는 다시 로그인할 수 없어요.',
      okLabel: '삭제',
      destructive: true,
    });
    if (ok) await logout();
  }
});

$('split-btn').addEventListener('click', toggleSplit);

// Private-beta banner: visible by default until the user dismisses it.
// Persists per-device in localStorage so a quick reload doesn't keep
// resurfacing it. The CSS variable --banner-h drives the app/auth-screen
// layout offset so the banner never overlaps the input area.
const BETA_BANNER_KEY = 'veil-demo-beta-banner-dismissed-v1';
const BETA_BANNER_HEIGHT_PX = 38;
const betaBanner = $('beta-banner');
const betaBannerClose = $('beta-banner-close');
function setBannerVisible(show) {
  if (!betaBanner) return;
  betaBanner.classList.toggle('hidden', !show);
  document.documentElement.style.setProperty(
    '--banner-h',
    show ? BETA_BANNER_HEIGHT_PX + 'px' : '0px',
  );
}
if (betaBanner && betaBannerClose) {
  setBannerVisible(localStorage.getItem(BETA_BANNER_KEY) !== '1');
  betaBannerClose.addEventListener('click', () => {
    setBannerVisible(false);
    try { localStorage.setItem(BETA_BANNER_KEY, '1'); } catch {}
  });
}

bootIfSession();

// ---------- device transfer ----------
// Two flows live here, sharing the same dialogs in index.html. The OLD
// device polls /device-transfer/sessions/:id with its JWT, watches for a
// claim to land, shows the new device's fingerprint, and approves. The
// NEW device — which has no session yet — generates a fresh keypair, posts
// /device-transfer/claim, then retries /device-transfer/complete every
// 2.5s with the same auth proof until the server returns 200.
const TRANSFER_POLL_MS = 2500;

let transferOldState = null;
async function startTransferOld() {
  if (!state.me) { toast('로그인 후 시도하세요', 'error'); return; }
  try {
    const init = await authedApi('/device-transfer/init', {
      method: 'POST',
      body: { oldDeviceId: state.me.deviceId },
    });
    const blob = JSON.stringify({ sessionId: init.sessionId, transferToken: init.transferToken });
    const code = btoa(blob).replace(/=+$/, '');
    transferOldState = { sessionId: init.sessionId, code, polling: true, claimId: null };
    $('transfer-old-token').value = code;
    $('transfer-old-status').textContent = '코드 복사 후 새 기기에 붙여넣기 — 새 기기 클레임 대기 중…';
    $('transfer-old-claim').classList.add('hidden');
    $('transfer-old-approve').classList.add('hidden');
    openDialog('transfer-old-dialog', 'transfer-old-token');
    pollTransferOld();
  } catch (e) {
    toast('이전 시작 실패: ' + e.message, 'error');
  }
}
async function pollTransferOld() {
  while (transferOldState?.polling) {
    try {
      const s = await authedApi('/device-transfer/sessions/' + transferOldState.sessionId);
      if (s.status === 'completed') {
        $('transfer-old-status').textContent = '완료됨. 이 기기는 이제 로그아웃됩니다.';
        transferOldState.polling = false;
        await session.wipe();
        setTimeout(async () => { closeDialog('transfer-old-dialog'); await showAuth(); }, 1200);
        return;
      }
      if (s.status === 'expired') {
        $('transfer-old-status').textContent = '만료되었습니다 (5분 초과). 다시 시작하세요.';
        transferOldState.polling = false; return;
      }
      if (s.pendingClaim && !transferOldState.claimId) {
        transferOldState.claimId = s.pendingClaim.claimId;
        $('transfer-old-fingerprint').textContent = s.pendingClaim.claimantFingerprint;
        $('transfer-old-claim').classList.remove('hidden');
        $('transfer-old-approve').classList.remove('hidden');
        $('transfer-old-status').textContent = '지문 확인 후 승인하세요.';
      }
    } catch (e) {
      $('transfer-old-status').textContent = '폴링 오류: ' + e.message;
    }
    await new Promise((r) => setTimeout(r, TRANSFER_POLL_MS));
  }
}
async function approveTransferOld() {
  if (!transferOldState?.claimId) return;
  $('transfer-old-approve').disabled = true;
  try {
    await authedApi('/device-transfer/approve', {
      method: 'POST',
      body: { sessionId: transferOldState.sessionId, claimId: transferOldState.claimId },
    });
    $('transfer-old-status').textContent = '승인됨 — 새 기기가 완료할 때까지 대기…';
  } catch (e) {
    toast('승인 실패: ' + e.message, 'error');
  } finally {
    $('transfer-old-approve').disabled = false;
  }
}
function cancelTransferOld() {
  if (transferOldState) transferOldState.polling = false;
  transferOldState = null;
  closeDialog('transfer-old-dialog');
}

let transferNewState = null;
function openTransferNew() {
  $('transfer-new-name').value = 'web-' + (navigator.platform || 'browser');
  $('transfer-new-token').value = '';
  $('transfer-new-error').textContent = '';
  $('transfer-new-status').textContent = '';
  $('transfer-new-fingerprint').classList.add('hidden');
  $('transfer-new-claim').textContent = '클레임';
  $('transfer-new-claim').disabled = false;
  transferNewState = null;
  openDialog('transfer-new-dialog', 'transfer-new-token');
}
async function claimTransferNew() {
  const code = $('transfer-new-token').value.trim();
  const name = $('transfer-new-name').value.trim() || 'VEIL';
  if (!code) { $('transfer-new-error').textContent = '코드가 필요합니다'; return; }
  let parsed;
  try {
    const padded = code + '='.repeat((4 - code.length % 4) % 4);
    parsed = JSON.parse(atob(padded));
    if (!parsed.sessionId || !parsed.transferToken) throw new Error('shape');
  } catch {
    $('transfer-new-error').textContent = '코드 형식 오류';
    return;
  }
  $('transfer-new-claim').disabled = true;
  $('transfer-new-error').textContent = '';
  $('transfer-new-status').textContent = '새 키 생성 중…';
  try {
    const keys = await generateIdentityKeys();
    const fingerprint = keys.edPubB64u.length <= 12
      ? keys.edPubB64u
      : keys.edPubB64u.slice(0, 6) + '...' + keys.edPubB64u.slice(-4);
    $('transfer-new-fingerprint-text').textContent = fingerprint;
    $('transfer-new-fingerprint').classList.remove('hidden');
    $('transfer-new-status').textContent = '서버에 클레임 중…';
    const claimSig = await signChallenge(keys.edPrivKey, `transfer-claim:${parsed.sessionId}:${parsed.transferToken}`);
    const claim = await api('/device-transfer/claim', {
      method: 'POST',
      body: {
        sessionId: parsed.sessionId,
        transferToken: parsed.transferToken,
        newDeviceName: name,
        platform: 'android',
        publicIdentityKey: keys.xPubB64u,
        signedPrekeyBundle: 'web-demo-no-prekey',
        authPublicKey: keys.edPubB64u,
        authProof: claimSig,
      },
    });
    transferNewState = { ...parsed, claimId: claim.claimId, keys };
    $('transfer-new-status').textContent = '이전 기기에서 승인 대기 중…';
    pollTransferNew();
  } catch (e) {
    $('transfer-new-error').textContent = e.message;
    $('transfer-new-claim').disabled = false;
  }
}
async function pollTransferNew() {
  if (!transferNewState) return;
  const { sessionId, transferToken, claimId, keys } = transferNewState;
  const completeSig = await signChallenge(
    keys.edPrivKey,
    `transfer-complete:${sessionId}:${claimId}:${transferToken}`,
  );
  while (transferNewState) {
    try {
      const res = await api('/device-transfer/complete', {
        method: 'POST',
        body: { sessionId, transferToken, claimId, authProof: completeSig },
      });
      // Success — save session as the new device and switch to the app.
      const me = {
        handle: res.handle,
        userId: res.handle, // userId not returned; we resolve it on first authedApi
        deviceId: res.newDeviceId,
        edPrivKey: keys.edPrivKey,
        xPrivKey: keys.xPrivKey,
        xPubB64u: keys.xPubB64u,
        edPubB64u: keys.edPubB64u,
        accessToken: null,
        refreshToken: null,
      };
      // We don't get tokens back from /complete — the new device must do
      // a normal challenge/verify with its newly trusted keypair.
      const ch = await api('/auth/challenge', {
        method: 'POST',
        body: { handle: res.handle, deviceId: res.newDeviceId },
      });
      const sig = await signChallenge(keys.edPrivKey, ch.challenge);
      const ver = await api('/auth/verify', {
        method: 'POST',
        body: { challengeId: ch.challengeId, deviceId: res.newDeviceId, signature: sig },
      });
      me.userId = ver.userId;
      me.accessToken = ver.accessToken;
      me.refreshToken = ver.refreshToken;
      state.me = me;
      await session.save({
        ...me,
        edPrivJwk: await crypto.subtle.exportKey('jwk', keys.edPrivKey),
        xPrivJwk: await crypto.subtle.exportKey('jwk', keys.xPrivKey),
      });
      transferNewState = null;
      closeDialog('transfer-new-dialog');
      toast('이전 완료 — 새 기기로 들어왔습니다', 'good');
      await loadConversations();
      showApp();
      startPolling();
      connectSocket();
      return;
    } catch (e) {
      const code = e.code || (e.body && e.body.code);
      if (code === 'transfer_approval_required' || e.status === 403) {
        $('transfer-new-status').textContent = '이전 기기에서 승인 대기 중…';
        await new Promise((r) => setTimeout(r, TRANSFER_POLL_MS));
        continue;
      }
      $('transfer-new-error').textContent = e.message;
      $('transfer-new-status').textContent = '실패. 다시 시도하세요.';
      $('transfer-new-claim').disabled = false;
      transferNewState = null;
      return;
    }
  }
}
function cancelTransferNew() {
  transferNewState = null;
  closeDialog('transfer-new-dialog');
}

document.addEventListener('DOMContentLoaded', () => {
  // Menu wiring is event-delegated via #menu, but transfer-start is one of
  // its actions — handle it in the same delegation by extending the menu
  // click listener. We do that by listening at capture phase here.
  const menu = $('menu');
  if (menu) {
    menu.addEventListener('click', (e) => {
      const action = e.target?.dataset?.action;
      if (action === 'transfer-start') {
        menu.classList.add('hidden');
        startTransferOld();
      }
    }, true);
  }
  $('transfer-old-cancel')?.addEventListener('click', cancelTransferOld);
  $('transfer-old-approve')?.addEventListener('click', approveTransferOld);
  $('transfer-new-btn')?.addEventListener('click', openTransferNew);
  $('transfer-new-cancel')?.addEventListener('click', cancelTransferNew);
  $('transfer-new-claim')?.addEventListener('click', claimTransferNew);
});
