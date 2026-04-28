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

// ---------- crypto (Ed25519 only in Phase A; X25519 envelope in Phase E) ----------
async function generateAuthKey() {
  const kp = await crypto.subtle.generateKey({ name: 'Ed25519' }, true, ['sign', 'verify']);
  const rawPub = await crypto.subtle.exportKey('raw', kp.publicKey);
  const jwkPriv = await crypto.subtle.exportKey('jwk', kp.privateKey);
  return { authPublicKey: b64uEncode(rawPub), jwkPriv };
}
async function importAuthPriv(jwk) {
  return await crypto.subtle.importKey('jwk', jwk, { name: 'Ed25519' }, false, ['sign']);
}
async function signChallenge(privateKey, challenge) {
  const sig = await crypto.subtle.sign({ name: 'Ed25519' }, privateKey, new TextEncoder().encode(challenge));
  return b64uEncode(sig);
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

// ---------- session ----------
const session = {
  load() { try { return JSON.parse(localStorage.getItem(STORE) ?? 'null'); } catch { return null; } },
  save(s) { localStorage.setItem(STORE, JSON.stringify(s)); },
  wipe() { localStorage.removeItem(STORE); },
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
};

// ---------- render ----------
function showAuth() {
  $('auth-screen').classList.remove('hidden');
  $('app').classList.add('hidden');
  const stored = session.load();
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
      const preview = last ? renderPreview(last.ciphertext) : '아직 메시지 없음';
      const time = last ? formatRelTime(last.serverReceivedAt) : '';
      return el(
        'button',
        {
          class: 'conv-item' + (isActive ? ' active' : ''),
          onclick: () => openConversation(c.id),
        },
        [
          avatarFor(peer?.handle ?? '?', 'md'),
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

function renderPreview(ciphertext) {
  // Strip the dev label so the sidebar shows the inner text.
  const m = /^DEMO-PLAINTEXT-LABEL\[(.*)\]$/s.exec(ciphertext || '');
  return (m ? m[1] : ciphertext) || '';
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
        stack.appendChild(el('div', { class: cls.join(' ') }, [renderPreview(m.ciphertext)]));
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
  const sendBtn = el(
    'button',
    { class: 'send-btn', 'aria-label': '전송', onclick: () => sendMessage(textarea, convId) },
    [el('span', { 'aria-hidden': 'true' }, ['↑'])],
  );
  // Auto-grow.
  const autoGrow = () => {
    textarea.style.height = 'auto';
    textarea.style.height = Math.min(textarea.scrollHeight, 140) + 'px';
    sendBtn.disabled = textarea.value.trim().length === 0;
  };
  textarea.addEventListener('input', autoGrow);
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

  const panelNode = el('div', { class: 'panel', dataset: { conv: convId } }, [
    el('div', { class: 'panel-header' }, [
      avatarFor(peer?.handle ?? '?', 'md'),
      el('div', { class: 'panel-title' }, [
        el('div', { class: 'name' }, ['@' + (peer?.handle ?? '?')]),
        el('div', { class: 'sub' }, [`대화 ${conv.id.slice(0, 8)}`]),
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

// ---------- actions ----------
async function doRegister(displayName, handle) {
  const { authPublicKey, jwkPriv } = await generateAuthKey();
  const reg = await api('/auth/register', {
    method: 'POST',
    body: {
      handle,
      displayName: displayName || handle,
      deviceName: 'web-' + (navigator.platform || 'browser'),
      platform: 'android',
      publicIdentityKey: 'pub-web-' + Date.now(),
      signedPrekeyBundle: 'prekey-web-' + Date.now(),
      authPublicKey,
    },
  });
  const ch = await api('/auth/challenge', {
    method: 'POST',
    body: { handle: reg.handle, deviceId: reg.deviceId },
  });
  const priv = await crypto.subtle.importKey('jwk', jwkPriv, { name: 'Ed25519' }, false, ['sign']);
  const signature = await signChallenge(priv, ch.challenge);
  const ver = await api('/auth/verify', {
    method: 'POST',
    body: { challengeId: ch.challengeId, deviceId: reg.deviceId, signature },
  });
  state.me = {
    handle: reg.handle,
    userId: reg.userId,
    deviceId: reg.deviceId,
    jwkPriv,
    accessToken: ver.accessToken,
    refreshToken: ver.refreshToken,
  };
  session.save(state.me);
}

async function doRestore(stored) {
  const ch = await api('/auth/challenge', {
    method: 'POST',
    body: { handle: stored.handle, deviceId: stored.deviceId },
  });
  const priv = await importAuthPriv(stored.jwkPriv);
  const signature = await signChallenge(priv, ch.challenge);
  const ver = await api('/auth/verify', {
    method: 'POST',
    body: { challengeId: ch.challengeId, deviceId: stored.deviceId, signature },
  });
  state.me = { ...stored, accessToken: ver.accessToken, refreshToken: ver.refreshToken };
  session.save(state.me);
}

async function loadConversations() {
  try {
    const r = await api('/conversations', { token: state.me.accessToken });
    state.conversations = Array.isArray(r) ? r : (r.items ?? []);
    renderSidebar();
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
    const seenClientIds = new Set((r.items ?? []).map((m) => m.clientMessageId));
    const merged = [
      ...(r.items ?? []),
      ...pendings.filter((m) => !seenClientIds.has(m.clientMessageId)),
    ];
    state.messagesByConv.set(target, merged);
    if (target === state.activeConv || target === state.secondaryConv) renderActivePanel();
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

  // Optimistic insert with pending status so the bubble appears immediately.
  const optimistic = {
    id: '__pending__' + clientMessageId,
    clientMessageId,
    conversationId: conv.id,
    senderDeviceId: state.me.deviceId,
    ciphertext: 'DEMO-PLAINTEXT-LABEL[' + text + ']',
    nonce: 'nonce-pending',
    messageType: 'text',
    serverReceivedAt: null,
    _localAt: new Date().toISOString(),
    _status: 'pending',
  };
  const list = state.messagesByConv.get(conv.id) || [];
  list.push(optimistic);
  state.messagesByConv.set(conv.id, list);
  textarea.value = '';
  textarea.style.height = 'auto';
  textarea.dispatchEvent(new Event('input'));
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
          ciphertext: 'DEMO-PLAINTEXT-LABEL[' + text + ']',
          nonce: 'nonce-' + Math.random().toString(36).slice(2, 10),
          messageType: 'text',
        },
      },
    });
    // Swap the optimistic entry with the server-acknowledged message.
    const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
    if (idx >= 0) list[idx] = sent.message;
    else list.push(sent.message);
    conv.lastMessage = sent.message;
    state.conversations.sort((a, b) => {
      const ax = a.lastMessage?.serverReceivedAt ?? a.createdAt;
      const bx = b.lastMessage?.serverReceivedAt ?? b.createdAt;
      return bx.localeCompare(ax);
    });
    renderActivePanel();
    renderSidebar();
  } catch (e) {
    if (e.status === 401) return logout();
    const idx = list.findIndex((m) => m.clientMessageId === clientMessageId);
    if (idx >= 0) list[idx] = { ...optimistic, _status: 'failed' };
    renderActivePanel();
    toast('전송 실패: ' + e.message, 'error');
  }
}

function logout() {
  session.wipe();
  state.me = null;
  state.conversations = [];
  state.messagesByConv.clear();
  state.activeConv = null;
  if (state.pollTimer) clearInterval(state.pollTimer);
  state.pollTimer = null;
  showAuth();
  toast('로그아웃되었습니다');
}

function startPolling() {
  if (state.pollTimer) clearInterval(state.pollTimer);
  state.pollTimer = setInterval(async () => {
    if (!state.me) return;
    if (document.hidden) return;
    await loadConversations();
    // Refresh every open tab so split view + background tabs stay live.
    for (const convId of state.openTabs) {
      await refreshMessages(convId);
    }
  }, POLL_MS);
}

// ---------- event wiring ----------
async function bootIfSession() {
  const stored = session.load();
  if (!stored) {
    showAuth();
    return;
  }
  try {
    await doRestore(stored);
    await loadConversations();
    showApp();
    startPolling();
    setConnPill('connected', '온라인 (폴링)');
  } catch (e) {
    toast('세션 복원 실패: ' + e.message, 'error');
    showAuth();
  }
}

function setConnPill(kind, text) {
  const pill = $('conn-pill');
  pill.className = 'topbar-pill ' + kind;
  pill.textContent = text;
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
    setConnPill('connected', '온라인 (폴링)');
    toast('환영합니다 @' + handle, 'good');
  } catch (e) {
    toast(e.message, 'error');
  } finally {
    $('reg-btn').disabled = false;
  }
});

$('restore-btn').addEventListener('click', async () => {
  const stored = session.load();
  if (!stored) return;
  $('restore-btn').disabled = true;
  try {
    await doRestore(stored);
    await loadConversations();
    showApp();
    startPolling();
    setConnPill('connected', '온라인 (폴링)');
  } catch (e) {
    toast('복원 실패: ' + e.message, 'error');
  } finally {
    $('restore-btn').disabled = false;
  }
});

$('wipe-btn').addEventListener('click', () => {
  if (!confirm('이 브라우저의 키를 전부 삭제합니다. 이 핸들로는 다시 로그인할 수 없어요.')) return;
  session.wipe();
  showAuth();
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
    toast('연결: 폴링 (' + POLL_MS / 1000 + '초). WebSocket은 다음 단계에서.', 'good');
  } else if (action === 'wipe') {
    if (confirm('로그아웃하고 이 브라우저의 키를 전부 삭제합니다.')) {
      logout();
      session.wipe();
    }
  }
});

$('split-btn').addEventListener('click', toggleSplit);

bootIfSession();
