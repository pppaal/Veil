// VEIL demo — Phase A: auth + sidebar + single chat send/receive + toasts.
// IndexedDB / WS / real crypto / token refresh land in later phases.

const API = '/v1';
const STORE = 'veil-demo-session';
const POLL_MS = 4000;

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
async function generateIdentityKeys() {
  const ed = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
  const x = await crypto.subtle.generateKey({ name: 'X25519' }, true, ['deriveBits']);
  return {
    edJwkPriv: await crypto.subtle.exportKey('jwk', ed.privateKey),
    edPubB64u: b64uEncode(await crypto.subtle.exportKey('raw', ed.publicKey)),
    xJwkPriv: await crypto.subtle.exportKey('jwk', x.privateKey),
    xPubB64u: b64uEncode(await crypto.subtle.exportKey('raw', x.publicKey)),
  };
}
async function importEdPriv(jwk) {
  return await crypto.subtle.importKey('jwk', jwk, { name: 'Ed25519' }, false, ['sign']);
}
async function importXPriv(jwk) {
  return await crypto.subtle.importKey('jwk', jwk, { name: 'X25519' }, false, ['deriveBits']);
}
async function importXPubFromB64u(b64u) {
  return await crypto.subtle.importKey('raw', b64uDecode(b64u), { name: 'X25519' }, false, []);
}
async function signChallenge(edPrivateKey, challenge) {
  const sig = await crypto.subtle.sign({ name: 'Ed25519' }, edPrivateKey, new TextEncoder().encode(challenge));
  return b64uEncode(sig);
}

async function deriveSharedAesKey(myXPriv, peerXPub) {
  const bits = await crypto.subtle.deriveBits({ name: 'X25519', public: peerXPub }, myXPriv, 256);
  const baseKey = await crypto.subtle.importKey('raw', bits, 'HKDF', false, ['deriveKey']);
  return await crypto.subtle.deriveKey(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: new Uint8Array(0),
      info: new TextEncoder().encode('veil-demo-v1-aesgcm'),
    },
    baseKey,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt'],
  );
}

async function encryptWithKey(key, plaintext) {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce },
    key,
    new TextEncoder().encode(plaintext),
  );
  return { ciphertext: 'v1.' + b64uEncode(ct), nonce: b64uEncode(nonce) };
}

async function decryptWithKey(key, ciphertextV1, nonceB64u) {
  if (!ciphertextV1?.startsWith('v1.')) return null;
  const ct = b64uDecode(ciphertextV1.slice(3));
  const nonce = b64uDecode(nonceB64u);
  try {
    const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce }, key, ct);
    return new TextDecoder().decode(pt);
  } catch {
    return null;
  }
}

// Per-conversation cached AES-GCM key (derived once per peer).
const sharedKeyByConv = new Map(); // convId -> CryptoKey
const peerXPubByUserId = new Map(); // userId -> CryptoKey (X25519 pub)

async function getPeerXPub(userId, handle) {
  if (peerXPubByUserId.has(userId)) return peerXPubByUserId.get(userId);
  const r = await api(`/users/${handle}/key-bundle`);
  const pub = await importXPubFromB64u(r.bundle.identityPublicKey);
  peerXPubByUserId.set(userId, pub);
  return pub;
}

async function getSharedKeyForConv(convId) {
  if (sharedKeyByConv.has(convId)) return sharedKeyByConv.get(convId);
  const conv = state.conversations.find((c) => c.id === convId);
  if (!conv || !state.me?.xPrivKey) return null;
  const peer = (conv.members || []).find((m) => m.userId !== state.me.userId);
  if (!peer) return null;
  try {
    const peerXPub = await getPeerXPub(peer.userId, peer.handle);
    const key = await deriveSharedAesKey(state.me.xPrivKey, peerXPub);
    sharedKeyByConv.set(convId, key);
    return key;
  } catch (e) {
    console.warn('shared key derive failed', e);
    return null;
  }
}

async function decryptMessage(msg) {
  if (msg._plaintext != null) return; // already done
  const ct = msg.ciphertext || '';
  // Legacy DEMO-LABEL still in DB from earlier phases.
  if (ct.startsWith('DEMO-PLAINTEXT-LABEL[') && ct.endsWith(']')) {
    msg._plaintext = ct.slice('DEMO-PLAINTEXT-LABEL['.length, -1);
    return;
  }
  if (!ct.startsWith('v1.')) {
    msg._plaintext = '(평문 아님)';
    return;
  }
  const key = await getSharedKeyForConv(msg.conversationId);
  if (!key) {
    msg._plaintext = '🔒 키 미해결';
    return;
  }
  const pt = await decryptWithKey(key, ct, msg.nonce);
  msg._plaintext = pt ?? '🔒 복호화 실패';
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
//                                       edJwkPriv, xJwkPriv, xPubB64u } }
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
};
// Expose for diagnostics — handy in DevTools and Playwright probes.
if (typeof window !== 'undefined') window.__veil = state;

