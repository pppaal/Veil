// Whom each direct conversation is with, recorded the first time its crypto
// admits an identity for it and never changed after that: the web side of
// mobile's ConversationPeerBindings (docs/crypto-envelope-spec.md, "Identity
// trust": what a 1:1 conversation encrypts to is always what it shows).
//
// A session stays with its conversation id for as long as this device keeps
// it, and a direct conversation never changes members. The conversation list
// is relayed by the server, though. Taken as it comes, a listing that names
// another user for an established conversation, or turns it into a group,
// would have the pins judge the conversation's frames for that user (pinned
// on first use, with no warning) and the panel show that user, with the
// earlier peer's history under the new name. Once bound, the crypto resolves
// the conversation's peer from the binding, and a listing that names anyone
// else updates only the conversation's last message and timer
// (adoptedConversation).
//
// What the crypto is about and what the user sees are one and the same
// member, resolved one way (createPeerResolver): by userId, the binding
// first. No view picks a member by handle, and our own entry in a listing is
// always this device's own userId and handle, never the relay's: a listing
// that put our own entry under a contact's handle would otherwise name the
// conversation after that contact, whoever its crypto is with.
//
// A binding also ties a handle to the account it was bound with. The user
// sees handles, never user ids, so a conversation that is not bound yet is
// held (hold) while its listed handle is one this device knows under
// another account (handleConflict), this device's own handle under another
// account, or one no honest server issues (src/domain/handles.js): a
// lookalike of a known handle, with an invisible or a non-Latin character
// in it, matches none of them. Until the user says it is a different
// account, nothing is pinned, installed or sealed for it.
//
// kv: src/platform/kv.js over 'direct-peers' ({ conversationId, userId, handle });
// self() -> the signed-in identity ({ userId, handle }) or null.

import { directPeer, shownPeer } from './conversations.js';
import { isIssuableHandle } from './handles.js';

// Why a conversation that is not bound yet is held.
export const HoldReason = Object.freeze({
  // Listed under a handle this device knows under another account.
  OTHER_ACCOUNT: 'other-account',
  // Listed under a handle no honest server issues.
  UNISSUED_HANDLE: 'unissued-handle',
  // Listed under this device's own handle, as another account.
  OWN_HANDLE: 'own-handle',
});

const sameHandle = (a, b) => typeof a === 'string' && typeof b === 'string' && a.toLowerCase() === b.toLowerCase();

export function createPeerBindings(kv, { self = () => null } = {}) {
  const bound = new Map(); // conversationId -> { userId, handle }
  // Conversations whose session bindSessions already looked for.
  const sessionChecked = new Set();
  let loading = null; // the load in flight or done; null before, after a failure and after reset
  let loaded = false;
  let generation = 0;

  // Shared by every caller, so a binding recorded while the read is in
  // flight is not dropped by a second read. A failed read binds nothing
  // over what the store may hold: callers refuse until a later read works.
  function load() {
    const current = generation;
    loading ??= kv.all().then((rows) => {
      if (current !== generation) return;
      for (const { conversationId, userId, handle } of rows) if (!bound.has(conversationId)) bound.set(conversationId, { userId, handle });
      loaded = true;
    }).catch((error) => {
      if (current === generation) loading = null;
      throw error;
    });
    return loading;
  }

  async function bind(conversationId, peer) {
    if (!loaded) throw new Error('peer bindings are not loaded');
    if (bound.has(conversationId) || !peer?.userId) return;
    const binding = { userId: peer.userId, handle: peer.handle ?? '' };
    bound.set(conversationId, binding);
    try {
      await kv.put({ conversationId, ...binding });
    } catch (error) {
      if (bound.get(conversationId) === binding) bound.delete(conversationId);
      throw error;
    }
  }

  function handleConflict(conversationId, peer) {
    if (!peer?.handle || bound.has(conversationId)) return null;
    for (const binding of bound.values()) {
      if (sameHandle(binding.handle, peer.handle) && binding.userId !== peer.userId) return { ...binding };
    }
    return null;
  }

  // Our own handle names one account, ours: no honest server lists another
  // under it.
  function isOwnHandleOfAnother(peer) {
    const me = self();
    return Boolean(me?.userId) && sameHandle(me.handle, peer.handle) && peer.userId !== me.userId;
  }

  // An unissued handle is held whatever this device knows: none it bound
  // can equal it, yet it may render as one of them.
  function hold(conversationId, peer) {
    if (!peer || bound.has(conversationId)) return null;
    if (!isIssuableHandle(peer.handle)) return { reason: HoldReason.UNISSUED_HANDLE };
    if (isOwnHandleOfAnother(peer)) return { reason: HoldReason.OWN_HANDLE };
    const binding = handleConflict(conversationId, peer);
    return binding ? { reason: HoldReason.OTHER_ACCOUNT, binding } : null;
  }

  return {
    load,
    // Resolves once the stored bindings are read, reading them again after
    // a failed read; rejects while they cannot be.
    ensureLoaded: () => (loaded ? Promise.resolve() : load()),

    // { userId, handle } or null.
    get: (conversationId) => {
      const binding = bound.get(conversationId);
      return binding ? { ...binding } : null;
    },

    // Records whom the conversation is with, unless it is bound already: a
    // binding is never replaced.
    bind,

    // The binding of another conversation under this peer's handle but
    // another account, while this conversation is not bound itself; null
    // otherwise.
    handleConflict,

    // Why the conversation admits nothing until the user chooses to talk to
    // the account it is listed with, while it is not bound:
    // { reason: HoldReason.UNISSUED_HANDLE } for a handle no honest server
    // issues, { reason: HoldReason.OWN_HANDLE } for this device's own
    // handle on another account, { reason: HoldReason.OTHER_ACCOUNT,
    // binding } for one this device knows under another account; null
    // otherwise.
    hold,

    // Binds the listed direct conversations that already hold a session,
    // each checked once per sign-in: sessions started before bindings
    // existed are bound to the peer they are listed with now, before a
    // later listing can name someone else. One listed under a handle no
    // honest server issues, or under our own, is left unbound, and so held,
    // for the user to settle. hasSession(conversationId) -> boolean.
    async bindSessions(conversations, { selfUserId, hasSession }) {
      if (!loaded) return;
      for (const conversation of conversations) {
        if (bound.has(conversation.id) || sessionChecked.has(conversation.id)) continue;
        const peer = directPeer(conversation, selfUserId);
        if (!peer || !isIssuableHandle(peer.handle) || isOwnHandleOfAnother(peer)) continue;
        sessionChecked.add(conversation.id);
        if (await hasSession(conversation.id)) await bind(conversation.id, peer);
      }
    },

    // Forgets what is held in memory (the session ended); the stored
    // bindings stay with the identity and go with it when it is wiped.
    reset() {
      generation += 1;
      bound.clear();
      sessionChecked.clear();
      loading = null;
      loaded = false;
    },
  };
}

