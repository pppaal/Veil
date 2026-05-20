// VEIL web demo client.
// Vanilla-JS chat shell that talks to the NestJS API at /v1 and the realtime
// gateway at /v1/realtime. Messages are end-to-end encrypted with X25519 ECDH
// + HKDF-SHA256 + AES-256-GCM (see deriveSharedAesKey / encryptWithKey). The
// server only ever sees ciphertext.

import { initI18n, t, setLang, activeLang } from './i18n/i18n.js';
import { escapeHtml, renderMessageInline } from './lib/markdown.js';
import {
  formatTime as fmtTime,
  dayKey as fmtDayKey,
  dayLabel as fmtDayLabel,
  formatBytes as fmtBytes,
} from './lib/format.js';
import { parseKakaoExport } from './lib/kakao-import.js';
import { buildAad } from './lib/aad.js';
// Initialize translations as early as possible so DOM static strings can be
// rewritten before the user sees them. Top-level await is supported in
// modules, which is exactly what this file is.
await initI18n();
// Expose for dev console + the lang switcher menu.
if (typeof window !== 'undefined') {
  window.__veilI18n = { t, setLang, activeLang };
}
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

// F-1 (internal-precheck-crypto-review.md): bind the sending device id
// to the AES-GCM tag via additionalData so a ciphertext can't be
// re-attributed to a different device. conversationId is already bound
// through the HKDF `info`; recipientUserId is omitted because group
// sends leave it empty and it isn't reliably present at every decrypt
// call site. Encrypt and decrypt build the AAD with the same pure
// buildAad() so there's no encode/decode mismatch.
async function encryptForConv(convId, plaintext) {
  const ctx = await getConvCryptoCtx(convId);
  if (!ctx) return null;
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const aesKey = await deriveAesKey(ctx.hkdfBase, nonce, ctx.info);
  const aad = buildAad({ conversationId: convId, senderDeviceId: state.me?.deviceId ?? '' });
  const ct = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: nonce, additionalData: aad },
    aesKey,
    new TextEncoder().encode(plaintext),
  );
  return { ciphertext: 'v2.' + b64uEncode(ct), nonce: b64uEncode(nonce) };
}

async function decryptFromConv(convId, ciphertext, nonceB64u, senderDeviceId) {
  if (!ciphertext?.startsWith('v2.')) return null;
  const ctx = await getConvCryptoCtx(convId);
  if (!ctx) return null;
  const nonceBuf = new Uint8Array(b64uDecode(nonceB64u));
  const ct = b64uDecode(ciphertext.slice(3));
  const aesKey = await deriveAesKey(ctx.hkdfBase, nonceBuf, ctx.info);
  // New path: messages encrypted with the F-1 AAD. We need the sender's
  // device id to rebuild the same AAD; it rides on the message envelope.
  if (senderDeviceId) {
    try {
      const aad = buildAad({ conversationId: convId, senderDeviceId });
      const pt = await crypto.subtle.decrypt(
        { name: 'AES-GCM', iv: nonceBuf, additionalData: aad },
        aesKey,
        ct,
      );
      return new TextDecoder().decode(pt);
    } catch {
      // fall through to the legacy (no-AAD) path below
    }
  }
  // Legacy / transition path: messages sent before F-1 carried no AAD.
  try {
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
  const pt = await decryptFromConv(msg.conversationId, ct, msg.nonce, msg.senderDeviceId);
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
  // Voice messages encode a JSON object with the audio bytes inline;
  // the regular text-payload unpack would render the raw JSON. Route
  // them through the voice materializer instead.
  if (msg.messageType === 'voice') {
    try {
      const payload = JSON.parse(typeof pt === 'string' ? pt : (pt?.text ?? ''));
      if (payload?.kind === 'voice' && payload.audio) {
        const bytes = b64uDecode(payload.audio);
        const blob = new Blob([bytes], { type: payload.mime || 'audio/webm' });
        msg._voiceUrl = URL.createObjectURL(blob);
        msg._plaintext = '🎤 음성';
        msg._replyTo = null;
        return;
      }
    } catch {}
  }
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
  // Phase AF: visual feedback class so the user notices a stuck
  // disconnect even when the pill text is small.
  pill.classList.remove('is-disconnected', 'is-connecting');
  if (kind === 'connecting' || kind === 'offline') pill.classList.add('is-connecting');
  if (kind === 'error' || kind === 'disconnected') pill.classList.add('is-disconnected');
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
  s.on('message.reaction', ({ messageId, userId, emoji, action }) => {
    onReactionEvent(messageId, userId, emoji, action);
  });
  s.on('message.edited', (msg) => onMessageEdited(msg));
  s.on('message.deleted', ({ messageId, deletedAt }) => {
    // Find the message first so we can release its blob URL before
    // we drop the references that point at it.
    for (const list of state.messagesByConv.values()) {
      const m = list.find((x) => x.id === messageId);
      if (m) { revokeBlobUrlsForMessage(m); break; }
    }
    patchMessage(messageId, { deletedAt, _plaintext: '🚫 삭제된 메시지' });
  });
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
  // Voice messages carry their audio bytes inline in the encrypted
  // payload. Reconstruct the playable blob URL once decryption lands.
  if (msg.messageType === 'voice') await maybeMaterializeVoice(msg, convId);
  // Image messages: fetch + decrypt the attachment ciphertext using
  // the per-attachment key inside the now-decrypted body.
  if (msg.messageType === 'image') maybeMaterializeImage(msg);
  // Phase AF: surface unread count in tab title + OS notification when
  // the tab is hidden. We only count peer messages, not our own echo.
  if (msg.senderDeviceId !== state.me?.deviceId) {
    bumpUnread();
    maybeShowNotification(msg);
  }
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
// v2 adds the kakao-archives store for Phase AS imports. Bumping the
// version triggers onupgradeneeded for existing users; we re-check
// every store and create only the missing ones, so old data
// (session, conversations, messages, outbound, drafts) survives.
const IDB_VERSION = 2;

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
      // Phase AS: KakaoTalk imported archives, read-only on this device.
      if (!db.objectStoreNames.contains('kakao-archives')) {
        db.createObjectStore('kakao-archives', { keyPath: 'id' });
      }
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
  conversationsLoaded: false,  // false until first /conversations response lands
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
  soundsEnabled: false,        // Phase AG: send/receive tones, persisted in localStorage
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
    // Phase AG: while we're still waiting on the first /conversations
    // response, show shimmering skeleton rows instead of the "no
    // conversations" empty state — the empty state would lie to the
    // user during the brief fetch window.
    if (!state.conversationsLoaded && !q) {
      list.replaceChildren(...renderConvSkeletons(4));
      return;
    }
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
    if (msgOrCiphertext._voiceUrl) {
      return el('audio', {
        controls: 'controls',
        src: msgOrCiphertext._voiceUrl,
        preload: 'metadata',
        style: 'max-width: 240px; height: 32px; vertical-align: middle;',
      });
    }
    if (msgOrCiphertext._imageUrl) {
      const wrap = document.createElement('span');
      const img = document.createElement('img');
      img.className = 'msg-inline-image';
      img.src = msgOrCiphertext._imageUrl;
      img.alt = 'image';
      img.onclick = (e) => { e.stopPropagation(); openImageZoom(msgOrCiphertext._imageUrl); };
      wrap.appendChild(img);
      if (msgOrCiphertext._plaintext && msgOrCiphertext._plaintext !== '🖼 이미지') {
        const cap = document.createElement('div');
        cap.style.marginTop = '4px';
        cap.innerHTML = renderMessageInline(msgOrCiphertext._plaintext);
        wrap.appendChild(cap);
      }
      return wrap;
    }
    if (msgOrCiphertext._plaintext != null) {
      // Phase AF: minimal markdown + URL auto-link. Returned as a
      // detached <span> so the caller appends it as a single child.
      const span = document.createElement('span');
      span.innerHTML = renderMessageInline(msgOrCiphertext._plaintext);
      return span;
    }
    return '🔒 암호화됨';
  }
  // Rare callers passing a raw ciphertext string instead of a message object.
  const ct = msgOrCiphertext;
  if (ct.startsWith('v1.')) return '🔒 암호화됨';
  return ct;
}

