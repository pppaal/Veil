// Decrypt once: every ciphertext is opened by the ratchet exactly once, its
// content kept encrypted at rest per conversation, and rendering reads only
// from that store.

import { describe, expect, it, vi } from 'vitest';

import { textContent } from '../src/domain/content.js';
import { ingestMessage } from '../src/domain/ingest.js';
import { CONVERSATION } from './support/devices.js';
import { contentStores, conversation, openContentStore, serverMessage } from './support/messaging.js';

const media = { subtle: null, fetchAttachment: null };
const view = (endpoint, raw) => ingestMessage(raw, { open: (message) => endpoint.secure.open(message), media });

describe('message content store', () => {
  it('decrypts once and renders from store after restart', async () => {
    const { alice, bob } = await conversation();
    const sent = [];
    for (const text of ['first', 'second', 'third']) {
      const clientMessageId = `web-${text}`;
      const envelope = await alice.secure.seal(CONVERSATION, textContent(text), { clientMessageId });
      const message = serverMessage(envelope, { clientMessageId });
      await alice.secure.acknowledge(message);
      sent.push(message);
    }

    const decrypt = vi.spyOn(bob.device.cipher, 'decrypt');
    const firstViews = [];
    for (const message of sent) firstViews.push(await view(bob, message));
    expect(firstViews.map((v) => v.displayText)).toEqual(['first', 'second', 'third']);
    expect(decrypt).toHaveBeenCalledTimes(3);
    // A history refresh in the same page: no message is decrypted twice.
    for (const message of sent) await view(bob, message);
    expect(decrypt).toHaveBeenCalledTimes(3);

    // A reload: new cipher, store and messaging over the same stored data.
    bob.restart();
    const reloadedDecrypt = vi.spyOn(bob.device.cipher, 'decrypt');
    const reloaded = [];
    for (const message of sent) reloaded.push(await view(bob, message));
    expect(reloadedDecrypt).not.toHaveBeenCalled();
    expect(reloaded).toEqual(firstViews);

    // The sender reads its own messages from the store as well; it could not
    // decrypt them (their message keys were single-use).
    alice.restart();
    const aliceDecrypt = vi.spyOn(alice.device.cipher, 'decrypt');
    expect((await Promise.all(sent.map((message) => view(alice, message)))).map((v) => v.displayText))
      .toEqual(['first', 'second', 'third']);
    expect(aliceDecrypt).not.toHaveBeenCalled();
  });

  it('record moved to another key fails AAD', async () => {
    const stores = contentStores();
    const store = openContentStore(stores);
    await store.put('c-1', 'm-1', { content: textContent('secret one'), nonce: 'n-1' });
    await store.put('c-1', 'm-2', { content: textContent('secret two'), nonce: 'n-2' });
    expect((await store.get('c-1', 'm-1')).content.text).toBe('secret one');

    // Copy m-1's sealed row over m-2: same conversation key, other id.
    const row = await stores.records.get('c-1/m-1');
    await stores.records.put({ ...row, key: 'c-1/m-2', id: 'm-2' });
    expect(await store.get('c-1', 'm-2')).toBeNull();

    // Or under another conversation: another key altogether.
    await store.put('c-2', 'm-9', { content: textContent('elsewhere'), nonce: 'n-9' });
    await stores.records.put({ ...row, key: 'c-2/m-1', conversationId: 'c-2' });
    expect(await store.get('c-2', 'm-1')).toBeNull();
    expect((await store.get('c-1', 'm-1')).content.text).toBe('secret one');

    // Nothing in a stored row is readable without the key.
    const serialized = JSON.stringify([...stores.records.rows.values()], (_, value) =>
      (value instanceof Uint8Array ? new TextDecoder().decode(value) : value));
    expect(serialized).not.toContain('secret');
    expect((await stores.keys.get('c-1')).key.extractable).toBe(false);
  });

  it('conversation delete destroys key', async () => {
    const stores = contentStores();
    const store = openContentStore(stores);
    await store.put('c-1', 'm-1', { content: textContent('to be shredded'), nonce: 'n-1' });
    await store.put('c-2', 'm-2', { content: textContent('kept'), nonce: 'n-2' });
    const leftover = await stores.records.get('c-1/m-1');

    await store.deleteConversation('c-1');
    expect(await stores.keys.get('c-1')).toBeNull();
    expect(await stores.records.byIndex('c-1')).toEqual([]);
    // A copy of the sealed row that survived elsewhere opens no more.
    await stores.records.put(leftover);
    expect(await store.get('c-1', 'm-1')).toBeNull();
    // A new message in the conversation gets a new key, which opens nothing
    // that was sealed under the old one.
    await store.put('c-1', 'm-3', { content: textContent('new'), nonce: 'n-3' });
    expect(await store.get('c-1', 'm-1')).toBeNull();
    expect((await store.get('c-2', 'm-2')).content.text).toBe('kept');
  });

  it('deleted history stays hidden while the relay still serves it', async () => {
    const { alice, bob } = await conversation();
    const sent = [];
    for (const text of ['before', 'deleted too']) {
      const envelope = await alice.secure.seal(CONVERSATION, textContent(text), { clientMessageId: text });
      sent.push(serverMessage(envelope, { clientMessageId: text }));
    }
    for (const message of sent) expect((await view(bob, message)).kind).toBe('text');

    await bob.secure.forgetConversation(CONVERSATION, sent.at(-1).conversationOrder);
    for (const message of sent) expect((await view(bob, message)).kind).toBe('cleared');

    // What arrives afterwards is a new history under a new key.
    const later = await alice.secure.seal(CONVERSATION, textContent('after'), { clientMessageId: 'after' });
    expect(await view(bob, serverMessage(later, { clientMessageId: 'after' }))).toMatchObject({
      kind: 'text',
      displayText: 'after',
    });
  });
});
