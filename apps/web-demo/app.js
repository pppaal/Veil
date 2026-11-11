// VEIL web demo client.
// Vanilla-JS chat shell that talks to the NestJS API at /v1 and the realtime
// gateway at /v1/realtime. Messages are end-to-end encrypted with protocol v2
// ('veil-envelope-v2', docs/crypto-envelope-spec.md): X3DH with signed and
// one-time prekeys, then a Double Ratchet, byte-compatible with the mobile
// client (src/crypto/). Each ciphertext is decrypted once into an encrypted
// local store, which is all rendering reads. The server only ever sees
// ciphertext.

import { initI18n, t, setLang, activeLang } from './i18n/i18n.js';
import {
  formatTime as fmtTime,
  dayKey as fmtDayKey,
  dayLabel as fmtDayLabel,
  formatBytes as fmtBytes,
} from './lib/format.js';
import { parseKakaoExport } from './lib/kakao-import.js';
import { decodeBase64Url } from './src/core/base64url.js';
import { isPast } from './src/core/expiry.js';
import { encryptAttachment } from './src/crypto/attachment-v2.js';
import { concatBytes } from './src/crypto/bytes.js';
import { ENVELOPE_VERSION_V2 } from './src/crypto/frame.js';
import { generateIdentity, isLegacyIdentity, publishedKeys, signChallenge } from './src/crypto/identity.js';
import { createKeySource, sha256 } from './src/crypto/keys.js';
import { createLegacyV1DevReader } from './src/crypto/legacy-v1dev.js';
import { createLocks } from './src/crypto/locks.js';
import { createIdentityTrust, createPinStore, PinVerdict, ReverificationRequiredError } from './src/crypto/pins.js';
import { claimedOneTimePrekey, createLocalKeyring, maintainPrekeys, PREKEY_LOCK } from './src/crypto/prekeys.js';
import { formatSafetyNumber, matchesPeerCode, safetyNumber, verificationCode } from './src/crypto/safety-number.js';
import { createSessionCipher } from './src/crypto/session-cipher.js';
import { createSessionRepo } from './src/crypto/session-repo.js';
import { mediaContent, textContent } from './src/domain/content.js';
import { ingestMessage, isGone, isShown, isTextKind, previewLabel } from './src/domain/ingest.js';
import { createAttachmentFetcher } from './src/domain/media.js';
import { KIND_LABELS } from './src/domain/payload.js';
import { reactionsByTarget } from './src/domain/reactions.js';
import { fileExtension, sanitizeFilename } from './src/domain/sanitize.js';
import { storeTransferredIdentity, TRANSFER_POLL_MS, watchOldDeviceTransfer } from './src/features/device-transfer.js';
import {
  buildNotification,
  NOTIFICATION_LEVELS,
  readNotificationLevel,
  writeNotificationLevel,
} from './src/features/notifications.js';
import {
  createSecureMessaging,
  LegacyIdentityError,
  PeerKeyChangedError,
  PeerUnavailableError,
} from './src/features/secure-messaging.js';
import { createSender } from './src/features/sender.js';
import { AuthError, createApiClient, isAuthRejection } from './src/platform/api-client.js';
import { createContentStore } from './src/platform/content-store.js';
import { createIdb } from './src/platform/idb.js';
import { createIdbKv } from './src/platform/kv.js';
import {
  kakaoArchiveMeta,
  messageCacheRecord,
  serializeConversationForCache,
  serializeMessageForCache,
} from './src/platform/persist.js';
import { createIdbSessionRepo, createSessionStore } from './src/platform/session-store.js';
import { wipeEverything, wipeInPlace } from './src/platform/wipe.js';
import { createDialogs } from './src/ui/dialogs.js';
import { toFragment } from './src/ui/markdown-dom.js';
// Initialize translations as early as possible so DOM static strings can be
// rewritten before the user sees them. Top-level await is supported in
// modules, which is exactly what this file is.
await initI18n();

const API = '/v1';
// Pre-IndexedDB builds kept the session record in localStorage.
const LEGACY_SESSION_KEY = 'veil-demo-session';
const POLL_MS = 4000;
// Cap a single message body. UTF-8 worst case is ~3 bytes/char so 8000 chars
// keeps us comfortably under the API's 64 KB envelope ceiling and prevents a
// 10 MB paste from locking the encrypt/render path.
const MESSAGE_MAX_CHARS = 8000;

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

// Storage access throws in some sandboxed and privacy modes.
const safeStorage = (name) => {
  try {
    return window[name];
  } catch {
    return null;
  }
};
const safeLocalStorage = () => safeStorage('localStorage');

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
// "@handle" for member and contact rows. Handles only: profile text is not
// something the server keeps.
const handleLine = (handle, handleStyle) => el('div', handleStyle ? { style: handleStyle } : {}, ['@' + (handle || '?')]);

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