// Date format helpers live in apps/web-demo/lib/format.js so vitest
// can hit the same source the runtime does. Locale-aware via
// activeLang() — Phase AA i18n harness picks the user's choice from
// localStorage / navigator.language and lib/format.js renders the
// right token (오늘 / today / 今日, AM/PM / 오전·오후 / 午前·午後).
function formatRelTime(iso) {
  const d = new Date(iso);
  const now = new Date();
  const sameDay = d.toDateString() === now.toDateString();
  const lang = (typeof activeLang === 'function' ? activeLang() : 'ko');
  if (sameDay) return fmtTime(d, lang);
  return fmtDayLabel(d, lang, now);
}
const formatTime = (d) => fmtTime(d, typeof activeLang === 'function' ? activeLang() : 'ko');
const dayKey = fmtDayKey;
const dayLabel = (d) => fmtDayLabel(d, typeof activeLang === 'function' ? activeLang() : 'ko');

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
        emptyStateSvg('chat'),
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
        if (m.deletedAt) cls.push('msg-deleted-bubble');
        const editedBadge = m.editedAt
          ? el('span', { class: 'msg-edited', style: 'opacity:0.55;font-size:11px;margin-left:6px' }, ['(수정됨)'])
          : null;
        const bubble = el('div', { class: cls.join(' ') }, [
          replyHead,
          el('span', { class: 'msg-text' }, [renderPreview(m)]),
          editedBadge,
        ]);
        const reactionsRow = (m.reactions && m.reactions.length > 0)
          ? renderReactionsRow(m, convId)
          : null;
        const wrap = el('div', { class: 'msg-row ' + (group.isMe ? 'me' : 'them') }, [
          group.isMe ? replyBtn : null,
          el('div', { class: 'msg-bubble-stack' }, [bubble, reactionsRow]),
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
        emptyStateSvg('wave'),
        el('div', { class: 'empty-title' }, ['첫 메시지를 보내보세요']),
        el('div', { class: 'empty-sub' }, ['이 대화의 메시지는 두 사람 외에는 아무도 못 봐요']),
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
  const voiceBtn = el(
    'button',
    {
      class: 'voice-btn',
      'aria-label': '음성 메시지',
      title: '꾹 눌러 녹음',
      onmousedown: (e) => { e.preventDefault(); startVoiceRecord(convId, voiceBtn); },
      onmouseup: () => stopVoiceRecord(convId, voiceBtn),
      onmouseleave: () => cancelVoiceRecord(voiceBtn),
      ontouchstart: (e) => { e.preventDefault(); startVoiceRecord(convId, voiceBtn); },
      ontouchend: () => stopVoiceRecord(convId, voiceBtn),
    },
    [el('span', { 'aria-hidden': 'true' }, ['🎤'])],
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

  const searchBar = renderPanelSearch(convId);
  const panelNode = el('div', { class: 'panel', dataset: { conv: convId } }, [
    el('div', { class: 'panel-header' }, [
      headerAvatar,
      el('div', { class: 'panel-title' }, [
        el('div', { class: 'name' }, ['@' + (peer?.handle ?? '?')]),
        el('div', { class: subClass }, [subText]),
      ]),
      el(
        'button',
        {
          class: 'icon-btn',
          'aria-label': '대화에서 찾기 (Ctrl/Cmd+F)',
          title: '대화에서 찾기',
          onclick: () => openPanelSearch(convId),
          style: 'padding: 4px 8px; opacity: 0.7;',
        },
        ['🔍'],
      ),
    ]),
    searchBar,
    msgsNode,
    el('div', { class: 'panel-input-wrap' }, [
      replyBanner,
      el('div', { class: 'panel-input' }, [textarea, voiceBtn, sendBtn]),
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
    state.conversationsLoaded = true;
    // Phase AK: drop search state for conversations that no longer
    // exist. Keeps the Map bounded over long sessions.
    if (typeof searchStateByConv !== 'undefined') {
      const live = new Set(state.conversations.map((c) => c.id));
      for (const cid of Array.from(searchStateByConv.keys())) {
        if (!live.has(cid)) searchStateByConv.delete(cid);
      }
    }
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
  playSendTone();
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

// Phase AK: revoke any blob: URLs we created for voice/image so the
// browser actually frees the underlying memory. Without this, the
// Blob bytes stay alive for the page's lifetime even after the user
// logs out or deletes the message.
function revokeBlobUrlsForMessage(msg) {
  if (msg?._voiceUrl?.startsWith('blob:')) {
    try { URL.revokeObjectURL(msg._voiceUrl); } catch {}
    msg._voiceUrl = null;
  }
  if (msg?._imageUrl?.startsWith('blob:')) {
    try { URL.revokeObjectURL(msg._imageUrl); } catch {}
    msg._imageUrl = null;
  }
}
function revokeAllBlobUrls() {
  for (const list of state.messagesByConv.values()) {
    for (const msg of list) revokeBlobUrlsForMessage(msg);
  }
}

async function logout() {
  await session.wipe();
  revokeAllBlobUrls();
  state.me = null;
  state.conversations = [];
  state.conversationsLoaded = false;
  state.messagesByConv.clear();
  state.activeConv = null;
  state.secondaryConv = null;
  state.openTabs = [];
  state.splitView = false;
  searchStateByConv.clear();
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

// ---------- message actions: react / edit / delete ----------
// Right-click (or long-press on touch) on a .msg-row pops a small menu.
// Reactions go through the existing /messages/:id/reactions endpoints
// (server already had those). Edit re-encrypts the body in place via
// PATCH /messages/:id; Delete tombstones server-side via DELETE.
const QUICK_REACTIONS = ['👍', '❤️', '😂', '😢', '🔥', '🎉'];

const msgActionStyles = document.createElement('style');
msgActionStyles.textContent = `
  .msg-action-menu {
    position: fixed; z-index: 1000;
    background: #1c1d22; border: 1px solid rgba(255,255,255,0.12);
    border-radius: 12px; padding: 6px;
    box-shadow: 0 12px 32px rgba(0,0,0,0.4);
    display: flex; flex-direction: column; min-width: 160px;
  }
  .msg-action-row { display: flex; gap: 4px; padding: 4px 6px; }
  .msg-action-row button {
    background: transparent; border: 0; color: inherit; cursor: pointer;
    font-size: 20px; padding: 4px 8px; border-radius: 8px;
  }
  .msg-action-row button:hover { background: rgba(255,255,255,0.08); }
  .msg-action-item {
    background: transparent; border: 0; color: inherit; cursor: pointer;
    text-align: left; padding: 8px 12px; border-radius: 8px; font-size: 14px;
  }
  .msg-action-item:hover { background: rgba(255,255,255,0.08); }
  .msg-action-item.danger { color: #ff7676; }
  .msg-action-divider { height: 1px; background: rgba(255,255,255,0.08); margin: 4px 0; }
  .msg-edit-input {
    background: rgba(255,255,255,0.04); color: inherit;
    border: 1px solid rgba(255,255,255,0.12); border-radius: 8px;
    padding: 8px; font-size: 14px; width: 100%; resize: vertical;
    min-height: 60px; box-sizing: border-box;
  }
  .msg-reactions {
    display: flex; gap: 4px; flex-wrap: wrap; margin-top: 4px;
    padding: 0 8px;
  }
  .msg-reaction-chip {
    display: inline-flex; align-items: center; gap: 3px;
    background: rgba(255,255,255,0.08); border-radius: 12px;
    padding: 2px 8px; font-size: 12px; cursor: pointer;
    border: 1px solid transparent;
  }
  .msg-reaction-chip.mine { border-color: rgba(108,142,255,0.4); background: rgba(108,142,255,0.15); }
  .msg-deleted-bubble { opacity: 0.5; font-style: italic; }
`;
document.head.appendChild(msgActionStyles);

let activeActionMenu = null;
function closeActionMenu() {
  if (activeActionMenu) { activeActionMenu.remove(); activeActionMenu = null; }
}
document.addEventListener('click', closeActionMenu);
document.addEventListener('scroll', closeActionMenu, true);

function openActionMenu(x, y, msg, convId) {
  closeActionMenu();
  const isMine = msg.senderDeviceId === state.me?.deviceId;
  const isDeleted = !!msg.deletedAt;
  if (isDeleted) return; // No actions on tombstones.

  const menu = document.createElement('div');
  menu.className = 'msg-action-menu';
  menu.style.left = Math.min(x, window.innerWidth - 200) + 'px';
  menu.style.top = Math.min(y, window.innerHeight - 240) + 'px';

  const reactRow = document.createElement('div');
  reactRow.className = 'msg-action-row';
  for (const e of QUICK_REACTIONS) {
    const b = document.createElement('button');
    b.textContent = e;
    b.title = '반응 추가';
    b.addEventListener('click', (ev) => {
      ev.stopPropagation();
      doReaction(msg.id, e);
      closeActionMenu();
    });
    reactRow.appendChild(b);
  }
  menu.appendChild(reactRow);
  menu.appendChild(Object.assign(document.createElement('div'), { className: 'msg-action-divider' }));

  const replyItem = document.createElement('button');
  replyItem.className = 'msg-action-item';
  replyItem.textContent = '↩  답장';
  replyItem.addEventListener('click', (ev) => {
    ev.stopPropagation(); startReply(convId, msg); closeActionMenu();
  });
  menu.appendChild(replyItem);

  if (msg._plaintext) {
    const copyItem = document.createElement('button');
    copyItem.className = 'msg-action-item';
    copyItem.textContent = '📋  복사';
    copyItem.addEventListener('click', async (ev) => {
      ev.stopPropagation();
      try { await navigator.clipboard.writeText(msg._plaintext); toast('복사됨', 'good'); }
      catch { toast('클립보드 접근 실패', 'error'); }
      closeActionMenu();
    });
    menu.appendChild(copyItem);
  }

  if (isMine && !msg.id?.startsWith('__pending__')) {
    const editItem = document.createElement('button');
    editItem.className = 'msg-action-item';
    editItem.textContent = '✏️  수정';
    editItem.addEventListener('click', (ev) => {
      ev.stopPropagation(); startEdit(msg, convId); closeActionMenu();
    });
    menu.appendChild(editItem);

    const delItem = document.createElement('button');
    delItem.className = 'msg-action-item danger';
    delItem.textContent = '🗑  삭제';
    delItem.addEventListener('click', async (ev) => {
      ev.stopPropagation(); closeActionMenu();
      const ok = await uiConfirm({
        title: '메시지 삭제',
        body: '이 메시지를 삭제합니다. 상대방 화면에서도 삭제 표시로 바뀌어요.',
        okLabel: '삭제', destructive: true,
      });
      if (!ok) return;
      doDelete(msg.id);
    });
    menu.appendChild(delItem);
  }

  document.body.appendChild(menu);
  activeActionMenu = menu;
}

document.addEventListener('contextmenu', (e) => {
  const row = e.target.closest('.msg-row');
  if (!row?.dataset?.msgId) return;
  e.preventDefault();
  const convId = row.closest('.panel')?.dataset?.conv;
  if (!convId) return;
  const msg = (state.messagesByConv.get(convId) || []).find((m) => m.id === row.dataset.msgId);
  if (msg) openActionMenu(e.clientX, e.clientY, msg, convId);
});

let touchHoldTimer = null;
document.addEventListener('touchstart', (e) => {
  const row = e.target.closest('.msg-row');
  if (!row?.dataset?.msgId) return;
  const convId = row.closest('.panel')?.dataset?.conv;
  if (!convId) return;
  const msg = (state.messagesByConv.get(convId) || []).find((m) => m.id === row.dataset.msgId);
  if (!msg) return;
  const t = e.touches[0];
  touchHoldTimer = setTimeout(() => openActionMenu(t.clientX, t.clientY, msg, convId), 500);
}, { passive: true });
document.addEventListener('touchend', () => { clearTimeout(touchHoldTimer); }, { passive: true });
document.addEventListener('touchmove', () => { clearTimeout(touchHoldTimer); }, { passive: true });

async function doReaction(messageId, emoji) {
  try {
    const list = (() => {
      for (const l of state.messagesByConv.values()) {
        const m = l.find((x) => x.id === messageId);
        if (m) return { msg: m };
      }
      return null;
    })();
    const mine = list?.msg?.reactions?.find((r) => r.userId === state.me.userId);
    const sameAsMine = mine?.emoji === emoji;
    if (sameAsMine) {
      await authedApi(`/messages/${messageId}/reactions`, { method: 'DELETE' });
    } else {
      await authedApi(`/messages/${messageId}/reactions`, { method: 'POST', body: { emoji } });
    }
  } catch (e) {
    toast('반응 실패: ' + e.message, 'error');
  }
}

function onReactionEvent(messageId, userId, emoji, action) {
  for (const list of state.messagesByConv.values()) {
    const m = list.find((x) => x.id === messageId);
    if (!m) continue;
    m.reactions = m.reactions || [];
    const idx = m.reactions.findIndex((r) => r.userId === userId);
    if (action === 'remove') {
      if (idx >= 0) m.reactions.splice(idx, 1);
    } else {
      if (idx >= 0) m.reactions[idx].emoji = emoji;
      else m.reactions.push({ userId, emoji });
    }
    renderActivePanel();
    return;
  }
}

function startEdit(msg, convId) {
  const text = msg._plaintext;
  if (typeof text !== 'string') {
    toast('이 메시지는 수정할 수 없어요', 'error');
    return;
  }
  const fresh = window.prompt('메시지 수정', text);
  if (fresh == null) return;
  const trimmed = fresh.trim();
  if (!trimmed || trimmed === text) return;
  doEdit(msg, convId, trimmed);
}

async function doEdit(msg, convId, newText) {
  try {
    const envelope = await encryptForConv(convId, packPayload(newText, msg._replyTo ?? null));
    if (!envelope) { toast('재암호화 실패', 'error'); return; }
    await authedApi(`/messages/${msg.id}`, {
      method: 'PATCH',
      body: {
        ciphertext: envelope.ciphertext,
        nonce: envelope.nonce,
        version: 'veil-envelope-v1-dev',
      },
    });
    msg._plaintext = newText;
    msg.editedAt = new Date().toISOString();
    msg.editCount = (msg.editCount || 0) + 1;
    renderActivePanel();
  } catch (e) {
    toast('수정 실패: ' + e.message, 'error');
  }
}

async function onMessageEdited(serverMsg) {
  for (const [convId, list] of state.messagesByConv) {
    const idx = list.findIndex((m) => m.id === serverMsg.id);
    if (idx < 0) continue;
    const local = list[idx];
    // Re-decrypt the new ciphertext into a plaintext we can render.
    let plaintext = null;
    try {
      plaintext = await decryptFromConv(convId, serverMsg.ciphertext, serverMsg.nonce, serverMsg.senderDeviceId);
    } catch {}
    list[idx] = {
      ...local,
      ciphertext: serverMsg.ciphertext,
      nonce: serverMsg.nonce,
      editedAt: serverMsg.editedAt,
      editCount: serverMsg.editCount,
      _plaintext: plaintext != null
        ? (typeof plaintext === 'object' && plaintext.text != null ? plaintext.text : String(plaintext))
        : local._plaintext,
    };
    if (convId === state.activeConv || convId === state.secondaryConv) renderActivePanel();
    return;
  }
}

async function doDelete(messageId) {
  try {
    await authedApi(`/messages/${messageId}`, { method: 'DELETE' });
  } catch (e) {
    toast('삭제 실패: ' + e.message, 'error');
  }
}

// Bubble reactions row — groups by emoji, shows count, my own reactions
// get a highlighted border. Click toggles via the same /reactions endpoint
// the action menu uses, so the picker and the chip share state.
function renderReactionsRow(msg, convId) {
  const tally = new Map();
  for (const r of msg.reactions || []) {
    const entry = tally.get(r.emoji) || { count: 0, mine: false };
    entry.count += 1;
    if (r.userId === state.me?.userId) entry.mine = true;
    tally.set(r.emoji, entry);
  }
  if (tally.size === 0) return null;
  const row = el('div', { class: 'msg-reactions' });
  for (const [emoji, entry] of tally) {
    const chip = el(
      'span',
      {
        class: 'msg-reaction-chip' + (entry.mine ? ' mine' : ''),
        title: entry.mine ? '내 반응 — 클릭해서 취소' : '같이 반응하기',
        onclick: (e) => { e.stopPropagation(); doReaction(msg.id, emoji); },
      },
      [emoji + ' ' + entry.count],
    );
    row.appendChild(chip);
  }
  return row;
}

// ---------- voice messages ----------
// Push-to-talk: hold the mic button to record, release to send.
// MediaRecorder produces opus/webm at the lowest bitrate the browser
// will give us (defaults are usually 32-48 kbps mono for opus). The
// bytes are b64-wrapped into the existing per-conversation AES-GCM
// envelope so the server only ever sees ciphertext, identical to the
// text path. Server-side ciphertext cap was bumped to 128 KB to fit
// ~30 s of voice without forcing the attachment-upload flow.
const VOICE_MAX_MS = 30_000;
const VOICE_MAX_CIPHERTEXT_LEN = 128 * 1024;

const voiceStyles = document.createElement('style');
voiceStyles.textContent = `
  .voice-btn {
    background: transparent; border: 0; color: inherit;
    cursor: pointer; font-size: 18px; padding: 0 8px;
    user-select: none; -webkit-user-select: none;
  }
  .voice-btn:hover { color: var(--accent, #6c8eff); }
  .voice-btn.recording {
    background: rgba(255, 80, 80, 0.18); border-radius: 50%;
    animation: voice-pulse 1.2s ease-in-out infinite;
  }
  @keyframes voice-pulse {
    0%, 100% { box-shadow: 0 0 0 0 rgba(255, 80, 80, 0.6); }
    50% { box-shadow: 0 0 0 8px rgba(255, 80, 80, 0); }
  }
  .voice-recording-indicator {
    position: fixed; left: 50%; top: 16px; transform: translateX(-50%);
    background: #1c1d22; color: #fff; padding: 6px 14px;
    border-radius: 999px; font-size: 13px; z-index: 1100;
    border: 1px solid rgba(255,255,255,0.12);
  }
`;
document.head.appendChild(voiceStyles);

let voiceState = null;
function makeIndicator() {
  const node = document.createElement('div');
  node.className = 'voice-recording-indicator';
  node.textContent = '🔴 녹음 중… 손을 떼면 전송';
  document.body.appendChild(node);
  return node;
}

async function startVoiceRecord(convId, btn) {
  if (voiceState) return;
  if (!navigator.mediaDevices?.getUserMedia) {
    toast('이 브라우저에서 녹음 미지원', 'error');
    return;
  }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
        channelCount: 1,
      },
    });
    const mimeType = pickVoiceMime();
    const recorder = new MediaRecorder(stream, mimeType ? { mimeType, audioBitsPerSecond: 32_000 } : undefined);
    const chunks = [];
    recorder.ondataavailable = (e) => { if (e.data?.size) chunks.push(e.data); };
    const indicator = makeIndicator();
    btn.classList.add('recording');
    voiceState = {
      convId, stream, recorder, chunks, indicator, btn,
      startedAt: Date.now(), canceled: false, deadline: null,
    };
    recorder.onstop = async () => finalizeVoiceRecord();
    recorder.start();
    voiceState.deadline = setTimeout(() => stopVoiceRecord(convId, btn), VOICE_MAX_MS);
  } catch (e) {
    toast('마이크 권한 필요: ' + (e.message || 'unknown'), 'error');
  }
}

function pickVoiceMime() {
  const candidates = ['audio/webm;codecs=opus', 'audio/webm', 'audio/ogg;codecs=opus', 'audio/mp4'];
  for (const m of candidates) {
    if (typeof MediaRecorder !== 'undefined' && MediaRecorder.isTypeSupported?.(m)) return m;
  }
  return undefined;
}

function stopVoiceRecord(convId, btn) {
  if (!voiceState || voiceState.canceled) return;
  if (voiceState.recorder.state === 'inactive') return;
  // Too short — treat as cancel.
  if (Date.now() - voiceState.startedAt < 400) {
    cancelVoiceRecord(btn);
    return;
  }
  if (voiceState.deadline) { clearTimeout(voiceState.deadline); voiceState.deadline = null; }
  voiceState.recorder.stop();
}

function cancelVoiceRecord(btn) {
  if (!voiceState) return;
  voiceState.canceled = true;
  if (voiceState.deadline) { clearTimeout(voiceState.deadline); voiceState.deadline = null; }
  try { voiceState.recorder.stop(); } catch {}
  cleanupVoiceState();
}

function cleanupVoiceState() {
  if (!voiceState) return;
  try { voiceState.stream.getTracks().forEach((t) => t.stop()); } catch {}
  try { voiceState.indicator.remove(); } catch {}
  voiceState.btn?.classList.remove('recording');
  voiceState = null;
}

async function finalizeVoiceRecord() {
  if (!voiceState || voiceState.canceled) {
    cleanupVoiceState();
    return;
  }
  const { convId, chunks } = voiceState;
  const mime = voiceState.recorder.mimeType || 'audio/webm';
  const blob = new Blob(chunks, { type: mime });
  cleanupVoiceState();
  if (blob.size === 0) return;

  // Build a small JSON payload so the receiver can rebuild the audio
  // blob without a separate metadata channel.
  const buf = await blob.arrayBuffer();
  const payload = {
    kind: 'voice',
    mime,
    durationMs: Math.min(VOICE_MAX_MS, Date.now() - (Date.now() - VOICE_MAX_MS)), // best effort
    audio: b64uEncode(buf),
  };
  const envelope = await encryptForConv(convId, JSON.stringify(payload));
  if (!envelope) { toast('상대 키 누락 — 전송 실패', 'error'); return; }
  if (envelope.ciphertext.length > VOICE_MAX_CIPHERTEXT_LEN) {
    toast('녹음이 너무 깁니다. 더 짧게 시도하세요.', 'error');
    return;
  }

  const conv = state.conversations.find((c) => c.id === convId);
  if (!conv) return;
  const peer = conv.members.find((m) => m.userId !== state.me.userId);
  const clientMessageId = 'voice-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);

  // Optimistic insert.
  const optimistic = {
    id: '__pending__' + clientMessageId,
    clientMessageId,
    conversationId: convId,
    senderDeviceId: state.me.deviceId,
    ciphertext: envelope.ciphertext,
    nonce: envelope.nonce,
    messageType: 'voice',
    serverReceivedAt: null,
    _localAt: new Date().toISOString(),
    _status: 'pending',
    _voiceUrl: URL.createObjectURL(blob),
  };
  const list = state.messagesByConv.get(convId) || [];
  list.push(optimistic);
  state.messagesByConv.set(convId, list);
  renderActivePanel();

  try {
    const sent = await authedApi('/messages', {
      method: 'POST',
      body: {
        conversationId: convId,
        clientMessageId,
        envelope: {
          version: 'veil-envelope-v1-dev',
          conversationId: convId,
          senderDeviceId: state.me.deviceId,
          recipientUserId: peer.userId,
          ciphertext: envelope.ciphertext,
          nonce: envelope.nonce,
          messageType: 'voice',
        },
      },
    });
    sent.message._voiceUrl = optimistic._voiceUrl;
    const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
    if (idx >= 0) list[idx] = sent.message;
    conv.lastMessage = sent.message;
    persistMessage(sent.message);
    persistConversation(conv);
    renderActivePanel();
    renderSidebar();
  } catch (e) {
    toast('음성 전송 실패: ' + e.message, 'error');
    const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
    if (idx >= 0) list[idx] = { ...list[idx], _status: 'failed' };
    renderActivePanel();
  }
}

// On receive of a voice message, decrypt the JSON payload and rebuild
// the audio blob so renderPreview can drop it into an <audio> tag.
async function maybeMaterializeVoice(msg, convId) {
  if (msg.messageType !== 'voice') return;
  if (msg._voiceUrl) return;
  try {
    const decrypted = await decryptFromConv(convId, msg.ciphertext, msg.nonce, msg.senderDeviceId);
    const text = typeof decrypted === 'string' ? decrypted : decrypted?.text;
    if (!text) return;
    const payload = JSON.parse(text);
    if (payload?.kind !== 'voice' || !payload.audio) return;
    const bytes = b64uDecode(payload.audio);
    const blob = new Blob([bytes], { type: payload.mime || 'audio/webm' });
    msg._voiceUrl = URL.createObjectURL(blob);
    if (convId === state.activeConv || convId === state.secondaryConv) renderActivePanel();
  } catch {}
}

// Voice ingestion is hooked at the call site inside onMessageNew —
// no wrapper required. See `if (msg.messageType === 'voice')` above.

// ---------- polish: notifications + tab badge + link detection + markdown ----------

const polishStyles = document.createElement('style');
polishStyles.textContent = `
  /* Polished link rendering inside messages */
  .msg-text a {
    color: var(--accent, #6c8eff);
    text-decoration: underline;
    text-underline-offset: 2px;
    word-break: break-all;
  }
  .msg-text a:hover { color: var(--accent-strong, #9bb3ff); }

  /* Inline code + bold/italic from minimal markdown */
  .msg-text code {
    background: rgba(255,255,255,0.08);
    padding: 1px 5px;
    border-radius: 4px;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 0.92em;
  }
  .msg-text strong { font-weight: 600; }
  .msg-text em { font-style: italic; opacity: 0.95; }

  /* Refined empty-state SVG container */
  .empty-svg {
    width: 96px;
    height: 96px;
    opacity: 0.55;
    margin-bottom: 4px;
  }

  /* Notification permission banner */
  .notif-prompt {
    display: flex;
    align-items: center;
    gap: 10px;
    background: rgba(108, 142, 255, 0.08);
    border: 1px solid rgba(108, 142, 255, 0.18);
    border-radius: 10px;
    padding: 10px 12px;
    margin: 8px;
    font-size: 13px;
  }
  .notif-prompt button {
    background: var(--accent, #6c8eff);
    border: 0;
    color: white;
    padding: 5px 12px;
    border-radius: 6px;
    cursor: pointer;
    font-size: 12px;
  }
  .notif-prompt .dismiss {
    background: transparent;
    color: inherit;
    opacity: 0.7;
    padding: 5px 8px;
  }

  /* Better connection pill with retry indicator */
  #conn-pill { transition: background-color 0.2s ease; }
  #conn-pill.is-disconnected {
    background: rgba(255, 80, 80, 0.18);
    color: #ffb3b3;
  }
  #conn-pill.is-connecting {
    background: rgba(255, 180, 80, 0.18);
    color: #ffd9a3;
  }

  /* Loading skeleton for sidebar while conversations are fetching */
  .conv-skeleton {
    display: flex;
    gap: 10px;
    padding: 10px 12px;
    align-items: center;
  }
  .conv-skeleton-avatar {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background: linear-gradient(90deg, rgba(255,255,255,0.04) 25%, rgba(255,255,255,0.08) 50%, rgba(255,255,255,0.04) 75%);
    background-size: 200% 100%;
    animation: skeleton-shimmer 1.4s infinite;
  }
  .conv-skeleton-line {
    height: 10px;
    border-radius: 4px;
    background: linear-gradient(90deg, rgba(255,255,255,0.04) 25%, rgba(255,255,255,0.08) 50%, rgba(255,255,255,0.04) 75%);
    background-size: 200% 100%;
    animation: skeleton-shimmer 1.4s infinite;
    margin-bottom: 6px;
  }
  .conv-skeleton-line.w-60 { width: 60%; }
  .conv-skeleton-line.w-40 { width: 40%; }
  @keyframes skeleton-shimmer {
    0% { background-position: 200% 0; }
    100% { background-position: -200% 0; }
  }

  /* Inline image preview inside bubble */
  .msg-inline-image {
    max-width: 280px;
    max-height: 320px;
    border-radius: 10px;
    margin-top: 4px;
    cursor: zoom-in;
    display: block;
  }
  .image-zoom-backdrop {
    position: fixed; inset: 0;
    background: rgba(0,0,0,0.85);
    z-index: 1500;
    display: flex; align-items: center; justify-content: center;
    cursor: zoom-out;
  }
  .image-zoom-backdrop img {
    max-width: 92vw;
    max-height: 92vh;
    border-radius: 6px;
  }
`;
document.head.appendChild(polishStyles);

// Markdown lite + mention chip rendering live in apps/web-demo/lib/
// markdown.js. Vitest tests them in __tests__/markdown.test.js — the
// same source of truth the app uses, so divergence is impossible.

// Patch renderPreview so message text gets formatted markup. We keep the
// non-string fast paths (audio blob, '🔒 …' fallbacks) intact.
// (Implementation patched at the call site below — globalThis re-bind
// doesn't reach module-local references.)

function openImageZoom(url) {
  const back = document.createElement('div');
  back.className = 'image-zoom-backdrop';
  const img = document.createElement('img');
  img.src = url;
  back.appendChild(img);
  back.addEventListener('click', () => back.remove());
  document.body.appendChild(back);
}

// SVG empty-state illustrations. Two variants: a chat bubble cluster
// for "no conversation selected" and a wave for "no messages yet".
// Inline so we don't add an extra HTTP request and so the colors
// inherit from the theme via currentColor.
function emptyStateSvg(kind) {
  const wrap = document.createElement('div');
  wrap.className = 'empty-svg';
  const svgNs = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(svgNs, 'svg');
  svg.setAttribute('viewBox', '0 0 96 96');
  svg.setAttribute('width', '96');
  svg.setAttribute('height', '96');
  svg.setAttribute('fill', 'none');
  svg.setAttribute('stroke', 'currentColor');
  svg.setAttribute('stroke-width', '2');
  svg.setAttribute('stroke-linecap', 'round');
  svg.setAttribute('stroke-linejoin', 'round');
  if (kind === 'chat') {
    // Two overlapping rounded rectangles + dots.
    const r1 = document.createElementNS(svgNs, 'rect');
    r1.setAttribute('x', '14'); r1.setAttribute('y', '20');
    r1.setAttribute('width', '50'); r1.setAttribute('height', '34');
    r1.setAttribute('rx', '8');
    svg.appendChild(r1);
    const r2 = document.createElementNS(svgNs, 'rect');
    r2.setAttribute('x', '34'); r2.setAttribute('y', '40');
    r2.setAttribute('width', '50'); r2.setAttribute('height', '34');
    r2.setAttribute('rx', '8');
    r2.setAttribute('opacity', '0.6');
    svg.appendChild(r2);
    [29, 39, 49].forEach((cx) => {
      const c = document.createElementNS(svgNs, 'circle');
      c.setAttribute('cx', String(cx)); c.setAttribute('cy', '37'); c.setAttribute('r', '1.5');
      c.setAttribute('fill', 'currentColor'); c.setAttribute('stroke', 'none');
      svg.appendChild(c);
    });
  } else {
    // Wave + chat bubble outline for "first message" empty.
    const path = document.createElementNS(svgNs, 'path');
    path.setAttribute('d', 'M14 60 Q 28 48 42 60 T 70 60 T 82 60');
    path.setAttribute('opacity', '0.7');
    svg.appendChild(path);
    const bubble = document.createElementNS(svgNs, 'path');
    bubble.setAttribute(
      'd',
      'M22 18 H 74 A 8 8 0 0 1 82 26 V 42 A 8 8 0 0 1 74 50 H 42 L 32 60 V 50 H 22 A 8 8 0 0 1 14 42 V 26 A 8 8 0 0 1 22 18 Z',
    );
    svg.appendChild(bubble);
    [32, 44, 56, 68].forEach((cx) => {
      const c = document.createElementNS(svgNs, 'circle');
      c.setAttribute('cx', String(cx)); c.setAttribute('cy', '34'); c.setAttribute('r', '1.5');
      c.setAttribute('fill', 'currentColor'); c.setAttribute('stroke', 'none');
      svg.appendChild(c);
    });
  }
  wrap.appendChild(svg);
  return wrap;
}

// --- Browser notifications + tab badge.
// Native Notifications API for OS-level alerts when the tab is hidden.
// Tab title shows an unread count; clears when the tab regains focus.

let unreadCount = 0;
let notifPromptDismissed = false;
const NOTIF_DISMISS_KEY = 'veil-demo-notif-prompt-dismissed-v1';
try { notifPromptDismissed = localStorage.getItem(NOTIF_DISMISS_KEY) === '1'; } catch {}

function updateTabBadge() {
  const base = document.title.replace(/^\(\d+\)\s*/, '').replace(/^VEIL$/, 'VEIL');
  document.title = unreadCount > 0 ? `(${unreadCount}) ${base.replace(/^\(\d+\)\s*/, '')}` : 'VEIL';
}

function bumpUnread() {
  if (document.visibilityState === 'visible') return;
  unreadCount += 1;
  updateTabBadge();
}

document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'visible') {
    unreadCount = 0;
    updateTabBadge();
  }
});

function maybeShowNotification(msg) {
  if (document.visibilityState === 'visible') return;
  if (!('Notification' in window)) return;
  if (Notification.permission !== 'granted') return;
  // Sender visible when we know it locally.
  const conv = state.conversations.find((c) => c.id === msg.conversationId);
  const peer = conv?.members?.find((m) => m.userId !== state.me?.userId);
  const title = peer?.handle ? `@${peer.handle}` : 'VEIL';
  // Body is the decrypted plaintext IFF we already have it locally —
  // otherwise we say "new encrypted message" to avoid faking content.
  // Plaintext that DOES surface here lives only in the user's own browser
  // notification system; the server still never sees it.
  const body = typeof msg._plaintext === 'string' && msg._plaintext.length > 0
    ? (msg._plaintext.length > 120 ? msg._plaintext.slice(0, 120) + '…' : msg._plaintext)
    : '🔒 새 암호화 메시지';
  try {
    const n = new Notification(title, {
      body,
      icon: './icon.svg',
      tag: 'veil-' + msg.conversationId,
      silent: false,
    });
    n.onclick = () => {
      window.focus();
      if (msg.conversationId) state.activeConv = msg.conversationId;
      try { n.close(); } catch {}
      if (typeof renderActivePanel === 'function') renderActivePanel();
    };
  } catch {}
}

function ensureNotifPrompt() {
  if (notifPromptDismissed) return;
  if (!('Notification' in window)) return;
  if (Notification.permission !== 'default') return;
  if (!state.me) return; // only after auth
  if (document.querySelector('.notif-prompt')) return;
  const sidebar = document.getElementById('sidebar');
  if (!sidebar) return;
  const node = document.createElement('div');
  node.className = 'notif-prompt';
  node.innerHTML = `
    <span style="flex:1;line-height:1.4">알림 켤까요?<br><span style="opacity:0.7;font-size:11px">백그라운드에서도 새 메시지를 알려요.</span></span>
    <button class="enable">켜기</button>
    <button class="dismiss">나중에</button>
  `;
  node.querySelector('.enable').addEventListener('click', async () => {
    try {
      const result = await Notification.requestPermission();
      if (result === 'granted') {
        toast('알림 켜짐', 'good');
      } else {
        toast('알림 거부됨', 'error');
      }
    } catch {}
    node.remove();
  });
  node.querySelector('.dismiss').addEventListener('click', () => {
    notifPromptDismissed = true;
    try { localStorage.setItem(NOTIF_DISMISS_KEY, '1'); } catch {}
    node.remove();
  });
  sidebar.insertBefore(node, sidebar.firstChild);
}
// Poll every 2s to inject the prompt once the user has authenticated.
setInterval(ensureNotifPrompt, 2000);

// onMessageNew gets the unread bump + notification call inline at its
// existing call site (search for "if (msg.messageType === 'voice')").
// setConnPill: we replace by patching the function body directly below.

// ---------- Phase AG: skeleton + sounds + shortcuts + help + a11y ----------

const agStyles = document.createElement('style');
agStyles.textContent = `
  /* Skeleton row in sidebar before first /conversations response. */
  .conv-skeleton-text { flex: 1; }

  /* Help / shortcuts dialog body */
  .help-grid {
    display: grid;
    grid-template-columns: max-content 1fr;
    gap: 8px 16px;
    font-size: 13px;
  }
  .help-grid kbd {
    display: inline-block;
    background: rgba(255,255,255,0.08);
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 4px;
    padding: 1px 6px;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 11px;
    line-height: 1.6;
  }
  .help-grid .seq { white-space: nowrap; }

  /* Visible focus outline for keyboard navigation. The default browser
     ring is suppressed across the dark theme; we add a clear one back
     for any control that lands focus via Tab. */
  .app *:focus-visible,
  .auth-screen *:focus-visible,
  .dialog *:focus-visible {
    outline: 2px solid var(--accent, #6c8eff);
    outline-offset: 2px;
    border-radius: 4px;
  }

  /* Screen-reader-only utility */
  .sr-only {
    position: absolute;
    width: 1px; height: 1px;
    padding: 0; margin: -1px;
    overflow: hidden; clip: rect(0,0,0,0);
    white-space: nowrap; border: 0;
  }
`;
document.head.appendChild(agStyles);

function renderConvSkeletons(count) {
  const out = [];
  for (let i = 0; i < count; i += 1) {
    const row = document.createElement('div');
    row.className = 'conv-skeleton';
    row.setAttribute('aria-hidden', 'true');
    const av = document.createElement('div');
    av.className = 'conv-skeleton-avatar';
    const text = document.createElement('div');
    text.className = 'conv-skeleton-text';
    const l1 = document.createElement('div');
    l1.className = 'conv-skeleton-line w-60';
    const l2 = document.createElement('div');
    l2.className = 'conv-skeleton-line w-40';
    text.appendChild(l1); text.appendChild(l2);
    row.appendChild(av); row.appendChild(text);
    out.push(row);
  }
  return out;
}

// --- Sound effects via Web Audio. Two short tones synthesized in code
// so we don't ship audio assets. Toggleable via the menu; persisted in
// localStorage. Off by default (privacy-tool defaults: nothing makes
// noise unless the user opts in).
const SOUND_KEY = 'veil-demo-sounds-enabled-v1';
try { state.soundsEnabled = localStorage.getItem(SOUND_KEY) === '1'; } catch {}
let __veilAudioCtx = null;
let __veilAudioUnlocked = false;
function audioCtx() {
  if (!__veilAudioCtx) {
    try {
      __veilAudioCtx = new (window.AudioContext || window.webkitAudioContext)();
    } catch {}
  }
  return __veilAudioCtx;
}
// iOS Safari + some Android browsers refuse to start an AudioContext
// outside a user gesture. We listen for the first click / touch / key
// and call ctx.resume() then to unlock subsequent programmatic plays
// (notification tones triggered by a websocket event are NOT a gesture).
function unlockAudioOnce() {
  if (__veilAudioUnlocked) return;
  const ctx = audioCtx();
  if (!ctx) return;
  if (ctx.state === 'suspended') {
    ctx.resume().catch(() => {});
  }
  __veilAudioUnlocked = true;
}
['click', 'touchend', 'keydown'].forEach((evt) => {
  window.addEventListener(evt, unlockAudioOnce, { once: true, capture: true });
});
function playTone({ freq, durationMs, type = 'sine', gain = 0.04 }) {
  if (!state.soundsEnabled) return;
  const ctx = audioCtx();
  if (!ctx) return;
  const osc = ctx.createOscillator();
  const g = ctx.createGain();
  osc.type = type;
  osc.frequency.value = freq;
  g.gain.setValueAtTime(gain, ctx.currentTime);
  g.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + durationMs / 1000);
  osc.connect(g).connect(ctx.destination);
  osc.start();
  osc.stop(ctx.currentTime + durationMs / 1000);
}
const playSendTone = () => playTone({ freq: 880, durationMs: 80, type: 'sine' });
const playReceiveTone = () => playTone({ freq: 660, durationMs: 120, type: 'triangle' });

