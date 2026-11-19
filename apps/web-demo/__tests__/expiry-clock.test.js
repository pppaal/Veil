// Disappearing-message expiries are absolute times, stamped and judged on
// one clock (src/core/expiry.js expiryNow): this device's clock corrected
// toward the relay's, by an hour at most (src/platform/api-client.js
// expiryNow). On the raw local clock a sender running slow seals an expiry
// already past for everyone else, and a recipient running fast retires a
// message before it was shown.

import { afterEach, describe, expect, it, vi } from 'vitest';

import { createSend } from '../src/app/services/send.js';
import { createStore } from '../src/app/store.js';
import { expiryNow, setExpiryClock } from '../src/core/expiry.js';
import { textContent } from '../src/domain/content.js';
import { ingestMessage, isShown } from '../src/domain/ingest.js';
import { searchMatches } from '../src/domain/search.js';
import { createApiClient } from '../src/platform/api-client.js';

const MINUTE_MS = 60 * 1000;

// An API client whose device clock runs `skewMs` off the relay's, after one
// response has told it the relay's time.
async function skewedClient(skewMs) {
  const relayNow = Date.parse('2026-11-12T09:00:00.000Z');
  const fetchImpl = async () => ({
    ok: true,
    status: 200,
    headers: new Headers({ date: new Date(relayNow).toUTCString() }),
    text: async () => '{}',
  });
  const client = createApiClient({ fetchImpl, baseUrl: '/v1', tokenStore: {}, now: () => relayNow + skewMs });
  await client.api('/health');
  return { client, relayNow };
}

afterEach(() => setExpiryClock(() => Date.now()));

describe('the expiry clock', () => {
  it('is the local clock until the messaging stack sets it', () => {
    const before = Date.now();
    const now = expiryNow();
    expect(now).toBeGreaterThanOrEqual(before);
    expect(now).toBeLessThanOrEqual(Date.now());
  });

  it('a slow sender seals the expiry on the relay clock', async () => {
    const { client, relayNow } = await skewedClient(-40_000);
    setExpiryClock(client.expiryNow);
    const store = createStore();
    store.state.me = { userId: 'u-alice', handle: 'alice', deviceId: 'd-alice' };
    const conv = { id: 'c-1', type: 'direct', members: [], disappearingTimerSeconds: 10, lastMessage: null };
    store.state.conversations = [conv];
    const target = { id: 'm-0', conversationId: 'c-1', kind: 'text', displayText: 'hi', senderDeviceId: 'd-bob' };
    store.state.messagesByConv.set('c-1', [target]);
    const sealed = [];
    const stop = new Error('stop here');
    const stack = {
      sender: {
        seal: async (conversationId, content) => {
          sealed.push(content.expiresAt);
          throw stop;
        },
        react: async ({ expiresAt }) => {
          sealed.push(expiresAt);
          throw stop;
        },
      },
    };
    const toast = vi.fn();
    const send = createSend({ store, stack, messages: {}, realtime: { stopTyping() {} }, onSent() {}, toast });

    await send.sendText('c-1', 'self-destructing');
    await send.react('m-0', '👍');

    expect(sealed).toEqual([relayNow + 10_000, relayNow + 10_000]);
    expect(toast).toHaveBeenCalledTimes(2);
  });

  it('a fast recipient shows a message until its expiry on the relay clock', async () => {
    const { client, relayNow } = await skewedClient(40_000);
    setExpiryClock(client.expiryNow);
    const raw = {
      id: 'm-1',
      conversationId: 'c-1',
      senderDeviceId: 'd-bob',
      ciphertext: 'ct',
      nonce: 'n',
      messageType: 'text',
      serverReceivedAt: new Date(relayNow).toISOString(),
      expiresAt: new Date(relayNow + 10_000).toISOString(),
      deletedAt: null,
    };
    const content = { ...textContent('see you at 4'), expiresAt: relayNow + 10_000 };
    const retire = vi.fn(async () => {});

    const view = await ingestMessage(raw, { open: async () => ({ content }), retire, media: null });

    expect(view.kind).toBe('text');
    expect(retire).not.toHaveBeenCalled();
    expect(isShown(view)).toBe(true);
    expect(searchMatches([view], 'see you')).toEqual([view]);
    // And it goes once the relay clock passes its expiry.
    setExpiryClock(() => relayNow + 10_000);
    expect(isShown(view)).toBe(false);
  });

  it('a relay lying in its Date header moves an expiry by an hour at most', async () => {
    const { client, relayNow } = await skewedClient(-6 * 60 * MINUTE_MS);
    expect(client.serverNow()).toBe(relayNow);
    expect(client.expiryNow()).toBe(relayNow - 5 * 60 * MINUTE_MS);
  });
});