// ---------- state ----------
const state = {
  me: null,                    // session record: { handle, userId, deviceId, identity keys (src/crypto/identity.js), accessToken, refreshToken }
  conversations: [],           // ConversationSummary[] (lastMessage ingested)
  conversationsLoaded: false,  // false until first /conversations response lands
  messagesByConv: new Map(),   // convId -> message views (src/domain/ingest.js) + receipts
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

// ---------- storage, session and crypto wiring ----------
const idb = createIdb(indexedDB, {
  onBlocked: () => toast(t('storage.upgradeBlocked'), 'error'),
  // Another tab wiped this browser's VEIL data. Reloading drops everything
  // this tab still holds in memory and boots from the now-empty storage.
  onDeletedElsewhere: () => location.reload(),
});

// A device transfer in another tab replaced the stored identity in place
// (clearReplacedIdentity), which, unlike a wipe, leaves the database for
// open tabs to keep writing to. Reloading drops the replaced identity this
// tab holds in memory before a token update writes it back over the new one.
let identityChannel = null;
try { identityChannel = new BroadcastChannel('veil-demo-identity'); } catch {}
identityChannel?.addEventListener('message', (ev) => {
  if (ev.data?.kind === 'identity-replaced') location.reload();
});

const sessionStore = createSessionStore({
  repo: createIdbSessionRepo(idb, { readLegacy: migrateLegacySession }),
  subtle: crypto.subtle,
});

// Background writes on behalf of the stored identity: caches, the outbound
// queue, pins. Work still in flight when the identity is destroyed (a
// refresh landing after the wipe, a send failing into the queue) must not
// recreate the deleted database with that identity's data.
const identityDb = {
  async put(store, value) {
    if (sessionStore.current()) await idb.put(store, value);
  },
  async delete(store, key) {
    if (sessionStore.current()) await idb.delete(store, key);
  },
};

async function migrateLegacySession() {
  const storage = safeLocalStorage();
  let legacy = null;
  try {
    legacy = JSON.parse(storage?.getItem(LEGACY_SESSION_KEY) ?? 'null');
  } catch {
    return null;
  }
  if (!legacy) return null;
  await idb.put('session', { id: 'me', value: legacy });
  storage.removeItem(LEGACY_SESSION_KEY);
  return legacy;
}

const apiClient = createApiClient({
  fetchImpl: (url, init) => fetch(url, init),
  baseUrl: API,
  tokenStore: {
    ...sessionStore,
    // Fresh tokens also revive a socket the server turned away with an
    // expired one; the socket reads the current token on every connect.
    async saveTokens(tokens) {
      await sessionStore.saveTokens(tokens);
      if (state.socket && !state.socket.connected) state.socket.connect();
    },
  },
  onSessionRejected,
});
const { api, authedApi } = apiClient;

// Once the user approved a device transfer, the server revoking this device
// is how the transfer's completion arrives here (src/features/device-transfer.js),
// and the transfer watcher then destroys the spent identity.
async function onSessionRejected() {
  if ((await transferOld?.sessionEnded()) === 'completed') return;
  await endSession({ rejected: true });
}

// Protocol v2 (src/crypto/): every crypto store is IndexedDB, written only
// while an identity is stored, and every private key in them is a
// non-extractable CryptoKey.
const locks = createLocks(navigator.locks);
const keySource = createKeySource(crypto);
const kv = (store, options) => createIdbKv({ ...idb, put: identityDb.put, delete: identityDb.delete }, store, options);
const oneTimePrekeyKv = kv('one-time-prekeys');
const PREKEY_MAINTENANCE_MS = 6 * 60 * 60 * 1000;

const trust = createIdentityTrust({
  pins: createPinStore(kv('identity-pins-v2', { index: 'byUser' }), { locks }),
  onChange: () => {
    renderSidebar();
    renderActivePanel();
  },
});

const cipher = createSessionCipher({
  subtle: crypto.subtle,
  keys: keySource,
  repo: createSessionRepo({
    subtle: crypto.subtle,
    random: keySource.randomBytes,
    getKek: async () => sessionStore.current().sessionKek,
    kv: kv('crypto-sessions'),
    clock: Date.now,
  }),
  locks,
  keyring: createLocalKeyring({ loadIdentity: () => sessionStore.reload(), opkKv: oneTimePrekeyKv, clock: Date.now }),
  clock: Date.now,
  // A session is installed by an authenticated handshake, and a frame is
  // sealed or opened, only for an identity the pins admit for that peer
  // and device.
  verifyIdentity:({ conversationId, remoteDeviceId, identityKey }) => {
    const peer = peerOf(conversationId);
    return peer ? trust.admit(peer.userId, remoteDeviceId, identityKey) : false;
  },
});

const contentStore = createContentStore({
  subtle: crypto.subtle,
  random: keySource.randomBytes,
  records: kv('message-contents', { index: 'byConversation', expiryIndex: 'byExpiry' }),
  keys: kv('content-keys'),
  locks,
});

const secure = createSecureMessaging({
  cipher,
  trust,
  lookupPeer,
  contentStore,
  // History an identity from before protocol v2 wrote, read with the peer
  // key that era pinned.
  legacyReader: createLegacyV1DevReader({
    subtle: crypto.subtle,
    getSelf: () => state.me,
    peerKey: async (conversationId) => {
      const peer = peerOf(conversationId);
      return peer ? (await idb.get('identity-pins', peer.userId))?.peerKey ?? null : null;
    },
  }),
  getSelf: () => state.me,
  getPeer: peerOf,
  clock: Date.now,
});

const sender = createSender({ secure, authedApi, queue: { put: (entry) => identityDb.put('outbound', entry) } });

// The peer's active device from the authenticated directory, with a
// one-time prekey claimed for the handshake.
async function lookupPeer(peer) {
  const { user, devices } = await authedApi(`/keys/${encodeURIComponent(peer.handle)}?claim=active`);
  if (user?.id !== peer.userId) throw new Error('key directory answered for another user');
  const device = devices?.find((candidate) => candidate.deviceId === user.activeDeviceId);
  if (!device) throw new Error('peer has no active device');
  return {
    deviceId: device.deviceId,
    identityKey: decodeBase64Url(device.identityPublicKey),
    signedPrekeyBundle: device.signedPrekeyBundle,
    oneTimePrekey: claimedOneTimePrekey(device.oneTimePrekey),
  };
}

// Keeps the directory able to start sessions with us (src/crypto/prekeys.js),
// one tab at a time, on the identity as stored now.
let prekeyTimer = null;
function startPrekeyMaintenance() {
  const run = () => locks.run(PREKEY_LOCK, async () => {
    if (isLegacyIdentity(await sessionStore.reload())) return;
    await maintainPrekeys({
      subtle: crypto.subtle,
      keys: keySource,
      authedApi,
      identity: { current: () => sessionStore.current(), update: (fields) => sessionStore.update(fields) },
      opkKv: oneTimePrekeyKv,
      clock: Date.now,
    });
  }).catch((error) => console.warn('prekey maintenance failed', error));
  run();
  prekeyTimer = setInterval(run, PREKEY_MAINTENANCE_MS);
}

// The other member of a direct conversation. Without our own userId the
// "other" member could be ourselves, and an envelope sealed to our own key
// reaches nobody, so there is no peer until a login has named us. A group
// has no single peer: sealing to, or pinning, any one member would be wrong.
function peerOf(conversationId) {
  const selfId = state.me?.userId;
  if (!selfId) return null;
  const conv = state.conversations.find((c) => c.id === conversationId);
  if (conv?.type !== 'direct') return null;
  return conv.members?.find((m) => m.userId !== selfId) ?? null;
}

// ---------- message ingest ----------
const mediaDeps = {
  subtle: crypto.subtle,
  fetchAttachment: createAttachmentFetcher({ authedApi, fetchImpl: (url) => fetch(url) }),
};

// Receipts change after delivery and are never cached, so they ride on the
// in-memory message next to its view.
const RECEIPT_FIELDS = ['clientMessageId', 'deliveredAt', 'readAt', 'editCount'];
// Blob URLs and load failures belong to a media handle; a reused view keeps them.
const MEDIA_STATE_FIELDS = ['_imageUrl', '_voiceUrl', '_mediaFailed'];

// Every path that turns a server envelope into a displayed message comes
// through here, and content comes from the decrypt-once store
// (src/features/secure-messaging.js). `content` is passed only for our own
// sends, whose content we already hold.
async function ingest(raw, { previous = null, content } = {}) {
  const open = content === undefined ? (envelope) => secure.open(envelope) : async () => ({ content });
  const view = await ingestMessage(raw, { open, retire: (envelope) => secure.retire(envelope), media: mediaDeps, previous });
  if (previous && view.media !== null && view.media === previous.media) {
    for (const field of MEDIA_STATE_FIELDS) if (previous[field] !== undefined) view[field] = previous[field];
  }
  for (const field of RECEIPT_FIELDS) {
    const value = raw[field] ?? previous?.[field];
    if (value !== undefined) view[field] = value;
  }
  return view;
}

function findMessage(conversationId, messageId) {
  const fromList = (state.messagesByConv.get(conversationId) || []).find((m) => m.id === messageId);
  if (fromList) return fromList;
  const last = state.conversations.find((c) => c.id === conversationId)?.lastMessage;
  return last?.id === messageId ? last : null;
}

function locateMessage(messageId) {
  for (const [convId, list] of state.messagesByConv) {
    const index = list.findIndex((m) => m.id === messageId);
    if (index >= 0) return { convId, list, index, message: list[index] };
  }
  return null;
}

// Replaces a conversation's message list and frees blob URLs that no
// remaining message uses.
function setConversationMessages(convId, next) {
  const live = new Set(next.flatMap(blobUrlsOf));
  for (const message of state.messagesByConv.get(convId) || []) {
    for (const url of blobUrlsOf(message)) if (!live.has(url)) URL.revokeObjectURL(url);
  }
  state.messagesByConv.set(convId, next);
}

// Own message that exists only locally until its upload and send finish.
function pendingLocalMessage({ clientMessageId, conversationId, messageType, kind, displayText }) {
  return {
    id: '__pending__' + clientMessageId,
    clientMessageId,
    conversationId,
    senderDeviceId: state.me.deviceId,
    messageType,
    serverReceivedAt: null,
    kind,
    displayText,
    replyTo: null,
    media: null,
    _status: 'pending',
    _localAt: new Date().toISOString(),
  };
}

function sortConversations() {
  state.conversations.sort((a, b) => {
    const ax = a.lastMessage?.serverReceivedAt ?? a.createdAt;
    const bx = b.lastMessage?.serverReceivedAt ?? b.createdAt;
    return bx.localeCompare(ax);
  });
}

// Shared failure toasts for the send paths: a frozen conversation gets the
// key-change explanation instead of a generic error.
function toastSendFailure(label, error) {
  if (error instanceof PeerKeyChangedError) {
    toast(t('keyChange.sendBlocked'), 'error');
    return;
  }
  if (error instanceof PeerUnavailableError) {
    toast(t(error.reason === 'not-upgraded' ? 'peer.notUpgraded' : 'peer.unavailable'), 'error');
    return;
  }
  if (error instanceof LegacyIdentityError) {
    toast(t('legacy.composerFrozen'), 'error');
    return;
  }
  toast(`${label}: ${error?.message || 'unknown'}`, 'error');
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
    auth: (send) => send({ token: sessionStore.getAccessToken() }),
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
  s.on('message.edited', (msg) => onMessageEdited(msg));
  s.on('message.deleted', ({ messageId, deletedAt }) => markDeleted(messageId, deletedAt));
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

async function onMessageNew(raw) {
  const convId = raw.conversationId;
  const list = state.messagesByConv.get(convId) || [];
  // If we already have this message id, ignore.
  if (list.some((m) => m.id === raw.id)) return;
  // The first message of a conversation can arrive before the conversation
  // list names its members, and a session-starting frame is only accepted
  // for the identity pinned for the member who sent it.
  if (!state.conversations.some((c) => c.id === convId)) await loadConversations();
  // Server echo of our own send replaces the optimistic entry and reuses
  // its already-decoded content.
  const pendingIndex = raw.clientMessageId
    ? list.findIndex((m) => m.clientMessageId === raw.clientMessageId)
    : -1;
  if (pendingIndex >= 0) {
    const view = await ingest(raw, { previous: list[pendingIndex] });
    list[pendingIndex] = view;
    state.messagesByConv.set(convId, list);
    bumpConversation(convId, view);
    return;
  }
  const view = await ingest(raw, { previous: findMessage(convId, raw.id) });
  if (list.some((m) => m.id === view.id)) return;
  list.push(view);
  state.messagesByConv.set(convId, list);
  bumpConversation(convId, view);
  // Phase AF: surface unread count in tab title + OS notification when
  // the tab is hidden. We only count peer messages, not our own echo, and
  // a reaction or an expired message is not one to be told about.
  if (view.senderDeviceId !== state.me?.deviceId && isShown(view)) {
    bumpUnread();
    maybeShowNotification(view);
  }
}

function bumpConversation(convId, message) {
  const conv = state.conversations.find((c) => c.id === convId);
  if (conv) {
    conv.lastMessage = message;
    sortConversations();
  }
  renderSidebar();
  if (convId === state.activeConv || convId === state.secondaryConv) renderActivePanel();
}

function patchMessage(messageId, patch) {
  const found = locateMessage(messageId);
  if (!found) return;
  Object.assign(found.message, patch);
  if (found.convId === state.activeConv || found.convId === state.secondaryConv) renderActivePanel();
}

async function markDeleted(messageId, deletedAt) {
  const found = locateMessage(messageId);
  if (!found) return;
  revokeBlobUrlsForMessage(found.message);
  await reingestInPlace(messageId, Object.assign(serializeMessageForCache(found.message), { deletedAt }));
}

// Re-ingests a changed envelope (edit, tombstone) and swaps the result in
// wherever the old view is shown.
async function reingestInPlace(messageId, raw, { content, editCount } = {}) {
  const previous = locateMessage(messageId)?.message ?? null;
  const view = await ingest(raw, { previous, content });
  if (editCount !== undefined) view.editCount = editCount;
  const current = locateMessage(messageId);
  if (!current) return;
  current.list[current.index] = view;
  const conv = state.conversations.find((c) => c.id === current.convId);
  if (conv?.lastMessage?.id === messageId) conv.lastMessage = view;
  persistMessage(view);
  renderSidebar();
  if (current.convId === state.activeConv || current.convId === state.secondaryConv) renderActivePanel();
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

// ---------- render ----------
async function showAuth({ rejected = false } = {}) {
  $('auth-screen').classList.remove('hidden');
  $('app').classList.add('hidden');
  let stored = sessionStore.current();
  if (!stored) {
    try {
      stored = await sessionStore.load();
    } catch (e) {
      toast('세션 불러오기 실패: ' + e.message, 'error');
    }
  }
  $('restore-row').classList.toggle('hidden', !stored);
  if (stored) $('restore-handle').textContent = '@' + stored.handle;
  $('restore-rejected').classList.toggle('hidden', !(stored && rejected));
  $('restore-btn').textContent = t(rejected ? 'auth.restore.retry' : 'auth.restore.continue');
  // wipe-btn stays visible regardless. A user with a corrupted/partially
  // restored session needs to be able to nuke local state without first
  // succeeding at restore.
}

function showApp() {
  $('auth-screen').classList.add('hidden');
  $('app').classList.remove('hidden');
  // An identity from before protocol v2 can read what it has but can never
  // send again (src/crypto/identity.js): offer to replace it.
  $('legacy-banner').classList.toggle('hidden', !isLegacyIdentity(state.me));
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

// The message a conversation row previews: its latest one a panel shows.
// The relay's last message may be gone (expired, or deleted from this
// device's history) or a reaction, which is no bubble of its own; then the
// loaded history stands in, and a reaction's label only when nothing does.
function previewMessageOf(conv, now) {
  const last = conv.lastMessage;
  if (last && isShown(last, now)) return last;
  const loaded = (state.messagesByConv.get(conv.id) || []).findLast((m) => isShown(m, now));
  return loaded ?? (last && !isGone(last, now) ? last : null);
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
    ]), ...renderKakaoArchiveRows());
    return;
  }

  const now = Date.now();
  list.replaceChildren(
    ...filtered.map((c) => {
      const peer = (c.members || []).find((m) => m.handle !== state.me.handle) ?? c.members?.[0];
      const isActive = state.activeConv === c.id || state.secondaryConv === c.id;
      const last = previewMessageOf(c, now);
      const preview = last ? previewLabel(last, now) : '아직 메시지 없음';
      const time = last?.serverReceivedAt ? formatRelTime(last.serverReceivedAt) : '';
      const peerOnline = peer && state.online.has(peer.userId);
      const keyChanged = peer && trust.pendingChange(peer.userId);
      const av = avatarFor(peer?.handle ?? '?', 'md');
      av.appendChild(el('span', { class: 'presence-dot' }));
      if (peerOnline) av.classList.add('online');
      return el(
        'button',
        {
          class: 'conv-item' + (isActive ? ' active' : ''),
          dataset: { convId: c.id },
          onclick: () => openConversation(c.id),
        },
        [
          av,
          el('div', { class: 'conv-meta' }, [
            el('div', { class: 'conv-row1' }, [
              el('span', { class: 'conv-name' }, ['@' + (peer?.handle ?? '?')]),
              time ? el('span', { class: 'conv-time' }, [time]) : null,
            ]),
            el('div', { class: 'conv-preview' }, [keyChanged ? t('keyChange.sidebar') : preview]),
          ]),
        ],
      );
    }),
    ...renderKakaoArchiveRows(),
  );
}

// Message body inside a bubble. Text goes through the DOM markdown builder;
// everything else renders from the view's kind and media handle, so no
// decrypted payload is ever shown as text.
function renderMessageBody(message) {
  switch (message.kind) {
    case 'text':
    case 'reply':
      return el('span', {}, [toFragment(message.displayText)]);
    case 'image':
      return renderImageBody(message);
    case 'voice':
      return renderVoiceBody(message);
    case 'file':
      return renderFileChip(message);
    default:
      return message.displayText;
  }
}

function renderImageBody(message) {
  const url = message._imageUrl;
  if (url) {
    return el('img', {
      class: 'msg-inline-image',
      src: url,
      alt: 'image',
      onclick: (e) => { e.stopPropagation(); openImageZoom(url); },
    });
  }
  if (message._mediaFailed) return '🖼 이미지 (불러오기 실패)';
  if (message.media) ensureMediaUrl(message, '_imageUrl');
  return el('span', { class: 'image-uploading' }, [KIND_LABELS.image]);
}

function renderVoiceBody(message) {
  if (message._voiceUrl) {
    return el('audio', {
      controls: 'controls',
      src: message._voiceUrl,
      preload: 'metadata',
      style: 'max-width: 240px; height: 32px; vertical-align: middle;',
    });
  }
  if (message.media) ensureMediaUrl(message, '_voiceUrl');
  return KIND_LABELS.voice;
}

// File names are sender-controlled: show the sanitized name and the real
// extension separately, and download as application/octet-stream.
function renderFileChip(message) {
  const name = message.media?.name ?? message._localFile?.name ?? '파일';
  const sizeBytes = message.media?.sizeBytes ?? message._localFile?.sizeBytes ?? 0;
  const extension = message.media?.extension ?? fileExtension(name);
  return el(
    'button',
    {
      class: 'msg-file-chip',
      type: 'button',
      onclick: (e) => { e.stopPropagation(); downloadFile(message); },
    },
    [
      el('div', { class: 'msg-file-chip-icon', 'aria-hidden': 'true' }, ['📁']),
      el('div', { class: 'msg-file-chip-meta' }, [
        el('div', { class: 'msg-file-chip-name' }, [name]),
        el('div', { class: 'msg-file-chip-size' }, [
          extension ? el('span', { class: 'msg-file-chip-ext' }, ['.' + extension]) : null,
          `${formatBytes(sizeBytes)} · 클릭해서 다운로드`,
        ]),
      ]),
    ],
  );
}

