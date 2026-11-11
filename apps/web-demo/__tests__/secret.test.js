import { describe, expect, it } from 'vitest';
import { webcrypto } from 'node:crypto';

import { decodeBase64Url } from '../src/core/base64url.js';
import {
  formatSecretFragment,
  openSecret,
  parseSecretFragment,
  PBKDF2_ITERATIONS,
  sealSecret,
} from '../src/crypto/secret-link.js';

const ID = '0f8fad5b-d9cb-469f-a165-70867728950e';

async function seal(text, passphrase) {
  const sealed = await sealSecret(webcrypto, text, passphrase);
  return { ...sealed, link: parseSecretFragment(formatSecretFragment(ID, sealed.fragmentSecret)) };
}

describe('one-time secret links', () => {
  it('always puts a random 32-byte key in the fragment', async () => {
    const a = await seal('one');
    const b = await seal('two', 'correct horse');
    for (const { link } of [a, b]) {
      expect(link.id).toBe(ID);
      expect(link.fragmentKey).toHaveLength(32);
    }
    expect(a.link.needsPassphrase).toBe(false);
    expect(b.link.needsPassphrase).toBe(true);
    expect(a.link.fragmentKey).not.toEqual(b.link.fragmentKey);
    // Nothing the server stores identifies the key.
    expect(a.blob).not.toContain(a.fragmentSecret.split('.')[1]);
    expect(a.blob.split('.')[0]).toBe('v2');
  });

  it('opens with the fragment key alone when no passphrase was set', async () => {
    const { blob, link } = await seal('hunter2 for the wifi');
    expect(await openSecret(webcrypto, blob, { fragmentKey: link.fragmentKey })).toBe('hunter2 for the wifi');
  });

  it('passphrase alone cannot decrypt', async () => {
    const passphrase = 'correct horse battery staple';
    const { blob, link } = await seal('vault code 4471', passphrase);
    expect(PBKDF2_ITERATIONS).toBe(600_000);

    // The server holds the blob (with its salt) and may guess the passphrase,
    // but without the fragment key every attempt fails.
    const wrongKey = webcrypto.getRandomValues(new Uint8Array(32));
    await expect(openSecret(webcrypto, blob, { fragmentKey: wrongKey, passphrase })).rejects.toThrow();
    await expect(openSecret(webcrypto, blob, { fragmentKey: new Uint8Array(32), passphrase })).rejects.toThrow();

    // A passphrase-only key (the v1 design) does not open it either.
    const [, salt, iv, sealed] = blob.split('.');
    const base = await webcrypto.subtle.importKey('raw', new TextEncoder().encode(passphrase), 'PBKDF2', false, ['deriveKey']);
    const passphraseOnlyKey = await webcrypto.subtle.deriveKey(
      { name: 'PBKDF2', salt: decodeBase64Url(salt), iterations: PBKDF2_ITERATIONS, hash: 'SHA-256' },
      base,
      { name: 'AES-GCM', length: 256 },
      false,
      ['decrypt'],
    );
    await expect(webcrypto.subtle.decrypt({ name: 'AES-GCM', iv: decodeBase64Url(iv) }, passphraseOnlyKey, decodeBase64Url(sealed)))
      .rejects.toThrow();

    // The fragment key without the passphrase fails too: both factors are needed.
    await expect(openSecret(webcrypto, blob, { fragmentKey: link.fragmentKey })).rejects.toThrow();
    await expect(openSecret(webcrypto, blob, { fragmentKey: link.fragmentKey, passphrase: 'wrong' })).rejects.toThrow();
    expect(await openSecret(webcrypto, blob, { fragmentKey: link.fragmentKey, passphrase })).toBe('vault code 4471');
  });

  it('rejects malformed links before anything is fetched', () => {
    expect(parseSecretFragment('')).toBeNull();
    expect(parseSecretFragment(`${ID}.p`)).toBeNull();
    expect(parseSecretFragment(`${ID}.k.${'A'.repeat(43)}`)).toBeNull();
    expect(parseSecretFragment(`${ID}.k2.AAAA`)).toBeNull();
    expect(parseSecretFragment(`${ID}.k2.${'A'.repeat(43)}.extra`)).toBeNull();
    expect(parseSecretFragment(`${ID}.k2.${'A'.repeat(43)}`)).toMatchObject({ id: ID, needsPassphrase: false });
  });

  it('refuses blobs in other formats', async () => {
    const { link } = await seal('x');
    await expect(openSecret(webcrypto, 'v1.aaa.bbb', { fragmentKey: link.fragmentKey })).rejects.toThrow('unsupported secret format');
  });
});