// ---------- render ----------
async function showAuth() {
  $('auth-screen').classList.remove('hidden');
  $('app').classList.add('hidden');
  const stored = await session.load();
  if (stored) {
    $('restore-row').classList.remove('hidden');
    $('restore-handle').textContent = '@' + stored.handle;
    $('wipe-btn').classList.remove('hidden');
  } else {
    $('restore-row').classList.add('hidden');
    $('wipe-btn').classList.add('hidden');
  }
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
      el('div', { style: 'font-size:11px;color:var(--fg-faint)' }, ['device ' + state.me.deviceId.slice(0, 8)]),
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
      q ? `"${q}" 검색 결과 없음` : '대화 없음. 위에서 새 대화를 시작하세요.',
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
  // Legacy string fallback (the sidebar lastMessage or rare callers passing ct).
  const ct = msgOrCiphertext;
  const m = /^DEMO-PLAINTEXT-LABEL\[(.*)\]$/s.exec(ct);
  if (m) return m[1];
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
        stack.appendChild(el('div', { class: cls.join(' ') }, [renderPreview(m)]));
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
        stack.appendChild(el('div', { class: 'msg-time' }, [...timeBits, ' · ', statusEl]));
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
  });
  // Restore the draft if we have one cached for this conversation.
  const cachedDraft = draftCache.get(convId);
  if (cachedDraft) textarea.value = cachedDraft;
  const sendBtn = el(
    'button',
    { class: 'send-btn', 'aria-label': '전송', onclick: () => sendMessage(textarea, convId) },
    [el('span', { 'aria-hidden': 'true' }, ['↑'])],
  );
  // Auto-grow + emit typing + persist the draft on every input.
  const autoGrow = () => {
    textarea.style.height = 'auto';
    textarea.style.height = Math.min(textarea.scrollHeight, 140) + 'px';
    sendBtn.disabled = textarea.value.trim().length === 0;
    if (textarea.value.trim().length > 0) emitTypingStart(convId);
    else emitTypingStop(convId);
    saveDraft(convId, textarea.value);
  };
  textarea.addEventListener('input', autoGrow);
  textarea.addEventListener('blur', () => emitTypingStop(convId));
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

  const panelNode = el('div', { class: 'panel', dataset: { conv: convId } }, [
    el('div', { class: 'panel-header' }, [
      headerAvatar,
      el('div', { class: 'panel-title' }, [
        el('div', { class: 'name' }, ['@' + (peer?.handle ?? '?')]),
        el('div', { class: subClass }, [subText]),
      ]),
    ]),
    msgsNode,
    el('div', { class: 'panel-input' }, [textarea, sendBtn]),
  ]);

  // Restore scroll: if user was near the bottom, snap to bottom; otherwise keep
  // them where they were.
  requestAnimationFrame(() => {
    if (wasNearBottom) {
      msgsNode.scrollTop = msgsNode.scrollHeight;
    } else {
      msgsNode.scrollTop = prevScrollTop;
    }
    if (state.activeConv === convId) textarea.focus();
  });

  // Mark visible peer messages as read in the background (only for primary tab).
  if (state.activeConv === convId) markVisibleAsRead(convId, msgs);

  return panelNode;
}