// Materializes a media handle once, then attaches the blob URL to whichever
// message objects still carry that handle (a refresh may have replaced the
// one that asked).
const mediaLoads = new WeakSet();
function ensureMediaUrl(message, field) {
  const { media, conversationId } = message;
  if (mediaLoads.has(media)) return;
  mediaLoads.add(media);
  media.materialize()
    .then((blob) => {
      const url = URL.createObjectURL(blob);
      const holders = messagesHolding(conversationId, media);
      for (const holder of holders) holder[field] = url;
      if (holders.length === 0) URL.revokeObjectURL(url);
    })
    .catch(() => {
      for (const holder of messagesHolding(conversationId, media)) holder._mediaFailed = true;
    })
    .finally(() => {
      if (conversationId === state.activeConv || conversationId === state.secondaryConv) renderActivePanel();
    });
}

function messagesHolding(conversationId, media) {
  const holders = (state.messagesByConv.get(conversationId) || []).filter((m) => m.media === media);
  const last = state.conversations.find((c) => c.id === conversationId)?.lastMessage;
  if (last?.media === media && !holders.includes(last)) holders.push(last);
  return holders;
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

function snippetOf(message, maxChars) {
  const text = previewLabel(message);
  return text.length > maxChars ? text.slice(0, maxChars) + '…' : text;
}

function renderReplyHead(replyToId, allMsgs) {
  const target = allMsgs.find((m) => m.id === replyToId);
  return el('div', { class: 'msg-reply-head' }, [
    el('span', { class: 'msg-reply-icon' }, ['↩']),
    el('span', { class: 'msg-reply-snippet' }, [target ? snippetOf(target, 80) : '이전 메시지']),
  ]);
}

function startReply(convId, msg) {
  const sender = msg.senderDeviceId === state.me.deviceId ? state.me.handle : null;
  state.replyDraftByConv.set(convId, { id: msg.id, snippet: snippetOf(msg, 60), sender });
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

// Shown while a peer presents an identity key the pins do not admit.
// Sending stays frozen until the user accepts the new key; a contact they
// had verified has to be verified again, by comparing the new safety number,
// and so does a device of theirs that was never verified.
function renderKeyChangeBanner(convId, peer) {
  const change = trust.pendingChange(peer.userId);
  let text = change?.verified ? 'keyChange.bannerVerified' : 'keyChange.banner';
  if (change?.verdict === PinVerdict.UNVERIFIED_DEVICE) text = 'keyChange.bannerUnverifiedDevice';
  return el('div', { class: 'key-change-banner', role: 'alert' }, [
    el('div', { class: 'key-change-text' }, [t(text, { handle: peer.handle })]),
    el('button', {
      class: 'btn btn-secondary btn-compact',
      onclick: () => (change?.verified ? openSafetyNumberDialog(convId, peer) : acceptPeerKeyChange(convId, peer)),
    }, [t(change?.verified ? 'safety.compare' : 'keyChange.review')]),
  ]);
}

// Accepts the change pending when the banner was clicked, never one that
// replaced it while the confirmation was open.
async function acceptPeerKeyChange(convId, peer) {
  const reviewed = trust.pendingChange(peer.userId);
  if (!reviewed) return;
  const ok = await uiConfirm({
    title: t('keyChange.confirmTitle', { handle: peer.handle }),
    body: t('keyChange.confirmBody', { handle: peer.handle }),
    okLabel: t('keyChange.accept'),
    destructive: true,
  });
  if (!ok) return;
  try {
    if (!(await trust.accept(peer.userId, reviewed))) {
      if (trust.pendingChange(peer.userId)) toast(t('keyChange.superseded', { handle: peer.handle }), 'error');
      return;
    }
  } catch (e) {
    if (e instanceof ReverificationRequiredError) {
      await openSafetyNumberDialog(convId, peer);
      return;
    }
    toast('키 수락 실패: ' + e.message, 'error');
    return;
  }
  await reopenLockedMessages(peer.userId);
}

// Handshakes refused while a key change was pending are retried once it is
// accepted; nothing about them was stored.
async function reopenLockedMessages(userId) {
  const affected = state.conversations.filter((c) => peerOf(c.id)?.userId === userId);
  for (const conv of affected) {
    const list = state.messagesByConv.get(conv.id) || [];
    const next = await Promise.all(list.map((m) => (m.kind === 'locked' ? ingest(m, { previous: m }) : m)));
    setConversationMessages(conv.id, next);
    if (conv.lastMessage?.kind === 'locked') conv.lastMessage = await ingest(conv.lastMessage, { previous: conv.lastMessage });
  }
  renderSidebar();
  renderActivePanel();
}

// Safety numbers v2 (src/crypto/safety-number.js), computed from the key
// the conversation uses (src/features/secure-messaging.js safetyKey) and
// never sent anywhere. The user compares the number in person or over a
// call, or pastes the verification code the peer's screen shows; what they
// mark verified is exactly the key the dialog showed.
async function openSafetyNumberDialog(convId, peer) {
  // A safety number binds our user id, which a transferred device learns
  // only at its first sign-in.
  if (!state.me.userId) {
    toast(t('safety.notSignedIn'), 'error');
    return;
  }
  const remoteKey = await secure.safetyKey(convId);
  if (!remoteKey) {
    toast(t('safety.noKey', { handle: peer.handle }), 'error');
    return;
  }
  const local = { identityKey: state.me.ik.publicKey, userId: state.me.userId };
  const remote = { identityKey: remoteKey.identityKey, userId: peer.userId };
  let pendingNote = remoteKey.pendingVerdict ? 'safety.pendingKey' : null;
  if (remoteKey.pendingVerdict === PinVerdict.UNVERIFIED_DEVICE) pendingNote = 'safety.unverifiedDevice';
  const number = formatSafetyNumber(await safetyNumber(crypto.subtle, local, remote));
  const codeInput = el('input', {
    id: 'safety-their-code',
    type: 'text',
    placeholder: t('safety.pastePlaceholder'),
    autocomplete: 'off',
    spellcheck: 'false',
  });
  const result = el('div', { class: 'dialog-error', role: 'status', 'aria-live': 'polite' });
  let back = null;
  const close = () => {
    closeDialog('safety-dialog');
    back.remove();
  };
  const markVerified = async () => {
    try {
      await trust.markVerified(peer.userId, remoteKey.deviceId, remoteKey.identityKey);
    } catch (e) {
      result.textContent = t('safety.verifyFailed', { error: e.message });
      return;
    }
    toast(t('safety.verified', { handle: peer.handle }), 'good');
    close();
    await reopenLockedMessages(peer.userId);
  };
  const compare = async () => {
    if (matchesPeerCode(local, remote, codeInput.value.trim())) await markVerified();
    else result.textContent = t('safety.mismatch');
  };
  back = el('div', { class: 'dialog-backdrop hidden', id: 'safety-dialog', role: 'presentation' }, [
    el('div', {
      class: 'dialog',
      role: 'dialog',
      'aria-modal': 'true',
      'aria-labelledby': 'safety-title',
      style: 'width:420px;max-width:92vw',
    }, [
      el('div', { class: 'dialog-title', id: 'safety-title' }, [t('safety.title', { handle: peer.handle })]),
      pendingNote ? el('div', { class: 'key-change-text', role: 'alert' }, [t(pendingNote, { handle: peer.handle })]) : null,
      remoteKey.verified ? el('div', { class: 'dialog-sub' }, [t('safety.alreadyVerified')]) : null,
      el('div', { class: 'safety-number', id: 'safety-number' }, [number]),
      el('div', { class: 'dialog-sub' }, [t('safety.explain', { handle: peer.handle })]),
      el('div', { class: 'field-label' }, [t('safety.yourCode')]),
      el('textarea', { readonly: 'readonly', rows: '3', class: 'safety-code' }, [verificationCode(local, remote)]),
      el('div', { class: 'field-label' }, [t('safety.theirCode')]),
      codeInput,
      result,
      el('div', { class: 'dialog-actions' }, [
        el('button', { class: 'btn btn-ghost', onclick: close }, [t('common.cancel')]),
        el('button', { class: 'btn btn-secondary', onclick: compare }, [t('safety.compareCode')]),
        el('button', { class: 'btn btn-primary', onclick: markVerified }, [t('safety.markVerified')]),
      ]),
    ]),
  ]);
  back.addEventListener('click', (e) => { if (e.target === back) close(); });
  back.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      close();
    } else {
      trapFocus('safety-dialog', e);
    }
  });
  // One safety dialog at a time: a second click while the first was being
  // prepared opens nothing.
  if ($('safety-dialog')) return;
  document.body.appendChild(back);
  openDialog('safety-dialog', 'safety-their-code');
}

// Deletes this device's copy of a conversation's history: its content key is
// destroyed (src/platform/content-store.js), which no copy of the stored
// records survives, and the cached envelopes go with it.
async function deleteLocalHistory(convId) {
  const ok = await uiConfirm({
    title: t('history.delete'),
    body: t('history.deleteBody'),
    okLabel: t('history.deleteConfirm'),
    destructive: true,
  });
  if (!ok) return;
  const conv = state.conversations.find((c) => c.id === convId);
  const known = [...(state.messagesByConv.get(convId) || []), conv?.lastMessage]
    .filter((m) => m?.id && !m.id.startsWith('__pending__'));
  const throughOrder = Math.max(0, ...known.map((m) => m.conversationOrder ?? 0));
  try {
    await secure.forgetConversation(convId, throughOrder);
    for (const message of known) await identityDb.delete('messages', messageCacheRecord(message)._key);
  } catch (e) {
    toast(t('history.deleteFailed', { error: e.message }), 'error');
    return;
  }
  setConversationMessages(convId, []);
  if (conv) conv.lastMessage = null;
  renderSidebar();
  renderActivePanel();
}