// --- Keyboard shortcuts. Skip when typing in inputs/textareas, except
// for the global toggles like Esc and the help binding.
const SHORTCUTS = [
  { keys: 'mod+k', label: '대화 검색', sequence: ['Ctrl/Cmd', 'K'] },
  { keys: 'mod+n', label: '새 대화', sequence: ['Ctrl/Cmd', 'N'] },
  { keys: 'mod+/', label: '도움말 열기', sequence: ['Ctrl/Cmd', '/'] },
  { keys: 'mod+shift+s', label: '사운드 토글', sequence: ['Ctrl/Cmd', 'Shift', 'S'] },
  { keys: 'esc', label: '다이얼로그 / 메뉴 닫기', sequence: ['Esc'] },
  { keys: 'enter', label: '메시지 전송 (입력창)', sequence: ['Enter'] },
  { keys: 'shift+enter', label: '입력창에서 줄바꿈', sequence: ['Shift', 'Enter'] },
];

function isTypingTarget(el) {
  if (!el) return false;
  const tag = el.tagName;
  return tag === 'INPUT' || tag === 'TEXTAREA' || el.isContentEditable;
}

document.addEventListener('keydown', (e) => {
  const mod = e.ctrlKey || e.metaKey;

  // Esc closes any open dialog or menu, regardless of focus target.
  if (e.key === 'Escape') {
    const openDialog = document.querySelector('.dialog-backdrop:not(.hidden)');
    if (openDialog) {
      e.preventDefault();
      openDialog.classList.add('hidden');
      return;
    }
    const openMenu = document.querySelector('.menu:not(.hidden)');
    if (openMenu) {
      e.preventDefault();
      openMenu.classList.add('hidden');
      return;
    }
  }

  if (mod && (e.key === '/' || e.key === '?')) {
    e.preventDefault();
    openHelpDialog();
    return;
  }

  // The next set of shortcuts skip when the user is typing.
  if (isTypingTarget(e.target)) return;

  if (mod && (e.key === 'k' || e.key === 'K')) {
    e.preventDefault();
    const search = $('search-input');
    if (search) { search.focus(); search.select?.(); }
    return;
  }
  if (mod && (e.key === 'n' || e.key === 'N')) {
    e.preventDefault();
    $('new-chat-btn')?.click();
    return;
  }
  if (mod && e.shiftKey && (e.key === 's' || e.key === 'S')) {
    e.preventDefault();
    toggleSounds();
    return;
  }
});

