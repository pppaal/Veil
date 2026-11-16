import { describe, expect, it } from 'vitest';

import { createMessages } from '../src/app/services/messages.js';
import { DecryptStatus } from '../src/crypto/session-cipher.js';
import { HoldReason } from '../src/domain/peer-bindings.js';

// What a message the crypto refused says: in a conversation held for its
// listed handle, that the account waits to be confirmed; otherwise, that
// the safety number changed. (Outside the app the dictionary is not loaded,
// so the words are the en.json keys.)

const MESSAGE_ID = '33333333-3333-4333-8333-333333333333';
const CONV_ID = '44444444-4444-4444-8444-444444444444';
const PEER = { userId: 'u-mallory', handle: 'bob' };

const raw = {
  id: MESSAGE_ID,
  conversationId: CONV_ID,
  senderDeviceId: 'd-mallory',
  messageType: 'text',
  ciphertext: 'c0',
  nonce: 'n0',
  version: 'veil-envelope-v2',
  conversationOrder: 1,
  serverReceivedAt: new Date().toISOString(),
};

function messagesWith({ failure, hold }) {
  const stack = {
    secure: { open: async () => ({ failure }), retire: async () => {} },
    peerOf: (conversationId) => (conversationId === CONV_ID ? PEER : null),
    bindings: { hold: (conversationId, peer) => (conversationId === CONV_ID && peer === PEER ? hold : null) },
    media: {},
    identityDb: { put: async () => {}, delete: async () => {} },
  };
  const store = { state: { messagesByConv: new Map(), conversations: [] } };
  return createMessages({ store, stack });
}

describe('a refused message', () => {
  it('in a held conversation waits for the account to be confirmed', async () => {
    for (const reason of Object.values(HoldReason)) {
      const view = await messagesWith({ failure: DecryptStatus.IDENTITY_REJECTED, hold: { reason } }).ingest(raw);
      expect(view.kind, reason).toBe('locked');
      expect(view.displayText, reason).toBe('msg.placeholder.held');
    }
  });

  it('anywhere else waits for the new safety number to be reviewed', async () => {
    const view = await messagesWith({ failure: DecryptStatus.IDENTITY_REJECTED, hold: null }).ingest(raw);
    expect(view.kind).toBe('locked');
    expect(view.displayText).toBe('msg.placeholder.locked');
  });

  it('keeps its own reason when the hold is not why it was refused', async () => {
    const view = await messagesWith({ failure: 'no-key', hold: { reason: HoldReason.OTHER_ACCOUNT } }).ingest(raw);
    expect(view.displayText).toBe('msg.placeholder.noKey');
  });
});