const readMarked = new Set();
async function markVisibleAsRead(convId, msgs) {
  if (document.hidden) return;
  for (const m of msgs) {
    if (m.senderDeviceId === state.me.deviceId) continue;
    if (m.readAt) continue;
    if (readMarked.has(m.id)) continue;
    readMarked.add(m.id);
    try {
      await api(`/messages/${m.id}/read`, { method: 'POST', token: state.me.accessToken, body: {} });
    } catch (e) {
      readMarked.delete(m.id); // allow retry next render
      if (e.status === 401) return;
    }
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
async function dequeueOutbound(clientMessageId) {
  await idbDelete('outbound', clientMessageId);
}
async function drainOutbound() {
  if (!state.me) return;
  const items = await idbAll('outbound');
  if (items.length === 0) return;
  for (const item of items) {
    if (item.nextRetryAt && item.nextRetryAt > Date.now()) continue;
    try {
      const sent = await api('/messages', {
        method: 'POST',
        token: state.me.accessToken,
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
async function loadDraftsFromIdb() {
  try {
    const all = await idbAll('drafts');
    for (const d of all) draftCache.set(d.convId, d.text);
  } catch {}
}
async function saveDraft(convId, text) {
  if (!convId) return;
  draftCache.set(convId, text);
  if (text) {
    try { await idbPut('drafts', { convId, text }); } catch {}
  } else {
    try { await idbDelete('drafts', convId); } catch {}
  }
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
  const edPriv = await importEdPriv(keys.edJwkPriv);
  const signature = await signChallenge(edPriv, ch.challenge);
  const ver = await api('/auth/verify', {
    method: 'POST',
    body: { challengeId: ch.challengeId, deviceId: reg.deviceId, signature },
  });
  state.me = {
    handle: reg.handle,
    userId: reg.userId,
    deviceId: reg.deviceId,
    edJwkPriv: keys.edJwkPriv,
    xJwkPriv: keys.xJwkPriv,
    xPubB64u: keys.xPubB64u,
    accessToken: ver.accessToken,
    refreshToken: ver.refreshToken,
  };
  state.me.xPrivKey = await importXPriv(keys.xJwkPriv);
  await session.save(serializableMe(state.me));
}

async function doRestore(stored) {
  if (!stored.edJwkPriv || !stored.xJwkPriv) {
    throw Object.assign(new Error('이 브라우저의 세션은 새 암호화 형식과 호환되지 않아요. 다시 등록해주세요.'), { status: 0 });
  }
  const ch = await api('/auth/challenge', {
    method: 'POST',
    body: { handle: stored.handle, deviceId: stored.deviceId },
  });
  const edPriv = await importEdPriv(stored.edJwkPriv);
  const signature = await signChallenge(edPriv, ch.challenge);
  const ver = await api('/auth/verify', {
    method: 'POST',
    body: { challengeId: ch.challengeId, deviceId: stored.deviceId, signature },
  });
  state.me = { ...stored, accessToken: ver.accessToken, refreshToken: ver.refreshToken };
  state.me.xPrivKey = await importXPriv(stored.xJwkPriv);
  await session.save(serializableMe(state.me));
}

// CryptoKey objects can't be JSON-serialized. Strip them before saving.
function serializableMe(me) {
  const { xPrivKey, ...rest } = me;
  return rest;
}

async function loadConversations() {
  try {
    const r = await api('/conversations', { token: state.me.accessToken });
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

async function openConversation(convId) {
  if (!state.openTabs.includes(convId)) state.openTabs.push(convId);
  if (state.splitView && state.activeConv && state.activeConv !== convId) {
    state.secondaryConv = state.activeConv;
  }
  state.activeConv = convId;
  if (state.secondaryConv === convId) state.secondaryConv = null;
  $('app').classList.add('viewing-chat');
  renderSidebar();
  renderTabs();
  renderActivePanel();
  // Pre-fetch the peer key so the first send doesn't have to wait on a
  // network round trip. Failures are non-fatal — sendMessage will retry.
  getSharedKeyForConv(convId).catch(() => {});
  await refreshMessages(convId);
}

function setActiveTab(convId) {
  if (state.splitView && state.activeConv && state.activeConv !== convId) {
    state.secondaryConv = state.activeConv;
  }
  state.activeConv = convId;
  if (state.secondaryConv === convId) state.secondaryConv = null;
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
    const r = await api(`/conversations/${target}/messages?limit=50`, { token: state.me.accessToken });
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
  const conv = state.conversations.find((c) => c.id === target);
  if (!conv) return;
  const peer = conv.members.find((m) => m.userId !== state.me.userId);
  const clientMessageId = 'web-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);

  // Encrypt the body with the per-peer derived AES-GCM key. The server only
  // ever sees `ciphertext` and `nonce`.
  const sharedKey = await getSharedKeyForConv(target);
  if (!sharedKey) {
    toast('상대 키를 찾지 못했어요. 잠시 후 다시 시도해주세요.', 'error');
    return;
  }
  const { ciphertext, nonce } = await encryptWithKey(sharedKey, text);

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
  };
  const list = state.messagesByConv.get(conv.id) || [];
  list.push(optimistic);
  state.messagesByConv.set(conv.id, list);
  textarea.value = '';
  textarea.style.height = 'auto';
  textarea.dispatchEvent(new Event('input'));
  emitTypingStop(target);
  renderActivePanel();

  try {
    const sent = await api('/messages', {
      method: 'POST',
      token: state.me.accessToken,
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
  if (!confirm('이 브라우저의 키를 전부 삭제합니다. 이 핸들로는 다시 로그인할 수 없어요.')) return;
  await session.wipe();
  await showAuth();
  toast('키를 삭제했습니다');
});

$('search-input').addEventListener('input', renderSidebar);

$('new-chat-btn').addEventListener('click', () => {
  $('new-peer-input').value = '';
  $('new-peer-error').textContent = '';
  $('new-chat-dialog').classList.remove('hidden');
  $('new-peer-input').focus();
});
$('new-cancel').addEventListener('click', () => $('new-chat-dialog').classList.add('hidden'));
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
    const r = await api('/conversations/direct', {
      method: 'POST',
      token: state.me.accessToken,
      body: { peerHandle: peer },
    });
    $('new-chat-dialog').classList.add('hidden');
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
  if (e.target.id === 'new-chat-dialog') $('new-chat-dialog').classList.add('hidden');
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
    if (confirm('로그아웃하고 이 브라우저의 키를 전부 삭제합니다.')) {
      await logout();
    }
  }
});

$('split-btn').addEventListener('click', toggleSplit);

bootIfSession();