function toggleSounds() {
  state.soundsEnabled = !state.soundsEnabled;
  try { localStorage.setItem(SOUND_KEY, state.soundsEnabled ? '1' : '0'); } catch {}
  toast(state.soundsEnabled ? '사운드 켜짐' : '사운드 꺼짐', 'good');
}

function openHelpDialog() {
  let dialog = document.getElementById('help-dialog');
  if (!dialog) {
    dialog = document.createElement('div');
    dialog.id = 'help-dialog';
    dialog.className = 'dialog-backdrop hidden';
    dialog.setAttribute('role', 'presentation');
    dialog.innerHTML = `
      <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="help-title">
        <div class="dialog-title" id="help-title">키보드 단축키</div>
        <div class="dialog-sub">VEIL 을 더 빠르게 쓰는 법.</div>
        <div class="help-grid"></div>
        <div class="dialog-sub" style="margin-top:14px;font-size:11px;opacity:0.6">
          ${state.soundsEnabled ? '🔊' : '🔇'} 사운드: ${state.soundsEnabled ? '켜짐' : '꺼짐'} (메뉴 또는 Ctrl/Cmd+Shift+S)
        </div>
        <div class="dialog-actions">
          <button class="btn btn-primary" id="help-ok">확인</button>
        </div>
      </div>
    `;
    document.body.appendChild(dialog);
    const grid = dialog.querySelector('.help-grid');
    for (const s of SHORTCUTS) {
      const seq = document.createElement('div');
      seq.className = 'seq';
      seq.innerHTML = s.sequence.map((k) => `<kbd>${k}</kbd>`).join(' + ');
      const lbl = document.createElement('div');
      lbl.textContent = s.label;
      grid.appendChild(seq);
      grid.appendChild(lbl);
    }
    dialog.querySelector('#help-ok').addEventListener('click', () => {
      dialog.classList.add('hidden');
    });
    dialog.addEventListener('click', (e) => {
      if (e.target === dialog) dialog.classList.add('hidden');
    });
  }
  dialog.classList.remove('hidden');
  dialog.querySelector('#help-ok')?.focus();
}

// Wire the menu actions for sound + help. Defer to the next tick so
// the menu node exists.
setTimeout(() => {
  const menu = document.getElementById('menu');
  if (!menu) return;
  if (!menu.querySelector('[data-action="toggle-sounds"]')) {
    const sep = menu.querySelector('.menu-sep');
    const sound = document.createElement('button');
    sound.className = 'menu-item';
    sound.dataset.action = 'toggle-sounds';
    sound.setAttribute('role', 'menuitem');
    sound.textContent = '🔔 사운드 토글';
    if (sep) menu.insertBefore(sound, sep); else menu.appendChild(sound);
    const help = document.createElement('button');
    help.className = 'menu-item';
    help.dataset.action = 'show-help';
    help.setAttribute('role', 'menuitem');
    help.textContent = '⌨️ 단축키';
    if (sep) menu.insertBefore(help, sep); else menu.appendChild(help);
  }
  menu.addEventListener('click', (e) => {
    const action = e.target?.dataset?.action;
    if (action === 'toggle-sounds') {
      menu.classList.add('hidden');
      toggleSounds();
    } else if (action === 'show-help') {
      menu.classList.add('hidden');
      openHelpDialog();
    }
  }, true);
}, 0);

// Sound triggers — receive on incoming peer message, send on our own.
// We hook the send path via a global flag set from sendMessage; receive
// path runs inside maybeShowNotification's onMessageNew hook above so
// unfocused tabs get OS notification + tone, focused tabs get just tone.
// We piggy-back on the existing onMessageNew hook by re-wrapping send:
const __veilOriginalSendMessage = typeof sendMessage === 'function' ? sendMessage : null;
// Sounds for inbound: hook into onMessageNew via a separate listener.
// We can't re-bind the function (module scope), but we CAN add another
// listener on the shared socket so the sound layer is independent.
const __veilWireSounds = () => {
  const s = state.socket;
  if (!s || s.__veilSoundsWired) return false;
  s.__veilSoundsWired = true;
  s.on('message.new', (msg) => {
    if (msg && msg.senderDeviceId !== state.me?.deviceId) playReceiveTone();
  });
  return true;
};
// One-shot wiring: poll until the first socket exists, wire sounds on
// it, then stop. socket.io auto-reconnect reuses the same socket
// object, so listeners survive disconnect/reconnect cycles. On logout
// the state.socket is cleared; the socket-replacement listener below
// rewires whenever a fresh socket appears.
let __veilSoundsTimer = setInterval(() => {
  if (__veilWireSounds()) {
    clearInterval(__veilSoundsTimer);
    __veilSoundsTimer = null;
    // After logout, state.socket is cleared. A subsequent login builds
    // a new socket object — restart the one-shot wire then.
    setInterval(() => {
      if (state.socket && !state.socket.__veilSoundsWired) __veilWireSounds();
    }, 1500);
  }
}, 500);

// a11y: aria-label on menus + dialogs that didn't have one. Body-level
// keyboard trap inside dialogs (Tab cycles within open dialog).
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Tab') return;
  const open = document.querySelector('.dialog-backdrop:not(.hidden) .dialog');
  if (!open) return;
  const focusable = open.querySelectorAll(
    'a[href], button:not([disabled]), input:not([disabled]), textarea:not([disabled]), select:not([disabled]), [tabindex]:not([tabindex="-1"])',
  );
  if (focusable.length === 0) return;
  const first = focusable[0];
  const last = focusable[focusable.length - 1];
  if (e.shiftKey && document.activeElement === first) {
    e.preventDefault(); last.focus();
  } else if (!e.shiftKey && document.activeElement === last) {
    e.preventDefault(); first.focus();
  }
});

// ---------- Phase AH: in-conversation search + @mention autocomplete ----------

const ahStyles = document.createElement('style');
ahStyles.textContent = `
  /* In-conversation search bar slides in below the panel header */
  .panel-search {
    display: flex; align-items: center; gap: 8px;
    padding: 8px 12px;
    background: rgba(255,255,255,0.03);
    border-bottom: 1px solid rgba(255,255,255,0.06);
  }
  .panel-search input {
    flex: 1;
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 6px;
    padding: 5px 10px;
    color: inherit;
    font-size: 13px;
  }
  .panel-search button {
    background: transparent; border: 0; color: inherit; cursor: pointer;
    padding: 4px 8px; border-radius: 4px; font-size: 13px;
  }
  .panel-search button:hover { background: rgba(255,255,255,0.08); }
  .panel-search .count {
    font-size: 11px; opacity: 0.6;
    min-width: 36px; text-align: center;
  }
  /* Highlight match inside bubble */
  .msg-text mark {
    background: rgba(255, 220, 100, 0.4);
    color: inherit;
    padding: 0 2px;
    border-radius: 2px;
  }
  .msg-row.search-active { box-shadow: 0 0 0 2px rgba(255, 220, 100, 0.45); border-radius: 8px; }

  /* @mention chip */
  .msg-text .mention {
    background: rgba(108, 142, 255, 0.15);
    border-radius: 4px;
    padding: 0 4px;
    color: var(--accent, #6c8eff);
    font-weight: 500;
  }

  /* @mention autocomplete dropdown */
  .mention-pop {
    position: absolute;
    background: #1c1d22;
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 10px;
    box-shadow: 0 12px 32px rgba(0,0,0,0.4);
    padding: 4px;
    z-index: 1100;
    min-width: 200px;
    max-height: 240px;
    overflow-y: auto;
  }
  .mention-pop-item {
    display: flex; align-items: center; gap: 10px;
    padding: 6px 10px;
    border-radius: 6px;
    cursor: pointer;
    font-size: 13px;
  }
  .mention-pop-item:hover, .mention-pop-item.active {
    background: rgba(108, 142, 255, 0.18);
  }
  .mention-pop-empty { padding: 10px; opacity: 0.6; font-size: 12px; text-align: center; }
`;
document.head.appendChild(ahStyles);

// --- Search state per conversation. We keep the open/closed flag and
// the current query in a Map so reopening a conversation that the user
// was searching restores the state.
const searchStateByConv = new Map();
function getSearchState(convId) {
  if (!searchStateByConv.has(convId)) {
    searchStateByConv.set(convId, { open: false, query: '', idx: 0 });
  }
  return searchStateByConv.get(convId);
}

function openPanelSearch(convId) {
  const st = getSearchState(convId);
  st.open = true;
  renderActivePanel();
  requestAnimationFrame(() => {
    const input = document.querySelector(`.panel[data-conv="${convId}"] .panel-search input`);
    input?.focus();
  });
}
function closePanelSearch(convId) {
  const st = getSearchState(convId);
  st.open = false;
  st.query = '';
  st.idx = 0;
  renderActivePanel();
}

// Build the search bar DOM. Returns null when search is closed for
// this conversation.
function renderPanelSearch(convId) {
  const st = getSearchState(convId);
  if (!st.open) return null;
  const list = state.messagesByConv.get(convId) || [];
  const q = st.query.trim().toLowerCase();
  const matches = q
    ? list.filter((m) => typeof m._plaintext === 'string' && m._plaintext.toLowerCase().includes(q))
    : [];
  const total = matches.length;
  if (st.idx >= total && total > 0) st.idx = total - 1;
  const counter = total > 0 ? `${st.idx + 1}/${total}` : (q ? '0/0' : '');

  const wrap = document.createElement('div');
  wrap.className = 'panel-search';
  wrap.setAttribute('role', 'search');
  const input = document.createElement('input');
  input.type = 'text';
  input.placeholder = '대화에서 찾기…';
  input.value = st.query;
  input.setAttribute('aria-label', '메시지 검색');
  input.addEventListener('input', () => {
    st.query = input.value;
    st.idx = 0;
    renderActivePanel();
    requestAnimationFrame(() => {
      const f = document.querySelector(`.panel[data-conv="${convId}"] .panel-search input`);
      if (f) { f.focus(); f.setSelectionRange(input.value.length, input.value.length); }
    });
  });
  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      if (total === 0) return;
      st.idx = e.shiftKey
        ? (st.idx - 1 + total) % total
        : (st.idx + 1) % total;
      scrollToMatch(convId, matches[st.idx]?.id);
      renderActivePanel();
      requestAnimationFrame(() => {
        document.querySelector(`.panel[data-conv="${convId}"] .panel-search input`)?.focus();
      });
    } else if (e.key === 'Escape') {
      closePanelSearch(convId);
    }
  });

  const counterEl = document.createElement('span');
  counterEl.className = 'count';
  counterEl.textContent = counter;

  const prev = document.createElement('button');
  prev.textContent = '↑';
  prev.title = '이전 결과 (Shift+Enter)';
  prev.addEventListener('click', () => {
    if (total === 0) return;
    st.idx = (st.idx - 1 + total) % total;
    scrollToMatch(convId, matches[st.idx]?.id);
    renderActivePanel();
  });
  const next = document.createElement('button');
  next.textContent = '↓';
  next.title = '다음 결과 (Enter)';
  next.addEventListener('click', () => {
    if (total === 0) return;
    st.idx = (st.idx + 1) % total;
    scrollToMatch(convId, matches[st.idx]?.id);
    renderActivePanel();
  });
  const close = document.createElement('button');
  close.textContent = '✕';
  close.title = '닫기 (Esc)';
  close.addEventListener('click', () => closePanelSearch(convId));

  wrap.append(input, counterEl, prev, next, close);
  return wrap;
}

function scrollToMatch(convId, msgId) {
  if (!msgId) return;
  const row = document.querySelector(
    `.panel[data-conv="${convId}"] .msg-row[data-msg-id="${msgId}"]`,
  );
  if (row) row.scrollIntoView({ behavior: 'smooth', block: 'center' });
}

// Mark search matches inside the bubble after render. Run after the
// regular renderActivePanel() call. The search-active class on the
// row gives a yellow outline; <mark> wraps the substring.
function highlightSearchMatches() {
  for (const [convId, st] of searchStateByConv) {
    if (!st.open) continue;
    const q = st.query.trim();
    if (!q) continue;
    const panel = document.querySelector(`.panel[data-conv="${convId}"]`);
    if (!panel) continue;
    const list = state.messagesByConv.get(convId) || [];
    const matches = list.filter((m) =>
      typeof m._plaintext === 'string' && m._plaintext.toLowerCase().includes(q.toLowerCase()),
    );
    matches.forEach((m, i) => {
      const row = panel.querySelector(`.msg-row[data-msg-id="${m.id}"]`);
      if (!row) return;
      if (i === st.idx) row.classList.add('search-active');
      const span = row.querySelector('.msg-text');
      if (!span || !m._plaintext) return;
      const lower = m._plaintext.toLowerCase();
      const qLower = q.toLowerCase();
      let cursor = 0;
      const out = document.createDocumentFragment();
      while (cursor < m._plaintext.length) {
        const found = lower.indexOf(qLower, cursor);
        if (found === -1) {
          out.appendChild(document.createTextNode(m._plaintext.slice(cursor)));
          break;
        }
        if (found > cursor) {
          out.appendChild(document.createTextNode(m._plaintext.slice(cursor, found)));
        }
        const mark = document.createElement('mark');
        mark.textContent = m._plaintext.slice(found, found + q.length);
        out.appendChild(mark);
        cursor = found + q.length;
      }
      span.replaceChildren(out);
    });
  }
}

// Hook the highlighter into renderActivePanel via a MutationObserver
// on the panels container. After every render we run the highlighter
// once so the open search bar's matches show up immediately.
const __veilSearchObserver = new MutationObserver(() => {
  // Defer to next frame so the render finishes before we mutate.
  requestAnimationFrame(highlightSearchMatches);
});
setTimeout(() => {
  const panels = document.getElementById('panels');
  if (panels) __veilSearchObserver.observe(panels, { childList: true, subtree: true });
}, 0);

// Open the panel search on Ctrl/Cmd+F when a conversation is active.
document.addEventListener('keydown', (e) => {
  const mod = e.ctrlKey || e.metaKey;
  if (!mod || (e.key !== 'f' && e.key !== 'F')) return;
  if (!state.activeConv) return;
  // Only intercept when not focused in another input — let the user use
  // the OS find for the rest of the page if they want it.
  if (isTypingTarget(e.target)) {
    const inSearch = e.target.closest('.panel-search');
    if (!inSearch) return;
  }
  e.preventDefault();
  openPanelSearch(state.activeConv);
});

// Add the search shortcut to the help dialog.
SHORTCUTS.splice(2, 0, {
  keys: 'mod+f', label: '대화 안에서 찾기', sequence: ['Ctrl/Cmd', 'F'],
});