function renderOnePanel(convId) {
  const conv = state.conversations.find((c) => c.id === convId);
  if (!conv) return null;
  const peer = (conv.members || []).find((m) => m.handle !== state.me.handle) ?? conv.members?.[0];
  const allMsgs = state.messagesByConv.get(conv.id) || [];
  // Reactions are control messages: they change what their targets show
  // and are never bubbles of their own. Expired messages and history this
  // device deleted are not shown.
  const now = Date.now();
  const reactionsOf = reactionsByTarget(allMsgs.filter((m) => !isGone(m, now)));
  const msgs = allMsgs.filter((m) => isShown(m, now));
  // Sessions, pins and safety numbers exist only in direct conversations:
  // the web demo cannot encrypt to a group, so it does not offer to send.
  const directPeer = peerOf(conv.id);
  const keyChanged = Boolean(directPeer && trust.pendingChange(directPeer.userId));
  const legacyIdentity = isLegacyIdentity(state.me);
  const frozen = keyChanged || legacyIdentity || !directPeer;

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
        const replyHead = m.replyTo ? renderReplyHead(m.replyTo, msgs) : null;
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
        // Read from a retired format: say so on the bubble itself.
        const legacyBadge = m.legacy
          ? el('span', { class: 'msg-legacy-badge', title: t('legacy.badge') }, [t('legacy.badge')])
          : null;
        const bubble = el('div', { class: cls.join(' ') }, [
          replyHead,
          el('span', { class: 'msg-text' }, [renderMessageBody(m)]),
          editedBadge,
          legacyBadge,
        ]);
        const reactionsRow = renderReactionsRow(m, reactionsOf.get(m.id));
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

  let placeholder = '메시지 입력 (Enter 전송, Shift+Enter 줄바꿈)';
  if (!directPeer) placeholder = t('group.composerFrozen');
  if (keyChanged) placeholder = t('keyChange.composerFrozen');
  if (legacyIdentity) placeholder = t('legacy.composerFrozen');
  const textarea = el('textarea', {
    placeholder,
    rows: '1',
    'aria-label': '메시지 입력',
    maxlength: String(MESSAGE_MAX_CHARS),
  });
  textarea.disabled = frozen;
  // Restore the in-memory draft for this conversation, if any.
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
  voiceBtn.disabled = frozen;
  // Auto-grow + emit typing + keep the draft on every input.
  const autoGrow = () => {
    // maxlength is enforced by the browser, but a paste larger than the cap
    // can still arrive as a one-shot input event; trim defensively.
    if (textarea.value.length > MESSAGE_MAX_CHARS) {
      textarea.value = textarea.value.slice(0, MESSAGE_MAX_CHARS);
      toast(`메시지가 잘렸어요 (최대 ${MESSAGE_MAX_CHARS.toLocaleString()}자)`, 'error');
    }
    textarea.style.height = 'auto';
    textarea.style.height = Math.min(textarea.scrollHeight, 140) + 'px';
    sendBtn.disabled = frozen || textarea.value.trim().length === 0;
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
      directPeer && !legacyIdentity
        ? el(
          'button',
          {
            class: 'icon-btn',
            'aria-label': t('safety.open'),
            title: t('safety.open'),
            onclick: () => openSafetyNumberDialog(convId, directPeer),
            style: 'padding: 4px 8px; opacity: 0.7;',
          },
          ['🛡'],
        )
        : null,
      el(
        'button',
        {
          class: 'icon-btn',
          'aria-label': t('history.delete'),
          title: t('history.delete'),
          onclick: () => deleteLocalHistory(convId),
          style: 'padding: 4px 8px; opacity: 0.7;',
        },
        ['🗑'],
      ),
    ]),
    keyChanged ? renderKeyChangeBanner(convId, directPeer) : null,
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
  } catch {
    readMarked.delete(messageId);
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
// network refresh comes back. Only envelopes are cached (src/platform/persist.js);
// views are rebuilt through the same ingest path as live messages.
async function hydrateFromCache() {
  try {
    const cachedConvs = await idb.all('conversations');
    if (cachedConvs.length === 0) return;
    await adoptConversations(cachedConvs);
    const rows = await idb.all('messages');
    const byConv = new Map();
    for (const row of rows) {
      const list = byConv.get(row.conversationId) ?? [];
      list.push(row);
      byConv.set(row.conversationId, list);
    }
    await Promise.all([...byConv].map(async ([convId, list]) => {
      list.sort((a, b) => a.conversationOrder - b.conversationOrder);
      const views = await Promise.all(list.map((row) => ingest(row, { previous: findMessage(convId, row.id) })));
      setConversationMessages(convId, views);
      for (const view of views) if (view.kind === 'expired') persistMessage(view);
    }));
  } catch (e) {
    console.warn('hydrate from cache failed', e);
  }
}

// Installs a fresh conversation list. The envelope crypto resolves peers
// from state.conversations, so the list goes in first and last messages are
// ingested after; meanwhile each keeps its previous view, if any.
async function adoptConversations(conversations) {
  const incoming = conversations.filter((conv) => conv.lastMessage).map((conv) => {
    const raw = conv.lastMessage;
    conv.lastMessage = findMessage(conv.id, raw.id);
    return [conv, raw];
  });
  state.conversations = conversations;
  await Promise.all(incoming.map(async ([conv, raw]) => {
    conv.lastMessage = await ingest(raw, { previous: conv.lastMessage });
  }));
  sortConversations();
}

async function persistConversation(conv) {
  try { await identityDb.put('conversations', serializeConversationForCache(conv)); } catch {}
}

async function persistAllConversations() {
  for (const c of state.conversations) await persistConversation(c);
}

async function persistMessage(msg) {
  if (!msg.id || !msg.conversationId || msg.id.startsWith('__pending__')) return;
  const record = messageCacheRecord(msg);
  // An expired message leaves the device altogether, its envelope included.
  try {
    if (msg.kind === 'expired') await identityDb.delete('messages', record._key);
    else await identityDb.put('messages', record);
  } catch {}
}

async function persistMessages(convId) {
  const list = state.messagesByConv.get(convId) || [];
  for (const m of list) await persistMessage(m);
}

// ---------- outbound queue ----------
async function retryFailedMessage(convId, clientMessageId) {
  if (!clientMessageId) return;
  const list = state.messagesByConv.get(convId) || [];
  const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
  if (idx < 0) return;
  list[idx]._status = 'pending';
  // Re-add to outbound with nextRetryAt=0 so the next drain runs immediately.
  const queued = await idb.get('outbound', clientMessageId);
  if (queued) {
    await identityDb.put('outbound', { ...queued, attempts: 0, nextRetryAt: 0 });
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
  try { await identityDb.delete('outbound', clientMessageId); } catch {}
  renderActivePanel();
  toast('전송 취소됨');
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
  const items = await idb.all('outbound');
  if (items.length === 0) return;
  for (const item of items) {
    // Envelopes an earlier build queued in a retired format are dropped,
    // never sent.
    if (item.envelope?.version !== ENVELOPE_VERSION_V2) {
      await identityDb.delete('outbound', item.clientMessageId);
      continue;
    }
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
      await secure.acknowledge(sent.message);
      const list = state.messagesByConv.get(item.conversationId) || [];
      const idx = list.findIndex((m) => m.clientMessageId === item.clientMessageId);
      // The queue holds no plaintext: the optimistic view (if this tab still
      // has it) is reused, otherwise our content comes from the store.
      const view = await ingest(sent.message, { previous: idx >= 0 ? list[idx] : null });
      if (idx >= 0) list[idx] = view;
      else list.push(view);
      state.messagesByConv.set(item.conversationId, list);
      const conv = state.conversations.find((c) => c.id === item.conversationId);
      if (conv) conv.lastMessage = view;
      await identityDb.delete('outbound', item.clientMessageId);
      await persistMessage(view);
      if (item.conversationId === state.activeConv || item.conversationId === state.secondaryConv) {
        renderActivePanel();
      }
      renderSidebar();
    } catch (e) {
      // The session ended; keep the queue for after the next restore.
      if (e instanceof AuthError) return;
      // Bump retry with exponential backoff up to 30s.
      const attempts = (item.attempts ?? 0) + 1;
      const delay = Math.min(30_000, 1000 * 2 ** attempts);
      await identityDb.put('outbound', { ...item, attempts, nextRetryAt: Date.now() + delay });
      if (e.status && e.status >= 400 && e.status < 500 && e.status !== 429) {
        // Permanent failure — surface to the user, mark as failed locally.
        await identityDb.delete('outbound', item.clientMessageId);
        const list = state.messagesByConv.get(item.conversationId) || [];
        const idx = list.findIndex((m) => m.clientMessageId === item.clientMessageId);
        if (idx >= 0) list[idx]._status = 'failed';
        toast('전송 실패: ' + e.message, 'error');
        renderActivePanel();
      }
    }
  }
}

// ---------- drafts ----------
// Drafts live in memory only: unsent text is plaintext and never touches disk.
const draftCache = new Map(); // convId -> text
function saveDraft(convId, text) {
  if (!convId) return;
  if (text) draftCache.set(convId, text);
  else draftCache.delete(convId);
}

// ---------- session lifecycle ----------
// Three distinct exits, so that nothing but an explicit, confirmed user
// action (or a completed transfer) can destroy the device identity:
//   endSession()      tokens dropped, keys kept, auth screen offers Retry
//   destroyIdentity() confirmed wipe of everything this browser stored
//   resetSessionState() in-memory teardown shared by both

// A handle and keys, nothing else: no profile text goes to the server.
async function registerIdentity(handle) {
  const keys = await generateIdentity(crypto.subtle);
  const reg = await api('/auth/register', {
    method: 'POST',
    body: {
      handle,
      deviceName: 'web-' + (navigator.platform || 'browser'),
      platform: 'android',
      // The Ed25519 identity key and its signed prekey bundle (contract C1),
      // which peers fetch from /v1/keys to start a session.
      ...(await publishedKeys(crypto.subtle, keys)),
    },
  });
  // Saved before the first login: if that fails the registered keys are
  // still here and the auth screen can retry.
  await sessionStore.save({
    handle: reg.handle,
    userId: reg.userId,
    deviceId: reg.deviceId,
    ...keys,
    accessToken: null,
    refreshToken: null,
  });
  await apiClient.login(await sessionStore.getDeviceCredentials());
}

// Re-authenticates the stored identity with a fresh device challenge.
// Returns false when this browser holds no identity.
async function restoreSession() {
  const stored = await sessionStore.load();
  if (!stored) return false;
  if (!stored.edPrivKey || !(stored.ik || stored.xPrivKey)) {
    throw new Error('이 브라우저의 세션은 새 암호화 형식과 호환되지 않아요. 다시 등록해주세요.');
  }
  await apiClient.login(await sessionStore.getDeviceCredentials());
  await enterApp();
  return true;
}

async function enterApp() {
  state.me = sessionStore.current();
  await hydrateFromCache();
  await loadKakaoArchiveRows();
  showApp();
  loadConversations();
  startPolling();
  connectSocket();
  startPrekeyMaintenance();
}

function resetSessionState() {
  revokeAllBlobUrls();
  state.me = null;
  state.conversations = [];
  state.conversationsLoaded = false;
  state.messagesByConv.clear();
  state.activeConv = null;
  state.secondaryConv = null;
  state.openTabs = [];
  state.splitView = false;
  state.replyDraftByConv.clear();
  draftCache.clear();
  searchStateByConv.clear();
  scrollPosByConv.clear();
  readMarked.clear();
  trust.reset();
  clearInterval(prekeyTimer);
  prekeyTimer = null;
  stopTransferOld();
  disconnectSocket();
  if (state.pollTimer) clearInterval(state.pollTimer);
  state.pollTimer = null;
  setConnPill('offline', '오프라인');
  $('app').classList.remove('viewing-chat');
}

async function endSession({ rejected = false } = {}) {
  await sessionStore.clearTokens();
  resetSessionState();
  await showAuth({ rejected });
}

// Wipes the identity and every other trace of VEIL from this browser
// (src/platform/wipe.js) without touching the UI.
async function purgeLocalIdentity() {
  resetSessionState();
  sessionStore.forget();
  mutedConvIds.clear();
  kakaoArchiveRows = [];
  await wipeEverything({
    closeDatabase: () => idb.close(),
    indexedDB,
    localStorage: safeLocalStorage(),
    sessionStorage: safeStorage('sessionStorage'),
    caches: globalThis.caches,
    onBlocked: () => toast(t('storage.wipeBlocked'), 'error'),
  });
}

// After a completed transfer has written its session record over the one
// stored here: clears everything else the replaced identity left, in memory,
// in other tabs and in storage. Unlike purgeLocalIdentity it keeps the
// database, so it waits on no other tab and leaves the new record in place.
async function clearReplacedIdentity() {
  identityChannel?.postMessage({ kind: 'identity-replaced' });
  resetSessionState();
  mutedConvIds.clear();
  kakaoArchiveRows = [];
  await wipeInPlace({
    clearDatabase: () => idb.clearAllExcept(['session']),
    localStorage: safeLocalStorage(),
    sessionStorage: safeStorage('sessionStorage'),
    caches: globalThis.caches,
  });
}

// Only for an explicit, confirmed wipe or a completed transfer.
async function destroyIdentity() {
  try {
    await purgeLocalIdentity();
  } catch (e) {
    toast('일부 데이터를 지우지 못했어요: ' + e.message, 'error');
  }
  await showAuth();
}

// Raw row check: a record that fails to load (or migrate) still holds keys
// and must not be overwritten without asking.
async function hasStoredIdentity() {
  if (sessionStore.current()) return true;
  try {
    return (await idb.get('session', 'me')) !== null;
  } catch {
    return false;
  }
}

async function confirmAndDestroyIdentity() {
  const handle = sessionStore.current()?.handle;
  const ok = await uiConfirm({
    title: t('auth.restore.delete'),
    body: handle
      ? `@${handle} 의 키와 이 브라우저의 VEIL 데이터를 전부 삭제합니다. 이 핸들로는 다시 로그인할 수 없어요.`
      : '이 브라우저의 VEIL 키와 데이터를 전부 삭제합니다.',
    okLabel: '삭제',
    destructive: true,
  });
  if (!ok) return false;
  await destroyIdentity();
  toast('키를 삭제했습니다');
  return true;
}

async function loadConversations() {
  try {
    const r = await authedApi('/conversations');
    await adoptConversations(Array.isArray(r) ? r : (r.items ?? []));
    state.conversationsLoaded = true;
    // Phase AK: drop search state for conversations that no longer
    // exist. Keeps the Map bounded over long sessions.
    const live = new Set(state.conversations.map((c) => c.id));
    for (const cid of Array.from(searchStateByConv.keys())) {
      if (!live.has(cid)) searchStateByConv.delete(cid);
    }
    renderSidebar();
    persistAllConversations();
    drainOutbound();
  } catch (e) {
    if (e instanceof AuthError) return;
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
    const items = r.items ?? [];
    // Unchanged messages keep their views (no re-decrypt, blob URLs intact).
    const fresh = await Promise.all(items.map((raw) => ingest(raw, { previous: findMessage(target, raw.id) })));
    // Preserve any pending optimistic entries that haven't been ACKed yet.
    const seenClientIds = new Set(items.map((m) => m.clientMessageId));
    const pendings = (state.messagesByConv.get(target) || []).filter(
      (m) => (m._status === 'pending' || m._status === 'failed') && !seenClientIds.has(m.clientMessageId),
    );
    setConversationMessages(target, [...fresh, ...pendings]);
    if (target === state.activeConv || target === state.secondaryConv) renderActivePanel();
    persistMessages(target);
  } catch {
    // A rejected session is handled by endSession; anything else retries on the next poll.
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
  const replyToId = state.replyDraftByConv.get(target)?.id ?? null;
  await sendContent(conv, textContent(text, replyToId), {
    onSealed: () => {
      // Reply consumed: clear the banner and the composer.
      if (replyToId) state.replyDraftByConv.delete(target);
      textarea.value = '';
      textarea.style.height = 'auto';
      textarea.dispatchEvent(new Event('input'));
      emitTypingStop(target);
      playSendTone();
    },
  });
}

const newClientMessageId = (prefix = 'web') => `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

// Local-only state of a bubble shown before its content was sealed (an
// upload's preview, a recording), carried over to the sent message.
const LOCAL_MEDIA_FIELDS = ['_imageUrl', '_voiceUrl', '_localFile'];

function replaceOwnMessage(convId, clientMessageId, view) {
  const list = state.messagesByConv.get(convId) || [];
  const index = list.findIndex((m) => m.clientMessageId === clientMessageId);
  if (index >= 0) list[index] = view;
  else list.push(view);
  state.messagesByConv.set(convId, list);
}

// Every send: the content is sealed end to end (src/features/sender.js) and
// shown at once as a pending bubble, then delivered; a send that cannot go
// out now waits, sealed, in the outbound queue. `local` is a bubble already
// shown for this send (an upload in progress). Resolves to the delivered
// view, or null.
async function sendContent(conv, content, {
  clientMessageId = newClientMessageId(),
  attachmentId = null,
  failureLabel = '전송 실패',
  local = null,
  onSealed = () => {},
} = {}) {
  const markFailed = (message) => {
    message._status = 'failed';
    renderActivePanel();
  };
  let envelope;
  try {
    envelope = await sender.seal(conv.id, content, { clientMessageId, attachmentId });
  } catch (e) {
    toastSendFailure(failureLabel, e);
    if (local) markFailed(local);
    return null;
  }
  onSealed();
  const optimistic = await ingest({
    id: '__pending__' + clientMessageId,
    clientMessageId,
    conversationId: conv.id,
    senderDeviceId: state.me.deviceId,
    ciphertext: envelope.ciphertext,
    nonce: envelope.nonce,
    messageType: envelope.messageType,
    serverReceivedAt: null,
  }, { content });
  for (const field of LOCAL_MEDIA_FIELDS) if (local?.[field] !== undefined) optimistic[field] = local[field];
  optimistic._status = 'pending';
  optimistic._localAt = local?._localAt ?? new Date().toISOString();
  replaceOwnMessage(conv.id, clientMessageId, optimistic);
  renderActivePanel();

  let delivered;
  try {
    delivered = await sender.deliver({ conversationId: conv.id, clientMessageId, envelope });
  } catch (e) {
    markFailed(optimistic);
    toast(`${failureLabel}: ${e.message}`, 'error');
    return null;
  }
  if (delivered.queued) {
    if (!delivered.sessionEnded) toast('연결 안 됨 — 큐잉 후 자동 재시도합니다');
    return null;
  }
  const view = await ingest(delivered.message, { previous: optimistic });
  for (const field of LOCAL_MEDIA_FIELDS) if (optimistic[field] !== undefined) view[field] ??= optimistic[field];
  replaceOwnMessage(conv.id, clientMessageId, view);
  conv.lastMessage = view;
  sortConversations();
  persistMessage(view);
  persistConversation(conv);
  renderActivePanel();
  renderSidebar();
  return view;
}

// Phase AK: revoke any blob: URLs we created for voice/image so the
// browser actually frees the underlying memory. Without this, the
// Blob bytes stay alive for the page's lifetime even after the user
// logs out or deletes the message.
function blobUrlsOf(msg) {
  return [msg?._voiceUrl, msg?._imageUrl].filter((url) => typeof url === 'string' && url.startsWith('blob:'));
}
function revokeBlobUrlsForMessage(msg) {
  for (const url of blobUrlsOf(msg)) {
    try { URL.revokeObjectURL(url); } catch {}
  }
  if (msg) {
    msg._voiceUrl = null;
    msg._imageUrl = null;
  }
}
function revokeAllBlobUrls() {
  for (const list of state.messagesByConv.values()) {
    for (const msg of list) revokeBlobUrlsForMessage(msg);
  }
}

// Contract C4 on this device: once a message's expiry passes it leaves
// every list and what was kept of it is retired, through the same ingest
// path as everything else. Stored contents of messages that are not loaded
// expire with them.
async function expireDueMessages() {
  const now = Date.now();
  const due = (message) => isPast(message?.expiresAtMs, now);
  const expire = (message) => ingest(serializeMessageForCache(message), { previous: message });
  let changed = false;
  for (const [convId, list] of state.messagesByConv) {
    const dueMessages = list.filter(due);
    if (dueMessages.length === 0) continue;
    const expired = new Map((await Promise.all(dueMessages.map(expire))).map((view) => [view.id, view]));
    // Swapped into the list as it is now: a message may have arrived meanwhile.
    setConversationMessages(convId, (state.messagesByConv.get(convId) || []).map((m) => expired.get(m.id) ?? m));
    for (const view of expired.values()) persistMessage(view);
    changed = true;
  }
  for (const conv of state.conversations) {
    if (!due(conv.lastMessage)) continue;
    const view = await expire(conv.lastMessage);
    if (conv.lastMessage?.id === view.id) conv.lastMessage = view;
    changed = true;
  }
  await secure.retireExpired();
  if (changed) {
    renderSidebar();
    renderActivePanel();
  }
}

function startPolling() {
  if (state.pollTimer) clearInterval(state.pollTimer);
  // Polling acts as a safety-net that runs while the WS handshake is pending
  // and stays at a relaxed cadence after WS connects. Expiry runs on every
  // tick, hidden tab or not.
  state.pollTimer = setInterval(async () => {
    if (!state.me) return;
    await expireDueMessages().catch((error) => console.warn('expiry sweep failed', error));
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
  try {
    if (!(await restoreSession())) await showAuth();
  } catch (e) {
    toast('세션 복원 실패: ' + e.message, 'error');
    await showAuth({ rejected: isAuthRejection(e) });
  }
}

$('register-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const handle = $('reg-handle').value.trim().toLowerCase();
  if (!handle) return toast('핸들을 입력하세요', 'error');
  if (!/^[a-z0-9_]{1,32}$/.test(handle)) return toast('소문자, 숫자, _ 만 사용 (최대 32자)', 'error');
  // A new handle replaces the identity stored here, which destroys it.
  if ((await hasStoredIdentity()) && !(await confirmAndDestroyIdentity())) return;
  $('reg-btn').disabled = true;
  try {
    await registerIdentity(handle);
    await enterApp();
    toast('환영합니다 @' + handle, 'good');
  } catch (e) {
    toast(e.message, 'error');
    if (sessionStore.current()) await showAuth({ rejected: isAuthRejection(e) });
  } finally {
    $('reg-btn').disabled = false;
  }
});

$('restore-btn').addEventListener('click', async () => {
  $('restore-btn').disabled = true;
  try {
    await restoreSession();
  } catch (e) {
    toast('복원 실패: ' + e.message, 'error');
    await showAuth({ rejected: isAuthRejection(e) });
  } finally {
    $('restore-btn').disabled = false;
  }
});

$('restore-delete-btn').addEventListener('click', confirmAndDestroyIdentity);
$('wipe-btn').addEventListener('click', confirmAndDestroyIdentity);
$('legacy-new-identity').addEventListener('click', confirmAndDestroyIdentity);

$('search-input').addEventListener('input', renderSidebar);

// Restores focus to what had it before a dialog opened, also when dialogs
// stack (src/ui/dialogs.js) — important for keyboard users.
const { open: openDialog, close: closeDialog } = createDialogs(document);
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
  } else if (action === 'transfer-start') {
    startTransferOld();
  } else if (action === 'wipe') {
    await confirmAndDestroyIdentity();
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
  setBannerVisible(safeLocalStorage()?.getItem(BETA_BANNER_KEY) !== '1');
  betaBannerClose.addEventListener('click', () => {
    setBannerVisible(false);
    try { localStorage.setItem(BETA_BANNER_KEY, '1'); } catch {}
  });
}

// ---------- device transfer ----------
// Two flows live here, sharing the same dialogs in index.html. The OLD
// device watches its transfer session (src/features/device-transfer.js),
// shows the new device's fingerprint once a claim lands, and approves. The
// NEW device — which has no session yet — generates a fresh keypair, posts
// /device-transfer/claim, then retries /device-transfer/complete every
// 2.5s with the same auth proof until the server returns 200.

let transferOld = null;
async function startTransferOld() {
  if (!state.me) { toast('로그인 후 시도하세요', 'error'); return; }
  // A new transfer session closes any earlier one on the server.
  stopTransferOld();
  let init;
  try {
    init = await authedApi('/device-transfer/init', {
      method: 'POST',
      body: { oldDeviceId: state.me.deviceId },
    });
  } catch (e) {
    toast('이전 시작 실패: ' + e.message, 'error');
    return;
  }
  const blob = JSON.stringify({ sessionId: init.sessionId, transferToken: init.transferToken });
  $('transfer-old-token').value = btoa(blob).replace(/=+$/, '');
  $('transfer-old-status').textContent = '코드 복사 후 새 기기에 붙여넣기 — 새 기기 클레임 대기 중…';
  $('transfer-old-claim').classList.add('hidden');
  $('transfer-old-approve').classList.add('hidden');
  $('transfer-old-cancel').textContent = '취소';
  const transfer = watchOldDeviceTransfer({
    sessionId: init.sessionId,
    authedApi,
    onClaim: (claim) => {
      $('transfer-old-fingerprint').textContent = claim.claimantFingerprint;
      $('transfer-old-claim').classList.remove('hidden');
      $('transfer-old-approve').classList.remove('hidden');
      $('transfer-old-status').textContent = '지문 확인 후 승인하세요.';
    },
    onPollError: (e) => {
      $('transfer-old-status').textContent = '폴링 오류: ' + e.message;
    },
  });
  transferOld = transfer;
  openDialog('transfer-old-dialog', 'transfer-old-token');
  const outcome = await transfer.outcome;
  if (transferOld === transfer) transferOld = null;
  await finishTransferOld(outcome);
}
async function finishTransferOld(outcome) {
  if (outcome === 'completed') {
    // The handle now lives on the new device; this copy of the identity is
    // spent, so a completed transfer is one of the two ways it goes.
    closeTransferOldDialog();
    await destroyIdentity();
    toast('이전 완료 — 이 기기의 키를 삭제했습니다', 'good');
  } else if (outcome === 'expired' || outcome === 'closed') {
    $('transfer-old-status').textContent = outcome === 'expired'
      ? '만료되었습니다 (5분 초과). 다시 시작하세요.'
      : '이 이전 세션은 닫혔어요. 다시 시작하세요.';
    $('transfer-old-approve').classList.add('hidden');
  }
  // 'session-ended' and 'cancelled': endSession or the cancel button
  // already took care of the screen.
}
async function approveTransferOld() {
  const transfer = transferOld;
  if (!transfer) return;
  $('transfer-old-approve').disabled = true;
  try {
    await transfer.approve();
    $('transfer-old-status').textContent = '승인됨 — 새 기기가 완료할 때까지 대기…';
    $('transfer-old-approve').classList.add('hidden');
    $('transfer-old-cancel').textContent = '닫기';
  } catch (e) {
    toast('승인 실패: ' + e.message, 'error');
  } finally {
    $('transfer-old-approve').disabled = false;
  }
}
function cancelTransferOld() {
  // The server cannot call off an approved transfer, so after an approval
  // the dialog only closes and the watch runs on until the transfer ends.
  if (transferOld?.approved) closeTransferOldDialog();
  else stopTransferOld();
}
function stopTransferOld() {
  transferOld?.cancel();
  transferOld = null;
  closeTransferOldDialog();
}
function closeTransferOldDialog() {
  if (!$('transfer-old-dialog').classList.contains('hidden')) closeDialog('transfer-old-dialog');
}

let transferNewState = null;
function openTransferNew() {
  // A completed transfer whose keys are not saved yet reopens on its retry.
  if (transferNewState?.completion) {
    openDialog('transfer-new-dialog', 'transfer-new-claim');
    return;
  }
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
// What the old device shows for this claim: SHA-256 over the auth key and
// the identity key the new device will be trusted with, in groups of four
// hex digits, computed the way the server computes claimantFingerprint.
async function transferFingerprint({ authPublicKey, publicIdentityKey }) {
  const digest = await sha256(crypto.subtle, concatBytes([decodeBase64Url(authPublicKey), decodeBase64Url(publicIdentityKey)]));
  return hexOf(digest).replace(/(.{4})(?!$)/g, '$1 ');
}

const hexOf = (bytes) => Array.from(bytes, (byte) => byte.toString(16).padStart(2, '0')).join('');

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
  // Completing the transfer replaces the identity stored here, so ask now,
  // while backing out is still free.
  const replacesIdentity = await hasStoredIdentity();
  if (replacesIdentity) {
    const ok = await uiConfirm({
      title: '기존 신원 교체',
      body: '이 브라우저에 저장된 신원은 이전이 완료되면 영구 삭제되고, 그 핸들로는 다시 로그인할 수 없어요.',
      okLabel: '계속',
      destructive: true,
    });
    if (!ok) return;
  }
  $('transfer-new-claim').disabled = true;
  $('transfer-new-error').textContent = '';
  $('transfer-new-status').textContent = '새 키 생성 중…';
  try {
    const keys = await generateIdentity(crypto.subtle);
    const published = await publishedKeys(crypto.subtle, keys);
    $('transfer-new-fingerprint-text').textContent = await transferFingerprint(published);
    $('transfer-new-fingerprint').classList.remove('hidden');
    $('transfer-new-status').textContent = '서버에 클레임 중…';
    const claimSig = await signChallenge(crypto.subtle, keys.edPrivKey, `transfer-claim:${parsed.sessionId}:${parsed.transferToken}`);
    const claim = await api('/device-transfer/claim', {
      method: 'POST',
      body: {
        sessionId: parsed.sessionId,
        transferToken: parsed.transferToken,
        newDeviceName: name,
        platform: 'android',
        ...published,
        authProof: claimSig,
      },
    });
    transferNewState = { ...parsed, claimId: claim.claimId, keys, replacesIdentity };
    $('transfer-new-status').textContent = '이전 기기에서 승인 대기 중…';
    pollTransferNew();
  } catch (e) {
    $('transfer-new-error').textContent = e.message;
    $('transfer-new-claim').disabled = false;
  }
}
async function pollTransferNew() {
  const transfer = transferNewState;
  if (!transfer) return;
  const completion = await awaitTransferCompletion(transfer);
  if (!completion) return;
  // Kept even if the dialog was cancelled while /complete was in flight: the
  // server has activated these keys and the old device destroys its copy, so
  // they are the identity's only copy until saveTransferNew stores them.
  transferNewState = { ...transfer, completion };
  await saveTransferNew();
}
// Runs once the transfer completed, and again from the dialog's button
// after a failed save: the keys stay in transferNewState until stored.
async function saveTransferNew() {
  const { completion, keys, replacesIdentity } = transferNewState;
  $('transfer-new-claim').disabled = true;
  $('transfer-new-error').textContent = '';
  $('transfer-new-status').textContent = '새 키 저장 중…';
  let cleanupError;
  try {
    ({ cleanupError } = await storeTransferredIdentity({
      completion,
      keys,
      sessionStore,
      clearReplacedIdentity: replacesIdentity ? clearReplacedIdentity : null,
    }));
  } catch (e) {
    $('transfer-new-error').textContent = '새 키를 저장하지 못했어요: ' + e.message;
    $('transfer-new-status').textContent = '이전은 완료됐고 키는 이 탭에만 있어요. 탭을 닫지 말고 다시 저장하세요.';
    $('transfer-new-claim').textContent = '다시 저장';
    $('transfer-new-claim').disabled = false;
    // The dialog may have been closed while /complete was in flight.
    if ($('transfer-new-dialog').classList.contains('hidden')) openDialog('transfer-new-dialog', 'transfer-new-claim');
    return;
  }
  if (cleanupError) toast('이전 신원의 데이터 일부를 지우지 못했어요: ' + cleanupError.message, 'error');
  transferNewState = null;
  closeDialog('transfer-new-dialog');
  try {
    // /complete returns no tokens: the new device signs a normal challenge
    // with its newly trusted key.
    await apiClient.login(await sessionStore.getDeviceCredentials());
  } catch (e) {
    // The transfer went through and the identity is stored here; only the
    // first sign-in failed, so the auth screen offers Retry.
    toast('이전은 완료됐지만 로그인하지 못했어요: ' + e.message, 'error');
    await showAuth({ rejected: isAuthRejection(e) });
    return;
  }
  toast('이전 완료 — 새 기기로 들어왔습니다', 'good');
  await enterApp();
}
// Retries /device-transfer/complete with one auth proof until the old device
// has approved. Resolves to the completion, or to null once the attempt
// failed or was cancelled.
async function awaitTransferCompletion({ sessionId, transferToken, claimId, keys }) {
  const authProof = await signChallenge(
    crypto.subtle,
    keys.edPrivKey,
    `transfer-complete:${sessionId}:${claimId}:${transferToken}`,
  );
  while (transferNewState) {
    try {
      return await api('/device-transfer/complete', {
        method: 'POST',
        body: { sessionId, transferToken, claimId, authProof },
      });
    } catch (e) {
      if (e.code !== 'transfer_approval_required' && e.status !== 403) {
        failTransferNew(e);
        return null;
      }
      $('transfer-new-status').textContent = '이전 기기에서 승인 대기 중…';
      await new Promise((r) => setTimeout(r, TRANSFER_POLL_MS));
    }
  }
  return null;
}
function failTransferNew(e) {
  $('transfer-new-error').textContent = e.message;
  $('transfer-new-status').textContent = '실패. 다시 시도하세요.';
  $('transfer-new-claim').disabled = false;
  transferNewState = null;
}
function cancelTransferNew() {
  // Keys a completed transfer activated are never dropped: the dialog only
  // closes, and opening it again brings back the retry.
  if (!transferNewState?.completion) transferNewState = null;
  closeDialog('transfer-new-dialog');
}

$('transfer-old-cancel').addEventListener('click', cancelTransferOld);
$('transfer-old-approve').addEventListener('click', approveTransferOld);
$('transfer-new-btn').addEventListener('click', openTransferNew);
$('transfer-new-cancel').addEventListener('click', cancelTransferNew);
$('transfer-new-claim').addEventListener('click', () => (transferNewState?.completion ? saveTransferNew() : claimTransferNew()));

// ---------- message actions: react / edit / delete ----------
// Right-click (or long-press on touch) on a .msg-row pops a small menu.
// Reactions are end-to-end encrypted control messages (src/domain/reactions.js);
// there is no REST reaction call. Edit seals a new frame and replaces the
// body via PATCH /messages/:id; Delete tombstones server-side via DELETE.
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

  if (isTextKind(msg.kind)) {
    const copyItem = document.createElement('button');
    copyItem.className = 'msg-action-item';
    copyItem.textContent = '📋  복사';
    copyItem.addEventListener('click', async (ev) => {
      ev.stopPropagation();
      try { await navigator.clipboard.writeText(msg.displayText); toast('복사됨', 'good'); }
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
  // A message the server has not named yet cannot be a reaction's target.
  const found = messageId.startsWith('__pending__') ? null : locateMessage(messageId);
  if (!found) return;
  const current = reactionsByTarget(found.list).get(messageId)
    ?.find((reaction) => reaction.senderDeviceId === state.me.deviceId)?.emoji ?? null;
  const clientMessageId = newClientMessageId('react');
  try {
    const { content, message } = await sender.react({
      conversationId: found.convId,
      clientMessageId,
      target: messageId,
      emoji,
      current,
    });
    // A queued reaction shows once the outbound queue delivers it.
    if (!message) return;
    const view = await ingest(message, { content });
    replaceOwnMessage(found.convId, clientMessageId, view);
    persistMessage(view);
    renderActivePanel();
  } catch (e) {
    toastSendFailure('반응 실패', e);
  }
}

function startEdit(msg, convId) {
  if (!isTextKind(msg.kind)) {
    toast('이 메시지는 수정할 수 없어요', 'error');
    return;
  }
  const text = msg.displayText;
  const fresh = window.prompt('메시지 수정', text);
  if (fresh == null) return;
  const trimmed = fresh.trim();
  if (!trimmed || trimmed === text) return;
  doEdit(msg, convId, trimmed);
}

// An edit is a new frame on the session; the stored content is replaced only
// once the server has taken it.
async function doEdit(msg, convId, newText) {
  const content = textContent(newText, msg.replyTo);
  try {
    const envelope = await secure.sealEdit(convId, content);
    await authedApi(`/messages/${msg.id}`, {
      method: 'PATCH',
      body: { ciphertext: envelope.ciphertext, nonce: envelope.nonce, version: envelope.version },
    });
    await secure.rememberEdit(convId, msg.id, content, envelope.nonce);
    const edited = Object.assign(serializeMessageForCache(msg), {
      ciphertext: envelope.ciphertext,
      nonce: envelope.nonce,
      editedAt: new Date().toISOString(),
    });
    await reingestInPlace(msg.id, edited, { content, editCount: (msg.editCount || 0) + 1 });
  } catch (e) {
    toastSendFailure('수정 실패', e);
  }
}

// Edits go through the same ingest path as new messages, so an edited reply
// renders its text rather than the raw payload.
async function onMessageEdited(serverMsg) {
  const found = locateMessage(serverMsg.id);
  if (!found) return;
  // Only the original sender can edit; never take the device id from the edit.
  const edited = Object.assign(serializeMessageForCache(found.message), {
    ciphertext: serverMsg.ciphertext,
    nonce: serverMsg.nonce,
    editedAt: serverMsg.editedAt ?? found.message.editedAt,
  });
  await reingestInPlace(serverMsg.id, edited, { editCount: serverMsg.editCount ?? found.message.editCount });
}

async function doDelete(messageId) {
  try {
    await authedApi(`/messages/${messageId}`, { method: 'DELETE' });
  } catch (e) {
    toast('삭제 실패: ' + e.message, 'error');
  }
}

// Bubble reactions row — groups by emoji, shows count, my own reactions
// get a highlighted border. Click toggles through the same E2E path the
// action menu uses, so the picker and the chip share state.
// reactions: [{ senderDeviceId, emoji }] (src/domain/reactions.js).
function renderReactionsRow(msg, reactions = []) {
  const tally = new Map();
  for (const r of reactions) {
    const entry = tally.get(r.emoji) || { count: 0, mine: false };
    entry.count += 1;
    if (r.senderDeviceId === state.me?.deviceId) entry.mine = true;
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
// recording goes out as an encrypted attachment like a file, its key
// inside the ratchet (src/crypto/attachment-v2.js), so the server only
// ever sees ciphertext.
const VOICE_MAX_MS = 30_000;

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
  await sendMedia(convId, {
    kind: 'voice',
    blob,
    contentType: mime,
    failureLabel: '음성 전송 실패',
    local: { _voiceUrl: URL.createObjectURL(blob) },
  });
}

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

// Markdown + mention chips are built as DOM nodes by src/ui/markdown-dom.js
// (tested in __tests__/markdown-dom.test.js); renderMessageBody uses it.

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

// Content follows the notification privacy level (generic by default); the
// body is the message's preview label, never its payload.
function maybeShowNotification(message) {
  if (document.visibilityState === 'visible') return;
  if (!('Notification' in window)) return;
  if (Notification.permission !== 'granted') return;
  if (mutedConvIds.has(message.conversationId)) return;
  const content = buildNotification({
    level: readNotificationLevel(safeLocalStorage()),
    senderHandle: peerOf(message.conversationId)?.handle,
    preview: previewLabel(message),
    conversationId: message.conversationId,
    labels: { appName: 'VEIL', newMessage: t('notifications.newMessage') },
  });
  if (!content) return;
  try {
    const n = new Notification(content.title, {
      body: content.body,
      icon: './icon.svg',
      tag: content.tag,
      silent: false,
    });
    n.onclick = () => {
      window.focus();
      if (message.conversationId) state.activeConv = message.conversationId;
      try { n.close(); } catch {}
      renderActivePanel();
    };
  } catch {}
}

function ensureNotifPrompt() {
  if (notifPromptDismissed) return;
  if (!('Notification' in window)) return;
  if (Notification.permission !== 'default') return;
  if (readNotificationLevel(safeLocalStorage()) === 'off') return;
  if (!state.me) return; // only after auth
  if (document.querySelector('.notif-prompt')) return;
  const sidebar = document.getElementById('sidebar');
  if (!sidebar) return;
  const enable = el('button', { class: 'enable' }, ['켜기']);
  const dismiss = el('button', { class: 'dismiss' }, ['나중에']);
  const node = el('div', { class: 'notif-prompt' }, [
    el('span', { style: 'flex:1;line-height:1.4' }, [
      '알림 켤까요?',
      el('br'),
      el('span', { style: 'opacity:0.7;font-size:11px' }, ['백그라운드에서도 새 메시지를 알려요.']),
    ]),
    enable,
    dismiss,
  ]);
  enable.addEventListener('click', async () => {
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
  dismiss.addEventListener('click', () => {
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

  // Esc closes any open dialog or menu, regardless of focus target. A dialog
  // that handled Esc itself (uiConfirm) has closed; without this check the
  // dialog it was stacked on would close with it.
  if (e.key === 'Escape' && !e.defaultPrevented) {
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
    const grid = el('div', { class: 'help-grid' });
    for (const s of SHORTCUTS) {
      const keys = s.sequence.flatMap((k, i) => (i === 0 ? [el('kbd', {}, [k])] : [' + ', el('kbd', {}, [k])]));
      grid.append(el('div', { class: 'seq' }, keys), el('div', {}, [s.label]));
    }
    dialog = el('div', { id: 'help-dialog', class: 'dialog-backdrop hidden', role: 'presentation' }, [
      el('div', { class: 'dialog', role: 'dialog', 'aria-modal': 'true', 'aria-labelledby': 'help-title' }, [
        el('div', { class: 'dialog-title', id: 'help-title' }, ['키보드 단축키']),
        el('div', { class: 'dialog-sub' }, ['VEIL 을 더 빠르게 쓰는 법.']),
        grid,
        el('div', { class: 'dialog-sub', style: 'margin-top:14px;font-size:11px;opacity:0.6' }, [
          `${state.soundsEnabled ? '🔊' : '🔇'} 사운드: ${state.soundsEnabled ? '켜짐' : '꺼짐'} (메뉴 또는 Ctrl/Cmd+Shift+S)`,
        ]),
        el('div', { class: 'dialog-actions' }, [
          el('button', { class: 'btn btn-primary', id: 'help-ok' }, ['확인']),
        ]),
      ]),
    ]);
    document.body.appendChild(dialog);
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

// The messages of a conversation whose shown text contains `query`.
function searchMatches(convId, query) {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  const now = Date.now();
  return (state.messagesByConv.get(convId) || []).filter((m) =>
    isShown(m, now) && isTextKind(m.kind) && m.displayText.toLowerCase().includes(q));
}

// Build the search bar DOM. Returns null when search is closed for
// this conversation.
function renderPanelSearch(convId) {
  const st = getSearchState(convId);
  if (!st.open) return null;
  const q = st.query.trim();
  const matches = searchMatches(convId, q);
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
    const matches = searchMatches(convId, q);
    matches.forEach((m, i) => {
      const row = panel.querySelector(`.msg-row[data-msg-id="${m.id}"]`);
      if (!row) return;
      if (i === st.idx) row.classList.add('search-active');
      const span = row.querySelector('.msg-text');
      if (!span) return;
      const text = m.displayText;
      const lower = text.toLowerCase();
      const qLower = q.toLowerCase();
      let cursor = 0;
      const out = document.createDocumentFragment();
      while (cursor < text.length) {
        const found = lower.indexOf(qLower, cursor);
        if (found === -1) {
          out.appendChild(document.createTextNode(text.slice(cursor)));
          break;
        }
        if (found > cursor) {
          out.appendChild(document.createTextNode(text.slice(cursor, found)));
        }
        const mark = document.createElement('mark');
        mark.textContent = text.slice(found, found + q.length);
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
      item.appendChild(avatarFor(m.handle, 'sm'));
      item.appendChild(el('div', {}, [handleLine(m.handle)]));
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

// ---------- Phase AI: image attachment upload ----------
// User picks an image → we generate a fresh AES-256-GCM key for this
// attachment, encrypt the bytes, upload the ciphertext, then send a
// message whose encrypted payload carries the attachment id, key and
// nonce (src/domain/payload.js). Receivers download and decrypt lazily
// when the bubble renders (src/domain/media.js).

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
  // The local file is the bubble's preview while it uploads.
  const sent = await sendMedia(convId, {
    kind: 'image',
    blob: file,
    contentType: file.type,
    failureLabel: '이미지 전송 실패',
    local: { _imageUrl: URL.createObjectURL(file) },
  });
  if (sent) playSendTone();
}

// Starts (or checks) the session before anything is uploaded, so a frozen
// conversation never uploads a blob.
async function ensureSendable(convId, failureLabel) {
  try {
    await secure.prepare(convId);
    return true;
  } catch (e) {
    toastSendFailure(failureLabel, e);
    return false;
  }
}

const MEDIA_PENDING_TEXT = {
  image: () => KIND_LABELS.image,
  voice: () => KIND_LABELS.voice,
  file: (name) => `📁 ${name}`,
};

// Image, voice note or file: shown at once as a local bubble, uploaded
// encrypted, then sent as a message whose content carries the attachment
// pointer. Resolves to the delivered view, or null.
async function sendMedia(convId, { kind, blob, contentType, name = '', failureLabel, local }) {
  const conv = state.conversations.find((c) => c.id === convId);
  if (!conv) return null;
  if (!(await ensureSendable(convId, failureLabel))) return null;
  const clientMessageId = newClientMessageId(kind);
  const pending = Object.assign(pendingLocalMessage({
    clientMessageId,
    conversationId: convId,
    messageType: kind,
    kind,
    displayText: MEDIA_PENDING_TEXT[kind](name),
  }), local);
  replaceOwnMessage(convId, clientMessageId, pending);
  renderActivePanel();
  let pointer;
  try {
    pointer = await uploadEncryptedAttachment(blob, contentType);
  } catch (e) {
    toastSendFailure(failureLabel, e);
    pending._status = 'failed';
    renderActivePanel();
    return null;
  }
  return sendContent(conv, mediaContent(kind, pointer, name), {
    clientMessageId,
    attachmentId: pointer.id,
    failureLabel,
    local: pending,
  });
}

// Seals the bytes under a fresh key (src/crypto/attachment-v2.js) and uploads
// only the blob. The id is ours, proposed with the ticket, because the blob's
// AAD binds it; the pointer (key, digest, type, size) travels only inside the
// end-to-end encrypted payload.
async function uploadEncryptedAttachment(blob, contentType) {
  const attachmentId = crypto.randomUUID();
  const plaintext = new Uint8Array(await blob.arrayBuffer());
  const sealed = await encryptAttachment(crypto.subtle, keySource.randomBytes, { attachmentId, contentType, plaintext });
  const ticket = await authedApi('/attachments/upload-ticket', {
    method: 'POST',
    body: {
      attachmentId,
      contentType: 'application/octet-stream',
      sizeBytes: sealed.blob.byteLength,
      sha256: hexOf(await sha256(crypto.subtle, sealed.blob)),
    },
  });
  if (ticket.attachmentId !== attachmentId) throw new Error('the relay assigned another attachment id');
  const putRes = await fetch(ticket.upload.uploadUrl, {
    method: 'PUT',
    headers: ticket.upload.headers,
    body: sealed.blob,
  });
  if (!putRes.ok) throw new Error(`upload PUT failed: ${putRes.status}`);
  await authedApi('/attachments/complete', {
    method: 'POST',
    body: { attachmentId, uploadStatus: 'uploaded' },
  });
  return sealed.pointer;
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
    btn.appendChild(el('span', { 'aria-hidden': 'true' }, ['📷']));
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
const undoStateByMsg = new Map(); // messageId → { text, convId, expiresAt }, memory only

function offerDeleteUndo({ messageId, convId, text }) {
  if (text === '') return;
  undoStateByMsg.set(messageId, { text, convId, expiresAt: Date.now() + 5_000 });
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
    ta.value = entry.text;
    ta.dispatchEvent(new Event('input'));
    ta.focus();
    toast('입력창에 복원했어요. Enter 로 다시 전송', 'good');
  } else {
    // Fallback: send immediately.
    const conv = state.conversations.find((c) => c.id === entry.convId);
    if (conv) {
      const dummy = document.createElement('textarea');
      dummy.value = entry.text;
      sendMessage(dummy, entry.convId);
    }
  }
}

// Hook into doDelete: capture the text + convId BEFORE the server
// delete propagates and replaces the view with the tombstone.
const __veilOriginalDoDelete = doDelete;
doDelete = async function (messageId) {
  const found = locateMessage(messageId);
  const captured = found && isTextKind(found.message.kind)
    ? { messageId, convId: found.convId, text: found.message.displayText }
    : null;
  await __veilOriginalDoDelete(messageId);
  if (captured) offerDeleteUndo(captured);
};

// ---------- Phase AM: unified Settings dialog ----------
// Replaces the existing "🔔 사운드 토글" and "⌨️ 단축키" menu entries
// with a single "⚙️ 설정" item that opens a structured dialog. The
// dialog hosts theme / sounds / language / notifications all in one
// place — discoverability win, single mental model.

const NOTIFICATION_LEVEL_LABEL_KEYS = {
  off: 'settings.notifications.off',
  generic: 'settings.notifications.generic',
  sender: 'settings.notifications.sender',
  sender_preview: 'settings.notifications.senderPreview',
};

function settingsSelect(key, options, value) {
  const select = el('select', { class: 'settings-select', dataset: { key } },
    options.map(([optionValue, label]) => el('option', { value: optionValue }, [label])));
  select.value = value;
  return select;
}

function openSettingsDialog() {
  document.getElementById('settings-dialog')?.remove();
  const themeSel = settingsSelect('theme', [['dark', '다크'], ['light', '라이트']],
    document.documentElement.classList.contains('theme-light') ? 'light' : 'dark');
  const langSel = settingsSelect('lang', [['ko', '한국어'], ['en', 'English'], ['ja', '日本語']],
    typeof activeLang === 'function' ? activeLang() : 'ko');
  const levelSel = settingsSelect('notification-level',
    NOTIFICATION_LEVELS.map((level) => [level, t(NOTIFICATION_LEVEL_LABEL_KEYS[level])]),
    readNotificationLevel(safeLocalStorage()));
  const sounds = el('input', { type: 'checkbox', class: 'settings-toggle', dataset: { key: 'sounds' } });
  sounds.checked = !!state.soundsEnabled;
  const notifBtn = el('button', { class: 'btn btn-ghost', dataset: { key: 'notif' } }, ['권한 요청']);
  const closeBtn = el('button', { class: 'btn btn-primary', id: 'settings-close' }, ['닫기']);
  const row = (label, control) => el('div', { class: 'settings-row' }, [
    el('div', { class: 'settings-label' }, [label]),
    control,
  ]);
  const back = el('div', { id: 'settings-dialog', class: 'dialog-backdrop', role: 'presentation' }, [
    el('div', {
      class: 'dialog',
      role: 'dialog',
      'aria-modal': 'true',
      'aria-labelledby': 'settings-title',
      style: 'width:380px;max-width:92vw',
    }, [
      el('div', { class: 'dialog-title', id: 'settings-title' }, ['⚙️ 설정']),
      el('div', { class: 'dialog-sub', style: 'margin-bottom:12px' }, ['VEIL 의 모든 토글을 한 곳에.']),
      row('테마', themeSel),
      row('언어 (재로드 필요)', langSel),
      row('사운드 (수신/전송 톤)', sounds),
      row('브라우저 알림', notifBtn),
      row(t('settings.notifications.level'), levelSel),
      renderBlockedSection(),
      el('div', { class: 'dialog-actions', style: 'margin-top:14px' }, [closeBtn]),
    ]),
  ]);
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
  levelSel.addEventListener('change', () => {
    if (!writeNotificationLevel(safeLocalStorage(), levelSel.value)) toast('설정을 저장하지 못했어요', 'error');
  });
  sounds.addEventListener('change', () => {
    state.soundsEnabled = sounds.checked;
    try { localStorage.setItem(SOUND_KEY, state.soundsEnabled ? '1' : '0'); } catch {}
  });
  notifBtn.addEventListener('click', async () => {
    if (!('Notification' in window)) { toast('알림 미지원 브라우저', 'error'); return; }
    if (Notification.permission === 'granted') { toast('이미 켜짐', 'good'); return; }
    if (Notification.permission === 'denied') { toast('브라우저 설정에서 풀어주세요', 'error'); return; }
    const r = await Notification.requestPermission();
    toast(r === 'granted' ? '알림 켜짐' : '알림 거부됨', r === 'granted' ? 'good' : 'error');
  });
  const close = () => back.remove();
  closeBtn.addEventListener('click', close);
  back.addEventListener('click', (e) => { if (e.target === back) close(); });
  closeBtn.focus();
}

// "차단된 사용자" list for the settings dialog, filled once the server answers.
function renderBlockedSection() {
  const container = el('div', { class: 'blocked-list', id: 'blocked-list-container' });
  listBlocked().then((items) => {
    container.replaceChildren(...items.map((u) => {
      const unblock = el('button', { class: 'unblock' }, ['해제']);
      const blockedRow = el('div', { class: 'blocked-row' }, [
        avatarFor(u.handle ?? '?', 'sm'),
        el('div', { class: 'grow' }, [handleLine(u.handle, 'font-size:13px')]),
        unblock,
      ]);
      unblock.addEventListener('click', async () => {
        await unblockUser(u.userId ?? u.id, u.handle ?? '?');
        blockedRow.remove();
      });
      return blockedRow;
    }));
  });
  return el('div', {
    dataset: { blockedSection: '1' },
    style: 'margin-top:10px;border-top:1px solid rgba(255,255,255,0.06);padding-top:10px',
  }, [
    el('div', { class: 'settings-label', style: 'margin-bottom:6px' }, ['차단된 사용자']),
    container,
  ]);
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
    font: inherit; text-align: left;
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
  const name = sanitizeFilename(file.name);
  const sent = await sendMedia(convId, {
    kind: 'file',
    blob: file,
    contentType: file.type || 'application/octet-stream',
    name,
    failureLabel: '파일 전송 실패',
    local: { _localFile: { name, sizeBytes: file.size } },
  });
  if (sent) playSendTone();
}

// Downloads go out as application/octet-stream under the sanitized name, so
// a hostile file is saved, never rendered in our origin.
async function downloadFile(message) {
  const { media } = message;
  if (!media) return;
  try {
    toast(`다운로드 중: ${media.name}…`);
    const url = URL.createObjectURL(await media.materialize());
    const a = el('a', { href: url, download: media.name });
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
  } catch (e) {
    toast('다운로드 실패: ' + (e.message || 'unknown'), 'error');
  }
}

// Forward dialog — pick another conversation, send the same text as a
// fresh message (no quote header, no edit linkage).
function openForwardDialog(msg) {
  if (!isTextKind(msg.kind) || msg.displayText === '') {
    toast('전달할 내용이 없어요', 'error'); return;
  }
  const others = state.conversations.filter((c) => c.id !== msg.conversationId);
  if (others.length === 0) { toast('전달할 다른 대화가 없어요'); return; }
  const list = el('div', { class: 'forward-list' });
  const cancelBtn = el('button', { class: 'btn btn-ghost', id: 'fwd-cancel' }, ['취소']);
  const confirmBtn = el('button', { class: 'btn btn-primary', id: 'fwd-confirm', disabled: 'disabled' }, ['전달']);
  const back = el('div', { class: 'dialog-backdrop', role: 'presentation' }, [
    el('div', {
      class: 'dialog',
      role: 'dialog',
      'aria-modal': 'true',
      'aria-labelledby': 'fwd-title',
      style: 'width:380px;max-width:92vw',
    }, [
      el('div', { class: 'dialog-title', id: 'fwd-title' }, ['메시지 전달']),
      el('div', { class: 'dialog-sub' }, ['전달할 대화를 고르세요. 원본 인용 없이 새 메시지로 보내져요.']),
      list,
      el('div', { class: 'dialog-actions' }, [cancelBtn, confirmBtn]),
    ]),
  ]);
  document.body.appendChild(back);
  let selected = null;
  for (const c of others) {
    const peer = c.members?.find((m) => m.userId !== state.me?.userId);
    const item = el('div', { class: 'forward-list-item', dataset: { convId: c.id } }, [
      avatarFor(peer?.handle ?? '?', 'sm'),
      el('div', { style: 'flex:1' }, [handleLine(peer?.handle)]),
    ]);
    item.addEventListener('click', () => {
      list.querySelectorAll('.forward-list-item').forEach((x) => x.classList.remove('selected'));
      item.classList.add('selected');
      selected = c.id;
      confirmBtn.disabled = false;
    });
    list.appendChild(item);
  }
  const close = () => back.remove();
  cancelBtn.addEventListener('click', close);
  back.addEventListener('click', (e) => { if (e.target === back) close(); });
  confirmBtn.addEventListener('click', async () => {
    if (!selected) return;
    const ta = document.createElement('textarea');
    ta.value = msg.displayText;
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
    btn.appendChild(el('span', { 'aria-hidden': 'true' }, ['📎']));
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

// ---------- Phase AS: KakaoTalk import wizard ----------
// Korean-market killer feature. User picks an exported .txt; we parse
// in-browser, store the result in IndexedDB as a read-only archive,
// and surface it in the sidebar with a 📥 prefix so it's obviously
// not a live conversation. The bytes never leave the device.
// The sidebar reads only the 'kakao-archive-meta' rows (kept in memory
// below); full message lists are read when an archive is opened.

let kakaoArchiveRows = [];

async function loadKakaoArchiveRows() {
  try {
    kakaoArchiveRows = await idb.all('kakao-archive-meta');
  } catch {
    kakaoArchiveRows = [];
  }
}

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
  const fileInput = el('input', { type: 'file', id: 'kakao-file', accept: '.txt,text/plain' });
  const previewBox = el('div', { id: 'kakao-preview', class: 'hidden', style: 'margin-top:14px' });
  const errorBox = el('div', { class: 'dialog-error', id: 'kakao-error', role: 'alert', 'aria-live': 'polite' });
  const cancelBtn = el('button', { class: 'btn btn-ghost', id: 'kakao-cancel' }, ['취소']);
  const confirmBtn = el('button', { class: 'btn btn-primary', id: 'kakao-confirm', disabled: 'disabled' }, ['아카이브로 저장']);
  const back = el('div', { class: 'dialog-backdrop', role: 'presentation' }, [
    el('div', {
      class: 'dialog',
      role: 'dialog',
      'aria-modal': 'true',
      'aria-labelledby': 'kakao-title',
      style: 'width:480px;max-width:92vw',
    }, [
      el('div', { class: 'dialog-title', id: 'kakao-title' }, ['📥 카카오톡 채팅 가져오기']),
      el('div', { class: 'dialog-sub' }, [
        '카톡 → 채팅방 → 설정 → ',
        el('strong', {}, ['대화 내용 내보내기']),
        ' → 텍스트 파일 (.txt) 받은 거 여기에 떨어뜨리세요. ',
        el('strong', {}, ['읽기 전용 아카이브']),
        '로 저장되며, 이 브라우저 밖으로 절대 나가지 않아요.',
      ]),
      fileInput,
      previewBox,
      errorBox,
      el('div', { class: 'dialog-actions' }, [cancelBtn, confirmBtn]),
    ]),
  ]);
  document.body.appendChild(back);

  let parsed = null;
  let archiveTitle = '';

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
      const { participants, errors } = parsed;
      const shown = participants.slice(0, 4).join(', ');
      const more = participants.length > 4 ? ` 외 ${participants.length - 4}명` : '';
      previewBox.replaceChildren(el('div', { class: 'kakao-import-summary' }, [
        el('div', {}, [el('strong', {}, [String(parsed.messages.filter((m) => m.kind === 'msg').length)]), ' 개 메시지']),
        el('div', {}, [el('strong', {}, [String(participants.length)]), ` 명 참여 (${shown}${more})`]),
        errors.length > 0
          ? el('div', { style: 'opacity:0.7;margin-top:4px' }, [`파싱 경고 ${errors.length}건 (계속 진행 가능)`])
          : null,
      ]));
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
      const archive = {
        id: 'kakao-' + Date.now().toString(36),
        title: archiveTitle,
        importedAt: new Date().toISOString(),
        participants: parsed.participants,
        messageCount: parsed.messages.filter((m) => m.kind === 'msg').length,
        messages: parsed.messages,
      };
      await idb.put('kakao-archives', archive);
      await idb.put('kakao-archive-meta', kakaoArchiveMeta(archive));
      toast('아카이브로 저장됨', 'good');
      close();
      await loadKakaoArchiveRows();
      renderSidebar();
    } catch (e) {
      errorBox.textContent = '저장 실패: ' + (e.message || 'unknown');
      confirmBtn.disabled = false;
    }
  });
}

// Sidebar rows for imported archives, appended after the live conversations.
function renderKakaoArchiveRows() {
  if (kakaoArchiveRows.length === 0) return [];
  return [
    el('div', {
      dataset: { kakaoSection: '1' },
      style: 'padding:10px 14px 4px;font-size:11px;opacity:0.55;letter-spacing:0.05em;text-transform:uppercase',
    }, ['카카오 아카이브']),
    ...kakaoArchiveRows.map((meta) => el('button', {
      class: 'conv-item',
      style: 'background:transparent;border:0;color:inherit;cursor:pointer;width:100%;display:flex;align-items:center;gap:10px;padding:10px 14px;text-align:left',
      onclick: () => openKakaoArchive(meta),
    }, [
      avatarFor(meta.title || 'kakao', 'sm'),
      el('div', { style: 'flex:1' }, [
        el('div', { style: 'font-size:13px' }, [
          el('span', { class: 'kakao-conv-prefix' }, ['📥']),
          meta.title || '아카이브',
        ]),
        el('div', { style: 'font-size:11px;opacity:0.6' }, [`${meta.messageCount} 메시지 · 읽기 전용`]),
      ]),
    ])),
  ];
}

// Open archive → render messages in the right panel as read-only.
async function openKakaoArchive(meta) {
  const panels = document.getElementById('panels');
  if (!panels) return;
  const archive = await idb.get('kakao-archives', meta.id).catch(() => null);
  if (!archive) {
    toast('아카이브를 불러오지 못했어요', 'error');
    return;
  }
  // Replace the panels container content with a read-only archive view.
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

bootIfSession();
