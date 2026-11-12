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
// (boundConversation).
//
// A binding also ties a handle to the account it was bound with. The user
// sees handles, never user ids, so a conversation that is not bound yet and
// lists a handle this device knows under another account is held
// (handleConflict) until the user says it is a different account; until
// then nothing is pinned, installed or sealed for it.
//
// kv: src/platform/kv.js over 'direct-peers' ({ conversationId, userId, handle }).

import { directPeer } from './conversations.js';

const sameHandle = (a, b) => typeof a === 'string' && typeof b === 'string' && a.toLowerCase() === b.toLowerCase();

export function createPeerBindings(kv) {
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
    handleConflict(conversationId, peer) {
      if (!peer?.handle || bound.has(conversationId)) return null;
      for (const binding of bound.values()) {
        if (sameHandle(binding.handle, peer.handle) && binding.userId !== peer.userId) return { ...binding };
      }
      return null;
    },

    // Binds the listed direct conversations that already hold a session,
    // each checked once per sign-in: sessions started before bindings
    // existed are bound to the peer they are listed with now, before a
    // later listing can name someone else. hasSession(conversationId) ->
    // boolean.
    async bindSessions(conversations, { selfUserId, hasSession }) {
      if (!loaded) return;
      for (const conversation of conversations) {
        if (bound.has(conversation.id) || sessionChecked.has(conversation.id)) continue;
        const peer = directPeer(conversation, selfUserId);
        if (!peer) continue;
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

// The conversation as this device shows it and encrypts for it. A bound
// conversation stays direct, with us and the bound peer under the handle it
// was bound with, whatever members or type the listing gives; everything
// else (last message, timer) is the listing's.
export function boundConversation(conversation, binding, self) {
  if (!binding || !self?.userId) return conversation;
  const members = conversation.members ?? [];
  const selfMember = members.find((member) => member.userId === self.userId) ?? { userId: self.userId, handle: self.handle };
  const listed = conversation.type === 'direct' ? members.find((member) => member.userId === binding.userId) : null;
  return {
    ...conversation,
    type: 'direct',
    members: [selfMember, { ...listed, userId: binding.userId, handle: binding.handle }],
  };
}

// The identity verifier the session cipher asks before it installs a
// session and for every frame it seals or opens
// (src/crypto/session-cipher.js verifyIdentity), about the conversation's
// bound peer: peerOf(conversationId) resolves the binding first. A
// conversation that is not bound yet is bound to the peer the pins
// admitted, before anything is installed or sealed for it; one whose
// listed handle this device knows under another account is refused until
// the user acknowledges that account (which binds it). Refuses while the
// bindings cannot be read.
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
    if (!bound && bindings.handleConflict(conversationId, peer)) return false;
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