// --- @mention autocomplete inside the message input.
// On every keystroke we look back from the caret for "@<word>" without
// whitespace. If found, we show a small popover with members of the
// active conversation whose handle matches the prefix.
let mentionPop = null;
function closeMentionPop() {
  if (mentionPop) { mentionPop.remove(); mentionPop = null; }
}
function getMentionContext(textarea) {
  const v = textarea.value;
  const caret = textarea.selectionStart ?? v.length;
  const left = v.slice(0, caret);
  const at = left.lastIndexOf('@');
  if (at < 0) return null;
  // Whitespace between '@' and caret kills the mention.
  if (/\s/.test(left.slice(at + 1))) return null;
  // The '@' must be at start-of-input or follow whitespace/punct.
  const before = at > 0 ? left[at - 1] : ' ';
  if (!/\s|[(\[{,.;:!?]/.test(before)) return null;
  return { start: at, prefix: left.slice(at + 1) };
}
function membersForActiveConv() {
  const conv = state.conversations.find((c) => c.id === state.activeConv);
  if (!conv) return [];
  return (conv.members ?? []).filter((m) => m.userId !== state.me?.userId);
}
function showMentionPop(textarea, ctx) {
  closeMentionPop();
  const candidates = membersForActiveConv()
    .filter((m) => (m.handle || '').toLowerCase().startsWith(ctx.prefix.toLowerCase()))
    .slice(0, 6);
  const pop = document.createElement('div');
  pop.className = 'mention-pop';
  pop.setAttribute('role', 'listbox');
  if (candidates.length === 0) {
    const empty = document.createElement('div');
    empty.className = 'mention-pop-empty';
    empty.textContent = '일치하는 핸들 없음';
    pop.appendChild(empty);
  } else {
    candidates.forEach((m, i) => {
      const item = document.createElement('div');
      item.className = 'mention-pop-item' + (i === 0 ? ' active' : '');
      item.dataset.handle = m.handle;
      item.dataset.userId = m.userId;
      item.setAttribute('role', 'option');
      const avatar = avatarFor(m.handle, 'sm');
      const text = document.createElement('div');
      text.innerHTML = `<div>@${escapeHtml(m.handle || '')}</div>`
        + (m.displayName ? `<div style="font-size:11px;opacity:0.6">${escapeHtml(m.displayName)}</div>` : '');
      item.appendChild(avatar);
      item.appendChild(text);
      item.addEventListener('mousedown', (e) => {
        e.preventDefault();
        completeMention(textarea, ctx, m.handle);
      });
      pop.appendChild(item);
    });
  }
  // Position below the textarea caret. Approximate via textarea bounds.
  const rect = textarea.getBoundingClientRect();
  pop.style.left = (rect.left + 8) + 'px';
  pop.style.bottom = (window.innerHeight - rect.top + 4) + 'px';
  document.body.appendChild(pop);
  mentionPop = pop;
}
function completeMention(textarea, ctx, handle) {
  const v = textarea.value;
  const caret = textarea.selectionStart ?? v.length;
  const next = v.slice(0, ctx.start) + '@' + handle + ' ' + v.slice(caret);
  textarea.value = next;
  const newCaret = ctx.start + handle.length + 2;
  textarea.setSelectionRange(newCaret, newCaret);
  textarea.dispatchEvent(new Event('input'));
  closeMentionPop();
  textarea.focus();
}

// Attach the mention listener to every textarea inside .panel-input.
// We use a single delegated listener on document so newly-rendered
// textareas pick it up automatically.
document.addEventListener('input', (e) => {
  const ta = e.target;
  if (!(ta instanceof HTMLTextAreaElement)) return;
  if (!ta.closest('.panel-input')) return;
  const ctx = getMentionContext(ta);
  if (!ctx) { closeMentionPop(); return; }
  showMentionPop(ta, ctx);
});

document.addEventListener('keydown', (e) => {
  if (!mentionPop) return;
  const items = mentionPop.querySelectorAll('.mention-pop-item');
  if (items.length === 0) return;
  let active = mentionPop.querySelector('.mention-pop-item.active');
  let activeIdx = Array.from(items).indexOf(active);
  if (e.key === 'ArrowDown') {
    e.preventDefault();
    activeIdx = (activeIdx + 1) % items.length;
  } else if (e.key === 'ArrowUp') {
    e.preventDefault();
    activeIdx = (activeIdx - 1 + items.length) % items.length;
  } else if (e.key === 'Enter' || e.key === 'Tab') {
    e.preventDefault();
    const handle = items[activeIdx]?.dataset?.handle;
    const ta = e.target instanceof HTMLTextAreaElement
      ? e.target
      : document.querySelector('.panel-input textarea');
    if (handle && ta) {
      const ctx = getMentionContext(ta);
      if (ctx) completeMention(ta, ctx, handle);
    }
    return;
  } else if (e.key === 'Escape') {
    closeMentionPop();
    return;
  } else {
    return;
  }
  items.forEach((it) => it.classList.remove('active'));
  items[activeIdx].classList.add('active');
}, true);

// Close the popover on any click outside.
document.addEventListener('click', (e) => {
  if (!mentionPop) return;
  if (!mentionPop.contains(e.target) && !(e.target instanceof HTMLTextAreaElement)) {
    closeMentionPop();
  }
});

// Mention chip rendering lives inside renderMessageInline (lib/
// markdown.js), so no separate wrapper here anymore. This keeps the
// vitest-tested function and the runtime function identical.

// ---------- Phase AI: image attachment upload ----------
// User picks an image → we generate a fresh AES-256-GCM key for this
// attachment, encrypt the bytes, compute sha256 of the ciphertext,
// hit the upload-ticket → PUT → complete endpoints, then send a
// message whose envelope.attachment carries the metadata and whose
// encrypted body carries the per-attachment key + nonce inside a JSON
// payload (so the recipient can decrypt after the existing per-conv
// key unwraps the body).

const IMAGE_MAX_BYTES = 10 * 1024 * 1024;
const IMAGE_MIME_ALLOW = new Set([
  'image/jpeg', 'image/png', 'image/webp',
]);

const aiStyles = document.createElement('style');
aiStyles.textContent = `
  .image-btn {
    background: transparent; border: 0; color: inherit;
    cursor: pointer; font-size: 18px; padding: 0 6px;
  }
  .image-btn:hover { color: var(--accent, #6c8eff); }
  .panel-input.drag-over {
    background: rgba(108, 142, 255, 0.08);
    outline: 2px dashed rgba(108, 142, 255, 0.4);
    outline-offset: -2px;
    border-radius: 8px;
  }
  .image-uploading {
    display: inline-flex; align-items: center; gap: 6px;
    font-size: 12px; opacity: 0.7;
  }
  .image-uploading::before {
    content: '';
    display: inline-block;
    width: 10px; height: 10px;
    border: 2px solid currentColor;
    border-top-color: transparent;
    border-radius: 50%;
    animation: spin 0.7s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }
`;
document.head.appendChild(aiStyles);

async function pickAndSendImage(convId) {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/jpeg,image/png,image/webp';
  input.addEventListener('change', async () => {
    const file = input.files?.[0];
    if (file) await sendImageFile(convId, file);
  });
  input.click();
}

async function sendImageFile(convId, file) {
  if (!IMAGE_MIME_ALLOW.has(file.type)) {
    toast('JPG / PNG / WebP 만 지원해요', 'error');
    return;
  }
  if (file.size > IMAGE_MAX_BYTES) {
    toast('이미지가 10MB 를 초과합니다', 'error');
    return;
  }
  const conv = state.conversations.find((c) => c.id === convId);
  if (!conv) return;
  const peer = conv.members.find((m) => m.userId !== state.me.userId);
  const clientMessageId = 'img-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);

  // Optimistic bubble with the local file as preview while we upload.
  const localUrl = URL.createObjectURL(file);
  const optimistic = {
    id: '__pending__' + clientMessageId,
    clientMessageId,
    conversationId: convId,
    senderDeviceId: state.me.deviceId,
    ciphertext: '',
    nonce: '',
    messageType: 'image',
    serverReceivedAt: null,
    _localAt: new Date().toISOString(),
    _status: 'pending',
    _imageUrl: localUrl,
    _plaintext: '🖼 이미지',
  };
  const list = state.messagesByConv.get(convId) || [];
  list.push(optimistic);
  state.messagesByConv.set(convId, list);
  renderActivePanel();

  try {
    // 1) Generate a fresh AES-256-GCM key + nonce, encrypt the file.
    const aesKey = await crypto.subtle.generateKey(
      { name: 'AES-GCM', length: 256 }, true, ['encrypt', 'decrypt'],
    );
    const nonce = crypto.getRandomValues(new Uint8Array(12));
    const plaintext = await file.arrayBuffer();
    const ciphertext = await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv: nonce },
      aesKey,
      plaintext,
    );

    // 2) sha256 of the ciphertext (the server validates the upload).
    const sha = await crypto.subtle.digest('SHA-256', ciphertext);
    const shaHex = Array.from(new Uint8Array(sha))
      .map((b) => b.toString(16).padStart(2, '0')).join('');

    // 3) Get an upload ticket.
    const ticket = await authedApi('/attachments/upload-ticket', {
      method: 'POST',
      body: {
        contentType: 'application/octet-stream',
        sizeBytes: ciphertext.byteLength,
        sha256: shaHex,
      },
    });

    // 4) PUT the ciphertext to the presigned URL.
    const putRes = await fetch(ticket.upload.uploadUrl, {
      method: 'PUT',
      headers: ticket.upload.headers,
      body: ciphertext,
    });
    if (!putRes.ok) throw new Error(`upload PUT failed: ${putRes.status}`);

    // 5) Complete the upload.
    await authedApi('/attachments/complete', {
      method: 'POST',
      body: { attachmentId: ticket.attachmentId, uploadStatus: 'uploaded' },
    });

    // 6) Build the message body — JSON with the per-attachment key +
    //    nonce so the recipient can decrypt after unwrapping the body
    //    via the per-conv key the existing path already uses.
    const rawKey = await crypto.subtle.exportKey('raw', aesKey);
    const bodyPayload = JSON.stringify({
      kind: 'image',
      attachmentId: ticket.attachmentId,
      mime: file.type,
      key: b64uEncode(rawKey),
      nonce: b64uEncode(nonce),
      width: 0, height: 0,
    });
    const envelope = await encryptForConv(convId, bodyPayload);
    if (!envelope) throw new Error('상대 키를 못 찾았어요');

    // 7) Send via /messages, populating envelope.attachment.
    const sent = await authedApi('/messages', {
      method: 'POST',
      body: {
        conversationId: convId,
        clientMessageId,
        envelope: {
          version: 'veil-envelope-v1-dev',
          conversationId: convId,
          senderDeviceId: state.me.deviceId,
          recipientUserId: peer.userId,
          ciphertext: envelope.ciphertext,
          nonce: envelope.nonce,
          messageType: 'image',
          attachment: {
            attachmentId: ticket.attachmentId,
            storageKey: ticket.upload.storageKey ?? '',
            contentType: 'application/octet-stream',
            sizeBytes: ciphertext.byteLength,
            sha256: shaHex,
            encryption: {
              encryptedKey: 'web-demo-inline-in-body',
              nonce: b64uEncode(nonce),
              algorithmHint: 'dev-wrap',
            },
          },
        },
      },
    });

    sent.message._imageUrl = localUrl;
    sent.message._plaintext = '🖼 이미지';
    const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
    if (idx >= 0) list[idx] = sent.message;
    conv.lastMessage = sent.message;
    persistMessage(sent.message);
    persistConversation(conv);
    renderActivePanel();
    renderSidebar();
    playSendTone();
  } catch (e) {
    toast('이미지 전송 실패: ' + (e.message || 'unknown'), 'error');
    const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
    if (idx >= 0) list[idx] = { ...list[idx], _status: 'failed' };
    renderActivePanel();
  }
}

// On receive: an image message arrives with envelope.attachment set
// and a JSON body holding the AES key. After the regular decryptMessage
// pass populates _plaintext with the JSON string, we parse it, fetch
// the ciphertext via download-ticket, decrypt, and attach _imageUrl.
async function maybeMaterializeImage(msg) {
  if (msg.messageType !== 'image') return;
  if (msg._imageUrl) return;
  if (!msg.attachment?.attachmentId) return;
  // _plaintext should be the JSON envelope body. Parse it.
  let payload = null;
  if (typeof msg._plaintext === 'string') {
    try { payload = JSON.parse(msg._plaintext); } catch {}
  }
  if (!payload || payload.kind !== 'image' || !payload.key) return;
  try {
    const ticket = await authedApi(`/attachments/${msg.attachment.attachmentId}/download-ticket`);
    const res = await fetch(ticket.ticket.downloadUrl);
    if (!res.ok) throw new Error('download failed: ' + res.status);
    const buf = await res.arrayBuffer();
    const aesKey = await crypto.subtle.importKey(
      'raw', b64uDecode(payload.key), { name: 'AES-GCM' }, false, ['decrypt'],
    );
    const nonce = new Uint8Array(b64uDecode(payload.nonce));
    const plaintext = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: nonce }, aesKey, buf,
    );
    const blob = new Blob([plaintext], { type: payload.mime || 'image/jpeg' });
    msg._imageUrl = URL.createObjectURL(blob);
    msg._plaintext = '🖼 이미지';
    if (msg.conversationId === state.activeConv || msg.conversationId === state.secondaryConv) {
      renderActivePanel();
    }
    renderSidebar();
  } catch (e) {
    msg._plaintext = '🖼 이미지 (불러오기 실패)';
    if (msg.conversationId === state.activeConv) renderActivePanel();
  }
}

// Add the 📷 button to the panel input, plus drag-and-drop on the
// .panel-input element. Done via document-level delegation so the
// listeners survive renderActivePanel rebuilds.
document.addEventListener('click', (e) => {
  const btn = e.target.closest('.image-btn');
  if (!btn) return;
  const panel = btn.closest('.panel');
  const convId = panel?.dataset?.conv;
  if (convId) pickAndSendImage(convId);
});

// Inject the image button next to the voice button after every render.
const __veilImgBtnObserver = new MutationObserver(() => {
  document.querySelectorAll('.panel-input').forEach((node) => {
    if (node.querySelector('.image-btn')) return;
    const voiceBtn = node.querySelector('.voice-btn');
    const btn = document.createElement('button');
    btn.className = 'image-btn';
    btn.setAttribute('aria-label', '이미지 첨부');
    btn.title = '이미지 첨부';
    btn.innerHTML = '<span aria-hidden="true">📷</span>';
    if (voiceBtn) node.insertBefore(btn, voiceBtn);
    else node.appendChild(btn);
  });
});
setTimeout(() => {
  const panels = document.getElementById('panels');
  if (panels) __veilImgBtnObserver.observe(panels, { childList: true, subtree: true });
}, 0);

// Drag-and-drop image into the panel input.
document.addEventListener('dragover', (e) => {
  const target = e.target.closest('.panel-input');
  if (!target) return;
  e.preventDefault();
  target.classList.add('drag-over');
});
document.addEventListener('dragleave', (e) => {
  const target = e.target.closest('.panel-input');
  if (!target) return;
  target.classList.remove('drag-over');
});
document.addEventListener('drop', (e) => {
  const target = e.target.closest('.panel-input');
  if (!target) return;
  e.preventDefault();
  target.classList.remove('drag-over');
  const panel = target.closest('.panel');
  const convId = panel?.dataset?.conv;
  const file = e.dataTransfer?.files?.[0];
  if (convId && file) showImagePreview(convId, file);
});

// Phase AM: image send confirmation. Show a preview modal with the
// chosen file before we encrypt + upload, so a wrong drag-drop or
// fat-finger tap doesn't leak. User confirms ("전송") or cancels.
function showImagePreview(convId, file) {
  if (!IMAGE_MIME_ALLOW.has(file.type)) {
    toast('JPG / PNG / WebP 만 지원해요', 'error'); return;
  }
  if (file.size > IMAGE_MAX_BYTES) {
    toast('이미지가 10MB 를 초과합니다', 'error'); return;
  }
  const url = URL.createObjectURL(file);
  const back = document.createElement('div');
  back.className = 'image-zoom-backdrop';
  back.style.cursor = 'default';
  back.setAttribute('role', 'dialog');
  back.setAttribute('aria-modal', 'true');
  const card = document.createElement('div');
  card.style.cssText = 'background:#1c1d22;padding:16px;border-radius:14px;max-width:480px;width:90vw;display:flex;flex-direction:column;gap:12px';
  const title = document.createElement('div');
  title.textContent = '이미지 전송 확인';
  title.style.cssText = 'font-size:15px;font-weight:600';
  const sub = document.createElement('div');
  sub.style.cssText = 'font-size:12px;opacity:0.7';
  sub.textContent = `${file.name || '이미지'} · ${(file.size / 1024).toFixed(0)} KB`;
  const img = document.createElement('img');
  img.src = url;
  img.style.cssText = 'max-width:100%;max-height:50vh;border-radius:8px;object-fit:contain;background:#0b0c10';
  const actions = document.createElement('div');
  actions.style.cssText = 'display:flex;gap:8px;justify-content:flex-end';
  const cancel = document.createElement('button');
  cancel.className = 'btn btn-ghost'; cancel.textContent = '취소';
  const send = document.createElement('button');
  send.className = 'btn btn-primary'; send.textContent = '전송';
  const close = () => {
    URL.revokeObjectURL(url);
    back.remove();
  };
  cancel.addEventListener('click', close);
  back.addEventListener('click', (e) => { if (e.target === back) close(); });
  send.addEventListener('click', () => {
    URL.revokeObjectURL(url);
    back.remove();
    sendImageFile(convId, file);
  });
  // Esc cancels.
  const onKey = (e) => {
    if (e.key === 'Escape') { close(); document.removeEventListener('keydown', onKey); }
  };
  document.addEventListener('keydown', onKey);
  actions.append(cancel, send);
  card.append(title, sub, img, actions);
  back.appendChild(card);
  document.body.appendChild(back);
  send.focus();
}

// Update file picker + drop to route through the preview, not directly
// to sendImageFile.
const __veilOriginalPickAndSendImage = pickAndSendImage;
pickAndSendImage = function (convId) {
  const input = document.createElement('input');
  input.type = 'file';
  input.accept = 'image/jpeg,image/png,image/webp';
  input.addEventListener('change', () => {
    const file = input.files?.[0];
    if (file) showImagePreview(convId, file);
  });
  input.click();
};

