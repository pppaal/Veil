// Reactions travel end to end inside the ratchet like any message; the
// server sees only a 'reaction' envelope and no REST reaction call exists.

import { describe, expect, it, vi } from 'vitest';

import { decodeBase64Url } from '../src/core/base64url.js';
import { ENVELOPE_VERSION_V2 } from '../src/crypto/frame.js';
import { textContent } from '../src/domain/content.js';
import { ingestMessage } from '../src/domain/ingest.js';
import { decodeReaction, encodeReaction, reactionsByTarget } from '../src/domain/reactions.js';
import { createSender } from '../src/features/sender.js';
import { CONVERSATION } from './support/devices.js';
import { conversation, serverMessage } from './support/messaging.js';

const media = { subtle: null, fetchAttachment: null };

// A relay that stores what POST /messages receives and fails everything else.
function relay() {
  const calls = [];
  const stored = [];
  const authedApi = vi.fn(async (path, { method = 'GET', body } = {}) => {
    calls.push({ path, method });
    if (path !== '/messages' || method !== 'POST') throw Object.assign(new Error('not found'), { status: 404 });
    const message = serverMessage(body.envelope, { clientMessageId: body.clientMessageId });
    stored.push(message);
    return { message };
  });
  return { calls, stored, authedApi };
}

describe('E2E reactions', () => {
  it('sent as E2E control message, no REST call', async () => {
    const { alice, bob } = await conversation();
    const server = relay();
    const queue = { put: vi.fn() };
    const aliceSender = createSender({ secure: alice.secure, authedApi: server.authedApi, queue });
    const bobSender = createSender({ secure: bob.secure, authedApi: server.authedApi, queue });

    const greetingEnvelope = await aliceSender.seal(CONVERSATION, textContent('lunch?'), { clientMessageId: 'web-1' });
    const { message: greeting } = await aliceSender.deliver({ conversationId: CONVERSATION, clientMessageId: 'web-1', envelope: greetingEnvelope });

    await bobSender.react({ conversationId: CONVERSATION, clientMessageId: 'web-2', target: greeting.id, emoji: '👍', current: null });
    await bobSender.react({ conversationId: CONVERSATION, clientMessageId: 'web-3', target: greeting.id, emoji: '🎉', current: '👍' });
    await aliceSender.react({ conversationId: CONVERSATION, clientMessageId: 'web-4', target: greeting.id, emoji: '🔥', current: null });
    await aliceSender.react({ conversationId: CONVERSATION, clientMessageId: 'web-5', target: greeting.id, emoji: '🔥', current: '🔥' });

    expect(server.calls).toEqual(Array(5).fill({ path: '/messages', method: 'POST' }));
    expect(server.calls.some((call) => call.path.includes('reaction'))).toBe(false);
    expect(queue.put).not.toHaveBeenCalled();
    const reactions = server.stored.slice(1);
    for (const message of reactions) {
      expect(message).toMatchObject({ messageType: 'reaction', version: ENVELOPE_VERSION_V2, attachment: null });
      // Neither the emoji nor the target travels in clear.
      const wire = JSON.stringify(message) + new TextDecoder().decode(decodeBase64Url(message.ciphertext));
      for (const secret of ['👍', '🎉', '🔥', '"target"']) expect(wire).not.toContain(secret);
    }

    // Each side folds the reaction messages it reads: last one per sender
    // wins, and none of them is a bubble.
    for (const endpoint of [alice, bob]) {
      const views = [];
      for (const message of server.stored) {
        views.push(await ingestMessage(message, { open: (raw) => endpoint.secure.open(raw), media }));
      }
      expect(views.filter((v) => v.kind !== 'reaction').map((v) => v.displayText)).toEqual(['lunch?']);
      expect(reactionsByTarget(views).get(greeting.id)).toEqual([{ senderDeviceId: 'd-bob', emoji: '🎉' }]);
    }
  });

  it('reaction bodies are strict', () => {
    const body = encodeReaction({ target: 'm-1', emoji: '👍', op: 'add' });
    expect(body).toBe('{"v":1,"target":"m-1","emoji":"👍","op":"add"}');
    expect(decodeReaction(body)).toEqual({ target: 'm-1', emoji: '👍', op: 'add' });
    for (const hostile of [
      '{"v":2,"target":"m-1","emoji":"👍","op":"add"}',
      '{"v":1,"target":"<img>","emoji":"👍","op":"add"}',
      '{"v":1,"target":"m-1","emoji":"far too long emoji","op":"add"}',
      '{"v":1,"target":"m-1","emoji":"👍","op":"replace"}',
      'not json',
      'null',
    ]) {
      expect(decodeReaction(hostile)).toBeNull();
    }
  });

  it('counts emoji in code points, as mobile does', () => {
    // 7 code points, 11 UTF-16 units.
    const family = '\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}';
    expect(decodeReaction(encodeReaction({ target: 'm-1', emoji: family, op: 'add' })))
      .toEqual({ target: 'm-1', emoji: family, op: 'add' });
    expect(decodeReaction(encodeReaction({ target: 'm-1', emoji: `${family}\u{1F44D}\u{1F44D}`, op: 'add' }))).toBeNull();
  });
});
