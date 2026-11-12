// Where the user's trust decisions about a peer's identity key are carried
// out: accepting or declining a key the pins do not admit
// (src/crypto/pins.js), and comparing and verifying safety numbers
// (src/crypto/safety-number.js). The views ask and show; this decides
// nothing on its own, and every decision is bound to the change or key the
// user was shown.

import { PinVerdict, ReverificationRequiredError } from '../../crypto/pins.js';
import { formatSafetyNumber, matchesPeerCode, safetyNumber, verificationCode } from '../../crypto/safety-number.js';

export function createIdentityTrust({ store, stack, messages }) {
  const { trust, secure } = stack;

  // Handshakes refused while a key change was pending are retried once the
  // key is accepted or verified; nothing about them was stored.
  async function reopenLockedMessages(userId) {
    const affected = store.state.conversations.filter((conv) => stack.peerOf(conv.id)?.userId === userId);
    for (const conv of affected) {
      const list = store.messagesOf(conv.id);
      const next = await Promise.all(list.map((message) => (message.kind === 'locked' ? messages.ingest(message, { previous: message }) : message)));
      messages.setMessages(conv.id, next);
      if (conv.lastMessage?.kind === 'locked') conv.lastMessage = await messages.ingest(conv.lastMessage, { previous: conv.lastMessage });
    }
    store.notify('sidebar', 'panels');
  }

  return {
    pendingChange: (userId) => trust.pendingChange(userId),

    // A direct conversation not bound to its peer yet, listed under a handle
    // this device knows under another account or under one no honest
    // server issues (src/domain/peer-bindings.js hold), admits nothing until
    // the user says it is a different account and wants to talk to it: then
    // the conversation is bound to it, and what it sent is opened again, as
    // a first contact. Resolves to false when there was no such hold to
    // settle.
    async acknowledgeAccount(convId) {
      const peer = stack.peerOf(convId);
      if (!peer || !stack.bindings.hold(convId, peer)) return false;
      await stack.bindings.bind(convId, peer);
      await reopenLockedMessages(peer.userId);
      return true;
    },

    // What the banner over a frozen conversation says, and whether its
    // change can only be accepted by comparing safety numbers: a contact
    // the user had verified, or a device of theirs never verified.
    bannerFor(peer) {
      const change = trust.pendingChange(peer.userId);
      let textKey = change?.verified ? 'keyChange.bannerVerified' : 'keyChange.banner';
      if (change?.verdict === PinVerdict.UNVERIFIED_DEVICE) textKey = 'keyChange.bannerUnverifiedDevice';
      return { textKey, needsComparison: Boolean(change?.verified) };
    },

    // Accepts `reviewed`, the change shown to the user, never one that
    // replaced it meanwhile. Resolves to 'accepted' (then the caller reopens
    // what was locked), 'superseded' (another change waits now), 'unchanged'
    // or 'reverify' (compare safety numbers instead); throws when the pins
    // could not be updated.
    async accept(peer, reviewed) {
      try {
        if (await trust.accept(peer.userId, reviewed)) return 'accepted';
      } catch (error) {
        if (error instanceof ReverificationRequiredError) return 'reverify';
        throw error;
      }
      return trust.pendingChange(peer.userId) ? 'superseded' : 'unchanged';
    },

    // Declines `reviewed`: that device and key stay refused without being
    // raised again, and the conversation sends on to the identity it has.
    // It adds no trust, so a verified contact's change may be declined too.
    // Resolves to src/features/secure-messaging.js declineChange's outcome,
    // with 'superseded' only while another change waits.
    async decline(convId, peer, reviewed) {
      const outcome = await secure.declineChange(convId, reviewed);
      if (outcome === 'superseded' && !trust.pendingChange(peer.userId)) return 'declined';
      return outcome;
    },

    // The safety number of a direct conversation, computed from the key the
    // conversation uses (src/features/secure-messaging.js safetyKey) and
    // never sent anywhere: { status: 'not-signed-in' | 'no-key' } or
    // { status: 'ready', number, code, remoteKey, pendingNoteKey,
    //   matches(theirCode) }.
    async safetyNumberFor(convId, peer) {
      const me = store.state.me;
      // A safety number binds our user id, which a transferred device learns
      // only at its first sign-in.
      if (!me.userId) return { status: 'not-signed-in' };
      const remoteKey = await secure.safetyKey(convId);
      if (!remoteKey) return { status: 'no-key' };
      const local = { identityKey: me.ik.publicKey, userId: me.userId };
      const remote = { identityKey: remoteKey.identityKey, userId: peer.userId };
      let pendingNoteKey = remoteKey.pendingVerdict ? 'safety.pendingKey' : null;
      if (remoteKey.pendingVerdict === PinVerdict.UNVERIFIED_DEVICE) pendingNoteKey = 'safety.unverifiedDevice';
      return {
        status: 'ready',
        number: formatSafetyNumber(await safetyNumber(crypto.subtle, local, remote)),
        code: verificationCode(local, remote),
        remoteKey,
        pendingNoteKey,
        matches: (theirCode) => matchesPeerCode(local, remote, theirCode),
      };
    },

    // Marks exactly the key the safety number was computed from as verified.
    async markVerified(peer, remoteKey) {
      await trust.markVerified(peer.userId, remoteKey.deviceId, remoteKey.identityKey);
    },

    reopenLockedMessages,
  };
}