// ---------- Phase AM: 5-minute delete-undo ----------
// When the user deletes a message we run the existing DELETE path
// immediately — server-side soft-delete is what other recipients see —
// but we ALSO show a 5-second toast with an "되돌리기" button. Tapping
// it within the window posts a fresh message restoring the body
// locally (the recipient sees a new bubble, not an undo, because the
// real delete has already propagated).
const undoStateByMsg = new Map(); // messageId → {plaintext, convId, replyToId, expiresAt}

function offerDeleteUndo({ messageId, convId, plaintext, replyToId }) {
  if (typeof plaintext !== 'string' || plaintext === '') return;
  undoStateByMsg.set(messageId, {
    plaintext, convId, replyToId,
    expiresAt: Date.now() + 5_000,
  });
  showUndoToast(messageId);
  setTimeout(() => undoStateByMsg.delete(messageId), 5_500);
}

function showUndoToast(messageId) {
  const root = $('toast-root');
  if (!root) return;
  const node = el('div', { class: 'toast' }, [
    el('span', { style: 'flex:1' }, ['메시지 삭제됨']),
    el(
      'button',
      {
        class: 'msg-action',
        style: 'background:rgba(255,255,255,0.12);padding:3px 10px;margin-left:10px;border-radius:6px;border:0;color:inherit;cursor:pointer',
        onclick: () => { node.remove(); restoreFromUndo(messageId); },
      },
      ['되돌리기'],
    ),
  ]);
  node.style.display = 'flex';
  node.style.alignItems = 'center';
  root.appendChild(node);
  setTimeout(() => {
    node.style.transition = 'opacity 0.2s ease';
    node.style.opacity = '0';
    setTimeout(() => node.remove(), 220);
  }, 5_000);
}

async function restoreFromUndo(messageId) {
  const entry = undoStateByMsg.get(messageId);
  if (!entry) { toast('되돌리기 시간 초과', 'error'); return; }
  if (Date.now() > entry.expiresAt) {
    undoStateByMsg.delete(messageId);
    toast('되돌리기 시간 초과', 'error'); return;
  }
  undoStateByMsg.delete(messageId);
  const ta = document.querySelector(`.panel[data-conv="${entry.convId}"] .panel-input textarea`);
  if (ta) {
    // Stage the restored body into the input; user confirms by Enter.
    ta.value = entry.plaintext;
    ta.dispatchEvent(new Event('input'));
    ta.focus();
    toast('입력창에 복원했어요. Enter 로 다시 전송', 'good');
  } else {
    // Fallback: send immediately.
    const conv = state.conversations.find((c) => c.id === entry.convId);
    if (conv) {
      const dummy = document.createElement('textarea');
      dummy.value = entry.plaintext;
      sendMessage(dummy, entry.convId);
    }
  }
}

// Hook into doDelete: capture plaintext + convId BEFORE the server
// delete propagates and replaces _plaintext with the tombstone.
const __veilOriginalDoDelete = doDelete;
doDelete = async function (messageId) {
  // Find the message we're about to delete so we can stash the body
  // for undo before the WS event clobbers _plaintext.
  let captured = null;
  for (const [convId, list] of state.messagesByConv) {
    const m = list.find((x) => x.id === messageId);
    if (m && typeof m._plaintext === 'string') {
      captured = {
        messageId,
        convId,
        plaintext: m._plaintext,
        replyToId: m._replyTo ?? null,
      };
      break;
    }
  }
  await __veilOriginalDoDelete(messageId);
  if (captured) offerDeleteUndo(captured);
};

// ---------- Phase AM: unified Settings dialog ----------
// Replaces the existing "🔔 사운드 토글" and "⌨️ 단축키" menu entries
// with a single "⚙️ 설정" item that opens a structured dialog. The
// dialog hosts theme / sounds / language / notifications all in one
// place — discoverability win, single mental model.

function openSettingsDialog() {
  const id = 'settings-dialog';
  let back = document.getElementById(id);
  if (back) back.remove();
  back = document.createElement('div');
  back.id = id;
  back.className = 'dialog-backdrop';
  back.setAttribute('role', 'presentation');
  back.innerHTML = `
    <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="settings-title" style="width:380px;max-width:92vw">
      <div class="dialog-title" id="settings-title">⚙️ 설정</div>
      <div class="dialog-sub" style="margin-bottom:12px">VEIL 의 모든 토글을 한 곳에.</div>
      <div class="settings-row">
        <div class="settings-label">테마</div>
        <select class="settings-select" data-key="theme">
          <option value="dark">다크</option>
          <option value="light">라이트</option>
        </select>
      </div>
      <div class="settings-row">
        <div class="settings-label">언어 (재로드 필요)</div>
        <select class="settings-select" data-key="lang">
          <option value="ko">한국어</option>
          <option value="en">English</option>
          <option value="ja">日本語</option>
        </select>
      </div>
      <div class="settings-row">
        <div class="settings-label">사운드 (수신/전송 톤)</div>
        <input type="checkbox" class="settings-toggle" data-key="sounds" />
      </div>
      <div class="settings-row">
        <div class="settings-label">브라우저 알림</div>
        <button class="btn btn-ghost" data-key="notif">권한 요청</button>
      </div>
      <div class="dialog-actions" style="margin-top:14px">
        <button class="btn btn-primary" id="settings-close">닫기</button>
      </div>
    </div>
  `;
  // Inline a small style block once.
  if (!document.getElementById('settings-dialog-styles')) {
    const s = document.createElement('style');
    s.id = 'settings-dialog-styles';
    s.textContent = `
      .settings-row {
        display: flex; align-items: center; justify-content: space-between;
        padding: 10px 0; border-top: 1px solid rgba(255,255,255,0.06);
      }
      .settings-row:first-of-type { border-top: 0; }
      .settings-label { font-size: 13px; }
      .settings-select {
        background: rgba(255,255,255,0.06);
        border: 1px solid rgba(255,255,255,0.1);
        color: inherit; padding: 4px 8px;
        border-radius: 6px; font-size: 13px;
      }
      .settings-toggle { width: 18px; height: 18px; }
    `;
    document.head.appendChild(s);
  }
  document.body.appendChild(back);

  // Initial values.
  const themeSel = back.querySelector('[data-key="theme"]');
  const langSel = back.querySelector('[data-key="lang"]');
  const sounds = back.querySelector('[data-key="sounds"]');
  themeSel.value = document.documentElement.classList.contains('theme-light') ? 'light' : 'dark';
  langSel.value = (typeof activeLang === 'function' ? activeLang() : 'ko');
  sounds.checked = !!state.soundsEnabled;

  themeSel.addEventListener('change', () => {
    if (themeSel.value === 'light') {
      document.documentElement.classList.add('theme-light');
    } else {
      document.documentElement.classList.remove('theme-light');
    }
    try { localStorage.setItem('veil-demo-theme', themeSel.value); } catch {}
  });
  langSel.addEventListener('change', () => {
    if (typeof setLang === 'function') setLang(langSel.value);
  });
  sounds.addEventListener('change', () => {
    state.soundsEnabled = sounds.checked;
    try { localStorage.setItem(SOUND_KEY, state.soundsEnabled ? '1' : '0'); } catch {}
  });
  back.querySelector('[data-key="notif"]').addEventListener('click', async () => {
    if (!('Notification' in window)) { toast('알림 미지원 브라우저', 'error'); return; }
    if (Notification.permission === 'granted') { toast('이미 켜짐', 'good'); return; }
    if (Notification.permission === 'denied') { toast('브라우저 설정에서 풀어주세요', 'error'); return; }
    const r = await Notification.requestPermission();
    toast(r === 'granted' ? '알림 켜짐' : '알림 거부됨', r === 'granted' ? 'good' : 'error');
  });
  const close = () => back.remove();
  back.querySelector('#settings-close').addEventListener('click', close);
  back.addEventListener('click', (e) => { if (e.target === back) close(); });
  back.querySelector('#settings-close').focus();
}

// Apply the saved theme immediately on every load (before render).
try {
  if (localStorage.getItem('veil-demo-theme') === 'light') {
    document.documentElement.classList.add('theme-light');
  }
} catch {}

// Inject "⚙️ 설정" into the menu, deprecating the standalone sound +
// shortcut items (move shortcut-help into settings dialog later if
// wanted; for now the keyboard shortcut Ctrl/Cmd+/ still opens the
// help dialog separately).
setTimeout(() => {
  const menu = document.getElementById('menu');
  if (!menu) return;
  if (menu.querySelector('[data-action="open-settings"]')) return;
  const sep = menu.querySelector('.menu-sep');
  const settings = document.createElement('button');
  settings.className = 'menu-item';
  settings.dataset.action = 'open-settings';
  settings.setAttribute('role', 'menuitem');
  settings.textContent = '⚙️ 설정';
  if (sep) menu.insertBefore(settings, sep); else menu.appendChild(settings);
  menu.addEventListener('click', (e) => {
    if (e.target?.dataset?.action === 'open-settings') {
      menu.classList.add('hidden');
      openSettingsDialog();
    }
  }, true);
}, 0);

// ---------- Phase AQ: code blocks + generic files + forward + WS retry ----------

const aqStyles = document.createElement('style');
aqStyles.textContent = `
  /* Multiline code block */
  .msg-text pre.msg-codeblock {
    background: rgba(0,0,0,0.35);
    border: 1px solid rgba(255,255,255,0.06);
    border-radius: 8px;
    padding: 10px 12px;
    margin: 6px 0 4px;
    overflow-x: auto;
    max-width: 100%;
  }
  html.theme-light .msg-text pre.msg-codeblock {
    background: rgba(0,0,0,0.04);
    border-color: rgba(0,0,0,0.08);
  }
  .msg-text pre.msg-codeblock code {
    background: transparent;
    padding: 0; border: 0;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 12px; line-height: 1.5;
    white-space: pre; color: inherit;
  }
  .msg-text pre.msg-codeblock[data-lang]::before {
    content: attr(data-lang);
    display: block; font-size: 10px; opacity: 0.5;
    margin-bottom: 4px; text-transform: lowercase;
    font-family: var(--font);
  }

  /* Generic file chip */
  .msg-file-chip {
    display: inline-flex; align-items: center; gap: 10px;
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 10px;
    padding: 8px 12px;
    margin-top: 4px;
    text-decoration: none;
    color: inherit; cursor: pointer;
    max-width: 280px;
  }
  .msg-file-chip:hover { background: rgba(255,255,255,0.1); }
  html.theme-light .msg-file-chip { background: rgba(0,0,0,0.03); border-color: rgba(0,0,0,0.06); }
  .msg-file-chip-icon {
    width: 36px; height: 36px; flex-shrink: 0;
    background: rgba(108, 142, 255, 0.18); border-radius: 8px;
    display: flex; align-items: center; justify-content: center;
    font-size: 18px;
  }
  .msg-file-chip-meta { display: flex; flex-direction: column; min-width: 0; }
  .msg-file-chip-name {
    font-size: 13px;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }
  .msg-file-chip-size { font-size: 11px; opacity: 0.6; }

  /* Forward dialog */
  .forward-list {
    max-height: 300px; overflow-y: auto;
    margin: 8px 0;
    border: 1px solid rgba(255,255,255,0.08); border-radius: 8px;
  }
  .forward-list-item {
    display: flex; align-items: center; gap: 10px;
    padding: 8px 12px; cursor: pointer;
    border-bottom: 1px solid rgba(255,255,255,0.04);
  }
  .forward-list-item:last-child { border-bottom: 0; }
  .forward-list-item:hover { background: rgba(108, 142, 255, 0.12); }
  .forward-list-item.selected { background: rgba(108, 142, 255, 0.22); }

  /* Connection retry counter inside the conn pill */
  #conn-pill .retry-count {
    margin-left: 4px;
    font-size: 10px;
    opacity: 0.7;
  }
`;
document.head.appendChild(aqStyles);

const FILE_MAX_BYTES = 25 * 1024 * 1024;
const FILE_ICON_BY_PREFIX = {
  'application/pdf': '📄',
  'video/': '🎬',
  'audio/': '🎵',
  'text/': '📝',
  'application/zip': '📦',
  'application/x-': '📦',
  'application/octet-stream': '📁',
};
function fileIconFor(mime) {
  for (const [prefix, icon] of Object.entries(FILE_ICON_BY_PREFIX)) {
    if (mime.startsWith(prefix)) return icon;
  }
  return '📁';
}
// formatBytes is the shared lib/format.js helper. Local alias keeps
// the existing call sites unchanged.
const formatBytes = fmtBytes;

async function pickAndSendFile(convId) {
  const input = document.createElement('input');
  input.type = 'file';
  input.addEventListener('change', () => {
    const file = input.files?.[0];
    if (!file) return;
    if (IMAGE_MIME_ALLOW.has(file.type)) { showImagePreview(convId, file); return; }
    if (file.size > FILE_MAX_BYTES) { toast('파일이 25MB 를 초과합니다', 'error'); return; }
    sendGenericFile(convId, file);
  });
  input.click();
}

async function sendGenericFile(convId, file) {
  const conv = state.conversations.find((c) => c.id === convId);
  if (!conv) return;
  const peer = conv.members.find((m) => m.userId !== state.me.userId);
  const clientMessageId = 'file-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);

  const optimistic = {
    id: '__pending__' + clientMessageId,
    clientMessageId,
    conversationId: convId,
    senderDeviceId: state.me.deviceId,
    ciphertext: '', nonce: '',
    messageType: 'file',
    serverReceivedAt: null,
    _localAt: new Date().toISOString(),
    _status: 'pending',
    _fileMeta: { name: file.name, sizeBytes: file.size, mime: file.type },
    _plaintext: `📁 ${file.name}`,
  };
  const list = state.messagesByConv.get(convId) || [];
  list.push(optimistic);
  state.messagesByConv.set(convId, list);
  renderActivePanel();

  try {
    const aesKey = await crypto.subtle.generateKey(
      { name: 'AES-GCM', length: 256 }, true, ['encrypt', 'decrypt'],
    );
    const nonce = crypto.getRandomValues(new Uint8Array(12));
    const plaintext = await file.arrayBuffer();
    const ciphertext = await crypto.subtle.encrypt(
      { name: 'AES-GCM', iv: nonce }, aesKey, plaintext,
    );
    const sha = await crypto.subtle.digest('SHA-256', ciphertext);
    const shaHex = Array.from(new Uint8Array(sha))
      .map((b) => b.toString(16).padStart(2, '0')).join('');
    const ticket = await authedApi('/attachments/upload-ticket', {
      method: 'POST',
      body: { contentType: 'application/octet-stream', sizeBytes: ciphertext.byteLength, sha256: shaHex },
    });
    const putRes = await fetch(ticket.upload.uploadUrl, {
      method: 'PUT', headers: ticket.upload.headers, body: ciphertext,
    });
    if (!putRes.ok) throw new Error(`upload PUT failed: ${putRes.status}`);
    await authedApi('/attachments/complete', {
      method: 'POST',
      body: { attachmentId: ticket.attachmentId, uploadStatus: 'uploaded' },
    });

    const rawKey = await crypto.subtle.exportKey('raw', aesKey);
    const bodyPayload = JSON.stringify({
      kind: 'file', attachmentId: ticket.attachmentId,
      mime: file.type || 'application/octet-stream',
      name: file.name, sizeBytes: file.size,
      key: b64uEncode(rawKey), nonce: b64uEncode(nonce),
    });
    const envelope = await encryptForConv(convId, bodyPayload);
    if (!envelope) throw new Error('상대 키를 못 찾았어요');

    const sent = await authedApi('/messages', {
      method: 'POST',
      body: {
        conversationId: convId, clientMessageId,
        envelope: {
          version: 'veil-envelope-v1-dev',
          conversationId: convId,
          senderDeviceId: state.me.deviceId,
          recipientUserId: peer.userId,
          ciphertext: envelope.ciphertext, nonce: envelope.nonce,
          messageType: 'file',
          attachment: {
            attachmentId: ticket.attachmentId,
            storageKey: ticket.upload.storageKey ?? '',
            contentType: 'application/octet-stream',
            sizeBytes: ciphertext.byteLength,
            sha256: shaHex,
            encryption: {
              encryptedKey: 'web-demo-inline-in-body',
              nonce: b64uEncode(nonce),
              algorithmHint: 'dev-wrap',
            },
          },
        },
      },
    });

    sent.message._fileMeta = {
      name: file.name, sizeBytes: file.size, mime: file.type,
      attachmentId: ticket.attachmentId,
      key: b64uEncode(rawKey), nonce: b64uEncode(nonce),
    };
    sent.message._plaintext = `📁 ${file.name}`;
    const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
    if (idx >= 0) list[idx] = sent.message;
    conv.lastMessage = sent.message;
    persistMessage(sent.message);
    persistConversation(conv);
    renderActivePanel();
    renderSidebar();
    playSendTone();
  } catch (e) {
    toast('파일 전송 실패: ' + (e.message || 'unknown'), 'error');
    const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
    if (idx >= 0) list[idx] = { ...list[idx], _status: 'failed' };
    renderActivePanel();
  }
}