// The conversation as this device shows it and encrypts for it, from the
// relay's listing of it. Our own entry is always this device's userId and
// handle, never the listing's. A bound conversation stays direct, with us
// and the bound peer under the handle it was bound with, whatever members or
// type the listing gives; everything else (last message, timer) is the
// listing's. self: the signed-in identity ({ userId, handle }).
export function adoptedConversation(conversation, binding, self) {
  if (!self?.userId) return conversation;
  const own = { userId: self.userId, handle: self.handle };
  if (binding) {
    return { ...conversation, type: 'direct', members: [own, { userId: binding.userId, handle: binding.handle }] };
  }
  const members = (conversation.members ?? []).map((member) => (member.userId === self.userId ? own : member));
  return { ...conversation, members };
}

// Whom a conversation is about, for its crypto and for every view of it,
// resolved one way: by userId, its bound peer first. peerOf(conversationId)
// is the peer its sessions, pins and safety number are about (the binding,
// else the listed direct peer); shownPeer(conversation) the member its row,
// tab and panel are named after, which for a direct conversation is that
// same peer (src/domain/conversations.js shownPeer).
// conversationOf(conversationId): the conversation as adopted;
// selfUserId(): the signed-in user's id.
export function createPeerResolver({ bindings, conversationOf, selfUserId }) {
  const peerOf = (conversationId) => bindings.get(conversationId) ?? directPeer(conversationOf(conversationId), selfUserId());
  return {
    peerOf,
    shownPeer: (conversation) => shownPeer(conversation, { selfUserId: selfUserId(), peerOf }),
  };
}

// The identity verifier the session cipher asks before it installs a
// session and for every frame it seals or opens
// (src/crypto/session-cipher.js verifyIdentity), about the conversation's
// bound peer: peerOf(conversationId) resolves the binding first. A
// conversation that is not bound yet is bound to the peer the pins
// admitted, before anything is installed or sealed for it; one held for
// its listed handle (hold: known under another account, or never issued)
// is refused, the pins not even asked, until the user acknowledges that
// account (which binds it). Refuses while the bindings cannot be read.
export function createConversationVerifier({ bindings, trust, peerOf }) {
  return async function verifyIdentity({ conversationId, remoteDeviceId, identityKey }) {
    try {
      await bindings.ensureLoaded();
    } catch {
      return false;
    }
    const peer = peerOf(conversationId);
    if (!peer) return false;
    const bound = bindings.get(conversationId);
    if (!bound && bindings.hold(conversationId, peer)) return false;
    if (!(await trust.admit(peer.userId, remoteDeviceId, identityKey))) return false;
    if (bound) return true;
    try {
      await bindings.bind(conversationId, peer);
    } catch {
      return false;
    }
    return true;
  };
}