async function maybeMaterializeFile(msg) {
  if (msg.messageType !== 'file') return;
  if (msg._fileMeta?.attachmentId && msg._fileMeta.key) return;
  if (typeof msg._plaintext !== 'string') return;
  try {
    const payload = JSON.parse(msg._plaintext);
    if (payload?.kind !== 'file') return;
    msg._fileMeta = {
      name: payload.name, sizeBytes: payload.sizeBytes, mime: payload.mime,
      attachmentId: payload.attachmentId, key: payload.key, nonce: payload.nonce,
    };
    msg._plaintext = `📁 ${payload.name}`;
    if (msg.conversationId === state.activeConv || msg.conversationId === state.secondaryConv) {
      renderActivePanel();
    }
  } catch {}
}

async function downloadFile(messageId) {
  let msg = null;
  for (const list of state.messagesByConv.values()) {
    msg = list.find((x) => x.id === messageId);
    if (msg) break;
  }
  if (!msg?._fileMeta?.attachmentId || !msg._fileMeta.key) return;
  const meta = msg._fileMeta;
  try {
    toast(`다운로드 중: ${meta.name}…`);
    const ticket = await authedApi(`/attachments/${meta.attachmentId}/download-ticket`);
    const res = await fetch(ticket.ticket.downloadUrl);
    if (!res.ok) throw new Error('download failed: ' + res.status);
    const buf = await res.arrayBuffer();
    const aesKey = await crypto.subtle.importKey(
      'raw', b64uDecode(meta.key), { name: 'AES-GCM' }, false, ['decrypt'],
    );
    const nonce = new Uint8Array(b64uDecode(meta.nonce));
    const plaintext = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: nonce }, aesKey, buf,
    );
    const blob = new Blob([plaintext], { type: meta.mime || 'application/octet-stream' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = meta.name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
  } catch (e) {
    toast('다운로드 실패: ' + (e.message || 'unknown'), 'error');
  }
}

// File chip click → download. Single delegation handles all chips.
document.addEventListener('click', (e) => {
  const dl = e.target.closest('.msg-file-chip');
  if (!dl) return;
  const id = dl.dataset.msgId;
  if (id) downloadFile(id);
}, true);

// Forward dialog — pick another conversation, send the same plaintext
// as a fresh message (no quote header, no edit linkage).
function openForwardDialog(msg) {
  if (typeof msg._plaintext !== 'string' || msg._plaintext === '') {
    toast('전달할 내용이 없어요', 'error'); return;
  }
  const others = state.conversations.filter((c) => c.id !== msg.conversationId);
  if (others.length === 0) { toast('전달할 다른 대화가 없어요'); return; }
  const back = document.createElement('div');
  back.className = 'dialog-backdrop';
  back.setAttribute('role', 'presentation');
  back.innerHTML = `
    <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="fwd-title" style="width:380px;max-width:92vw">
      <div class="dialog-title" id="fwd-title">메시지 전달</div>
      <div class="dialog-sub">전달할 대화를 고르세요. 원본 인용 없이 새 메시지로 보내져요.</div>
      <div class="forward-list"></div>
      <div class="dialog-actions">
        <button class="btn btn-ghost" id="fwd-cancel">취소</button>
        <button class="btn btn-primary" id="fwd-confirm" disabled>전달</button>
      </div>
    </div>
  `;
  document.body.appendChild(back);
  const list = back.querySelector('.forward-list');
  let selected = null;
  for (const c of others) {
    const peer = c.members?.find((m) => m.userId !== state.me?.userId);
    const item = document.createElement('div');
    item.className = 'forward-list-item';
    item.dataset.convId = c.id;
    item.appendChild(avatarFor(peer?.handle ?? '?', 'sm'));
    const meta = document.createElement('div');
    meta.style.flex = '1';
    meta.innerHTML = `<div>@${escapeHtml(peer?.handle ?? '?')}</div>` +
      (peer?.displayName ? `<div style="font-size:11px;opacity:0.6">${escapeHtml(peer.displayName)}</div>` : '');
    item.appendChild(meta);
    item.addEventListener('click', () => {
      list.querySelectorAll('.forward-list-item').forEach((x) => x.classList.remove('selected'));
      item.classList.add('selected');
      selected = c.id;
      back.querySelector('#fwd-confirm').disabled = false;
    });
    list.appendChild(item);
  }
  const close = () => back.remove();
  back.querySelector('#fwd-cancel').addEventListener('click', close);
  back.addEventListener('click', (e) => { if (e.target === back) close(); });
  back.querySelector('#fwd-confirm').addEventListener('click', async () => {
    if (!selected) return;
    const ta = document.createElement('textarea');
    ta.value = msg._plaintext;
    close();
    await sendMessage(ta, selected);
    toast('전달했습니다', 'good');
  });
}

// Inject 🔁 전달 into the action menu when it appears. Same observer
// pattern Phase AY uses for the file chip.
const __veilMenuObserver = new MutationObserver(() => {
  document.querySelectorAll('.msg-action-menu').forEach((menu) => {
    if (menu.dataset.veilFwdAdded === '1') return;
    menu.dataset.veilFwdAdded = '1';
    if (!activeActionMenu) return;
    // We can't recover the message from the menu alone, so we rebuild
    // by sniffing the most recently-clicked .msg-row via dataset.
    const lastRow = document.querySelector('.msg-row[data-veil-last-context="1"]');
    const msgId = lastRow?.dataset?.msgId;
    if (!msgId) return;
    let target = null;
    for (const list of state.messagesByConv.values()) {
      const m = list.find((x) => x.id === msgId);
      if (m) { target = m; break; }
    }
    if (!target) return;
    const fwd = document.createElement('button');
    fwd.className = 'msg-action-item';
    fwd.textContent = '🔁  전달';
    fwd.addEventListener('click', (ev) => {
      ev.stopPropagation();
      closeActionMenu();
      openForwardDialog(target);
    });
    menu.appendChild(fwd);
  });
});
setTimeout(() => __veilMenuObserver.observe(document.body, { childList: true, subtree: true }), 0);
// Mark the row that owned the most recent context-menu so we can
// recover the message in the menu observer above.
document.addEventListener('contextmenu', (e) => {
  document.querySelectorAll('.msg-row[data-veil-last-context]').forEach(
    (n) => n.removeAttribute('data-veil-last-context'),
  );
  const row = e.target.closest('.msg-row');
  if (row) row.dataset.veilLastContext = '1';
});
document.addEventListener('touchstart', (e) => {
  document.querySelectorAll('.msg-row[data-veil-last-context]').forEach(
    (n) => n.removeAttribute('data-veil-last-context'),
  );
  const row = e.target.closest('.msg-row');
  if (row) row.dataset.veilLastContext = '1';
}, { passive: true });

// 📎 file picker button next to 📷 image button.
const __veilFileBtnObserver = new MutationObserver(() => {
  document.querySelectorAll('.panel-input').forEach((node) => {
    if (node.querySelector('.file-btn')) return;
    const imgBtn = node.querySelector('.image-btn');
    if (!imgBtn) return;
    const btn = document.createElement('button');
    btn.className = 'file-btn image-btn';
    btn.setAttribute('aria-label', '파일 첨부');
    btn.title = '파일 첨부 (PDF / 비디오 / 기타)';
    btn.innerHTML = '<span aria-hidden="true">📎</span>';
    btn.style.fontSize = '16px';
    imgBtn.parentNode?.insertBefore(btn, imgBtn);
    btn.addEventListener('click', () => {
      const panel = btn.closest('.panel');
      const convId = panel?.dataset?.conv;
      if (convId) pickAndSendFile(convId);
    });
  });
});
setTimeout(() => {
  const panels = document.getElementById('panels');
  if (panels) __veilFileBtnObserver.observe(panels, { childList: true, subtree: true });
}, 0);

// File-message bubble swap: replace the text span with a chip when
// the row is for a file message. Idempotent via dataset flag.
const __veilFileChipObserver = new MutationObserver(() => {
  document.querySelectorAll('.msg-row[data-msg-id]').forEach((row) => {
    if (row.dataset.veilFileChipDone === '1') return;
    const msgId = row.dataset.msgId;
    if (!msgId) return;
    let msg = null;
    for (const list of state.messagesByConv.values()) {
      msg = list.find((x) => x.id === msgId);
      if (msg) break;
    }
    if (!msg || msg.messageType !== 'file' || !msg._fileMeta) return;
    const text = row.querySelector('.msg-text');
    if (!text) return;
    row.dataset.veilFileChipDone = '1';
    const chip = document.createElement('div');
    chip.className = 'msg-file-chip';
    chip.dataset.msgId = msgId;
    chip.innerHTML = `
      <div class="msg-file-chip-icon">${fileIconFor(msg._fileMeta.mime || 'application/octet-stream')}</div>
      <div class="msg-file-chip-meta">
        <div class="msg-file-chip-name">${escapeHtml(msg._fileMeta.name)}</div>
        <div class="msg-file-chip-size">${formatBytes(msg._fileMeta.sizeBytes || 0)} · 클릭해서 다운로드</div>
      </div>
    `;
    text.replaceChildren(chip);
  });
});
setTimeout(() => {
  const panels = document.getElementById('panels');
  if (panels) __veilFileChipObserver.observe(panels, { childList: true, subtree: true });
}, 0);

// --- WS connection retry visual ---
// socket.io's auto-reconnect is silent. Add a small badge on the
// conn pill while we're in a backoff window so the user sees the
// retry count instead of the generic "재연결 중…".
let __veilRetryCount = 0;
let __veilRetryWired = false;
function wireRetryVisual() {
  if (__veilRetryWired || !state.socket) return;
  __veilRetryWired = true;
  const s = state.socket;
  s.io?.on?.('reconnect_attempt', (attempt) => {
    __veilRetryCount = attempt;
    const pill = document.getElementById('conn-pill');
    if (!pill) return;
    let badge = pill.querySelector('.retry-count');
    if (!badge) {
      badge = document.createElement('span');
      badge.className = 'retry-count';
      pill.appendChild(badge);
    }
    badge.textContent = `(${attempt})`;
  });
  s.io?.on?.('reconnect', () => {
    __veilRetryCount = 0;
    const badge = document.querySelector('#conn-pill .retry-count');
    if (badge) badge.remove();
  });
  s.on?.('connect', () => {
    __veilRetryCount = 0;
    const badge = document.querySelector('#conn-pill .retry-count');
    if (badge) badge.remove();
  });
}
setInterval(() => {
  if (state.socket && !__veilRetryWired) wireRetryVisual();
  if (!state.socket) __veilRetryWired = false;
}, 1000);

// Hook file materialization into the existing decrypt path.
const __veilOriginalDecryptMessage = decryptMessage;
decryptMessage = async function (msg) {
  await __veilOriginalDecryptMessage(msg);
  if (msg.messageType === 'file') await maybeMaterializeFile(msg);
};

// ---------- Phase AS: KakaoTalk import wizard ----------
// Korean-market killer feature. User picks an exported .txt; we parse
// in-browser, store the result in IndexedDB as a read-only archive,
// and surface it in the sidebar with a 📥 prefix so it's obviously
// not a live conversation. The bytes never leave the device.

const KAKAO_ARCHIVE_STORE = 'kakao-archives';

const asStyles = document.createElement('style');
asStyles.textContent = `
  .kakao-import-summary {
    background: rgba(255,205,80,0.08);
    border: 1px solid rgba(255,205,80,0.18);
    border-radius: 8px;
    padding: 10px 12px;
    margin: 10px 0;
    font-size: 12px;
  }
  .kakao-import-summary strong { color: #ffd25c; }
  .kakao-archive-banner {
    background: rgba(255,205,80,0.06);
    border-bottom: 1px solid rgba(255,205,80,0.2);
    padding: 8px 16px;
    font-size: 12px;
    text-align: center;
  }
  .kakao-archive-banner strong { color: #ffd25c; }
  .kakao-conv-prefix { color: #ffd25c; margin-right: 4px; }
`;
document.head.appendChild(asStyles);

// Read the file → parse → preview → save flow lives in one dialog.
function openKakaoImportDialog() {
  const back = document.createElement('div');
  back.className = 'dialog-backdrop';
  back.setAttribute('role', 'presentation');
  back.innerHTML = `
    <div class="dialog" role="dialog" aria-modal="true" aria-labelledby="kakao-title" style="width:480px;max-width:92vw">
      <div class="dialog-title" id="kakao-title">📥 카카오톡 채팅 가져오기</div>
      <div class="dialog-sub">
        카톡 → 채팅방 → 설정 → <strong>대화 내용 내보내기</strong> →
        텍스트 파일 (.txt) 받은 거 여기에 떨어뜨리세요. <strong>읽기
        전용 아카이브</strong>로 저장되며, 이 브라우저 밖으로 절대 나가지 않아요.
      </div>
      <input type="file" id="kakao-file" accept=".txt,text/plain" />
      <div id="kakao-preview" class="hidden" style="margin-top:14px"></div>
      <div class="dialog-error" id="kakao-error" role="alert" aria-live="polite"></div>
      <div class="dialog-actions">
        <button class="btn btn-ghost" id="kakao-cancel">취소</button>
        <button class="btn btn-primary" id="kakao-confirm" disabled>아카이브로 저장</button>
      </div>
    </div>
  `;
  document.body.appendChild(back);

  let parsed = null;
  let archiveTitle = '';

  const fileInput = back.querySelector('#kakao-file');
  const previewBox = back.querySelector('#kakao-preview');
  const errorBox = back.querySelector('#kakao-error');
  const confirmBtn = back.querySelector('#kakao-confirm');
  const cancelBtn = back.querySelector('#kakao-cancel');

  fileInput.addEventListener('change', async () => {
    errorBox.textContent = '';
    const file = fileInput.files?.[0];
    if (!file) return;
    if (!file.name.endsWith('.txt')) {
      errorBox.textContent = '.txt 파일만 지원합니다.';
      return;
    }
    if (file.size > 50 * 1024 * 1024) {
      errorBox.textContent = '50MB 초과 — 아카이브 분할이 필요해요.';
      return;
    }
    try {
      const text = await file.text();
      parsed = parseKakaoExport(text);
      archiveTitle = file.name.replace(/\.txt$/i, '');
      const summary = `
        <div class="kakao-import-summary">
          <div><strong>${parsed.messages.filter((m) => m.kind === 'msg').length}</strong> 개 메시지</div>
          <div><strong>${parsed.participants.length}</strong> 명 참여 (${parsed.participants.slice(0, 4).map(escapeHtml).join(', ')}${parsed.participants.length > 4 ? ` 외 ${parsed.participants.length - 4}명` : ''})</div>
          ${parsed.errors.length > 0 ? `<div style="opacity:0.7;margin-top:4px">파싱 경고 ${parsed.errors.length}건 (계속 진행 가능)</div>` : ''}
        </div>
      `;
      previewBox.innerHTML = summary;
      previewBox.classList.remove('hidden');
      confirmBtn.disabled = false;
    } catch (e) {
      errorBox.textContent = '파일을 읽지 못했어요: ' + (e.message || 'unknown');
    }
  });

  const close = () => back.remove();
  cancelBtn.addEventListener('click', close);
  back.addEventListener('click', (e) => { if (e.target === back) close(); });
  confirmBtn.addEventListener('click', async () => {
    if (!parsed) return;
    confirmBtn.disabled = true;
    try {
      const archiveId = 'kakao-' + Date.now().toString(36);
      await idbPut(KAKAO_ARCHIVE_STORE, {
        id: archiveId,
        title: archiveTitle,
        importedAt: new Date().toISOString(),
        participants: parsed.participants,
        messageCount: parsed.messages.filter((m) => m.kind === 'msg').length,
        messages: parsed.messages,
      });
      toast('아카이브로 저장됨', 'good');
      close();
      await refreshKakaoArchivesInSidebar();
    } catch (e) {
      errorBox.textContent = '저장 실패: ' + (e.message || 'unknown');
      confirmBtn.disabled = false;
    }
  });
}

// Append Kakao archives to the sidebar conv list. We treat each
// archive as a pseudo-conversation with id "kakao-..." so existing
// click handlers route through the read-only viewer below.
async function loadKakaoArchives() {
  try {
    return await idbAll(KAKAO_ARCHIVE_STORE);
  } catch {
    return [];
  }
}

async function refreshKakaoArchivesInSidebar() {
  // Trigger a sidebar re-render. The renderSidebar function below has
  // a small extension to splice in archive rows.
  if (typeof renderSidebar === 'function') renderSidebar();
}

// Open archive → render messages in the right panel as read-only.
function openKakaoArchive(archive) {
  const main = document.getElementById('main') || document.getElementById('panels');
  if (!main) return;
  // Replace the panels container content with a read-only archive view.
  const panels = document.getElementById('panels');
  if (!panels) return;
  panels.replaceChildren(renderKakaoArchivePanel(archive));
  state.activeConv = archive.id; // so highlight + actions don't break
}

function renderKakaoArchivePanel(archive) {
  const wrap = el('div', { class: 'panel', dataset: { conv: archive.id } });
  wrap.appendChild(el('div', { class: 'panel-header' }, [
    avatarFor(archive.title || 'kakao', 'md'),
    el('div', { class: 'panel-title' }, [
      el('div', { class: 'name' }, ['📥 ' + (archive.title || '카카오 아카이브')]),
      el('div', { class: 'sub' }, [`${archive.messageCount} 메시지 · 읽기 전용`]),
    ]),
  ]));
  wrap.appendChild(el('div', { class: 'kakao-archive-banner' }, [
    '📥 ',
    el('strong', {}, ['카카오톡 아카이브']),
    ' — 답장 / 전송 불가. 이 브라우저에만 저장됨.',
  ]));
  const list = el('div', { class: 'msgs', style: 'flex:1;overflow-y:auto;padding:14px' });
  let lastDay = null;
  for (const m of archive.messages) {
    if (m.kind === 'system') {
      list.appendChild(el('div', { class: 'day-divider' }, [el('span', {}, [m.body])]));
      continue;
    }
    if (!m.sender || !m.sentAt) continue;
    const d = new Date(m.sentAt);
    const dk = dayKey(d);
    if (dk !== lastDay) {
      list.appendChild(el('div', { class: 'day-divider' }, [el('span', {}, [dayLabel(d)])]));
      lastDay = dk;
    }
    const isMe = false; // Without auth context we can't tell; treat all as "them".
    const bubble = el('div', { class: 'msg first-of-group last-of-group' }, [
      el('span', { class: 'msg-text' }, [m.body]),
    ]);
    const stack = el('div', { class: 'group-stack' }, [
      el('div', { class: 'group-meta' }, [m.sender]),
      el('div', { class: 'msg-row them' }, [bubble]),
      el('div', { class: 'msg-time' }, [formatTime(d)]),
    ]);
    list.appendChild(stack);
  }
  wrap.appendChild(list);
  return wrap;
}

// Hook into renderSidebar to splice archives at the bottom. We patch
// the function via wrapping (it's a function declaration, mutable
// binding works inside the same module).
const __veilOriginalRenderSidebar = renderSidebar;
renderSidebar = function () {
  __veilOriginalRenderSidebar();
  // After the original render has populated the conv list, append a
  // small section for any Kakao archives.
  loadKakaoArchives().then((archives) => {
    if (!archives || archives.length === 0) return;
    const list = document.getElementById('conv-list');
    if (!list) return;
    if (list.querySelector('[data-kakao-section]')) return;
    const sep = document.createElement('div');
    sep.dataset.kakaoSection = '1';
    sep.style.cssText = 'padding:10px 14px 4px;font-size:11px;opacity:0.55;letter-spacing:0.05em;text-transform:uppercase';
    sep.textContent = '카카오 아카이브';
    list.appendChild(sep);
    for (const a of archives) {
      const row = document.createElement('button');
      row.className = 'conv-item';
      row.style.cssText = 'background:transparent;border:0;color:inherit;cursor:pointer;width:100%;display:flex;align-items:center;gap:10px;padding:10px 14px;text-align:left';
      const avatar = avatarFor(a.title || 'kakao', 'sm');
      const meta = document.createElement('div');
      meta.style.flex = '1';
      meta.innerHTML = `
        <div style="font-size:13px"><span class="kakao-conv-prefix">📥</span>${escapeHtml(a.title || '아카이브')}</div>
        <div style="font-size:11px;opacity:0.6">${a.messageCount} 메시지 · 읽기 전용</div>
      `;
      row.appendChild(avatar); row.appendChild(meta);
      row.addEventListener('click', () => openKakaoArchive(a));
      list.appendChild(row);
    }
  }).catch(() => {});
};

// Inject "📥 카카오톡 가져오기" into the menu before the danger zone.
setTimeout(() => {
  const menu = document.getElementById('menu');
  if (!menu) return;
  if (menu.querySelector('[data-action="kakao-import"]')) return;
  const sep = menu.querySelector('.menu-sep');
  const item = document.createElement('button');
  item.className = 'menu-item';
  item.dataset.action = 'kakao-import';
  item.setAttribute('role', 'menuitem');
  item.textContent = '📥 카카오톡 가져오기';
  if (sep) menu.insertBefore(item, sep); else menu.appendChild(item);
  menu.addEventListener('click', (e) => {
    if (e.target?.dataset?.action === 'kakao-import') {
      menu.classList.add('hidden');
      openKakaoImportDialog();
    }
  }, true);
}, 0);

// Make sure the IDB has the kakao-archives store. The session store
// upgrade path is in idb.* helpers; we extend the schema by adding a
// new object store on the same DB. If the helpers don't expose
// migrate-on-open, this will silently fail and the user will see a
// "저장 실패" toast — acceptable for a non-critical archive feature.
(async () => {
  try {
    if (typeof __veilEnsureIdbStore === 'function') {
      await __veilEnsureIdbStore(KAKAO_ARCHIVE_STORE);
    }
  } catch {}
})();

// ---------- Phase AT: block / mute / report UI ----------
// Server endpoints already exist (apps/api/src/modules/safety):
//   GET    /safety/blocks               list my blocked users
//   POST   /safety/blocks  {userId}     block
//   DELETE /safety/blocks/:userId       unblock
//   POST   /safety/mutes/:cid {mutedForSeconds}  mute (null = unmute)
//   POST   /safety/reports {...}        file an abuse report
// This phase wires UI on top: action-menu entries for peer messages,
// a header toggle for conversation mute, a list inside the settings
// dialog for managing blocks.

const atStyles = document.createElement('style');
atStyles.textContent = `
  .blocked-list {
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 8px;
    margin-top: 6px;
    max-height: 220px;
    overflow-y: auto;
  }
  .blocked-list:empty::before {
    content: '차단된 사용자 없음';
    display: block;
    padding: 12px;
    opacity: 0.55;
    font-size: 12px;
    text-align: center;
  }
  .blocked-row {
    display: flex; align-items: center; gap: 10px;
    padding: 8px 12px;
    border-bottom: 1px solid rgba(255,255,255,0.04);
  }
  .blocked-row:last-child { border-bottom: 0; }
  .blocked-row .grow { flex: 1; min-width: 0; }
  .blocked-row .unblock {
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.1);
    color: inherit; padding: 3px 10px;
    border-radius: 6px; font-size: 12px;
    cursor: pointer;
  }
  .blocked-row .unblock:hover { background: rgba(255,255,255,0.12); }
  html.theme-light .blocked-list { border-color: rgba(0,0,0,0.06); }
  html.theme-light .blocked-row { border-bottom-color: rgba(0,0,0,0.04); }
  .panel-header .mute-toggle {
    background: transparent; border: 0; color: inherit;
    cursor: pointer; padding: 4px 8px; opacity: 0.7;
    margin-left: 6px; font-size: 14px;
  }
  .panel-header .mute-toggle:hover { opacity: 1; }
  .conv-item.muted .conv-meta { opacity: 0.5; }
  .conv-item.muted .conv-name::after { content: ' 🔕'; }
`;
document.head.appendChild(atStyles);

// Per-conversation mute state lives in localStorage so it survives
// reload before we've fetched it from the server. The server is the
// source of truth; we hydrate from the server on loadConversations.
const MUTE_KEY = 'veil-demo-muted-convs-v1';
let mutedConvIds = (() => {
  try { return new Set(JSON.parse(localStorage.getItem(MUTE_KEY) || '[]')); }
  catch { return new Set(); }
})();
function persistMutedConvs() {
  try { localStorage.setItem(MUTE_KEY, JSON.stringify(Array.from(mutedConvIds))); } catch {}
}

async function blockUser(userId, handle) {
  const ok = await uiConfirm({
    title: '@' + handle + ' 차단',
    body: `이 사용자가 보낸 메시지가 더 이상 도착하지 않고, 이 사용자가 보낸 새 채팅도 시작할 수 없게 됩니다. 언제든지 설정에서 해제할 수 있어요.`,
    okLabel: '차단', destructive: true,
  });
  if (!ok) return;
  try {
    await authedApi('/safety/blocks', { method: 'POST', body: { userId } });
    toast(`@${handle} 차단됨`, 'good');
  } catch (e) {
    toast('차단 실패: ' + (e.message || 'unknown'), 'error');
  }
}

async function unblockUser(userId, handle) {
  try {
    await authedApi(`/safety/blocks/${userId}`, { method: 'DELETE' });
    toast(`@${handle} 차단 해제됨`, 'good');
  } catch (e) {
    toast('해제 실패: ' + (e.message || 'unknown'), 'error');
  }
}

async function listBlocked() {
  try {
    const res = await authedApi('/safety/blocks');
    return Array.isArray(res?.items) ? res.items : (Array.isArray(res) ? res : []);
  } catch {
    return [];
  }
}

async function setConversationMute(conversationId, seconds) {
  try {
    await authedApi(`/safety/mutes/${conversationId}`, {
      method: 'POST',
      body: { mutedForSeconds: seconds },
    });
    if (seconds == null || seconds <= 0) {
      mutedConvIds.delete(conversationId);
      toast('알림 켜짐', 'good');
    } else {
      mutedConvIds.add(conversationId);
      toast(`${formatMuteDuration(seconds)} 동안 알림 끔`, 'good');
    }
    persistMutedConvs();
    renderActivePanel();
    renderSidebar();
  } catch (e) {
    toast('알림 설정 실패: ' + (e.message || 'unknown'), 'error');
  }
}

function formatMuteDuration(seconds) {
  if (seconds >= 86400 * 365) return '영구';
  if (seconds >= 86400) return `${Math.round(seconds / 86400)}일`;
  if (seconds >= 3600) return `${Math.round(seconds / 3600)}시간`;
  return `${Math.round(seconds / 60)}분`;
}

async function reportMessage(messageId, peerUserId, peerHandle) {
  const reason = window.prompt(
    `@${peerHandle} 신고 — 사유를 짧게 적어주세요 (이 텍스트는 운영자에게 전송됩니다):`,
  );
  if (!reason || reason.trim().length === 0) return;
  try {
    await authedApi('/safety/reports', {
      method: 'POST',
      body: {
        targetUserId: peerUserId,
        relatedMessageId: messageId,
        category: 'other',
        details: reason.trim(),
      },
    });
    toast('신고 접수됨', 'good');
  } catch (e) {
    toast('신고 실패: ' + (e.message || 'unknown'), 'error');
  }
}

// Hook: extend the action menu with 차단 / 신고 entries for peer
// messages. Same observer pattern Phase AQ uses for forward.
const __veilSafetyMenuObserver = new MutationObserver(() => {
  document.querySelectorAll('.msg-action-menu').forEach((menu) => {
    if (menu.dataset.veilSafetyAdded === '1') return;
    menu.dataset.veilSafetyAdded = '1';
    const lastRow = document.querySelector('.msg-row[data-veil-last-context="1"]');
    const msgId = lastRow?.dataset?.msgId;
    if (!msgId) return;
    let target = null;
    let convId = null;
    for (const [cid, list] of state.messagesByConv) {
      const m = list.find((x) => x.id === msgId);
      if (m) { target = m; convId = cid; break; }
    }
    if (!target) return;
    // Only peer messages get the safety items; you can't block yourself.
    if (target.senderDeviceId === state.me?.deviceId) return;
    const conv = state.conversations.find((c) => c.id === convId);
    const peer = conv?.members?.find((m) => m.userId !== state.me?.userId);
    if (!peer) return;

    const sep = document.createElement('div');
    sep.className = 'msg-action-divider';
    menu.appendChild(sep);

    const blockBtn = document.createElement('button');
    blockBtn.className = 'msg-action-item danger';
    blockBtn.textContent = '🚫  차단';
    blockBtn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      closeActionMenu();
      blockUser(peer.userId, peer.handle);
    });
    menu.appendChild(blockBtn);

    const reportBtn = document.createElement('button');
    reportBtn.className = 'msg-action-item';
    reportBtn.textContent = '🚨  신고';
    reportBtn.addEventListener('click', (ev) => {
      ev.stopPropagation();
      closeActionMenu();
      reportMessage(target.id, peer.userId, peer.handle);
    });
    menu.appendChild(reportBtn);
  });
});
setTimeout(() => __veilSafetyMenuObserver.observe(document.body, { childList: true, subtree: true }), 0);

// Mute toggle in the panel header. Adds a 🔔 / 🔕 button after the
// search button. Click cycles unmute → 1 hour → 24 hours → 영구 →
// unmute (matches a typical messenger UX).
const __veilMuteHeaderObserver = new MutationObserver(() => {
  document.querySelectorAll('.panel').forEach((panel) => {
    if (panel.dataset.veilMuteWired === '1') return;
    const header = panel.querySelector('.panel-header');
    if (!header) return;
    panel.dataset.veilMuteWired = '1';
    const convId = panel.dataset.conv;
    if (!convId || convId.startsWith('kakao-')) return;
    const btn = document.createElement('button');
    btn.className = 'mute-toggle';
    btn.setAttribute('aria-label', '알림 토글');
    btn.title = '알림 토글';
    btn.textContent = mutedConvIds.has(convId) ? '🔕' : '🔔';
    btn.addEventListener('click', async () => {
      if (mutedConvIds.has(convId)) {
        await setConversationMute(convId, null);
        btn.textContent = '🔔';
      } else {
        // Cycle: 1h → 24h → forever via a small inline picker.
        const choice = window.prompt(
          '알림 끄기 기간을 분 단위로 입력하세요 (예: 60 = 1시간, 1440 = 24시간, 999999 = 영구):',
          '60',
        );
        if (!choice) return;
        const minutes = Math.max(1, parseInt(choice, 10) || 60);
        await setConversationMute(convId, minutes * 60);
        btn.textContent = '🔕';
      }
    });
    header.appendChild(btn);
  });
});
setTimeout(() => {
  const panels = document.getElementById('panels');
  if (panels) __veilMuteHeaderObserver.observe(panels, { childList: true, subtree: true });
}, 0);

// Visual: muted conversations get a dimmed sidebar row.
const __veilMutedSidebarObserver = new MutationObserver(() => {
  document.querySelectorAll('.conv-item').forEach((row) => {
    const id = row.dataset?.convId;
    if (!id) return;
    row.classList.toggle('muted', mutedConvIds.has(id));
  });
});
setTimeout(() => {
  const list = document.getElementById('conv-list');
  if (list) __veilMutedSidebarObserver.observe(list, { childList: true, subtree: true });
}, 0);

// Settings dialog gains a "차단된 사용자" section. We extend the
// existing openSettingsDialog by patching it (function decl =
// reassignable inside the same module).
const __veilOriginalOpenSettings = openSettingsDialog;
openSettingsDialog = function () {
  __veilOriginalOpenSettings();
  setTimeout(async () => {
    const dialog = document.getElementById('settings-dialog');
    if (!dialog) return;
    if (dialog.querySelector('[data-blocked-section]')) return;
    const dialogActions = dialog.querySelector('.dialog-actions');
    const wrap = document.createElement('div');
    wrap.dataset.blockedSection = '1';
    wrap.style.cssText = 'margin-top:10px;border-top:1px solid rgba(255,255,255,0.06);padding-top:10px';
    wrap.innerHTML = `
      <div class="settings-label" style="margin-bottom:6px">차단된 사용자</div>
      <div class="blocked-list" id="blocked-list-container"></div>
    `;
    if (dialogActions) dialog.querySelector('.dialog').insertBefore(wrap, dialogActions);
    const container = wrap.querySelector('#blocked-list-container');
    const items = await listBlocked();
    if (items.length === 0) return;
    container.replaceChildren();
    for (const u of items) {
      const row = document.createElement('div');
      row.className = 'blocked-row';
      const av = avatarFor(u.handle ?? '?', 'sm');
      const meta = document.createElement('div');
      meta.className = 'grow';
      meta.innerHTML = `<div style="font-size:13px">@${escapeHtml(u.handle ?? '?')}</div>` +
        (u.displayName ? `<div style="font-size:11px;opacity:0.6">${escapeHtml(u.displayName)}</div>` : '');
      const btn = document.createElement('button');
      btn.className = 'unblock';
      btn.textContent = '해제';
      btn.addEventListener('click', async () => {
        await unblockUser(u.userId ?? u.id, u.handle ?? '?');
        row.remove();
      });
      row.append(av, meta, btn);
      container.appendChild(row);
    }
  }, 50);
};
